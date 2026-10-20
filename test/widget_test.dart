import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:s_delivery/main.dart';
import 'package:s_delivery/models/chat.dart';
import 'package:s_delivery/models/delivery.dart';
import 'package:s_delivery/models/payment.dart';
import 'package:s_delivery/models/user.dart';
import 'package:s_delivery/services/api_client.dart';
import 'package:s_delivery/widgets/brand_logo.dart';

Map<String, dynamic> _deliveryJson() => {
      'id': 1,
      'reference': 'SD-ABC123',
      'type': 'express',
      'type_label': 'Express',
      'status': 'assigned',
      'status_label': 'Livreur assigné',
      'payment_status': 'verified',
      'payment_status_label': 'Paiement confirmé',
      'pickup': {'address': 'Bè', 'lat': 6.1375, 'lng': 1.24, 'contact_name': 'Ama', 'contact_phone': '+22890'},
      'dropoff': {'address': 'Kégué', 'lat': 6.165, 'lng': 1.26, 'contact_name': 'Yao', 'contact_phone': '+22893'},
      'distance_km': 4.2,
      'delivery_fee': 2100,
      'items_amount': 0,
      'total_amount': 2100,
      'courier': {'name': 'Kossi', 'phone_number': '+22891', 'vehicle': 'Moto'},
      'latest_payment': null,
      'can_pay': false,
      'can_cancel': false,
      'created_at': '2026-10-06T15:10:00+00:00',
    };

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr');
  });

  testWidgets('démarre sur le splash puis affiche la connexion sans session', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = ApiClient(httpClient: MockClient((_) async => http.Response('{}', 404)));

    await tester.pumpWidget(SDeliveryApp(api: api));
    expect(find.byType(SDeliveryMark), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Connectez-vous à votre compte'), findsOneWidget);
    expect(find.text('Email ou téléphone'), findsOneWidget);
  });

  test('ApiClient remonte le premier message de validation Laravel', () async {
    final api = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer t0k');
        return http.Response(
          jsonEncode({
            'message': 'The given data was invalid.',
            'errors': {
              'transaction_ref': ['Cette référence de transaction a déjà été utilisée.'],
            },
          }),
          422,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    )..token = 't0k';

    expect(
      () => api.post('/deliveries/1/payment'),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', 'Cette référence de transaction a déjà été utilisée.')
          .having((e) => e.statusCode, 'status', 422)),
    );
  });

  test('ApiClient signale une session expirée (401)', () async {
    var unauthorized = false;
    final api = ApiClient(httpClient: MockClient((_) async => http.Response('{"message":"Unauthenticated."}', 401)))
      ..onUnauthorized = () => unauthorized = true;

    await expectLater(api.get('/me'), throwsA(isA<ApiException>()));
    expect(unauthorized, isTrue);
  });

  test('PaymentInfo lit les numéros marchands Flooz / Mixx', () {
    final info = PaymentInfo.fromJson({
      'merchant_name': 'S-Delivery',
      'instructions': 'Indiquez la référence de la livraison.',
      'methods': [
        {'method': 'flooz', 'label': 'Flooz (Moov Africa)', 'merchant_number': '99 00 00 00'},
        {'method': 'mixx', 'label': 'Mixx by Yas', 'merchant_number': '70 00 00 00'},
      ],
    });
    expect(info.merchantName, 'S-Delivery');
    expect(info.methods.map((m) => m.method), ['flooz', 'mixx']);
    expect(info.methods.first.merchantNumber, '99 00 00 00');
  });

  test('Delivery.fromJson lit les points A/B et le livreur', () {
    final d = Delivery.fromJson(_deliveryJson());

    expect(d.type, DeliveryType.express);
    expect(d.pickup.lat, 6.1375);
    expect(d.dropoff.contactPhone, '+22893');
    expect(d.courier?.name, 'Kossi');
    expect(d.isActive, isTrue);
    expect(d.photos, isEmpty);
    expect(d.requestId, isNull);
  });

  test('Delivery.fromJson lit les photos des articles et la discussion liée', () {
    final d = Delivery.fromJson({
      ..._deliveryJson(),
      'photos': ['https://api/media/a', 'https://api/media/b'],
      'request_id': 12,
    });

    expect(d.photos, hasLength(2));
    expect(d.requestId, 12);
  });

  test('User.fromJson lit la photo de profil', () {
    final user = User.fromJson({
      'id': 3,
      'name': 'Ama Mensah',
      'email': null,
      'phone_number': '+22890000000',
      'role': 'client',
      'vehicle': null,
      'avatar_url': 'https://api/media/x',
    });

    expect(user.avatarUrl, 'https://api/media/x');
    expect(user.firstName, 'Ama');
    expect(user.roleLabel, 'Client');
    // Session enregistrée puis relue : les nouveaux champs survivent.
    expect(User.fromJson(user.toJson()).avatarUrl, user.avatarUrl);
  });

  test('ChatRequest.fromJson lit messages, non-lus et livraison programmée', () {
    final r = ChatRequest.fromJson({
      'id': 5,
      'reference': 'DR-0005',
      'status': 'scheduled',
      'status_label': 'Livraison programmée',
      'unread': 2,
      'messages': [
        {
          'id': 1, 'from': 'client', 'body': null, 'photo_url': 'https://api/media/p', 'lat': null, 'lng': null,
          'created_at': '2026-10-10T09:00:00+00:00',
        },
        {
          'id': 2, 'from': 'client', 'body': 'Agoè', 'photo_url': null, 'lat': 6.2, 'lng': 1.2,
          'created_at': '2026-10-10T09:01:00+00:00',
        },
        {
          'id': 3, 'from': 'agency', 'body': 'Ok', 'photo_url': null, 'lat': null, 'lng': null,
          'created_at': '2026-10-10T09:02:00+00:00',
        },
      ],
      'delivery': {
        'id': 9, 'reference': 'SD-XYZ123', 'status_label': 'En attente', 'payment_status': 'unpaid',
        'total_amount': 1500, 'can_pay': true,
      },
      'last_message_at': '2026-10-10T09:02:00+00:00',
    });

    expect(r.unread, 2);
    expect(r.messages.first.preview, '📷 Photo');
    expect(r.messages[1].hasLocation, isTrue);
    expect(r.messages[1].isMine, isTrue);
    expect(r.messages.last.isMine, isFalse);
    expect(r.delivery?.canPay, isTrue);
    expect(r.delivery?.totalAmount, 1500);
  });
}
