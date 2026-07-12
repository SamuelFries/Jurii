import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controle global de tema (claro/escuro/sistema).
///
/// O MaterialApp escuta este controller. Sem escolha salva o app segue o
/// sistema; a escolha do usuário (sheet "Aparência" no perfil) é persistida
/// com shared_preferences e recarregada em [load] antes do primeiro frame.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._() : super(ThemeMode.system);

  static final ThemeController instance = ThemeController._();

  static const String _prefKey = 'jurii.theme_mode';

  ThemeMode get mode => value;

  /// Restaura a escolha persistida (chamado no main, antes do runApp).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefKey);
      value = ThemeMode.values.firstWhere(
        (mode) => mode.name == stored,
        orElse: () => ThemeMode.system,
      );
    } catch (error) {
      // Sem preferência legível, segue o sistema.
      debugPrint('ThemeController.load: $error');
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (value == mode) return;
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, mode.name);
    } catch (error) {
      // Tema já trocou em memória; só a persistência falhou.
      debugPrint('ThemeController.setMode: $error');
    }
  }
}
