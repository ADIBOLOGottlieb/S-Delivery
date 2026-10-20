import 'package:flutter/material.dart';

/// Palette S-Delivery, inspirée des apps de mobilité : fonds blancs, noir d'encre pour l'action,
/// gris neutres pour les surfaces, et un seul accent lime réservé à la marque et au suivi en direct.
class AppColors {
  // Marque
  static const Color ink = Color(0xFF0A0A0A); // Noir d'encre : boutons, titres, icônes actives
  static const Color accent = Color(0xFFC6FF3D); // Lime S-Delivery : logo, suivi, mises en avant
  static const Color onAccent = ink;

  /// Action principale (boutons pleins, sélection) : noir.
  static const Color primary = ink;
  static const Color onPrimary = Colors.white;

  /// Fond des sélections et puces atténuées.
  static const Color primarySoft = Color(0xFFF3F3F3);
  static const Color primaryDark = ink;

  /// Blocs sombres (cartes de suivi, bandeaux) : noir, texte blanc.
  static const Color secondary = ink;
  static const Color onSecondary = Colors.white;

  // Surfaces (du plus clair au plus foncé)
  static const Color background = Colors.white; // Fond des écrans
  static const Color card = Colors.white; // Cartes
  static const Color surface = Color(0xFFF3F3F3); // Champs, tuiles, rails
  static const Color surfaceStrong = Color(0xFFE8E8E8); // Tuiles appuyées, séparateurs épais
  static const Color border = Color(0xFFEAEAEA); // Contours fins
  static const Color cream = background;

  static const Color onBackground = ink;
  static const Color onSurface = ink;

  // Couleurs d'état (contraste ≥ 4,5:1 sur blanc pour le texte)
  static const Color success = Color(0xFF05944F);
  static const Color warning = Color(0xFFB45309);
  static const Color error = Color(0xFFE11900);
  static const Color info = Color(0xFF276EF1);

  // Texte
  static const Color textPrimary = ink;
  static const Color textSecondary = Color(0xFF5E5E5E);
  static const Color textHint = Color(0xFF8A8A8A);
}
