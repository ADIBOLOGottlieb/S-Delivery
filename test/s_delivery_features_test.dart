import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:s_delivery/models/delivery.dart';
import 'package:s_delivery/models/delivery_message.dart';
import 'package:s_delivery/models/payment.dart';
import 'package:s_delivery/services/api_client.dart';
import 'package:s_delivery/services/delivery_service.dart';
import 'package:s_delivery/utils/theme.dart';
import 'package:s_delivery/widgets/brand_logo.dart';
import 'package:s_delivery/widgets/ui.dart';

Map<String, dynamic> _delivery([Map<String, dynamic> extra = const {}]) => {
      'id': 7,
      'reference': 'SD-TRK001',
      'type': 'colis',
      'status': 'picked_up',
      'status_label': 'Colis récupéré',
      'payment_status': 'verified',
      'payment_status_label': 'Paiement confirmé',
      'pickup': {'address': 'Bè', 'lat': 6.13, 'lng': 1.24},
      'dropoff': {'address': 'Kégué', 'lat': 6.16, 'lng': 1.26, 'contact_name': 'Yao', 'contact_phone': '+22893000000'},
      'distance_km': 3.2,
      'delivery_fee': 1500,
      'total_amount': 1500,
      'can_pay': false,
      'can_cancel': false,
      'created_at': '2026-10-20T10:00:00+00:00',
      ...extra,
    };

