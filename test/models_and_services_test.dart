import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voom_delivery_app/models/delivery.dart';
import 'package:voom_delivery_app/models/product.dart';
import 'package:voom_delivery_app/services/api_client.dart';
import 'package:voom_delivery_app/services/auth_service.dart';
import 'package:voom_delivery_app/services/paged_api.dart';

Map<String, dynamic> _delivery([Map<String, dynamic> extra = const {}]) => {
      'id': 7,
      'reference': 'VD-PAY777',
      'type': 'colis',
      'status': 'pending',
      'status_label': 'En attente',
      'payment_status': 'submitted',
      'payment_status_label': 'En vérification',
      'pickup': {'address': 'Bè', 'lat': 6.13, 'lng': 1.24, 'contact_name': null, 'contact_phone': null},
      'dropoff': {'address': 'Kégué', 'lat': 6.16, 'lng': 1.26, 'contact_name': 'Yao', 'contact_phone': '+22893'},
      'distance_km': 3.5,
      'delivery_fee': 1500,
      'items_amount': 0,
      'total_amount': 1500,
      'can_pay': false,
      'can_cancel': false,
      'created_at': '2026-10-14T08:00:00+00:00',
      ...extra,
    };

Map<String, dynamic> _userJson() => {
      'id': 1,
      'name': 'Ama',
      'email': null,
      'phone_number': '+22890000001',
      'role': 'client',
    };

void main() {
  group('Delivery.fromJson', () {
    test('accepte un paiement sans référence de transaction (transaction_ref null)', () {
      final d = Delivery.fromJson(_delivery({
        'latest_payment': {
          'id': 3,
          'method': 'flooz',
          'method_label': 'Flooz',
          'transaction_ref': null,
          'payer_phone': '+22890',
          'amount': 1500,
          'status': 'submitted',
          'status_label': 'En vérification',
          'rejection_reason': null,
        },
      }));

      expect(d.latestPayment, isNotNull);
      expect(d.latestPayment!.transactionRef, isNull);
      expect(d.latestPayment!.amount, 1500);
    });

    test('lit parcel_amount (montant à encaisser) et le tolère absent', () {
      expect(Delivery.fromJson(_delivery({'parcel_amount': 12000})).parcelAmount, 12000);
      expect(Delivery.fromJson(_delivery({'parcel_amount': null})).parcelAmount, isNull);
      expect(Delivery.fromJson(_delivery()).parcelAmount, isNull);
    });

    test('contact de récupération absent ou vide : null', () {
      final d = Delivery.fromJson(_delivery({
        'pickup': {'address': 'Marché', 'lat': 6.1, 'lng': 1.2, 'contact_name': '', 'contact_phone': '  '},
      }));
      expect(d.pickup.contactPhone, isNull);
      expect(d.pickup.contactName, isNull);
    });

    test('photos acceptées seulement avant la récupération du colis', () {
      expect(Delivery.fromJson(_delivery()).acceptsPhotos, isTrue);
      expect(Delivery.fromJson(_delivery({'status': 'assigned'})).acceptsPhotos, isTrue);
      expect(Delivery.fromJson(_delivery({'status': 'picked_up'})).acceptsPhotos, isFalse);
    });
  });

  test('PaymentInfo lit support_phone et le tolère absent', () {
    expect(PaymentInfo.fromJson({'methods': [], 'support_phone': '+228 90 11 22 33'}).supportPhone, '+228 90 11 22 33');
    expect(PaymentInfo.fromJson({'methods': [], 'support_phone': ''}).supportPhone, isNull);
    expect(PaymentInfo.fromJson({'methods': []}).supportPhone, isNull);
  });

  test('PagedApi détecte la page suivante via meta Laravel', () {
    final page = PagedApi.parsePage(
      {
        'data': [_delivery()],
        'meta': {'current_page': 1, 'last_page': 3},
      },
      Delivery.fromJson,
      page: 1,
    );
    expect(page.items, hasLength(1));
    expect(page.hasMore, isTrue);
    expect(PagedApi.parsePage({'data': []}, Delivery.fromJson, page: 1).hasMore, isFalse);
  });

  group('ApiClient messages', () {
    Future<ApiException> errorFor(int status, Map<String, dynamic> body) async {
      final api = ApiClient(httpClient: MockClient((_) async => http.Response(jsonEncode(body), status)));
      try {
        await api.get('/x');
      } on ApiException catch (e) {
        return e;
      }
      fail('ApiException attendue');
    }

    test('validation en anglais : message français générique', () async {
      final e = await errorFor(422, {
        'message': 'The phone number field is required.',
        'errors': {
          'phone_number': ['The phone number field is required.'],
        },
      });
      expect(e.message, 'Vérifiez les informations saisies.');
    });

    test('429 en français affiché tel quel', () async {
      final e = await errorFor(429, {'message': 'Trop de tentatives. Réessayez dans 5 minutes.'});
      expect(e.message, 'Trop de tentatives. Réessayez dans 5 minutes.');
    });

    test('message Laravel par défaut remplacé par le message du code HTTP', () async {
      final e = await errorFor(401, {'message': 'Unauthenticated.'});
      expect(e.message, 'Session expirée. Reconnectez-vous.');
    });
  });

  group('AuthService session expirée', () {
    test('un 401 sur une session ouverte signale « session expirée »', () async {
      FlutterSecureStorage.setMockInitialValues({
        'auth_token': 't0k',
        'user_data': jsonEncode(_userJson()),
      });
      final api = ApiClient(httpClient: MockClient((_) async => http.Response('{"message":"Unauthenticated."}', 401)));
      final auth = AuthService(api);
      await auth.init();
      // Laisse le rafraîchissement du profil (/me → 401) se terminer.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(auth.isAuthenticated, isFalse);
      expect(auth.consumeSessionExpired(), isTrue);
      expect(auth.consumeSessionExpired(), isFalse);
    });

    test('une déconnexion volontaire ne signale pas de session expirée', () async {
      FlutterSecureStorage.setMockInitialValues({
        'auth_token': 't0k',
        'user_data': jsonEncode(_userJson()),
      });
      final api = ApiClient(
        httpClient: MockClient((request) async => request.url.path.endsWith('/me')
            ? http.Response(jsonEncode({'data': _userJson()}), 200)
            : http.Response('{"message":"Unauthenticated."}', 401)),
      );
      final auth = AuthService(api);
      await auth.init();
      await auth.logout();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.sessionExpired, isFalse);
    });

    test('connexion : le jeton est enregistré et la session restaurable', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = ApiClient(
        httpClient: MockClient((_) async => http.Response(jsonEncode({'token': 'abc', 'user': _userJson()}), 200)),
      );
      final auth = AuthService(api);
      await auth.login(login: '+22890000001', password: 'secret');
      expect(auth.isAuthenticated, isTrue);
      expect(api.token, 'abc');

      final restored = AuthService(ApiClient(httpClient: MockClient((_) async => http.Response('{}', 500))));
      await restored.init();
      expect(restored.isAuthenticated, isTrue);
    });
  });
}
