import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/push_service.dart';
import '../utils/app_navigator.dart';
import '../utils/colors.dart';
import 'auth/login_screen.dart';
import 'chat/chat_screen.dart';
import 'chat/delivery_chat_screen.dart';
import 'courier/courier_delivery_screen.dart';
import 'home/delivery_detail_screen.dart';
import 'splash_screen.dart';

/// Ouvre l'écran visé par une notification touchée :
/// livraison (client ou livreur selon le rôle) ou discussion avec l'agence.
void openFromNotification(Map<String, dynamic> data) {
  final navigator = appNavigatorKey.currentState;
  final context = appNavigatorKey.currentContext;
  if (navigator == null || context == null) {
    PushService.keepPending(data);
    return;
  }
  final auth = Provider.of<AuthService>(context, listen: false);
  // Personne n'est connecté : la notification sera ouverte après la connexion.
  if (!auth.isAuthenticated) {
    PushService.keepPending(data);
    return;
  }
  final courier = auth.user!.isCourier;

  final type = data['type']?.toString();
  final deliveryId = PushService.deliveryIdOf(data);
  final requestId = PushService.requestIdOf(data);

  if (type == 'chat' && requestId != null && !courier) {
    // Discussion déjà affichée : on la recharge au lieu d'empiler un doublon.
    if (ShownScreens.top == ShownScreens.chatKey(requestId)) {
      PushService.notifyChatUpdated(requestId);
      return;
    }
    navigator.push(MaterialPageRoute(builder: (_) => ChatScreen(requestId: requestId)));
  } else if (type == 'delivery_chat' && deliveryId != null) {
    // Message du livreur, du client ou de l'agence : discussion de la course.
    if (ShownScreens.top == ShownScreens.deliveryChatKey(deliveryId)) {
      PushService.notifyDeliveryChatUpdated(deliveryId);
      return;
    }
    navigator.push(MaterialPageRoute(builder: (_) => DeliveryChatScreen(deliveryId: deliveryId, courier: courier)));
  } else if (deliveryId != null && (type == null || type == 'delivery')) {
    if (ShownScreens.top == ShownScreens.deliveryKey(deliveryId)) {
      PushService.notifyDeliveryUpdated(deliveryId);
      return;
    }
    navigator.push(MaterialPageRoute(
      builder: (_) =>
          courier ? CourierDeliveryScreen(deliveryId: deliveryId) : DeliveryDetailScreen(deliveryId: deliveryId),
    ));
  }
  // Autres notifications : l'app s'ouvre simplement sur l'accueil.
}

/// Renvoie à la connexion quand la session expire (401) sans déconnexion volontaire,
/// et vers le bon accueil quand l'admin change le rôle du compte (client ↔ livreur).
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
    if (_auth.consumeRoleChanged() && _auth.isAuthenticated) {
      appNavigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => SplashScreen.homeFor(_auth)),
        (_) => false,
      );
      _showMessage('Votre compte a été modifié par l\'agence : espace ${_auth.user!.roleLabel.toLowerCase()}.');
      return;
    }
    if (!_auth.consumeSessionExpired()) return;
    appNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
    _showMessage('Session expirée, reconnectez-vous.', error: true);
  }

  void _showMessage(String text, {bool error = false}) {
    appMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.error : null,
      ));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
