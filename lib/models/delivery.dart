import 'package:latlong2/latlong.dart';

/// Types de livraison proposés (valeurs identiques au backend).
enum DeliveryType {
  plis('plis', 'Plis'),
  colis('colis', 'Colis'),
  express('express', 'Express'),
  programmee('programmee', 'Programmée');

  const DeliveryType(this.value, this.label);
  final String value;
  final String label;

  static DeliveryType fromValue(String value) =>
      values.firstWhere((t) => t.value == value, orElse: () => DeliveryType.colis);
}

class DeliveryStatus {
  static const pending = 'pending';
  static const assigned = 'assigned';
  static const pickedUp = 'picked_up';
  static const delivered = 'delivered';
  static const cancelled = 'cancelled';
}

class PaymentStatus {
  static const unpaid = 'unpaid';
  static const submitted = 'submitted';
  static const verified = 'verified';
  static const rejected = 'rejected';
}

/// Point A (récupération) ou point B (destination).
class DeliveryPoint {
  final String address;
  final double lat;
  final double lng;
  final String? contactName;
  final String? contactPhone;

  const DeliveryPoint({
    required this.address,
    required this.lat,
    required this.lng,
    this.contactName,
    this.contactPhone,
  });

  LatLng get latLng => LatLng(lat, lng);

  factory DeliveryPoint.fromJson(Map<String, dynamic> json) => DeliveryPoint(
        address: json['address'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        contactName: _text(json['contact_name']),
        contactPhone: _text(json['contact_phone']),
      );

  /// Contact absent ou vide (ex. commande produit sans téléphone vendeur) : null, pas de bouton « Appeler » cassé.
  static String? _text(dynamic value) {
    final text = (value as String?)?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class PaymentProof {
  final String method;
  final String methodLabel;

  /// Absente pour un paiement passé par une passerelle (ou pas encore renseignée).
  final String? transactionRef;
  final int amount;
  final String status;
  final String statusLabel;
  final String? rejectionReason;

  const PaymentProof({
    required this.method,
    required this.methodLabel,
    this.transactionRef,
    required this.amount,
    required this.status,
    required this.statusLabel,
    this.rejectionReason,
  });

  factory PaymentProof.fromJson(Map<String, dynamic> json) => PaymentProof(
        method: json['method'] as String? ?? '',
        methodLabel: json['method_label'] as String? ?? '',
        transactionRef: json['transaction_ref'] as String?,
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? PaymentStatus.submitted,
        statusLabel: json['status_label'] as String? ?? '',
        rejectionReason: json['rejection_reason'] as String?,
      );
}

class Person {
  final String name;
  final String? phoneNumber;
  final String? vehicle;

  const Person({required this.name, this.phoneNumber, this.vehicle});

  static Person? fromJson(dynamic json) => json is Map<String, dynamic>
      ? Person(
          name: json['name'] as String? ?? '',
          phoneNumber: json['phone_number'] as String?,
          vehicle: json['vehicle'] as String?,
        )
      : null;
}

class Delivery {
  final int id;
  final String reference;
  final DeliveryType type;
  final String status;
  final String statusLabel;
  final String paymentStatus;
  final String paymentStatusLabel;
  final DeliveryPoint pickup;
  final DeliveryPoint dropoff;
  final String? packageDescription;
  final String? notes;
  final DateTime? scheduledAt;

  /// Heure limite de livraison choisie par le client.
  final DateTime? deadlineAt;

  /// Express ou heure limite proche : mise en avant pour le livreur.
  final bool isUrgent;
  final double distanceKm;
  final int deliveryFee;
  final int itemsAmount;
  final int totalAmount;

  /// Montant à encaisser auprès du destinataire (null : rien à encaisser).
  final int? parcelAmount;
  final Person? client;
  final Person? courier;
  final PaymentProof? latestPayment;
  final bool canPay;
  final bool canCancel;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final String? cancelReason;

  /// Photos des articles (URL publiques), visibles par le livreur.
  final List<String> photos;

  /// Discussion (demande rapide) à l'origine de la livraison, le cas échéant.
  final int? requestId;

  const Delivery({
    required this.id,
    required this.reference,
    required this.type,
    required this.status,
    required this.statusLabel,
    required this.paymentStatus,
    required this.paymentStatusLabel,
    required this.pickup,
    required this.dropoff,
    this.packageDescription,
    this.notes,
    this.scheduledAt,
    this.deadlineAt,
    this.isUrgent = false,
    required this.distanceKm,
    required this.deliveryFee,
    required this.itemsAmount,
    required this.totalAmount,
    this.parcelAmount,
    this.client,
    this.courier,
    this.latestPayment,
    required this.canPay,
    required this.canCancel,
    required this.createdAt,
    this.deliveredAt,
    this.cancelReason,
    this.photos = const [],
    this.requestId,
  });

  bool get isActive => status != DeliveryStatus.delivered && status != DeliveryStatus.cancelled;

  /// Le serveur accepte encore des photos tant que le colis n'est pas récupéré.
  bool get acceptsPhotos => status == DeliveryStatus.pending || status == DeliveryStatus.assigned;

  static DateTime? _date(dynamic value) => value == null ? null : DateTime.parse(value as String).toLocal();

  factory Delivery.fromJson(Map<String, dynamic> json) => Delivery(
        id: json['id'] as int,
        reference: json['reference'] as String,
        type: DeliveryType.fromValue(json['type'] as String),
        status: json['status'] as String,
        statusLabel: json['status_label'] as String,
        paymentStatus: json['payment_status'] as String,
        paymentStatusLabel: json['payment_status_label'] as String,
        pickup: DeliveryPoint.fromJson(json['pickup'] as Map<String, dynamic>),
        dropoff: DeliveryPoint.fromJson(json['dropoff'] as Map<String, dynamic>),
        packageDescription: json['package_description'] as String?,
        notes: json['notes'] as String?,
        scheduledAt: _date(json['scheduled_at']),
        deadlineAt: _date(json['deadline_at']),
        isUrgent: json['is_urgent'] as bool? ?? false,
        distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
        deliveryFee: (json['delivery_fee'] as num?)?.toInt() ?? 0,
        itemsAmount: (json['items_amount'] as num?)?.toInt() ?? 0,
        totalAmount: (json['total_amount'] as num?)?.toInt() ?? 0,
        parcelAmount: (json['parcel_amount'] as num?)?.toInt(),
        client: Person.fromJson(json['client']),
        courier: Person.fromJson(json['courier']),
        latestPayment: json['latest_payment'] is Map<String, dynamic>
            ? PaymentProof.fromJson(json['latest_payment'] as Map<String, dynamic>)
            : null,
        canPay: json['can_pay'] as bool? ?? false,
        canCancel: json['can_cancel'] as bool? ?? false,
        createdAt: _date(json['created_at']) ?? DateTime.now(),
        deliveredAt: _date(json['delivered_at']),
        cancelReason: json['cancel_reason'] as String?,
        photos: (json['photos'] as List? ?? const []).whereType<String>().toList(),
        requestId: json['request_id'] as int?,
      );
}

/// Devis renvoyé par POST /deliveries/quote.
class DeliveryQuote {
  final double distanceKm;
  final int deliveryFee;

  const DeliveryQuote({required this.distanceKm, required this.deliveryFee});

  factory DeliveryQuote.fromJson(Map<String, dynamic> json) => DeliveryQuote(
        distanceKm: (json['distance_km'] as num).toDouble(),
        deliveryFee: json['delivery_fee'] as int,
      );
}
