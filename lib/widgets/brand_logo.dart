import 'package:flutter/material.dart';

import '../utils/colors.dart';
import '../utils/theme.dart';

/// Symbole S-Delivery : un « S » tracé comme un itinéraire, avec un point de départ et un point d'arrivée.
/// Dessiné en vectoriel (net à toutes les tailles) sur la même géométrie que l'icône de l'application.
class SDeliveryMark extends StatelessWidget {
  final double size;

  /// Fond arrondi derrière le S ; null pour poser le S directement sur un fond sombre.
  final Color? background;
  final Color color;

  const SDeliveryMark({super.key, this.size = 48, this.background = AppColors.ink, this.color = AppColors.accent});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'S-Delivery',
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _MarkPainter(background: background, color: color, hole: background ?? AppColors.ink),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final Color? background;
  final Color color;
  final Color hole;

  const _MarkPainter({required this.background, required this.color, required this.hole});

  // Coordonnées sur une grille de 1024, comme le fichier source de l'icône.
  static const _start = Offset(633.2, 303);
  static const _middle = Offset(512, 512);
  static const _end = Offset(390.8, 721);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 1024);
    if (background != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 1024, 1024), const Radius.circular(232)),
        Paint()..color = background!,
      );
    }
    final route = Path()
      ..moveTo(_start.dx, _start.dy)
      ..arcToPoint(_middle, radius: const Radius.circular(140), largeArc: true, clockwise: false)
      ..arcToPoint(_end, radius: const Radius.circular(140), largeArc: true, clockwise: true);
    canvas.drawPath(
      route,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 96
        ..strokeCap = StrokeCap.round,
    );
    // Départ et arrivée : extrémités évidées, comme des points d'étape.
    final holePaint = Paint()..color = hole;
    canvas.drawCircle(_start, 30, holePaint);
    canvas.drawCircle(_end, 30, holePaint);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.background != background || old.color != color || old.hole != hole;
}

/// Logo horizontal : symbole + « S-Delivery » (trait d'union en pastille lime).
class SDeliveryLogo extends StatelessWidget {
  final double height;

  /// Texte blanc, pour les fonds sombres.
  final bool light;

  /// Sans le symbole (mot-symbole seul).
  final bool showMark;

  const SDeliveryLogo({super.key, this.height = 40, this.light = false, this.showMark = true});

  @override
  Widget build(BuildContext context) {
    final fontSize = height * 0.62;
    final text = TextStyle(
      fontFamily: AppTheme.fontFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: -fontSize * 0.04,
      height: 1,
      color: light ? Colors.white : AppColors.ink,
    );
    return Semantics(
      label: 'S-Delivery',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showMark) ...[
            SDeliveryMark(size: height),
            SizedBox(width: height * 0.22),
          ],
          Text('S', style: text),
          Container(
            width: fontSize * 0.36,
            height: fontSize * 0.17,
            margin: EdgeInsets.fromLTRB(fontSize * 0.07, fontSize * 0.08, fontSize * 0.06, 0),
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(fontSize)),
          ),
          Text('Delivery', style: text),
        ],
      ),
    );
  }
}
