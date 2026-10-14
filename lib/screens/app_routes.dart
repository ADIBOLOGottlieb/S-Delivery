import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/push_service.dart';
import '../utils/app_navigator.dart';
import '../utils/colors.dart';
import 'auth/login_screen.dart';
import 'chat/chat_screen.dart';
import 'courier/courier_delivery_screen.dart';
import 'home/delivery_detail_screen.dart';

/// Ouvre l'écran visé par une notification touchée :
/// livraison (client ou livreur selon le rôle) ou discussion avec l'agence.
void openFromNotification(Map<String, dynamic> data) {
  final navigator = appNavigatorKey.currentState;
  final context = appNavigatorKey.currentContext;
  if (navigator == null || context == null) return;
  final auth = Provider.of<AuthService>(context, listen: false);
  if (!auth.isAuthenticated) return;
  final courier = auth.user!.isCourier;

  final type = data['type']?.toString();
  final deliveryId = PushService.deliveryIdOf(data);
  final requestId = PushService.requestIdOf(data);

  if (type == 'chat' && requestId != null && !courier) {
    navigator.push(MaterialPageRoute(builder: (_) => ChatScreen(requestId: requestId)));
  } else if (deliveryId != null && (type == null || type == 'delivery')) {
    navigator.push(MaterialPageRoute(
      builder: (_) =>
          courier ? CourierDeliveryScreen(deliveryId: deliveryId) : DeliveryDetailScreen(deliveryId: deliveryId),
    ));
  }
  // Promotions : l'app s'ouvre simplement sur l'accueil.
}

/// Renvoie à la connexion quand la session expire (401) sans déconnexion volontaire.
class SessionGuard extends StatefulWidget {
  final Widget child;

  const SessionGuard({super.key, required this.child});

  @override
  State<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends State<SessionGuard> {
  late final AuthService _auth = context.read<AuthService>();

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!_auth.consumeSessionExpired()) return;
    appNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
    appMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Session expirée, reconnectez-vous.'),
        backgroundColor: AppColors.error,
      ));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
