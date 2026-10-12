import 'package:flutter/material.dart';

import '../utils/colors.dart';

/// Barre d'action fixée en bas de l'écran, au-dessus de la barre de navigation du téléphone.
/// À utiliser comme `Scaffold.bottomNavigationBar` pour l'action principale d'un écran,
/// afin qu'elle reste toujours visible et à portée du pouce.
class BottomActionBar extends StatelessWidget {
  /// Ligne d'information facultative au-dessus des boutons (ex. prix total).
  final Widget? summary;
  final List<Widget> children;

  const BottomActionBar({super.key, this.summary, required this.children});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // Panneau ivoire arrondi qui se détache du fond crème.
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: AppColors.primaryDark.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (summary != null) ...[summary!, const SizedBox(height: 10)],
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Indicateur de chargement aux dimensions d'un libellé de bouton.
class ButtonProgress extends StatelessWidget {
  const ButtonProgress({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPrimary),
    );
  }
}
