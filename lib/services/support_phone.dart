import '../config/api_config.dart';
import '../models/product.dart';
import 'api_client.dart';

/// Numéro de l'agence et liens publics, lus depuis GET /payment-info (renseignés par l'admin).
class SupportPhone {
  static PaymentInfo? _info;

  static Future<PaymentInfo?> _load(ApiClient api) async {
    // Numéro absent : on relit à la prochaine demande (l'admin a pu le renseigner depuis).
    if (_info?.supportPhone != null) return _info;
    try {
      return _info = PaymentInfo.fromJson(await api.get('/payment-info') as Map<String, dynamic>);
    } catch (_) {
      return _info;
    }
  }

  /// Numéro réel de l'agence, ou null s'il n'est pas (encore) configuré ou si le serveur est injoignable.
  static Future<String?> load(ApiClient api) async => (await _load(api))?.supportPhone;

  /// Politique de confidentialité (URL du serveur, sinon page par défaut).
  static Future<String> privacyUrl(ApiClient api) async =>
      (await _load(api))?.privacyUrl ?? ApiConfig.privacyUrl;

  /// Page web de demande de suppression de compte.
  static Future<String> accountDeletionUrl(ApiClient api) async =>
      (await _load(api))?.accountDeletionUrl ?? ApiConfig.accountDeletionUrl;
}
