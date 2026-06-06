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
        shadowColor: Color(0x140A1C3B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
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

        bodyLarge: TextStyle(
          fontSize: 16,
          color: textPrimary,
        ),

        bodyMedium: TextStyle(
          fontSize: 14,
          color: textSecondary,
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,

        indicatorColor: accent.withOpacity(0.12),

        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,

          minimumSize: const Size(110, 48),

          elevation: 0,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,

        fillColor: background,

        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: Color(0x220A1C3B),
          ),
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: Color(0x220A1C3B),
          ),
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: primary,
            width: 2,
          ),
        ),
      ),
    );
  }
}