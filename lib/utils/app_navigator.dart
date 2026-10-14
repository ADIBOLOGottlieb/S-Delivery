import 'package:flutter/material.dart';

/// Navigateur racine de l'application : utilisé hors des écrans
/// (session expirée, ouverture d'une notification push).
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Messages (SnackBar) affichés hors des écrans, ex. « Session expirée ».
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();
