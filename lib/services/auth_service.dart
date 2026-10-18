import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/user.dart';
import '../widgets/photos.dart';
import 'api_client.dart';
import 'delivery_service.dart';
import 'push_service.dart';

class AuthService extends ChangeNotifier {
  AuthService(this._api, {FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage() {
    _api.onUnauthorized = _onUnauthorized;
  }

  static const _tokenKey = 'auth_token';
  static const _userKey = 'user_data';

  final ApiClient _api;
  final FlutterSecureStorage _storage;

  User? _user;
  bool _isLoading = false;
  bool _sessionExpired = false;
  bool _roleChanged = false;

  /// Désinscription des notifications en cours (déconnexion) : la prochaine inscription l'attend.
  Future<void> _pushCleanup = Future.value();

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _api.token != null && _user != null;

  /// Vrai quand le serveur a refusé le jeton (401) alors que l'utilisateur était connecté,
  /// sans déconnexion volontaire. Remis à faux par [consumeSessionExpired].
  bool get sessionExpired => _sessionExpired;

  /// Lit et efface le signal « session expirée » (traité une seule fois).
  bool consumeSessionExpired() {
    final expired = _sessionExpired;
    _sessionExpired = false;
    return expired;
  }

  /// Lit et efface le signal « rôle modifié par l'admin » (client devenu livreur…), détecté au rafraîchissement du profil.
  bool consumeRoleChanged() {
    final changed = _roleChanged;
    _roleChanged = false;
    return changed;
  }

  /// Réponse 401 : jeton expiré ou compte désactivé par l'agence.
  void _onUnauthorized() {
    // Plusieurs requêtes peuvent échouer en même temps : un seul signal.
    if (!isAuthenticated) return;
    _sessionExpired = true;
    _unregisterPush();
    _clearSession();
  }

  /// Restaure la session enregistrée. À attendre avant de choisir l'écran de départ.
  Future<void> init() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      final userJson = await _storage.read(key: _userKey);
      if (token != null && userJson != null) {
        _api.token = token;
        _user = User.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
        notifyListeners();
        // Rafraîchit le profil en arrière-plan (rôle ou statut modifié par l'admin).
        _refreshProfile();
        _registerPush();
      }
    } catch (e) {
      debugPrint('Session illisible, réinitialisation : $e');
      await _clearSession();
    }
  }

  Future<void> _refreshProfile() async {
    try {
      await _saveUser(await _api.get('/me'));
    } catch (e) {
      debugPrint('Profil non rafraîchi : $e');
    }
  }

  /// Recharge le profil (ex. modifié depuis le panneau admin).
  Future<void> refreshProfile() => _refreshProfile();

  /// Ajoute ou remplace la photo de profil. Lève [ApiException] en cas d'échec.
  Future<void> updateAvatar(String filePath) async =>
      _saveUser(await _api.postFiles('/me/avatar', files: [('photo', filePath)]));

  Future<void> removeAvatar() async => _saveUser(await _api.delete('/me/avatar'));

  /// Identifiants de connexion (reçus de l'agence ou choisis à l'inscription).
  /// Lève [ApiException] (ex. mot de passe actuel incorrect).
  Future<void> updateCredentials({
    required String currentPassword,
    String? phoneNumber,
    String? email,
    String? newPassword,
  }) async =>
      _saveUser(await _api.put('/me/credentials', {
        'current_password': currentPassword,
        if (phoneNumber != null) 'phone_number': phoneNumber,
        if (email != null) 'email': email.isEmpty ? null : email,
        if (newPassword != null) ...{'password': newPassword, 'password_confirmation': newPassword},
      }));

  Future<void> _saveUser(dynamic response) async {
    // Réponse arrivée après une déconnexion : on ne recrée pas de session.
    if (_api.token == null) return;
    final previous = _user;
    _user = User.fromJson((response as Map<String, dynamic>)['data'] as Map<String, dynamic>);
    // Rôle changé par l'admin : autre écran d'accueil et autres annonces push.
    if (previous != null && previous.role != _user!.role) {
      _roleChanged = true;
      _registerPush();
    }
    try {
      await _storage.write(key: _userKey, value: jsonEncode(_user!.toJson()));
    } catch (e) {
      debugPrint('Profil non enregistré sur le téléphone : $e');
    }
    notifyListeners();
  }

