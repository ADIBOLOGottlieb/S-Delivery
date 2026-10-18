import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voom_delivery_app/config/api_config.dart';
import 'package:voom_delivery_app/models/product.dart';
import 'package:voom_delivery_app/services/api_client.dart';
import 'package:voom_delivery_app/services/auth_service.dart';
import 'package:voom_delivery_app/services/paged_api.dart';
import 'package:voom_delivery_app/services/support_phone.dart';
import 'package:voom_delivery_app/widgets/paged_loader.dart';

Map<String, dynamic> _userJson() => {
      'id': 1,
      'name': 'Ama',
      'email': null,
      'phone_number': '+22890000001',
      'role': 'client',
    };

Future<ApiException> _caught(Future<dynamic> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('ApiException attendue');
}

void main() {
  group('ApiClient : conversion des erreurs', () {
    ApiClient throwing(Object error) => ApiClient(httpClient: MockClient((_) async => throw error));

    test('pas de réseau (SocketException)', () async {
      final e = await _caught(() => throwing(const SocketException('down')).get('/x'));
      expect(e.message, contains('Impossible de joindre le serveur'));
    });

    test('erreur TLS (HandshakeException)', () async {
      final e = await _caught(() => throwing(const HandshakeException('bad cert')).get('/x'));
      expect(e.message, contains('Connexion sécurisée impossible'));
    });

    test('autre IOException', () async {
      final e = await _caught(() => throwing(const HttpException('reset')).get('/x'));
      expect(e.message, 'Erreur réseau. Réessayez.');
    });

    test("photo introuvable (FileSystemException) à l'envoi multipart", () async {
      final api = ApiClient(httpClient: MockClient((_) async => http.Response('{}', 200)));
      final e = await _caught(
        () => api.postFiles('/deliveries/1/photos', files: [('photo', '/chemin/inexistant/photo.jpg')]),
      );
      expect(e.message, contains('Photo illisible'));
    });

    test('erreurs de parsing (FormatException, réponse 200 non JSON)', () async {
      expect((await _caught(() => throwing(const FormatException('x')).get('/x'))).message,
          'Réponse inattendue du serveur. Réessayez.');
      // Réponse 200 qui n'est pas du JSON (page d'erreur d'un proxy).
      final html = ApiClient(httpClient: MockClient((_) async => http.Response('<html>oops</html>', 200)));
      expect((await _caught(() => html.get('/x'))).message, 'Réponse inattendue du serveur. Réessayez.');
    });

    test('délai dépassé : message neutre pour une écriture, « serveur démarre » pour une lecture', () async {
      final slow = ApiClient(
        httpClient: MockClient(
          (_) => Future.delayed(const Duration(milliseconds: 200), () => http.Response('{}', 200)),
        ),
        timeout: const Duration(milliseconds: 20),
      );
      final write = await _caught(() => slow.post('/deliveries', {'a': 1}));
      expect(write.message, ApiClient.timeoutWriteMessage);
      expect(write.timedOut, isTrue);
      final read = await _caught(() => slow.get('/deliveries'));
      expect(read.message, ApiClient.timeoutReadMessage);
    });

    test('DELETE avec corps JSON', () async {
      late http.Request sent;
      final api = ApiClient(httpClient: MockClient((request) async {
        sent = request;
        return http.Response('{}', 200);
      }));
      await api.delete('/me', {'password': 'secret'});
      expect(sent.method, 'DELETE');
      expect(jsonDecode(sent.body), {'password': 'secret'});
      expect(sent.headers['Content-Type'], startsWith('application/json'));
    });
  });

  group('ApiClient : filtre des messages anglais', () {
    test('ne remplace que les vrais messages de validation Laravel', () {
      expect(ApiClient.looksLikeEnglishValidation('The phone number field is required.'), isTrue);
      expect(ApiClient.looksLikeEnglishValidation('The password must be at least 8 characters.'), isTrue);
      expect(ApiClient.looksLikeEnglishValidation('The selected type is invalid.'), isTrue);
      // Messages français, ou anglais sans rapport avec la validation : gardés.
      expect(ApiClient.looksLikeEnglishValidation('Le champ « field » est obligatoire.'), isFalse);
      expect(ApiClient.looksLikeEnglishValidation('Theo, votre colis est en route.'), isFalse);
      expect(ApiClient.looksLikeEnglishValidation('The Express service is closed today.'), isFalse);
    });

    test('un message français contenant « field » est affiché tel quel', () async {
      final api = ApiClient(
        httpClient: MockClient((_) async => http.Response(jsonEncode({'message': 'Champ field_x invalide.'}), 422)),
      );
      expect((await _caught(() => api.get('/x'))).message, 'Champ field_x invalide.');
    });
  });

  group('AuthService : suppression du compte', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({
          'auth_token': 't0k',
          'user_data': jsonEncode(_userJson()),
        }));

    AuthService serviceWith(Future<http.Response> Function(http.Request) onDelete) {
      final api = ApiClient(
        httpClient: MockClient((request) async {
          if (request.method == 'DELETE' && request.url.path.endsWith('/me')) return onDelete(request);
          if (request.url.path.endsWith('/me')) return http.Response(jsonEncode({'data': _userJson()}), 200);
          return http.Response('{}', 200);
        }),
      );
      return AuthService(api);
    }

    test('succès : mot de passe envoyé et session effacée', () async {
      String? password;
      final auth = serviceWith((request) async {
        password = (jsonDecode(request.body) as Map)['password'] as String?;
        return http.Response(jsonEncode({'message': 'Compte supprimé.'}), 200);
      });
      await auth.init();
      expect(auth.isAuthenticated, isTrue);

      await auth.deleteAccount('secret123');
      expect(password, 'secret123');
      expect(auth.isAuthenticated, isFalse);
      expect(auth.sessionExpired, isFalse);
      expect(await const FlutterSecureStorage().read(key: 'auth_token'), isNull);
    });

    test('422 (mot de passe faux, livraison active) : message français, session gardée', () async {
      final auth = serviceWith((_) async => http.Response(
            jsonEncode({
              'message': 'Mot de passe incorrect.',
              'errors': {
                'password': ['Mot de passe incorrect.'],
              },
            }),
            422,
          ));
      await auth.init();
      final e = await _caught(() => auth.deleteAccount('faux'));
      expect(e.message, 'Mot de passe incorrect.');
      expect(auth.isAuthenticated, isTrue);
    });

    test('serveur sans la route (404) : message clair', () async {
      final auth = serviceWith((_) async => http.Response('{"message":"Not Found"}', 404));
      await auth.init();
      final e = await _caught(() => auth.deleteAccount('secret123'));
      expect(e.message, contains("n'est pas encore disponible"));
      expect(auth.isAuthenticated, isTrue);
    });
  });

  test('AuthService.logout : session locale effacée sans attendre le serveur', () async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 't0k', 'user_data': jsonEncode(_userJson())});
    final never = Completer<http.Response>();
    final api = ApiClient(
      httpClient: MockClient((request) =>
          request.url.path.endsWith('/logout') ? never.future : Future.value(http.Response('{}', 500))),
    );
    final auth = AuthService(api);
    await auth.init();
    await auth.logout().timeout(const Duration(seconds: 2));
    expect(auth.isAuthenticated, isFalse);
    expect(api.token, isNull);
  });

  test('rôle modifié par l\'admin détecté au rafraîchissement du profil', () async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 't0k', 'user_data': jsonEncode(_userJson())});
    final api = ApiClient(
      httpClient: MockClient((_) async => http.Response(jsonEncode({'data': {..._userJson(), 'role': 'livreur'}}), 200)),
    );
    final auth = AuthService(api);
    await auth.init();
    await auth.refreshProfile();
    expect(auth.user!.isCourier, isTrue);
    expect(auth.consumeRoleChanged(), isTrue);
    expect(auth.consumeRoleChanged(), isFalse);
  });

  test('PaymentInfo lit privacy_url / account_deletion_url, sinon pages par défaut', () async {
    final info = PaymentInfo.fromJson({
      'methods': [],
      'privacy_url': 'https://exemple.tg/confidentialite',
      'account_deletion_url': '',
    });
    expect(info.privacyUrl, 'https://exemple.tg/confidentialite');
    expect(info.accountDeletionUrl, isNull);

    final api = ApiClient(httpClient: MockClient((_) async => http.Response(jsonEncode({'methods': []}), 200)));
    expect(await SupportPhone.privacyUrl(api), ApiConfig.privacyUrl);
    expect(ApiConfig.privacyUrl, endsWith('/confidentialite'));
    expect(ApiConfig.accountDeletionUrl, endsWith('/compte/suppression'));
  });

  group('PagedLoader', () {
    test('rafraîchissement partagé, pages suivantes gardées et dédoublonnées', () async {
      var calls = 0;
      var firstPage = [1, 2];
      final loader = PagedLoader<int>((page) async {
        calls++;
        await Future<void>.delayed(Duration.zero);
        return page == 1
            ? PageResult(items: firstPage, page: 1, hasMore: true)
            : const PageResult(items: [2, 3, 4], page: 2, hasMore: false);
      }, idOf: (i) => i);

      await Future.wait([loader.refresh(), loader.refresh()]);
      expect(calls, 1, reason: 'un seul appel pour deux rafraîchissements simultanés');

      await loader.loadMore();
      expect(loader.items, [1, 2, 3, 4]);

      // Polling : la 1re page change, la page 2 déjà chargée reste affichée.
      firstPage = [5, 1];
      await loader.refresh();
      expect(loader.items, [5, 1, 3, 4]);
      expect(loader.hasMore, isFalse);

      // Tirer pour rafraîchir : retour à la 1re page seule.
      await loader.reset();
      expect(loader.items, [5, 1]);
      expect(loader.hasMore, isTrue);
    });
  });
}
