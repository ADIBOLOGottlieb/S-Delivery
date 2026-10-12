import '../models/chat.dart';
import '../models/delivery.dart';
import '../models/product.dart';
import 'api_client.dart';

/// Accès aux livraisons (client et livreur) et au catalogue.
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

  Future<PaymentInfo> paymentInfo() async =>
      PaymentInfo.fromJson(await _api.get('/payment-info') as Map<String, dynamic>);

  /// Lance un paiement via l'agrégateur (Flooz ou Mixx by Yas).
  Future<CheckoutStart> checkout({required int deliveryId, required String method, required String phone}) async =>
      CheckoutStart.fromJson(
        await _api.post('/deliveries/$deliveryId/checkout', {'method': method, 'phone': phone}) as Map<String, dynamic>,
      );

  /// Statut d'une tentative ; le serveur interroge l'agrégateur à chaque appel.
  /// Renvoie (statut de la tentative, livraison à jour).
  Future<(String, Delivery)> paymentStatus({required int deliveryId, required int paymentId}) async {
    final data = await _api.get('/deliveries/$deliveryId/payments/$paymentId') as Map<String, dynamic>;
    return (
      (data['payment'] as Map<String, dynamic>)['status'] as String,
      Delivery.fromJson(data['delivery'] as Map<String, dynamic>),
    );
  }

  /// Photo d'un article, jointe à une livraison après sa création.
  Future<Delivery> addDeliveryPhoto(int deliveryId, String filePath) async =>
      _one(await _api.postFiles('/deliveries/$deliveryId/photos', files: [('photo', filePath)]));

  // --- Demandes rapides (clients habitués) : photos + chat ----------------

  Future<List<ChatRequest>> chatRequests() async => _list(await _api.get('/requests'), ChatRequest.fromJson);

  Future<ChatRequest> chatRequest(int id) async =>
      ChatRequest.fromJson((await _api.get('/requests/$id') as Map<String, dynamic>)['data'] as Map<String, dynamic>);

  /// Programmation par photo : quartier, numéro et montant total du colis sont obligatoires.
  Future<ChatRequest> createChatRequest({
    required List<String> photoPaths,
    required String district,
    required String recipientPhone,
    required int parcelAmount,
    String? message,
  }) async {
    final data = await _api.postFiles(
      '/requests',
      fields: {
        'district': district,
        'recipient_phone': recipientPhone,
        'parcel_amount': '$parcelAmount',
        if (message != null && message.isNotEmpty) 'message': message,
      },
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

  Future<List<Product>> products({required String category, int? subcategoryId, String? type, String? search}) async =>
      _list(
        await _api.get('/products', query: {
          'category': category,
          if (subcategoryId != null) 'subcategory_id': '$subcategoryId',
          if (type != null) 'type': type,
          if (search != null && search.isNotEmpty) 'search': search,
        }),
        Product.fromJson,
      );

  /// Onglets d'une catégorie (et présence de packs).
  Future<(List<Subcategory>, bool)> subcategories(String category) async {
    final data = await _api.get('/subcategories', query: {'category': category}) as Map<String, dynamic>;
    return (
      (data['data'] as List).map((e) => Subcategory.fromJson(e as Map<String, dynamic>)).toList(),
      data['has_packs'] as bool? ?? false,
    );
  }

  Future<List<Promotion>> promotions() async => _list(await _api.get('/promotions'), Promotion.fromJson);

  /// Jeton Firebase de l'appareil (notifications push).
  Future<void> registerDeviceToken(String token) async => _api.post('/me/device-token', {'token': token});

  // --- Livreur --------------------------------------------------------------

  Future<List<Delivery>> courierDeliveries({bool history = false}) async => _list(
        await _api.get('/courier/deliveries', query: history ? {'scope': 'history'} : null),
        Delivery.fromJson,
      );

  Future<Delivery> courierDelivery(int id) async => _one(await _api.get('/courier/deliveries/$id'));

  Future<Delivery> updateCourierStatus(int id, String status) async =>
      _one(await _api.post('/courier/deliveries/$id/status', {'status': status}));
}
