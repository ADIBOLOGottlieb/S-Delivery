import 'package:flutter/material.dart';

/// Palette VOOM Delivery : jaune et noir de la marque, sur des fonds crème chauds
/// plutôt que du blanc pur (moins éblouissant au soleil, plus chaleureux).
class AppColors {
  // Marque
  static const Color primary = Color(0xFFFAC223); // Jaune officiel VOOM (logo)
  static const Color primaryDark = Color(0xFFE0A800); // Jaune plus foncé (bordures, accents)
  static const Color primarySoft = Color(0xFFFFE7A3); // Jaune pâle (puces, sélection)
  static const Color secondary = Color(0xFF16130E); // Noir chaud
  static const Color onPrimary = Color(0xFF16130E); // Texte sur jaune
  static const Color onSecondary = Color(0xFFFFFFFF); // Texte sur noir

  // Surfaces (du plus foncé au plus clair)
  static const Color background = Color(0xFFFFF3D6); // Fond des écrans : crème chaud
  static const Color surface = Color(0xFFFBE9C0); // Zones atténuées : champs, puces, rails
  static const Color card = Color(0xFFFFFAEB); // Cartes : ivoire, jamais blanc pur
  static const Color border = Color(0xFFF0DCA6); // Contours doux
  static const Color cream = background;

  static const Color onBackground = Color(0xFF16130E);
  static const Color onSurface = Color(0xFF16130E);

  // Couleurs d'état
  static const Color success = Color(0xFF2E9D57);
  static const Color warning = Color(0xFFEF8A17);
  static const Color error = Color(0xFFD93A2F);
  static const Color info = Color(0xFF2F7DE1);

  // Texte (gris chauds, contraste ≥ 4,5:1 sur crème)
  static const Color textPrimary = Color(0xFF16130E);
  static const Color textSecondary = Color(0xFF5F5644);
  static const Color textHint = Color(0xFF8C8069);
}
