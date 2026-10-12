import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/delivery.dart';
import '../screens/common/full_map_screen.dart';
import '../utils/colors.dart';

/// Fond de carte OpenStreetMap : gratuit, sans clé ni carte bancaire.
TileLayer osmTiles() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.voomdelivery.app',
      maxZoom: 19,
    );

/// Mention obligatoire de la licence OpenStreetMap.
Widget osmAttribution() => const Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: BoxDecoration(color: Color(0xB3FFFFFF)),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: Text('© OpenStreetMap', style: TextStyle(fontSize: 10, color: Colors.black87)),
          ),
        ),
      ),
    );

/// Marqueur rond lettré (A vert = récupération, B rouge = destination).
Marker pointMarker(LatLng point, String letter, Color color) => Marker(
      point: point,
      width: 40,
      height: 48,
      alignment: Alignment.topCenter,
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Text(letter, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          Container(width: 3, height: 12, color: color),
        ],
      ),
    );

/// Carte affichant le point A et le point B.
///
/// Intégrée dans une page qui défile ([interactive] = false), la carte est figée pour ne pas
/// bloquer le défilement, et un bouton ouvre la version plein écran manipulable.
class DeliveryMap extends StatelessWidget {
  final DeliveryPoint pickup;
  final DeliveryPoint dropoff;
  final double height;
  final bool interactive;

  const DeliveryMap({
    super.key,
    required this.pickup,
    required this.dropoff,
    this.height = 260,
    this.interactive = false,
  });

  @override
  Widget build(BuildContext context) {
    final map = FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.coordinates(
          coordinates: [pickup.latLng, dropoff.latLng],
          padding: const EdgeInsets.all(48),
          maxZoom: 16,
        ),
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
        ),
      ),
      children: [
        osmTiles(),
        PolylineLayer(
          polylines: [
            Polyline(
              points: [pickup.latLng, dropoff.latLng],
              strokeWidth: 4,
              color: AppColors.secondary.withValues(alpha: 0.7),
              pattern: StrokePattern.dashed(segments: const [12, 8]),
            ),
          ],
        ),
        MarkerLayer(markers: [
          pointMarker(pickup.latLng, 'A', AppColors.success),
          pointMarker(dropoff.latLng, 'B', AppColors.error),
        ]),
        osmAttribution(),
      ],
    );

    if (interactive) return SizedBox(height: height, child: map);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: map),
            Positioned(
              right: 8,
              bottom: 8,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.card,
                  foregroundColor: AppColors.textPrimary,
                  elevation: 2,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FullMapScreen(title: 'Carte A → B', pickup: pickup, dropoff: dropoff),
                  ),
                ),
                icon: const Icon(Icons.fullscreen),
                label: const Text('Plein écran'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
