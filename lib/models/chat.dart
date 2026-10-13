/// Demande rapide (programmation par photo) : photos des articles + discussion avec l'agence.
class ChatRequest {
  final int id;
  final String reference;
  final String status;
  final String statusLabel;
  final int unread;
  final ChatMessage? lastMessage;
  final List<ChatMessage> messages;
  final ScheduledDelivery? delivery;
  final DateTime? lastMessageAt;

  /// Éléments obligatoires de la programmation par photo.
  final String? district;
  final String? recipientPhone;
  final int? parcelAmount;

  const ChatRequest({
    this.district,
    this.recipientPhone,
    this.parcelAmount,
    required this.id,
    required this.reference,
    required this.status,
    required this.statusLabel,
    this.unread = 0,
    this.lastMessage,
    this.messages = const [],
    this.delivery,
    this.lastMessageAt,
  });

  bool get isOpen => status == 'open';

  factory ChatRequest.fromJson(Map<String, dynamic> json) => ChatRequest(
        id: json['id'] as int,
        reference: json['reference'] as String,
        status: json['status'] as String,
        statusLabel: json['status_label'] as String,
        unread: json['unread'] as int? ?? 0,
        lastMessage: json['last_message'] is Map<String, dynamic>
            ? ChatMessage.fromJson(json['last_message'] as Map<String, dynamic>)
            : null,
        messages: (json['messages'] as List? ?? const [])
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
        delivery: json['delivery'] is Map<String, dynamic>
            ? ScheduledDelivery.fromJson(json['delivery'] as Map<String, dynamic>)
            : null,
        lastMessageAt:
            json['last_message_at'] == null ? null : DateTime.parse(json['last_message_at'] as String).toLocal(),
        district: json['district'] as String?,
        recipientPhone: json['recipient_phone'] as String?,
        parcelAmount: json['parcel_amount'] as int?,
      );
}

/// Livraison créée par l'agence à partir de la discussion.
class ScheduledDelivery {
  final int id;
  final String reference;
  final String statusLabel;
  final int totalAmount;
  final bool canPay;

  const ScheduledDelivery({
    required this.id,
    required this.reference,
    required this.statusLabel,
    required this.totalAmount,
    required this.canPay,
  });

  factory ScheduledDelivery.fromJson(Map<String, dynamic> json) => ScheduledDelivery(
        id: json['id'] as int,
        reference: json['reference'] as String,
        statusLabel: json['status_label'] as String,
        totalAmount: json['total_amount'] as int,
        canPay: json['can_pay'] as bool? ?? false,
      );
}

class ChatMessage {
  final int id;

  /// client | agency | system
  final String from;
  final String? body;
  final String? photoUrl;
  final double? lat;
  final double? lng;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.from,
    this.body,
    this.photoUrl,
    this.lat,
    this.lng,
    required this.createdAt,
  });

  bool get isMine => from == 'client';
  bool get isSystem => from == 'system';
  bool get hasLocation => lat != null && lng != null;

  /// Aperçu d'une ligne pour la liste des discussions.
  String get preview => photoUrl != null
      ? '📷 Photo'
      : hasLocation
          ? '📍 Position'
          : (body ?? '');

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as int,
        from: json['from'] as String,
        body: json['body'] as String?,
        photoUrl: json['photo_url'] as String?,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
}
