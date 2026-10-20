import 'package:flutter/material.dart';

import 'colors.dart';

/// Thème S-Delivery : typographie Inter serrée et très contrastée, fonds blancs, boutons noirs pleine largeur,
/// champs gris sans contour, cartes plates séparées par des filets fins. Inspiré des apps de mobilité (Uber).
class AppTheme {
  static const fontFamily = 'Inter';
  static const _radius = 14.0;

  static TextStyle _t(double size, FontWeight weight, {Color color = AppColors.textPrimary, double? spacing}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: spacing,
        height: 1.25,
      );

  static ThemeData get lightTheme {
    OutlineInputBorder inputBorder(Color color, [double width = 1.6]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );

    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    final buttonText = _t(16, FontWeight.w600, color: Colors.white);

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: const ColorScheme.light(
        primary: AppColors.ink,
        onPrimary: Colors.white,
        primaryContainer: AppColors.surface,
        onPrimaryContainer: AppColors.ink,
        secondary: AppColors.ink,
        onSecondary: Colors.white,
        tertiary: AppColors.accent,
        onTertiary: AppColors.ink,
        surface: Colors.white,
        onSurface: AppColors.ink,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Colors.white,
        surfaceContainer: AppColors.surface,
        surfaceContainerHigh: AppColors.surface,
        surfaceContainerHighest: AppColors.surfaceStrong,
        onSurfaceVariant: AppColors.textSecondary,
        outline: AppColors.border,
        outlineVariant: AppColors.border,
        error: AppColors.error,
      ),
      textTheme: TextTheme(
        displaySmall: _t(34, FontWeight.w800, spacing: -1.2),
        headlineLarge: _t(30, FontWeight.w800, spacing: -1),
        headlineMedium: _t(26, FontWeight.w800, spacing: -0.8),
        headlineSmall: _t(21, FontWeight.w700, spacing: -0.5),
        titleLarge: _t(19, FontWeight.w700, spacing: -0.3),
        titleMedium: _t(16, FontWeight.w600, spacing: -0.2),
        titleSmall: _t(14, FontWeight.w600),
        bodyLarge: _t(16, FontWeight.w400),
        bodyMedium: _t(14, FontWeight.w400, color: AppColors.textSecondary),
        bodySmall: _t(12.5, FontWeight.w400, color: AppColors.textSecondary),
        labelLarge: _t(15, FontWeight.w600),
        labelMedium: _t(13, FontWeight.w600),
        labelSmall: _t(11.5, FontWeight.w600, color: AppColors.textSecondary),
      ),
      // Barres d'écran blanches, sans ombre ; le titre suit la couleur de premier plan de chaque barre.
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: AppColors.ink,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.surfaceStrong,
          disabledForegroundColor: AppColors.textHint,
          elevation: 0,
          minimumSize: const Size(0, 56),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0,
          minimumSize: const Size(0, 52),
          shape: buttonShape,
          textStyle: buttonText.copyWith(color: AppColors.ink),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          backgroundColor: Colors.white,
          side: const BorderSide(color: AppColors.surfaceStrong, width: 1.4),
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: buttonShape,
          textStyle: buttonText.copyWith(color: AppColors.ink),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          textStyle: _t(14.5, FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        border: inputBorder(Colors.transparent),
        enabledBorder: inputBorder(Colors.transparent),
        focusedBorder: inputBorder(AppColors.ink, 2),
        errorBorder: inputBorder(AppColors.error),
        focusedErrorBorder: inputBorder(AppColors.error, 2),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        labelStyle: _t(15, FontWeight.w400, color: AppColors.textSecondary),
        floatingLabelStyle: _t(15, FontWeight.w600),
        hintStyle: _t(15, FontWeight.w400, color: AppColors.textHint),
        helperStyle: _t(12, FontWeight.w400, color: AppColors.textSecondary),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.ink,
        titleTextStyle: _t(15.5, FontWeight.w500),
        subtitleTextStyle: _t(13, FontWeight.w400, color: AppColors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.ink,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: _t(13.5, FontWeight.w600),
        secondaryLabelStyle: _t(13.5, FontWeight.w600, color: Colors.white),
        showCheckmark: false,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textSecondary,
          selectedBackgroundColor: AppColors.ink,
          selectedForegroundColor: Colors.white,
          side: BorderSide.none,
          textStyle: _t(14, FontWeight.w600),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: AppColors.surfaceStrong,
        showDragHandle: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: _t(20, FontWeight.w700, spacing: -0.4),
        contentTextStyle: _t(15, FontWeight.w400, color: AppColors.textSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: _t(14, FontWeight.w500, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.surface,
        height: 68,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => _t(12, states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: states.contains(WidgetState.selected) ? AppColors.ink : AppColors.textHint),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(color: states.contains(WidgetState.selected) ? AppColors.ink : AppColors.textHint),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.ink,
        unselectedLabelColor: AppColors.textHint,
        indicatorColor: AppColors.ink,
        dividerColor: AppColors.border,
        labelStyle: _t(15, FontWeight.w700),
        unselectedLabelStyle: _t(15, FontWeight.w500),
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      timePickerTheme: const TimePickerThemeData(backgroundColor: Colors.white),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.ink,
        linearTrackColor: AppColors.surfaceStrong,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.ink : null),
      ),
    );
  }
}
