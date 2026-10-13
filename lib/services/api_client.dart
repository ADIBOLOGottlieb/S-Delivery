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

  ApiException(this.message, {this.statusCode, this.fieldErrors = const {}});

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Client HTTP minimal : JSON, multipart, jeton Bearer et erreurs Laravel.
class ApiClient {
  ApiClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;
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
      _send(() => _http.get(_uri(path, query), headers: _headers));

  /// Réveille le serveur (veille Render) dès l'ouverture de l'app, sans bloquer l'interface.
  Future<void> warmUp() async {
    try {
      await _http.get(Uri.parse('${ApiConfig.serverRoot}/up')).timeout(ApiConfig.timeout);
    } catch (_) {
      // Sans importance : les vraies requêtes gèrent elles-mêmes les erreurs.
    }
  }

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) => _send(
        () => _http.post(
          _uri(path),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body ?? const {}),
        ),
      );

  Future<dynamic> delete(String path) => _send(() => _http.delete(_uri(path), headers: _headers));

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

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request().timeout(ApiConfig.timeout);
    } on SocketException {
      throw ApiException('Impossible de joindre le serveur. Vérifiez votre connexion internet.');
    } on TimeoutException {
      throw ApiException('Le serveur démarre (cela peut prendre une minute). Réessayez dans quelques secondes.');
    } on http.ClientException {
      throw ApiException('Erreur réseau. Réessayez.');
    }

    dynamic data;
    if (response.body.isNotEmpty) {
      try {
        data = jsonDecode(response.body);
      } on FormatException {
        data = null;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
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
          fieldErrors[key] = (value as List).map((e) => e.toString()).toList();
        });
      }
      // Pour une erreur de validation, le premier message de champ est le plus parlant.
      message = fieldErrors.values.firstOrNull?.firstOrNull ?? data['message'] as String?;
    }

    message ??= switch (status) {
      401 => 'Session expirée. Reconnectez-vous.',
      403 => 'Action non autorisée.',
      404 => 'Élément introuvable.',
      429 => 'Trop de tentatives. Patientez une minute.',
      >= 500 => 'Erreur du serveur. Réessayez plus tard.',
      _ => 'Une erreur est survenue.',
    };

    return ApiException(message, statusCode: status, fieldErrors: fieldErrors);
  }
}
