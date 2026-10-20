import 'package:flutter/material.dart';

import '../utils/colors.dart';

/// Briques d'interface communes, dans l'esprit des apps de mobilité : listes aérées, icônes dans des carrés gris,
/// itinéraire départ (rond) → arrivée (carré), barre de progression segmentée.

/// Titre de section, avec action facultative à droite (« Tout voir »).
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionTitle(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(0, 24, 0, 10)});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Icône dans un carré arrondi gris (ou de la couleur donnée).
class IconSquare extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color background;
  final Color foreground;

  const IconSquare(
    this.icon, {
    super.key,
    this.size = 44,
    this.background = AppColors.surface,
    this.foreground = AppColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(size * 0.28)),
      child: Icon(icon, size: size * 0.5, color: foreground),
    );
  }
}

/// Ligne de liste : icône, titre, sous-titre, élément de fin (chevron par défaut).
class ListRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? color;

  const ListRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.ink;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            IconSquare(icon, size: 40, foreground: tint),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: tint)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                    ),
                ],
              ),
            ),
            trailing ??
                (onTap == null
                    ? const SizedBox.shrink()
                    : const Icon(Icons.chevron_right_rounded, color: AppColors.textHint)),
          ],
        ),
      ),
    );
  }
}

/// Itinéraire compact : départ (rond) relié par un trait à l'arrivée (carré).
class RouteStops extends StatelessWidget {
  final String pickup;
  final String dropoff;
  final String? pickupLabel;
  final String? dropoffLabel;
  final int maxLines;

  const RouteStops({
    super.key,
    required this.pickup,
    required this.dropoff,
    this.pickupLabel,
    this.dropoffLabel,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    Widget stop(String text, String? label) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null) Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(
              text,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
            ),
          ],
        );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 16,
            child: Column(
              children: [
                const SizedBox(height: 4),
                const StopDot(pickup: true),
                Expanded(
                  child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 3), color: AppColors.ink),
                ),
                const StopDot(pickup: false),
                const SizedBox(height: 4),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                stop(pickup, pickupLabel),
                const SizedBox(height: 14),
                stop(dropoff, dropoffLabel),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Puce d'étape : rond plein (départ) ou carré plein (arrivée).
class StopDot extends StatelessWidget {
  final bool pickup;
  final double size;
  final Color color;

  const StopDot({super.key, required this.pickup, this.size = 12, this.color = AppColors.ink});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: pickup ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: pickup ? null : BorderRadius.circular(2),
      ),
    );
  }
}

/// Barre de progression segmentée (étapes de la course).
class ProgressSteps extends StatelessWidget {
  final int step;
  final int total;
  final Color color;
  final Color track;

  const ProgressSteps({
    super.key,
    required this.step,
    this.total = 4,
    this.color = AppColors.ink,
    this.track = AppColors.surfaceStrong,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              height: 4,
              decoration: BoxDecoration(color: i < step ? color : track, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ],
      ],
    );
  }
}

/// Ligne « libellé ……… valeur » d'un récapitulatif.
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const InfoRow(this.label, this.value, {super.key, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: bold ? 17 : 14.5,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: AppColors.ink,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: bold ? style : Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14.5)),
          ),
          const SizedBox(width: 12),
          Flexible(child: Text(value, style: style, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

/// Séparateur épais entre deux blocs d'un écran (comme les fiches de course).
class ThickDivider extends StatelessWidget {
  const ThickDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(height: 8, color: AppColors.surface);
}

/// Pastille de compteur (messages non lus).
class CountBadge extends StatelessWidget {
  final int count;

  const CountBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(10)),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Bouton rond gris (appel, message…), avec pastille facultative.
class RoundAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final int badge;
  final Color background;
  final Color foreground;

  const RoundAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge = 0,
    this.background = AppColors.surface,
    this.foreground = AppColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton.filled(
          tooltip: tooltip,
          onPressed: onTap,
          style: IconButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            minimumSize: const Size(46, 46),
          ),
          icon: Icon(icon, size: 21),
        ),
        if (badge > 0) Positioned(top: -2, right: -2, child: CountBadge(count: badge)),
      ],
    );
  }
}
