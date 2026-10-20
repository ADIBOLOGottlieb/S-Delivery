import '../models/chat.dart';
import '../models/delivery.dart';
import '../models/delivery_message.dart';
import '../models/payment.dart';
import 'api_client.dart';

/// Accès aux livraisons (client et livreur) : création, paiement, suivi, discussion.
class DeliveryService {
  DeliveryService(this._api);

  final ApiClient _api;

  List<T> _list<T>(dynamic response, T Function(Map<String, dynamic>) parse) =>
      ((response as Map<String, dynamic>)['data'] as List).map((e) => parse(e as Map<String, dynamic>)).toList();

  Delivery _one(dynamic response) =>
      Delivery.fromJson((response as Map<String, dynamic>)['data'] as Map<String, dynamic>);

  // --- Client ---------------------------------------------------------------

  Future<List<Delivery>> myDeliveries() async => _list(await _api.get('/deliveries'), Delivery.fromJson);

  Future<Delivery> getDelivery(int id) async => _one(await _api.get('/deliveries/$id'));

  Future<DeliveryQuote> quote({
    required DeliveryType type,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
  }) async {
    final data = await _api.post('/deliveries/quote', {
      'type': type.value,
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'dropoff_lat': dropoffLat,
      'dropoff_lng': dropoffLng,
    });
    return DeliveryQuote.fromJson(data as Map<String, dynamic>);
  }

  Future<Delivery> createDelivery(Map<String, dynamic> payload) async => _one(await _api.post('/deliveries', payload));

  Future<Delivery> cancelDelivery(int id) async => _one(await _api.post('/deliveries/$id/cancel'));

  /// Note du livreur (1 à 5) après la livraison.
  Future<Delivery> rateDelivery(int id, {required int rating, String? comment}) async => _one(await _api.post(
        '/deliveries/$id/rating',
        {'rating': rating, if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim()},
      ));

  /// Photo d'un article, jointe à une livraison après sa création.
  Future<Delivery> addDeliveryPhoto(int deliveryId, String filePath) async =>
      _one(await _api.postFiles('/deliveries/$deliveryId/photos', files: [('photo', filePath)]));

  // --- Paiement ---------------------------------------------------------------

  Future<PaymentInfo> paymentInfo() async =>
      PaymentInfo.fromJson(await _api.get('/payment-info') as Map<String, dynamic>);

  /// Paiement intégré : demande poussée sur le téléphone (PayGate) ou page sécurisée (KKiaPay).
  Future<CheckoutResult> checkout(int deliveryId, {required String method, required String phone}) async =>
      CheckoutResult.fromJson(
        await _api.post('/deliveries/$deliveryId/checkout', {'method': method, 'phone': phone}) as Map<String, dynamic>,
      );

  /// Interrogé pendant que le client valide le paiement : statut du paiement et livraison à jour.
  Future<({String status, Delivery delivery})> paymentStatus(int deliveryId, int paymentId) async {
    final data = await _api.get('/deliveries/$deliveryId/payments/$paymentId') as Map<String, dynamic>;
    return (
      status: (data['payment'] as Map<String, dynamic>)['status'] as String,
      delivery: Delivery.fromJson(data['delivery'] as Map<String, dynamic>),
    );
  }

  /// Paiement manuel : virement au numéro marchand puis capture d'écran vérifiée par l'agence.
  Future<Delivery> submitPayment({
    required int deliveryId,
    required String method,
    required String transactionRef,
    required String payerPhone,
    required String screenshotPath,
  }) async {
    return _one(await _api.postMultipart(
      '/deliveries/$deliveryId/payment',
      fields: {'method': method, 'transaction_ref': transactionRef, 'payer_phone': payerPhone},
      fileField: 'screenshot',
      filePath: screenshotPath,
    ));
  }

  // --- Discussion de la course (client ↔ livreur ↔ agence) -------------------------

  String _messagesPath(int deliveryId, {required bool courier}) =>
      courier ? '/courier/deliveries/$deliveryId/messages' : '/deliveries/$deliveryId/messages';

  Future<DeliveryThread> deliveryThread(int deliveryId, {bool courier = false}) async => DeliveryThread.fromJson(
        await _api.get(_messagesPath(deliveryId, courier: courier)) as Map<String, dynamic>,
      );

  /// Texte, photo ou position partagée.
  Future<DeliveryMessage> sendDeliveryMessage(
    int deliveryId, {
    bool courier = false,
    String? body,
    String? photoPath,
    double? lat,
    double? lng,
  }) async {
    final data = await _api.postFiles(
      _messagesPath(deliveryId, courier: courier),
      fields: {
        if (body != null && body.isNotEmpty) 'body': body,
        if (lat != null) 'lat': '$lat',
        if (lng != null) 'lng': '$lng',
      },
      files: [if (photoPath != null) ('photo', photoPath)],
    );
    return DeliveryMessage.fromJson((data as Map<String, dynamic>)['data'] as Map<String, dynamic>);
  }

  // --- Demandes rapides (programmation par photo) : photos + chat avec l'agence ---------

  Future<List<ChatRequest>> chatRequests() async => _list(await _api.get('/requests'), ChatRequest.fromJson);

  Future<ChatRequest> chatRequest(int id) async =>
      ChatRequest.fromJson((await _api.get('/requests/$id') as Map<String, dynamic>)['data'] as Map<String, dynamic>);

  /// Programmation par photo : la photo du colis suffit, l'agence complète le reste.
  Future<ChatRequest> createChatRequest({required List<String> photoPaths, String? message}) async {
    final data = await _api.postFiles(
      '/requests',
      fields: {if (message != null && message.isNotEmpty) 'message': message},
      files: [for (final p in photoPaths) ('photos[]', p)],
    );
    return ChatRequest.fromJson((data as Map<String, dynamic>)['data'] as Map<String, dynamic>);
  }

  /// Texte, photo ou position partagée.
  Future<ChatMessage> sendChatMessage(int requestId, {String? body, String? photoPath, double? lat, double? lng}) async {
    final data = await _api.postFiles(
      '/requests/$requestId/messages',
      fields: {
        if (body != null && body.isNotEmpty) 'body': body,
        if (lat != null) 'lat': '$lat',
        if (lng != null) 'lng': '$lng',
      },
      files: [if (photoPath != null) ('photo', photoPath)],
    );
    return ChatMessage.fromJson((data as Map<String, dynamic>)['data'] as Map<String, dynamic>);
  }

  /// Jeton Firebase de l'appareil (notifications push).
  Future<void> registerDeviceToken(String token) async => _api.post('/me/device-token', {'token': token});

  // --- Livreur --------------------------------------------------------------

  Future<List<Delivery>> courierDeliveries({bool history = false}) async => _list(
        await _api.get('/courier/deliveries', query: history ? {'scope': 'history'} : null),
        Delivery.fromJson,
      );

  Future<Delivery> courierDelivery(int id) async => _one(await _api.get('/courier/deliveries/$id'));

  /// [code] : code de remise donné par le destinataire, exigé pour clôturer la course.
  Future<Delivery> updateCourierStatus(int id, String status, {String? code}) async => _one(await _api.post(
        '/courier/deliveries/$id/status',
        {'status': status, if (code != null) 'code': code},
      ));

  /// Position du livreur, partagée au client pendant la course.
  Future<void> shareCourierLocation(double lat, double lng) async =>
      _api.post('/courier/location', {'lat': lat, 'lng': lng});
}
