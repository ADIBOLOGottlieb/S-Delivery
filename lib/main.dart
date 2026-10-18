import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'screens/app_routes.dart';
import 'screens/splash_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/delivery_service.dart';
import 'services/paged_api.dart';
import 'services/push_service.dart';
import 'utils/app_navigator.dart';
import 'utils/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorHandlers();
  await initializeDateFormatting('fr');
  final api = ApiClient();
  // Réveille le serveur pendant l'écran de démarrage (l'hébergement gratuit se met en veille).
  unawaited(api.warmUp());
  // Notifications push (ignorées si Firebase n'est pas configuré) ; un appui ouvre la livraison ou la discussion.
  PushService.onOpen = openFromNotification;
  unawaited(PushService.init());
  runApp(VoomDeliveryApp(api: api));
}

/// Erreurs non rattrapées : journalisées au lieu de faire planter l'app ; en release, un petit message
/// remplace l'écran gris d'un widget en erreur.
void _installErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Erreur Flutter : ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Erreur non rattrapée : $error\n$stack');
    return true;
  };
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => const Material(
          color: Colors.transparent,
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Un problème est survenu',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF757575), fontSize: 14),
              ),
            ),
          ),
        );
  }
}

class VoomDeliveryApp extends StatelessWidget {
  final ApiClient api;
  final AuthService? authService;

  const VoomDeliveryApp({super.key, required this.api, this.authService});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        Provider<DeliveryService>(create: (_) => DeliveryService(api)),
        Provider<PagedApi>(create: (_) => PagedApi(api)),
        ChangeNotifierProvider<AuthService>(create: (_) => authService ?? AuthService(api)),
      ],
      child: MaterialApp(
        title: 'VOOM Delivery',
        theme: AppTheme.lightTheme,
        navigatorKey: appNavigatorKey,
        scaffoldMessengerKey: appMessengerKey,
        // Session expirée (401) : retour à la connexion depuis n'importe quel écran.
        builder: (context, child) => SessionGuard(child: child ?? const SizedBox.shrink()),
        home: const SplashScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