void main() {
  group('Delivery (S-Delivery 2.0)', () {
    test('lit le code de remise, les non-lus, la note et la position du livreur', () {
      final d = Delivery.fromJson(_delivery({
        'dropoff_code': '0427',
        'requires_code': true,
        'unread_messages': 3,
        'chat_open': true,
        'can_rate': false,
        'courier': {
          'name': 'Kossi Mensah',
          'phone_number': '+22891',
          'vehicle': 'Moto',
          'avatar_url': 'https://api/media/k',
          'location': {'lat': 6.15, 'lng': 1.25, 'updated_at': '2026-10-20T10:05:00+00:00'},
        },
      }));

      expect(d.dropoffCode, '0427');
      expect(d.requiresCode, isTrue);
      expect(d.unreadMessages, 3);
      expect(d.chatOpen, isTrue);
      expect(d.isInProgress, isTrue);
      expect(d.progressStep, 3);
      expect(d.courier?.firstName, 'Kossi');
      expect(d.courier?.location?.lat, 6.15);
      expect(d.courier?.avatarUrl, 'https://api/media/k');
    });

    test('anciennes réponses sans nouveaux champs : valeurs par défaut sûres', () {
      final d = Delivery.fromJson(_delivery({'status': 'pending', 'payment_status': 'unpaid', 'courier': null}));

      expect(d.dropoffCode, isNull);
      expect(d.requiresCode, isFalse);
      expect(d.unreadMessages, 0);
      expect(d.canRate, isFalse);
      expect(d.progressStep, 0);
      expect(d.courier, isNull);
    });

    test('étapes de progression', () {
      expect(Delivery.fromJson(_delivery({'status': 'pending'})).progressStep, 1); // payée, en attente du livreur
      expect(Delivery.fromJson(_delivery({'status': 'assigned'})).progressStep, 2);
      expect(Delivery.fromJson(_delivery({'status': 'delivered'})).progressStep, 4);
    });
  });

  group('Paiement intégré', () {
    test('PaymentInfo lit le paiement en ligne et ses moyens (dont la carte)', () {
      final info = PaymentInfo.fromJson({
        'merchant_name': 'S-Delivery',
        'methods': [],
        'online': {
          'enabled': true,
          'gateway': 'kkiapay',
          'simulation': false,
          'methods': [
            {'method': 'flooz', 'label': 'Flooz (Moov Africa)'},
            {'method': 'mixx', 'label': 'Mixx by Yas'},
            {'method': 'card', 'label': 'Carte bancaire'},
          ],
        },
      });

      expect(info.online.enabled, isTrue);
      expect(info.online.methods.map((m) => m.method), ['flooz', 'mixx', 'card']);
      expect(info.online.methods.last.isCard, isTrue);
      expect(info.isEmpty, isFalse);
    });

    test('sans agrégateur ni numéro marchand : aucun moyen de payer', () {
      final info = PaymentInfo.fromJson({'methods': []});
      expect(info.online.enabled, isFalse);
      expect(info.isEmpty, isTrue);
      expect(info.merchantName, 'S-Delivery');
    });

    test('checkout puis suivi du paiement jusqu\'à la confirmation', () async {
      final calls = <String>[];
      final api = ApiClient(
        httpClient: MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          if (request.method == 'POST') {
            expect(jsonDecode(request.body), {'method': 'card', 'phone': '+22890112233'});
            return http.Response(
              jsonEncode({
                'payment': {'id': 42, 'status': 'pending'},
                'mode': 'redirect',
                'message': 'Finalisez le paiement',
                'redirect_url': 'https://api/paiement/abc',
              }),
              201,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({'payment': {'id': 42, 'status': 'verified'}, 'delivery': _delivery()}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final service = DeliveryService(api);

      final started = await service.checkout(7, method: 'card', phone: '+22890112233');
      expect(started.paymentId, 42);
      expect(started.opensPage, isTrue);

      final status = await service.paymentStatus(7, 42);
      expect(status.status, 'verified');
      expect(status.delivery.isPaid, isTrue);
      expect(calls, ['POST /api/v1/deliveries/7/checkout', 'GET /api/v1/deliveries/7/payments/42']);
    });
  });

  group('Discussion de la course', () {
    test('DeliveryThread lit les messages et la possibilité d\'écrire', () {
      final thread = DeliveryThread.fromJson({
        'data': [
          {'id': 1, 'from': 'client', 'is_mine': true, 'body': 'Portail bleu', 'created_at': '2026-10-20T10:00:00+00:00'},
          {'id': 2, 'from': 'courier', 'is_mine': false, 'sender_name': 'Kossi', 'lat': 6.1, 'lng': 1.2},
          {'id': 3, 'from': 'system', 'is_mine': false, 'body': 'Colis récupéré'},
        ],
        'chat_open': true,
      });

      expect(thread.open, isTrue);
      expect(thread.messages.first.isMine, isTrue);
      expect(thread.messages[1].hasLocation, isTrue);
      expect(thread.messages[1].senderLabel, 'Livreur');
      expect(thread.messages.last.isSystem, isTrue);
    });

    test('le livreur passe par les routes /courier et envoie le code de remise', () async {
      final paths = <String>[];
      final api = ApiClient(
        httpClient: MockClient((request) async {
          paths.add('${request.method} ${request.url.path}');
          if (request.url.path.endsWith('/status')) {
            expect(jsonDecode(request.body), {'status': 'delivered', 'code': '0427'});
            return http.Response(jsonEncode({'data': _delivery({'status': 'delivered'})}), 200,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(jsonEncode({'data': [], 'chat_open': true}), 200, headers: {'content-type': 'application/json'});
        }),
      );
      final service = DeliveryService(api);

      await service.deliveryThread(7, courier: true);
      await service.deliveryThread(7);
      final d = await service.updateCourierStatus(7, 'delivered', code: '0427');

      expect(d.status, 'delivered');
      expect(paths, [
        'GET /api/v1/courier/deliveries/7/messages',
        'GET /api/v1/deliveries/7/messages',
        'POST /api/v1/courier/deliveries/7/status',
      ]);
    });
  });

  testWidgets('logo et barre de progression s\'affichent', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: const Scaffold(
        body: Column(children: [SDeliveryLogo(height: 40), ProgressSteps(step: 2)]),
      ),
    ));

    expect(find.byType(SDeliveryMark), findsOneWidget);
    expect(find.text('Delivery'), findsOneWidget);
    expect(find.byType(AnimatedContainer), findsNWidgets(4));
  });
}
