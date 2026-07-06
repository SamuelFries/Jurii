import 'package:flutter/material.dart';

/// Controle global de tema (claro/escuro/sistema).
///
/// O MaterialApp já escuta este controller; hoje o app permanece em
/// [ThemeMode.light] porque as telas ainda referenciam as constantes
/// estáticas de AppTheme e não reagiriam ao tema escuro.
///
/// Quando a migração para `context.jColors` terminar (docs/architecture.md):
///  1. troque o default para ThemeMode.system;
///  2. exponha o toggle no perfil chamando [setMode];
///  3. persista a escolha (shared_preferences) dentro de [setMode].
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._() : super(ThemeMode.light);

  static final ThemeController instance = ThemeController._();

  ThemeMode get mode => value;

  void setMode(ThemeMode mode) {
    if (value == mode) return;
    value = mode;
  }
}
