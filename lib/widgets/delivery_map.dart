import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/delivery.dart';
import '../screens/common/full_map_screen.dart';
import '../utils/colors.dart';

/// Matrice de couleur : fond de carte désaturé et éclairci, pour que l'itinéraire noir ressorte.
const _mutedTiles = ColorFilter.matrix(<double>[
  0.30, 0.55, 0.10, 0, 30, //
  0.30, 0.55, 0.10, 0, 30, //
  0.30, 0.55, 0.10, 0, 30, //
  0, 0, 0, 1, 0,
]);

/// Fond de carte OpenStreetMap (gratuit, sans clé), en tons gris neutres.
TileLayer osmTiles() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.voomdelivery.app',
      maxZoom: 19,
      tileBuilder: (context, tile, _) => ColorFiltered(colorFilter: _mutedTiles, child: tile),
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

/// Marqueur d'étape : rond (départ) ou carré (arrivée), noir à centre blanc — le code visuel des apps de mobilité.
Marker stopMarker(LatLng point, {required bool pickup}) => Marker(
      point: point,
      width: 26,
      height: 26,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.ink,
          shape: pickup ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: pickup ? null : BorderRadius.circular(4),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
        ),
        alignment: Alignment.center,
        child: Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: pickup ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: pickup ? null : BorderRadius.circular(1.5),
          ),
        ),
      ),
    );

/// Compatibilité : marqueur A (départ) / B (arrivée).
Marker pointMarker(LatLng point, String letter, Color color) => stopMarker(point, pickup: letter == 'A');

/// Livreur en direct : pastille lime avec la moto, entourée d'un halo.
Marker courierMarker(LatLng point) => Marker(
      point: point,
      width: 56,
      height: 56,
      child: Container(
        decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.28), shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.ink,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.accent, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
          ),
          child: const Icon(Icons.two_wheeler_rounded, color: AppColors.accent, size: 19),
        ),
      ),
    );

/// Trajet A → B tracé en noir épais, comme un itinéraire.
PolylineLayer routeLine(List<LatLng> points) => PolylineLayer(polylines: [
      Polyline(points: points, strokeWidth: 5, color: AppColors.ink),
    ]);

/// Carte affichant le point A, le point B et, pendant la course, le livreur.
///
/// Intégrée dans une page qui défile ([interactive] = false), la carte est figée pour ne pas
/// bloquer le défilement, et un bouton ouvre la version plein écran manipulable.
class DeliveryMap extends StatelessWidget {
  final DeliveryPoint pickup;
  final DeliveryPoint dropoff;
  final LatLng? courier;
  final double height;
  final bool interactive;
  final BorderRadius borderRadius;

  /// Marge de cadrage autour des points (ex. plus grande en bas quand une feuille recouvre la carte).
  final EdgeInsets fitPadding;

  const DeliveryMap({
    super.key,
    required this.pickup,
    required this.dropoff,
    this.courier,
    this.height = 260,
    this.interactive = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.fitPadding = const EdgeInsets.all(48),
  });

  @override
  Widget build(BuildContext context) {
    final map = FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.coordinates(
          coordinates: [pickup.latLng, dropoff.latLng, if (courier != null) courier!],
          padding: fitPadding,
          maxZoom: 16,
        ),
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
        ),
      ),
      children: [
        osmTiles(),
        routeLine([pickup.latLng, dropoff.latLng]),
        MarkerLayer(markers: [
          stopMarker(pickup.latLng, pickup: true),
          stopMarker(dropoff.latLng, pickup: false),
          if (courier != null) courierMarker(courier!),
        ]),
        osmAttribution(),
      ],
    );

    if (interactive) return SizedBox(height: height, child: map);

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: map),
            Positioned(
              right: 10,
              bottom: 10,
              child: Material(
                color: Colors.white,
                shape: const StadiumBorder(),
                elevation: 2,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FullMapScreen(title: 'Itinéraire', pickup: pickup, dropoff: dropoff),
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_full_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Agrandir', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
