import 'package:flutter/material.dart';

class AppTheme {
  // Cores oficiais da Jurii (Figma)

  static const Color primary = Color(0xFF0A1C3B);
  static const Color accent = Color(0xFFB8972A);

  static const Color background = Color(0xFFF7F8FC);

  static const Color card = Colors.white;

  static const Color textPrimary = Color(0xFF0A1C3B);
  static const Color textSecondary = Color(0xFF6B7A99);

  static const Color lightBlue = Color(0xFFEEF1F8);
  static const Color lightBlueBorder = Color(0xFFC5CFE8);

  static const Color lightGold = Color(0xFFFDF6E3);
  static const Color lightGoldBorder = Color(0xFFE8D5A0);
  static const Color warning = Color(0xFFE07B3A);
  static const Color warningSurface = Color(0xFFFEF9EB);
  static const Color warningBorder = Color(0xFFF0E5C0);
  static const Color warningText = Color(0xFF5A4F1E);
  static const Color success = Color(0xFF2D7A4F);
  static const Color successSurface = Color(0xFFE8F4EC);
  static const Color officePurple = Color(0xFF3B2A6D);
  static const Color officePurpleSurface = Color(0xFFF2EEFF);
  static const Color officePurpleBorder = Color(0xFFD8CDFB);
  static const Color officePurpleText = Color(0xFF2B214C);
  static const Color danger = Color(0xFFD32F2F);
  static const Color dangerSurface = Color(0xFFFFF1F1);
  static const Color dangerBorder = Color(0xFFF1B8B8);
  static const Color divider = Color(0xFFE8ECF5);
  static const Color muted = Color(0xFFB8C0D4);
  static const Color softShadow = Color(0x140A1C3B);
  static const Color softBorder = Color(0x220A1C3B);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,

      scaffoldBackgroundColor: background,

      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: accent,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
        foregroundColor: primary,
      ),

      cardTheme: CardThemeData(
        color: card,
        elevation: 1.5,
        shadowColor: softShadow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),

        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),

        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),

        bodyLarge: TextStyle(fontSize: 16, color: textPrimary),

        bodyMedium: TextStyle(fontSize: 14, color: textSecondary),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,

        indicatorColor: accent.withValues(alpha: 0.12),

        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: card,

          minimumSize: const Size(110, 56),

          elevation: 0,
          shadowColor: Colors.transparent,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),

          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: card,

          foregroundColor: textPrimary,

          minimumSize: const Size(double.infinity, 56),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),

          side: const BorderSide(color: softBorder, width: 1.5),

          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,

        fillColor: card,

        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: softBorder),
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: softBorder),
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
      ),
    );
  }
}
