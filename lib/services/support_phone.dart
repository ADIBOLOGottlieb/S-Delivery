import '../models/product.dart';
import 'api_client.dart';

/// Numéro de l'agence, lu depuis GET /payment-info (champ support_phone, renseigné par l'admin).
class SupportPhone {
  static String? _cached;

  /// Numéro réel de l'agence, ou null s'il n'est pas (encore) configuré ou si le serveur est injoignable.
  static Future<String?> load(ApiClient api) async {
    if (_cached != null) return _cached;
    try {
      final info = PaymentInfo.fromJson(await api.get('/payment-info') as Map<String, dynamic>);
      return _cached = info.supportPhone;
    } catch (_) {
      return null;
    }
  }
}
