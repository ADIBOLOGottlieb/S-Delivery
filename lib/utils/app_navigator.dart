import 'package:flutter/material.dart';

/// Navigateur racine de l'application : utilisé hors des écrans
/// (session expirée, ouverture d'une notification push).
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Messages (SnackBar) affichés hors des écrans, ex. « Session expirée ».
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Livraisons / discussions actuellement affichées (la dernière ouverte en fin de liste),
/// pour ne pas empiler un doublon quand une notification vise l'écran déjà ouvert.
class ShownScreens {
  static final _keys = <String>[];

  static String deliveryKey(int id) => 'delivery:$id';
  static String chatKey(int id) => 'chat:$id';
  static String deliveryChatKey(int id) => 'delivery-chat:$id';

  static void enter(String key) => _keys.add(key);
  static void leave(String key) => _keys.remove(key);

  /// Écran de ce type le plus récemment ouvert (encore affiché).
  static String? get top => _keys.isEmpty ? null : _keys.last;
}
