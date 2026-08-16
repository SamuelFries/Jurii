import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rascunho de formulário longo, no aparelho.
///
/// O formulário de verificação tem onze passos; uma ligação no meio, e tudo
/// que a pessoa digitou evaporava. O rascunho guarda os CAMPOS DE TEXTO E
/// ESCOLHAS em shared_preferences e devolve na volta.
///
/// O QUE ELE NÃO GUARDA, de propósito: os arquivos escolhidos. Os bytes vivem
/// só na memória até o submit (decisão antiga, boa: documento de OAB não
/// para em disco fora do app), então na volta a pessoa re-escolhe os
/// arquivos — retrabalho de dois toques, contra redigitar tudo.
///
/// Todas as operações falham em SILÊNCIO: rascunho é cortesia, e um aparelho
/// sem espaço não pode transformar o formulário em erro.
class FormDraftStore {
  const FormDraftStore();

  static const String lawyerVerificationKey = 'jurii.rascunho.verificacao';
  static const String firmVerificationKey =
      'jurii.rascunho.verificacao_escritorio';

  Future<Map<String, dynamic>?> load(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (error) {
      debugPrint('FormDraftStore.load falhou: $error');
      return null;
    }
  }

  Future<void> save(String key, Map<String, dynamic> values) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Rascunho todo vazio é o mesmo que rascunho nenhum, e guardar "{}"
      // faria a tela de volta anunciar restauração de nada.
      final hasContent = values.values.any(
        (value) =>
            value != null &&
            (value is! String || value.trim().isNotEmpty) &&
            (value is! List || value.isNotEmpty),
      );
      if (!hasContent) {
        await prefs.remove(key);
        return;
      }
      await prefs.setString(key, jsonEncode(values));
    } catch (error) {
      debugPrint('FormDraftStore.save falhou: $error');
    }
  }

  Future<void> clear(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (error) {
      debugPrint('FormDraftStore.clear falhou: $error');
    }
  }
}
