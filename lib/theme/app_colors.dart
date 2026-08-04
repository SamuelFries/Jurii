import 'package:flutter/material.dart';

/// Paleta semântica da Jurii como [ThemeExtension].
///
/// Os valores de [AppColors.light] são idênticos às constantes históricas de
/// AppTheme — telas migradas para `context.jColors` não mudam nada no tema
/// claro e passam a reagir automaticamente ao tema escuro.
///
/// Migração de uma tela: trocar `AppTheme.background` por
/// `context.jColors.background` (e assim por diante) dentro de `build`.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.accent,
    required this.background,
    required this.card,
    required this.textPrimary,
    required this.textSecondary,
    required this.lightBlue,
    required this.lightBlueBorder,
    required this.lightGold,
    required this.lightGoldBorder,
    required this.warning,
    required this.warningSurface,
    required this.warningBorder,
    required this.warningText,
    required this.success,
    required this.successSurface,
    required this.officePurple,
    required this.officePurpleSurface,
    required this.officePurpleBorder,
    required this.officePurpleText,
    required this.danger,
    required this.dangerSurface,
    required this.dangerBorder,
    required this.divider,
    required this.muted,
    required this.softShadow,
    required this.softBorder,
    required this.readReceipt,
  });

  final Color primary;
  final Color accent;
  final Color background;
  final Color card;
  final Color textPrimary;
  final Color textSecondary;
  final Color lightBlue;
  final Color lightBlueBorder;
  final Color lightGold;
  final Color lightGoldBorder;
  final Color warning;
  final Color warningSurface;
  final Color warningBorder;
  final Color warningText;
  final Color success;
  final Color successSurface;
  final Color officePurple;
  final Color officePurpleSurface;
  final Color officePurpleBorder;
  final Color officePurpleText;
  final Color danger;
  final Color dangerSurface;
  final Color dangerBorder;
  final Color divider;
  final Color muted;
  final Color softShadow;
  final Color softBorder;

  /// Cor do tique de "visualizado" no balão da própria mensagem.
  ///
  /// Muda de tom entre os temas porque o FUNDO muda de lado: no tema claro o
  /// balão de quem enviou é navy (tique claro por cima), no escuro ele é azul
  /// claro (tique escuro por cima). Um azul só não serviria nos dois.
  final Color readReceipt;

  /// Tique de "visualizado" sobre superfície SEMPRE escura — o véu que fica em
  /// cima da foto ou do vídeo, que não acompanha o tema.
  static const Color readReceiptOnDark = Color(0xFF6FC3FF);

  static const AppColors light = AppColors(
    primary: Color(0xFF0A1C3B),
    accent: Color(0xFFB8972A),
    background: Color(0xFFF7F8FC),
    card: Colors.white,
    textPrimary: Color(0xFF0A1C3B),
    // 0xFF6B7A99 dava 4.1:1 sobre o background — abaixo do AA (4.5:1).
    // Este tom passa em background (4.9), card (5.2) e lightBlue (4.6).
    textSecondary: Color(0xFF5E6D8C),
    lightBlue: Color(0xFFEEF1F8),
    lightBlueBorder: Color(0xFFC5CFE8),
    lightGold: Color(0xFFFDF6E3),
    lightGoldBorder: Color(0xFFE8D5A0),
    warning: Color(0xFFE07B3A),
    warningSurface: Color(0xFFFEF9EB),
    warningBorder: Color(0xFFF0E5C0),
    warningText: Color(0xFF5A4F1E),
    success: Color(0xFF2D7A4F),
    successSurface: Color(0xFFE8F4EC),
    officePurple: Color(0xFF3B2A6D),
    officePurpleSurface: Color(0xFFF2EEFF),
    officePurpleBorder: Color(0xFFD8CDFB),
    officePurpleText: Color(0xFF2B214C),
    danger: Color(0xFFD32F2F),
    dangerSurface: Color(0xFFFFF1F1),
    dangerBorder: Color(0xFFF1B8B8),
    divider: Color(0xFFE8ECF5),
    muted: Color(0xFFB8C0D4),
    softShadow: Color(0x140A1C3B),
    softBorder: Color(0x220A1C3B),
    readReceipt: readReceiptOnDark,
  );

  /// Tema escuro mantendo a identidade Jurii: navy profundo como base,
  /// dourado preservado como destaque, superfícies com contraste AA.
  static const AppColors dark = AppColors(
    primary: Color(0xFF9DB4E8),
    accent: Color(0xFFD4B14A),
    background: Color(0xFF0A1120),
    card: Color(0xFF141F36),
    textPrimary: Color(0xFFEDF1F9),
    textSecondary: Color(0xFF9DA9C4),
    lightBlue: Color(0xFF1A2740),
    lightBlueBorder: Color(0xFF2C3D61),
    lightGold: Color(0xFF2A2414),
    lightGoldBorder: Color(0xFF4A3F1E),
    warning: Color(0xFFF0915A),
    warningSurface: Color(0xFF2A2113),
    warningBorder: Color(0xFF4A3A1A),
    warningText: Color(0xFFE8D5A0),
    success: Color(0xFF5BBd8B),
    successSurface: Color(0xFF14291D),
    officePurple: Color(0xFFA795E0),
    officePurpleSurface: Color(0xFF211A38),
    officePurpleBorder: Color(0xFF3A2F5D),
    officePurpleText: Color(0xFFCFC4F0),
    danger: Color(0xFFEF6B68),
    dangerSurface: Color(0xFF2D1516),
    dangerBorder: Color(0xFF5C2626),
    divider: Color(0xFF24304A),
    muted: Color(0xFF5A6784),
    softShadow: Color(0x66000000),
    softBorder: Color(0x22FFFFFF),
    readReceipt: Color(0xFF0F3C6E),
  );

  @override
  AppColors copyWith({
    Color? primary,
    Color? accent,
    Color? background,
    Color? card,
    Color? textPrimary,
    Color? textSecondary,
    Color? lightBlue,
    Color? lightBlueBorder,
    Color? lightGold,
    Color? lightGoldBorder,
    Color? warning,
    Color? warningSurface,
    Color? warningBorder,
    Color? warningText,
    Color? success,
    Color? successSurface,
    Color? officePurple,
    Color? officePurpleSurface,
    Color? officePurpleBorder,
    Color? officePurpleText,
    Color? danger,
    Color? dangerSurface,
    Color? dangerBorder,
    Color? divider,
    Color? muted,
    Color? softShadow,
    Color? softBorder,
    Color? readReceipt,
  }) {
    return AppColors(
      primary: primary ?? this.primary,
      accent: accent ?? this.accent,
      background: background ?? this.background,
      card: card ?? this.card,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      lightBlue: lightBlue ?? this.lightBlue,
      lightBlueBorder: lightBlueBorder ?? this.lightBlueBorder,
      lightGold: lightGold ?? this.lightGold,
      lightGoldBorder: lightGoldBorder ?? this.lightGoldBorder,
      warning: warning ?? this.warning,
      warningSurface: warningSurface ?? this.warningSurface,
      warningBorder: warningBorder ?? this.warningBorder,
      warningText: warningText ?? this.warningText,
      success: success ?? this.success,
      successSurface: successSurface ?? this.successSurface,
      officePurple: officePurple ?? this.officePurple,
      officePurpleSurface: officePurpleSurface ?? this.officePurpleSurface,
      officePurpleBorder: officePurpleBorder ?? this.officePurpleBorder,
      officePurpleText: officePurpleText ?? this.officePurpleText,
      danger: danger ?? this.danger,
      dangerSurface: dangerSurface ?? this.dangerSurface,
      dangerBorder: dangerBorder ?? this.dangerBorder,
      divider: divider ?? this.divider,
      muted: muted ?? this.muted,
      softShadow: softShadow ?? this.softShadow,
      softBorder: softBorder ?? this.softBorder,
      readReceipt: readReceipt ?? this.readReceipt,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      primary: mix(primary, other.primary),
      accent: mix(accent, other.accent),
      background: mix(background, other.background),
      card: mix(card, other.card),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      lightBlue: mix(lightBlue, other.lightBlue),
      lightBlueBorder: mix(lightBlueBorder, other.lightBlueBorder),
      lightGold: mix(lightGold, other.lightGold),
      lightGoldBorder: mix(lightGoldBorder, other.lightGoldBorder),
      warning: mix(warning, other.warning),
      warningSurface: mix(warningSurface, other.warningSurface),
      warningBorder: mix(warningBorder, other.warningBorder),
      warningText: mix(warningText, other.warningText),
      success: mix(success, other.success),
      successSurface: mix(successSurface, other.successSurface),
      officePurple: mix(officePurple, other.officePurple),
      officePurpleSurface: mix(officePurpleSurface, other.officePurpleSurface),
      officePurpleBorder: mix(officePurpleBorder, other.officePurpleBorder),
      officePurpleText: mix(officePurpleText, other.officePurpleText),
      danger: mix(danger, other.danger),
      dangerSurface: mix(dangerSurface, other.dangerSurface),
      dangerBorder: mix(dangerBorder, other.dangerBorder),
      divider: mix(divider, other.divider),
      muted: mix(muted, other.muted),
      readReceipt: mix(readReceipt, other.readReceipt),
      softShadow: mix(softShadow, other.softShadow),
      softBorder: mix(softBorder, other.softBorder),
    );
  }
}

extension JuriiColors on BuildContext {
  /// Paleta semântica do tema ativo (claro ou escuro).
  AppColors get jColors => Theme.of(this).extension<AppColors>()!;
}
