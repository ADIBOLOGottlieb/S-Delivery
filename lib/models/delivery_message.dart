/// Message de la discussion d'une course (client, livreur, agence) : texte, photo ou position.
class DeliveryMessage {
  final int id;

  /// client | courier | agency | system
  final String from;
  final bool isMine;
  final String? senderName;
  final String? body;
  final String? photoUrl;
  final double? lat;
  final double? lng;
  final DateTime createdAt;

  const DeliveryMessage({
    required this.id,
    required this.from,
    required this.isMine,
    this.senderName,
    this.body,
    this.photoUrl,
    this.lat,
    this.lng,
    required this.createdAt,
  });

  bool get isSystem => from == 'system';
  bool get hasLocation => lat != null && lng != null;

  /// Libellé de l'auteur affiché au-dessus des bulles des autres participants.
  String get senderLabel => switch (from) {
        'courier' => 'Livreur',
        'agency' => 'Agence S-Delivery',
        'client' => 'Client',
        _ => '',
      };

  factory DeliveryMessage.fromJson(Map<String, dynamic> json) => DeliveryMessage(
        id: json['id'] as int,
        from: json['from'] as String? ?? 'system',
        isMine: json['is_mine'] as bool? ?? false,
        senderName: json['sender_name'] as String?,
        body: json['body'] as String?,
        photoUrl: json['photo_url'] as String?,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        createdAt: json['created_at'] == null ? DateTime.now() : DateTime.parse(json['created_at'] as String).toLocal(),
      );
}

/// Discussion d'une course : messages et possibilité d'écrire.
class DeliveryThread {
  final List<DeliveryMessage> messages;
  final bool open;

  const DeliveryThread({required this.messages, required this.open});

  factory DeliveryThread.fromJson(Map<String, dynamic> json) => DeliveryThread(
        messages: (json['data'] as List? ?? const [])
            .map((e) => DeliveryMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
        open: json['chat_open'] as bool? ?? false,
      );
}
