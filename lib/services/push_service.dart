import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/user.dart';
import 'delivery_service.dart';

/// Ouvre l'écran correspondant aux données d'une notification (livraison, discussion…).
typedef PushOpenHandler = void Function(Map<String, dynamic> data);

/// Notifications push (Firebase Cloud Messaging, gratuit) : rappels livreur et promos client.
///
/// Si Firebase n'est pas configuré (pas de google-services.json), tout est ignoré sans erreur.
class PushService {
  static final _local = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static bool get isReady => _ready;

  /// Appelé quand l'utilisateur touche une notification (branché dans main.dart).
  static PushOpenHandler? onOpen;

  /// Notification touchée avant que l'app soit prête (lancement à froid) : ouverte par [markAppReady].
  static Map<String, dynamic>? _pending;
  static bool _appReady = false;

  static StreamSubscription<String>? _tokenRefresh;

  /// Identifiants des livraisons mises à jour (push reçu app ouverte) : les écrans ouverts se rafraîchissent.
  static final _deliveryUpdates = StreamController<int>.broadcast();
  static Stream<int> get deliveryUpdates => _deliveryUpdates.stream;

  static const _urgent = AndroidNotificationChannel(
    'voom_urgent',
    'Livraisons urgentes',
    description: 'Rappels pour les livraisons Express et les heures limites',
    importance: Importance.max,
  );
  static const _default = AndroidNotificationChannel(
    'voom_default',
    'Notifications VOOM',
    description: 'Promotions et informations',
    importance: Importance.high,
  );

  /// Identifiant de livraison contenu dans les données d'un push (null s'il n'y en a pas).
  static int? deliveryIdOf(Map<String, dynamic> data) => int.tryParse('${data['delivery_id'] ?? ''}');

  /// Identifiant de discussion contenu dans les données d'un push.
  static int? requestIdOf(Map<String, dynamic> data) => int.tryParse('${data['request_id'] ?? ''}');

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Notifications désactivées (Firebase non configuré) : $e');
      return;
    }

    try {
      final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_urgent);
      await android?.createNotificationChannel(_default);
      await _local.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        // Notification affichée par l'app (app ouverte) puis touchée.
        onDidReceiveNotificationResponse: (response) => _openPayload(response.payload),
      );

      // Application ouverte : Android n'affiche pas les notifications FCM, on les affiche nous-mêmes.
      FirebaseMessaging.onMessage.listen(_showForeground);

      // Notification touchée app en arrière-plan.
      FirebaseMessaging.onMessageOpenedApp.listen((message) => _handleOpen(message.data));

      // Notification touchée alors que l'app était fermée.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _handleOpen(initial.data);
      } else {
        final launch = await _local.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp ?? false) _openPayload(launch!.notificationResponse?.payload);
      }
    } catch (e) {
      debugPrint('Notifications partiellement initialisées : $e');
    }

    _ready = true;
  }

  static void _showForeground(RemoteMessage message) {
    final deliveryId = deliveryIdOf(message.data);
    if (deliveryId != null) _deliveryUpdates.add(deliveryId);

    final n = message.notification;
    if (n == null) return;
    final urgent = n.android?.channelId == _urgent.id;
    final channel = urgent ? _urgent : _default;
    _local.show(
      id: message.hashCode & 0x7fffffff,
      title: n.title,
      body: n.body,
      payload: message.data.isEmpty ? null : jsonEncode(message.data),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          importance: channel.importance,
          priority: urgent ? Priority.max : Priority.high,
        ),
      ),
    );
  }

  static void _openPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload);
      if (data is Map<String, dynamic>) _handleOpen(data);
    } catch (_) {}
  }

  static void _handleOpen(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    if (!_appReady || onOpen == null) {
      _pending = data;
      return;
    }
    onOpen!(data);
  }

  /// L'écran d'accueil est affiché : ouvre la notification qui a lancé l'app, le cas échéant.
  static void markAppReady() {
    _appReady = true;
    final pending = _pending;
    _pending = null;
    if (pending != null) onOpen?.call(pending);
  }

  /// Après connexion : autorisation, envoi du jeton au serveur et abonnement aux annonces.
  static Future<void> register(User user, DeliveryService deliveries) async {
    if (!_ready) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) await deliveries.registerDeviceToken(token);
      await _tokenRefresh?.cancel();
      _tokenRefresh =
          messaging.onTokenRefresh.listen((t) => deliveries.registerDeviceToken(t).catchError((_) {}));

      if (user.isCourier) {
        await messaging.subscribeToTopic('couriers');
        await messaging.unsubscribeFromTopic('clients');
      } else {
        await messaging.subscribeToTopic('clients');
        await messaging.unsubscribeFromTopic('couriers');
      }
    } catch (e) {
      debugPrint('Enregistrement des notifications impossible : $e');
    }
  }

  /// Déconnexion : plus d'annonces pour ce compte sur cet appareil.
  static Future<void> unregister() async {
    if (!_ready) return;
    try {
      await _tokenRefresh?.cancel();
      _tokenRefresh = null;
      await FirebaseMessaging.instance.unsubscribeFromTopic('clients');
      await FirebaseMessaging.instance.unsubscribeFromTopic('couriers');
    } catch (_) {}
  }
}
