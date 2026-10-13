import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/user.dart';
import 'api_client.dart';
import 'delivery_service.dart';
import 'push_service.dart';

class AuthService extends ChangeNotifier {
  AuthService(this._api, {FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage() {
    _api.onUnauthorized = _clearSession;
  }

  static const _tokenKey = 'auth_token';
  static const _userKey = 'user_data';

  final ApiClient _api;
  final FlutterSecureStorage _storage;

  User? _user;
  bool _isLoading = false;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _api.token != null && _user != null;

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
    } on ApiException catch (e) {
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
    _user = User.fromJson((response as Map<String, dynamic>)['data'] as Map<String, dynamic>);
    await _storage.write(key: _userKey, value: jsonEncode(_user!.toJson()));
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

  Future<void> _authenticate(String path, Map<String, dynamic> body) async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await _api.post(path, body) as Map<String, dynamic>;
      _api.token = data['token'] as String;
      _user = User.fromJson(data['user'] as Map<String, dynamic>);
      _registerPush();
      _user = User.fromJson(data['user'] as Map<String, dynamic>);
      await _storage.write(key: _tokenKey, value: _api.token);
      await _storage.write(key: _userKey, value: jsonEncode(_user!.toJson()));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Notifications : rappels (livreur) ou promos (client). Sans effet si Firebase est absent.
  void _registerPush() {
    final user = _user;
    if (user != null) PushService.register(user, DeliveryService(_api));
  }

  Future<void> logout() async {
    await PushService.unregister();
    try {
      if (_api.token != null) await _api.post('/logout');
    } on ApiException catch (e) {
      debugPrint('Déconnexion serveur impossible : $e');
    }
    await _clearSession();
  }

  Future<void> _clearSession() async {
    _api.token = null;
    _user = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    notifyListeners();
  }
}
