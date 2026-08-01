import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  // Cores oficiais da Jurii (Figma).
  //
  // ATENÇÃO (dark mode): estas constantes não reagem ao tema. Em código novo
  // use `context.jColors.<token>` (lib/theme/app_colors.dart) — mesmos valores
  // no tema claro, adaptados automaticamente no escuro. A migração das telas
  // existentes está documentada em docs/architecture.md.

  static const Color primary = Color(0xFF0A1C3B);
  static const Color accent = Color(0xFFB8972A);

  static const Color background = Color(0xFFF7F8FC);

  static const Color card = Colors.white;

  static const Color textPrimary = Color(0xFF0A1C3B);
  // Mantém paridade com AppColors.light.textSecondary (contraste AA).
  static const Color textSecondary = Color(0xFF5E6D8C);

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

      extensions: const [AppColors.light],

      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: accent,
        error: danger,
        surface: card,
        onSurface: textPrimary,
        outline: softBorder,
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

        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: danger),
        ),

        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: danger, width: 2),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),

      // Sem surfaceTintColor: dialogs/sheets M3 ganhariam tint lilás da seed,
      // destoando dos cards brancos da marca.
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: primary,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      dividerTheme: const DividerThemeData(color: divider),
    );
  }

  /// Tema escuro Jurii: navy profundo como base, dourado preservado como
  /// destaque. As telas só reagem depois de migrar de AppTheme.* para
  /// context.jColors — até lá o app permanece em ThemeMode.light.
  static ThemeData get darkTheme {
    const colors = AppColors.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      scaffoldBackgroundColor: colors.background,

      extensions: const [colors],

      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
        primary: colors.primary,
        secondary: colors.accent,
        error: colors.danger,
        surface: colors.card,
        onSurface: colors.textPrimary,
        outline: colors.softBorder,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        elevation: 0,
        centerTitle: false,
        foregroundColor: colors.textPrimary,
      ),

      cardTheme: CardThemeData(
        color: colors.card,
        elevation: 1.5,
        shadowColor: colors.softShadow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: colors.textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: colors.textSecondary),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.card,
        indicatorColor: colors.accent.withValues(alpha: 0.16),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: const Color(0xFF10131C),
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
          backgroundColor: colors.card,
          foregroundColor: colors.textPrimary,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: BorderSide(color: colors.softBorder, width: 1.5),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.softBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.softBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.danger, width: 2),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colors.accent),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.lightBlue,
        contentTextStyle: TextStyle(color: colors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      dividerTheme: DividerThemeData(color: colors.divider),
    );
  }
}
