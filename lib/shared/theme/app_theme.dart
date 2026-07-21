/// Visual design system.
///
/// The palette is deliberately calm and low-contrast in its accents. This app
/// interrupts people during a religious obligation; an aggressive, gamified
/// colour scheme would be tonally wrong. Deep green reads as traditional
/// without being kitsch, and the surface colours stay quiet so prayer times
/// are the loudest thing on screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AppColors {
  // Primary: deep green, long associated with Islamic design.
  static const Color primary = Color(0xFF1B5E4A);
  static const Color primaryLight = Color(0xFF2E7D63);
  static const Color primaryDark = Color(0xFF0F3B2E);

  // Accent: muted gold, used sparingly for the active prayer only.
  static const Color accent = Color(0xFFC9A227);

  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFE08700);
  static const Color danger = Color(0xFFC62828);

  // Light surfaces
  static const Color lightBackground = Color(0xFFF7F6F2);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE3E1DA);
  static const Color lightTextPrimary = Color(0xFF1A1C1A);
  static const Color lightTextSecondary = Color(0xFF5F6560);

  // Dark surfaces. Fajr is used in the dark, so the dark theme is not an
  // afterthought here — it is the theme most users will see first each day.
  static const Color darkBackground = Color(0xFF101412);
  static const Color darkSurface = Color(0xFF1A201D);
  static const Color darkBorder = Color(0xFF2C3531);
  static const Color darkTextPrimary = Color(0xFFECEFEC);
  static const Color darkTextSecondary = Color(0xFF9DA6A0);
}

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 20;
  static const double pill = 999;
}

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? AppColors.primaryLight : AppColors.primary,
      secondary: AppColors.accent,
      surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      error: AppColors.danger,
    );

    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,

      appBarTheme: AppBarTheme(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),

      cardTheme: CardThemeData(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // 56dp: comfortably above the 48dp minimum touch target, because
          // the primary action is often tapped half-asleep before Fajr.
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          side: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        thickness: 1,
        space: 1,
      ),

      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 56,
          fontWeight: FontWeight.w300,
          color: textPrimary,
          // Tight tracking keeps the large countdown from feeling airy.
          letterSpacing: -1.5,
          height: 1.05,
        ),
        headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: textPrimary, height: 1.45),
        bodyMedium: TextStyle(fontSize: 14, color: textSecondary, height: 1.45),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: textSecondary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
