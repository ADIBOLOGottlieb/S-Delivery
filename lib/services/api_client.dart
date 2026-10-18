import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Erreur renvoyée par l'API, avec un message lisible par l'utilisateur.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Map<String, List<String>> fieldErrors;

  /// Délai dépassé : pour une écriture, la requête a pu aboutir côté serveur.
  final bool timedOut;

  ApiException(this.message, {this.statusCode, this.fieldErrors = const {}, this.timedOut = false});

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Client HTTP minimal : JSON, multipart, jeton Bearer et erreurs Laravel.
class ApiClient {
  ApiClient({http.Client? httpClient, Duration? timeout})
      : _http = httpClient ?? http.Client(),
        _timeout = timeout ?? ApiConfig.timeout;

  final http.Client _http;
  final Duration _timeout;
  String? token;

  /// Appelé quand le serveur répond 401 (jeton expiré ou compte désactivé).
  void Function()? onUnauthorized;

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send(() => _http.get(_uri(path, query), headers: _headers), idempotent: true);

  /// Réveille le serveur (veille Render) dès l'ouverture de l'app, sans bloquer l'interface.
  Future<void> warmUp() async {
    try {
      await _http.get(Uri.parse('${ApiConfig.serverRoot}/up')).timeout(ApiConfig.timeout);
    } catch (_) {
      // Sans importance : les vraies requêtes gèrent elles-mêmes les erreurs.
    }
  }

  /// Révoque côté serveur un jeton déjà retiré de la session locale (déconnexion en arrière-plan).
  /// Ne lève jamais d'erreur et ne déclenche pas [onUnauthorized].
  Future<void> revokeToken(String bearer) async {
    try {
      await _http.post(
        _uri('/logout'),
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $bearer'},
      ).timeout(_timeout);
    } catch (_) {
      // Jeton laissé côté serveur : il expirera de lui-même.
    }
  }

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) => _send(
        () => _http.post(
          _uri(path),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body ?? const {}),
        ),
      );

  /// [body] optionnel (ex. mot de passe pour supprimer le compte).
  Future<dynamic> delete(String path, [Map<String, dynamic>? body]) => _send(
        () => body == null
            ? _http.delete(_uri(path), headers: _headers)
            : _http.delete(
                _uri(path),
                headers: {..._headers, 'Content-Type': 'application/json'},
                body: jsonEncode(body),
              ),
      );

  Future<dynamic> put(String path, Map<String, dynamic> body) => _send(
        () => _http.put(
          _uri(path),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ),
      );

  Future<dynamic> postMultipart(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required String filePath,
  }) =>
      postFiles(path, fields: fields, files: [(fileField, filePath)]);

  /// Formulaire multipart avec plusieurs fichiers : [(champ, chemin), …] (ex. ('photos[]', '/…/a.jpg')).
  Future<dynamic> postFiles(
    String path, {
    Map<String, String> fields = const {},
    List<(String, String)> files = const [],
  }) {
    return _send(() async {
      final request = http.MultipartRequest('POST', _uri(path))
        ..headers.addAll(_headers)
        ..fields.addAll(fields);
      for (final (field, filePath) in files) {
        request.files.add(await http.MultipartFile.fromPath(field, filePath));
      }
      return http.Response.fromStream(await _http.send(request));
    });
  }

  /// Délai dépassé sur une écriture (création, paiement…) : elle a pu aboutir côté serveur.
  static const timeoutWriteMessage = 'Le serveur n\'a pas répondu à temps. Vérifiez dans Suivi avant de recommencer.';

  /// Délai dépassé sur une lecture : sans risque de doublon, on peut réessayer.
  static const timeoutReadMessage =
      'Le serveur démarre (cela peut prendre une minute). Réessayez dans quelques secondes.';

  static const _unexpectedMessage = 'Réponse inattendue du serveur. Réessayez.';

  /// [idempotent] : lecture (GET) qu'on peut relancer sans créer de doublon.
  Future<dynamic> _send(Future<http.Response> Function() request, {bool idempotent = false}) async {
    final http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on SocketException {
      throw ApiException('Impossible de joindre le serveur. Vérifiez votre connexion internet.');
    } on TimeoutException {
      throw ApiException(idempotent ? timeoutReadMessage : timeoutWriteMessage, timedOut: true);
    } on HandshakeException {
      throw ApiException('Connexion sécurisée impossible. Vérifiez la date du téléphone et votre réseau.');
    } on FileSystemException {
      throw ApiException('Photo illisible (supprimée ou inaccessible). Choisissez-la à nouveau.');
    } on IOException {
      throw ApiException('Erreur réseau. Réessayez.');
    } on http.ClientException {
      throw ApiException('Erreur réseau. Réessayez.');
    } on FormatException {
      throw ApiException(_unexpectedMessage);
    } on TypeError {
      throw ApiException(_unexpectedMessage);
    }

    final ok = response.statusCode >= 200 && response.statusCode < 300;
    dynamic data;
    if (response.body.isNotEmpty) {
      try {
        data = jsonDecode(response.body);
      } on FormatException {
        // Succès mais réponse illisible (page HTML d'un proxy…) : erreur claire plutôt qu'un plantage plus loin.
        if (ok) throw ApiException(_unexpectedMessage, statusCode: response.statusCode);
        data = null;
      }
    }

    if (ok) {
      return data;
    }

    if (response.statusCode == 401) {
      onUnauthorized?.call();
    }

    throw _toException(response.statusCode, data);
  }

  ApiException _toException(int status, dynamic data) {
    final fieldErrors = <String, List<String>>{};
    String? message;

    if (data is Map<String, dynamic>) {
      final errors = data['errors'];
      if (errors is Map<String, dynamic>) {
        errors.forEach((key, value) {
          fieldErrors[key] = value is List ? value.map((e) => e.toString()).toList() : ['$value'];
        });
      }
      // Pour une erreur de validation, le premier message de champ est le plus parlant.
      final raw = fieldErrors.values.firstOrNull?.firstOrNull ?? data['message'];
      message = raw is String ? _readable(raw) : null;
    }

    message ??= switch (status) {
      401 => 'Session expirée. Reconnectez-vous.',
      403 => 'Action non autorisée.',
      404 => 'Élément introuvable.',
      422 => 'Vérifiez les informations saisies.',
      429 => 'Trop de tentatives. Patientez une minute.',
      >= 500 => 'Erreur du serveur. Réessayez plus tard.',
      _ => 'Une erreur est survenue.',
    };

    return ApiException(message, statusCode: status, fieldErrors: fieldErrors);
  }

  /// Messages par défaut de Laravel (en anglais) : remplacés par le message du code HTTP.
  static const _laravelDefaults = {
    'unauthenticated.',
    'the given data was invalid.',
    'server error',
    'not found',
    'too many attempts.',
    'this action is unauthorized.',
    'forbidden',
  };

  /// Message affichable en français ; null pour retomber sur le message du code HTTP.
  static String? _readable(String raw) {
    final text = raw.trim();
    if (text.isEmpty || _laravelDefaults.contains(text.toLowerCase())) return null;
    // Message de validation Laravel non traduit (« The phone number field is required. »…).
    if (looksLikeEnglishValidation(text)) return 'Vérifiez les informations saisies.';
    return text;
  }

  /// Vrai seulement pour un message de validation Laravel en anglais (« The … field … », « The … must … »,
  /// « The selected … ») : un message français qui contient « field » ou commence par « The » est gardé.
  static bool looksLikeEnglishValidation(String text) =>
      text.startsWith('The ') && (text.contains('field') || text.contains('must') || text.contains('selected'));
}
