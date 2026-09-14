import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Centralized "premium" design system for ScanDis: refined typographic
/// hierarchy, consistent pill-shaped buttons, softer surfaces, and smooth
/// cross-platform page transitions. No external fonts are used — this
/// stays true to the app's 100%-local, zero-network promise (a font
/// package like google_fonts would otherwise fetch files over the
/// network on first use).
class AppTheme {
  static const double _radius = 16;

  static PageTransitionsTheme get _transitions => const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      );

  static TextTheme _textTheme(Color color) => TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5, color: color),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3, color: color),
        titleMedium: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.1, color: color),
        titleSmall: TextStyle(fontWeight: FontWeight.w600, color: color),
        bodyLarge: TextStyle(fontWeight: FontWeight.w400, height: 1.4, color: color),
        bodyMedium: TextStyle(fontWeight: FontWeight.w400, height: 1.4, color: color),
        labelLarge: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.1, color: color),
      );

  static FilledButtonThemeData _filledButtons(ColorScheme scheme) => FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.1),
        ),
      );

  static OutlinedButtonThemeData _outlinedButtons(ColorScheme scheme) => OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
          side: BorderSide(color: scheme.outline),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.1),
        ),
      );

  static TextButtonThemeData get _textButtons => TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );

  static ChipThemeData _chips(ColorScheme scheme) => ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12.5),
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      );

  static SnackBarThemeData _snackBar(ColorScheme scheme) => SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 4,
      );

  static ThemeData light() {
    const seed = Color(0xFF0E7C86);
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      pageTransitionsTheme: _transitions,
      textTheme: _textTheme(scheme.onSurface),
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0, scrolledUnderElevation: 2),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      filledButtonTheme: _filledButtons(scheme),
      outlinedButtonTheme: _outlinedButtons(scheme),
      textButtonTheme: _textButtons,
      chipTheme: _chips(scheme),
      snackBarTheme: _snackBar(scheme),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(_radius)),
      ),
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      surface: AppColors.background,
      primary: AppColors.cyan,
      onPrimary: Color(0xFF00303A),
      secondary: AppColors.cyanDim,
      primaryContainer: Color(0xFF0E3A42),
      onPrimaryContainer: AppColors.cyan,
      secondaryContainer: Color(0xFF12303A),
      onSecondaryContainer: AppColors.cyan,
      surfaceContainerLow: Color(0xFF101A28),
      surfaceContainerHighest: Color(0xFF1A2635),
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      outline: Color(0xFF2A3A4C),
      outlineVariant: Color(0xFF223244),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: scheme,
      pageTransitionsTheme: _transitions,
      textTheme: _textTheme(AppColors.textPrimary).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero, color: AppColors.surface),
      filledButtonTheme: _filledButtons(scheme),
      outlinedButtonTheme: _outlinedButtons(scheme),
      textButtonTheme: _textButtons,
      chipTheme: _chips(scheme),
      snackBarTheme: _snackBar(scheme),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: AppColors.textSecondary),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.cyan,
        foregroundColor: Color(0xFF00303A),
        elevation: 0,
      ),
    );
  }
}
