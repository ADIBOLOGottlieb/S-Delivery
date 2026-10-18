/// Configuration de l'API backend (Laravel).
///
/// Surchargeable au lancement :
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api/v1
///
/// Par défaut : l'API Render en release, sinon 10.0.2.2 (la machine hôte vue depuis l'émulateur Android).
class ApiConfig {
  static const String productionUrl = 'https://voom-delivery-api.onrender.com/api/v1';

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: bool.fromEnvironment('dart.vm.product') ? productionUrl : 'http://10.0.2.2:8000/api/v1',
  );

  /// Racine du serveur (sans /api/v1), pour l'URL de santé /up.
  static String get serverRoot => baseUrl.replaceFirst(RegExp(r'/api/v\d+/?$'), '');

  /// Large : le serveur Render gratuit peut mettre 30 à 60 s à sortir de veille.
  static const Duration timeout = Duration(seconds: 60);

  /// Pages publiques par défaut (si GET /payment-info ne fournit pas privacy_url / account_deletion_url).
  static String get privacyUrl => '$serverRoot/confidentialite';
  static String get accountDeletionUrl => '$serverRoot/compte/suppression';
}
