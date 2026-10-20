import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'delivery_service.dart';

/// Partage de la position du livreur pendant ses courses (suivi en direct côté client).
///
/// Actif seulement quand le livreur a une course en cours et que l'app est ouverte ;
/// au plus un envoi toutes les [minInterval], et seulement après un déplacement réel.
class CourierLocationService {
  CourierLocationService(this._deliveries);

  final DeliveryService _deliveries;

  static const minInterval = Duration(seconds: 15);

  StreamSubscription<Position>? _positions;
  DateTime? _lastSent;
  bool _starting = false;

  bool get isSharing => _positions != null;

  /// Démarre le partage (demande l'autorisation si besoin). Sans autorisation, ne fait rien.
  Future<void> start() async {
    if (_positions != null || _starting) return;
    _starting = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;

      _positions = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 20),
      ).listen(_send, onError: (Object e) => debugPrint('Position du livreur indisponible : $e'));
    } catch (e) {
      debugPrint('Partage de position impossible : $e');
    } finally {
      _starting = false;
    }
  }

  Future<void> _send(Position position) async {
    final now = DateTime.now();
    if (_lastSent != null && now.difference(_lastSent!) < minInterval) return;
    _lastSent = now;
    try {
      await _deliveries.shareCourierLocation(position.latitude, position.longitude);
    } catch (_) {
      // Réseau coupé : la position suivante sera envoyée au prochain déplacement.
      _lastSent = null;
    }
  }

  Future<void> stop() async {
    await _positions?.cancel();
    _positions = null;
    _lastSent = null;
  }
}