  /// Lève [ApiException] avec un message affichable en cas d'échec.
  Future<void> login({required String login, required String password}) {
    return _authenticate('/login', {'login': login, 'password': password});
  }

  Future<void> register({
    required String name,
    String? email,
    required String phoneNumber,
    required String password,
    required String confirmPassword,
  }) {
    return _authenticate('/register', {
      'name': name,
      if (email != null && email.isNotEmpty) 'email': email,
      'phone_number': phoneNumber,
      'password': password,
      'password_confirmation': confirmPassword,
    });
  }

  /// Mot de passe oublié : envoie un code à l'email du compte, renvoie l'email masqué (« a***@gmail.com »).
  /// Le serveur peut répondre de façon générique (sans email) : chaîne vide.
  Future<String> sendResetCode(String login) async {
    final data = await _api.post('/password/forgot', {'login': login});
    return data is Map<String, dynamic> ? data['email'] as String? ?? '' : '';
  }

  /// Nouveau mot de passe avec le code reçu par email ; l'utilisateur est ensuite connecté.
  Future<void> resetPassword({
    required String login,
    required String code,
    required String password,
    required String confirmPassword,
  }) {
    return _authenticate('/password/reset', {
      'login': login,
      'code': code,
      'password': password,
      'password_confirmation': confirmPassword,
    });
  }

  Future<void> _authenticate(String path, Map<String, dynamic> body) async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await _api.post(path, body);
      if (data is! Map<String, dynamic> || data['token'] is! String || data['user'] is! Map<String, dynamic>) {
        throw ApiException('Réponse inattendue du serveur. Réessayez.');
      }
      final token = data['token'] as String;
      final user = User.fromJson(data['user'] as Map<String, dynamic>);
      // Jeton enregistré avant de marquer l'utilisateur connecté (session restaurable au prochain lancement).
      try {
        await _storage.write(key: _tokenKey, value: token);
        await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
      } catch (e) {
        debugPrint('Session non enregistrée sur le téléphone : $e');
      }
      _sessionExpired = false;
      _roleChanged = false;
      _api.token = token;
      _user = user;
      _registerPush();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Notifications : rappels (livreur) ou promos (client). Sans effet si Firebase est absent.
  void _registerPush() {
    final user = _user;
    if (user == null) return;
    final deliveries = DeliveryService(_api);
    // Attend la fin d'une désinscription (déconnexion juste avant) pour ne pas la voir annuler l'inscription.
    _pushCleanup = _pushCleanup.whenComplete(() {
      if (_user != null) return PushService.register(user, deliveries);
    });
  }

  void _unregisterPush() {
    _pushCleanup = _pushCleanup.whenComplete(PushService.unregister);
  }

  /// Déconnexion : l'écran de connexion s'affiche tout de suite ; la révocation du jeton
  /// et la désinscription des notifications se font en arrière-plan.
  Future<void> logout() async {
    final token = _api.token;
    _sessionExpired = false;
    _unregisterPush();
    await _clearSession();
    await PhotoDraft.clear();
    if (token != null) unawaited(_api.revokeToken(token));
  }

  /// Suppression définitive du compte (DELETE /me avec le mot de passe).
  /// Lève [ApiException] (mot de passe incorrect, livraison en cours…) ; en cas de succès, la session est effacée.
  Future<void> deleteAccount(String password) async {
    try {
      await _api.delete('/me', {'password': password});
    } on ApiException catch (e) {
      // Serveur pas encore à jour (route absente).
      if (e.statusCode == 404 || e.statusCode == 405) {
        throw ApiException(
          'La suppression du compte n\'est pas encore disponible. Contactez l\'agence.',
          statusCode: e.statusCode,
        );
      }
      rethrow;
    }
    _sessionExpired = false;
    _unregisterPush();
    await _clearSession();
    await PhotoDraft.clear();
  }

  Future<void> _clearSession() async {
    _api.token = null;
    _user = null;
    notifyListeners();
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userKey);
    } catch (e) {
      debugPrint('Session locale non effacée : $e');
    }
  }
}
