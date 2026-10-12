import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

/// Thème VOOM : fonds crème, cartes ivoire très arrondies, gros boutons jaunes,
/// texte noir chaud. Inspiré des apps de livraison (Glovo, Yango, Gozem).
class AppTheme {
  static const _radius = 18.0;

  static ThemeData get lightTheme {
    final text = GoogleFonts.poppinsTextTheme().apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    OutlineInputBorder inputBorder(Color color, [double width = 1.2]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: width),
        );

    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    final buttonText = GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700);

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.primarySoft,
        onPrimaryContainer: AppColors.onPrimary,
        secondary: AppColors.secondary,
        onSecondary: AppColors.onSecondary,
        surface: AppColors.card,
        onSurface: AppColors.onSurface,
        surfaceContainerLowest: AppColors.card,
        surfaceContainerLow: AppColors.card,
        surfaceContainer: AppColors.background,
        surfaceContainerHigh: AppColors.surface,
        surfaceContainerHighest: AppColors.surface,
        onSurfaceVariant: AppColors.textSecondary,
        outline: AppColors.border,
        outlineVariant: AppColors.border,
        error: AppColors.error,
      ),
      textTheme: text.copyWith(
        headlineLarge: GoogleFonts.poppins(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        headlineMedium: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        headlineSmall: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        titleLarge: GoogleFonts.poppins(fontSize: 19, fontWeight: FontWeight.w700),
        titleMedium: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        bodyLarge: GoogleFonts.poppins(fontSize: 16, color: AppColors.textPrimary),
        bodyMedium: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary),
        bodySmall: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.textSecondary),
        labelLarge: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      // Barres d'écran fondues dans le fond crème, titre en gras.
      // Pas de titleTextStyle : le titre suit la couleur de premier plan de chaque barre.
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.surface,
          disabledForegroundColor: AppColors.textHint,
          elevation: 0,
          minimumSize: const Size(0, 54),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.secondary,
          foregroundColor: AppColors.primary,
          minimumSize: const Size(0, 54),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.secondary,
          backgroundColor: AppColors.card,
          side: const BorderSide(color: AppColors.secondary, width: 1.4),
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        // Le jaune sur crème est peu lisible : les liens texte sont en noir.
        style: TextButton.styleFrom(
          foregroundColor: AppColors.secondary,
          textStyle: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: inputBorder(AppColors.border),
        enabledBorder: inputBorder(AppColors.border),
        focusedBorder: inputBorder(AppColors.primaryDark, 2),
        errorBorder: inputBorder(AppColors.error),
        focusedErrorBorder: inputBorder(AppColors.error, 2),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        labelStyle: GoogleFonts.poppins(color: AppColors.textSecondary),
        floatingLabelStyle: GoogleFonts.poppins(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        hintStyle: GoogleFonts.poppins(color: AppColors.textHint),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      listTileTheme: const ListTileThemeData(iconColor: AppColors.secondary),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primary,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: AppColors.primaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.secondary,
        contentTextStyle: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      timePickerTheme: const TimePickerThemeData(backgroundColor: AppColors.background),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.secondary),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.secondary,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.surface,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
