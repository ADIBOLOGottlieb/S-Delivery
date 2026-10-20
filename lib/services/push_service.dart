import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/user.dart';
import 'api_client.dart';
import 'delivery_service.dart';

/// Ouvre l'écran correspondant aux données d'une notification (livraison, discussion…).
typedef PushOpenHandler = void Function(Map<String, dynamic> data);

/// Notifications push (Firebase Cloud Messaging, gratuit) : suivi des courses, messages et rappels livreur.
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

  /// Identifiants des discussions ayant reçu un message (push reçu app ouverte) : badges et chat se rafraîchissent.
  static final _chatUpdates = StreamController<int>.broadcast();
  static Stream<int> get chatUpdates => _chatUpdates.stream;

  /// Identifiants des livraisons dont la discussion a reçu un message (client, livreur ou agence).
  static final _deliveryChatUpdates = StreamController<int>.broadcast();
  static Stream<int> get deliveryChatUpdates => _deliveryChatUpdates.stream;

  static const _urgent = AndroidNotificationChannel(
    'voom_urgent',
    'Livraisons urgentes',
    description: 'Rappels pour les livraisons Express et les heures limites',
    importance: Importance.max,
  );
  // Identifiants de canaux inchangés : les téléphones déjà installés gardent leurs réglages de notification.
  static const _default = AndroidNotificationChannel(
    'voom_default',
    'Livraisons et messages',
    description: 'Suivi de vos courses et messages du livreur ou de l\'agence',
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
    if (deliveryId != null && message.data['type']?.toString() == 'delivery_chat') _deliveryChatUpdates.add(deliveryId);
    final requestId = requestIdOf(message.data);
    if (message.data['type']?.toString() == 'chat' && requestId != null) _chatUpdates.add(requestId);

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

  /// Notification gardée en attente (ex. touchée alors que personne n'était connecté) : ouverte par [openPending].
  static void keepPending(Map<String, dynamic> data) => _pending = data;

  /// Écran d'accueil affiché après connexion : ouvre la notification restée en attente.
  static void openPending() {
    if (!_appReady) return;
    final pending = _pending;
    _pending = null;
    if (pending != null) onOpen?.call(pending);
  }

  /// Signale aux écrans ouverts qu'une livraison / une discussion a changé (ils se rechargent).
  static void notifyDeliveryUpdated(int id) => _deliveryUpdates.add(id);
  static void notifyChatUpdated(int id) => _chatUpdates.add(id);
  static void notifyDeliveryChatUpdated(int id) => _deliveryChatUpdates.add(id);

  static Timer? _retry;
  static int _retryCount = 0;

  /// Après connexion : autorisation, envoi du jeton au serveur et abonnement aux annonces.
  /// Chaque étape est indépendante : l'échec de l'une n'empêche pas les suivantes.
  static Future<void> register(User user, DeliveryService deliveries) async {
    if (!_ready) return;
    _retry?.cancel();
    _retryCount = 0;
    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.requestPermission();
    } catch (e) {
      debugPrint('Autorisation des notifications impossible : $e');
    }

    await _sendToken(deliveries);

    try {
      await _tokenRefresh?.cancel();
      _tokenRefresh =
          messaging.onTokenRefresh.listen((t) => deliveries.registerDeviceToken(t).catchError((_) {}));
    } catch (e) {
      debugPrint('Suivi du jeton de notification impossible : $e');
    }

    try {
      if (user.isCourier) {
        await messaging.subscribeToTopic('couriers');
        await messaging.unsubscribeFromTopic('clients');
      } else {
        await messaging.subscribeToTopic('clients');
        await messaging.unsubscribeFromTopic('couriers');
      }
    } catch (e) {
      debugPrint('Abonnement aux annonces impossible : $e');
    }
  }

  /// Envoie le jeton de l'appareil au serveur ; en cas d'échec (réseau, serveur en veille), nouvel essai différé.
  static Future<void> _sendToken(DeliveryService deliveries) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await deliveries.registerDeviceToken(token);
      _retryCount = 0;
    } catch (e) {
      debugPrint('Jeton de notification non enregistré : $e');
      // Session refusée : inutile d'insister.
      if (e is ApiException && e.isUnauthorized) return;
      if (_retryCount >= 5) return;
      _retryCount++;
      _retry?.cancel();
      _retry = Timer(Duration(seconds: 30 * _retryCount), () => _sendToken(deliveries));
    }
  }

  /// Déconnexion : plus d'annonces pour ce compte sur cet appareil.
  static Future<void> unregister() async {
    _retry?.cancel();
    _retry = null;
    if (!_ready) return;
    try {
      await _tokenRefresh?.cancel();
      _tokenRefresh = null;
      await FirebaseMessaging.instance.unsubscribeFromTopic('clients');
      await FirebaseMessaging.instance.unsubscribeFromTopic('couriers');
    } catch (_) {}
  }
}
