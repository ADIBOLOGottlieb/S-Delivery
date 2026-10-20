/// Moyen de paiement par virement au numéro marchand (mode manuel, preuve par capture d'écran).
class PaymentMethodInfo {
  final String method;
  final String label;
  final String merchantNumber;

  const PaymentMethodInfo({required this.method, required this.label, required this.merchantNumber});

  factory PaymentMethodInfo.fromJson(Map<String, dynamic> json) => PaymentMethodInfo(
        method: json['method'] as String,
        label: json['label'] as String,
        merchantNumber: json['merchant_number'] as String,
      );
}

/// Moyen payable directement dans l'app (Flooz, Mixx by Yas, carte bancaire selon l'agrégateur).
class OnlineMethod {
  final String method;
  final String label;

  const OnlineMethod({required this.method, required this.label});

  bool get isCard => method == 'card';

  factory OnlineMethod.fromJson(Map<String, dynamic> json) =>
      OnlineMethod(method: json['method'] as String, label: json['label'] as String);
}

/// Paiement intégré : actif quand l'agence a configuré un agrégateur (ou le mode simulation).
class OnlinePayment {
  final bool enabled;
  final String? gateway;
  final bool simulation;
  final List<OnlineMethod> methods;

  const OnlinePayment({this.enabled = false, this.gateway, this.simulation = false, this.methods = const []});

  static const disabled = OnlinePayment();

  factory OnlinePayment.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return disabled;
    return OnlinePayment(
      enabled: json['enabled'] as bool? ?? false,
      gateway: json['gateway'] as String?,
      simulation: json['simulation'] as bool? ?? false,
      methods: (json['methods'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(OnlineMethod.fromJson)
          .toList(),
    );
  }
}

/// Moyens de paiement, numéro de l'agence et liens publics (GET /payment-info).
class PaymentInfo {
  final String merchantName;
  final String? instructions;

  /// Numéros marchands pour le virement manuel.
  final List<PaymentMethodInfo> methods;
  final OnlinePayment online;

  /// Numéro de l'agence (null tant que l'admin ne l'a pas renseigné).
  final String? supportPhone;

  /// Pages publiques (URL absolues) ; null si le serveur ne les fournit pas encore.
  final String? privacyUrl;
  final String? accountDeletionUrl;

  const PaymentInfo({
    required this.merchantName,
    this.instructions,
    required this.methods,
    this.online = OnlinePayment.disabled,
    this.supportPhone,
    this.privacyUrl,
    this.accountDeletionUrl,
  });

  /// Aucun moyen de payer depuis l'app (ni en ligne, ni numéro marchand).
  bool get isEmpty => !online.enabled && methods.isEmpty;

  factory PaymentInfo.fromJson(Map<String, dynamic> json) {
    String? text(String key) {
      final value = json[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    return PaymentInfo(
      merchantName: json['merchant_name'] as String? ?? 'S-Delivery',
      instructions: json['instructions'] as String?,
      methods: (json['methods'] as List? ?? const [])
          .map((m) => PaymentMethodInfo.fromJson(m as Map<String, dynamic>))
          .toList(),
      online: OnlinePayment.fromJson(json['online']),
      supportPhone: text('support_phone'),
      privacyUrl: text('privacy_url'),
      accountDeletionUrl: text('account_deletion_url'),
    );
  }
}

/// Paiement en ligne démarré (POST /deliveries/{id}/checkout).
class CheckoutResult {
  final int paymentId;
  final String status;

  /// ussd : demande envoyée sur le téléphone ; redirect : page de paiement sécurisée à ouvrir.
  final String mode;
  final String message;
  final String? redirectUrl;

  const CheckoutResult({
    required this.paymentId,
    required this.status,
    required this.mode,
    required this.message,
    this.redirectUrl,
  });

  bool get opensPage => mode == 'redirect' && redirectUrl != null;

  factory CheckoutResult.fromJson(Map<String, dynamic> json) {
    final payment = json['payment'] as Map<String, dynamic>;
    return CheckoutResult(
      paymentId: payment['id'] as int,
      status: payment['status'] as String? ?? 'pending',
      mode: json['mode'] as String? ?? 'ussd',
      message: json['message'] as String? ?? '',
      redirectUrl: json['redirect_url'] as String?,
    );
  }
}
