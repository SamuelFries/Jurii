import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Colunas pedidas num `.select('a, b, c')`, incluindo listas quebradas em
/// várias strings adjacentes pelo formatador.
Set<String> _colunasDoSelect(String fonte, String metodo) {
  final corpo = _corpoDoMetodo(fonte, metodo);
  final chamada = RegExp(
    r"\.select\(\s*((?:'[^']*'\s*)+)\s*,?\s*\)",
  ).firstMatch(corpo);
  expect(
    chamada,
    isNotNull,
    reason: 'não achei um .select com lista explícita em $metodo',
  );

  final literal = RegExp(
    r"'([^']*)'",
  ).allMatches(chamada!.group(1)!).map((m) => m.group(1)!).join();

  return literal
      .split(',')
      .map((c) => c.trim())
      // Descarta o join aninhado ("tabela(*)"), que traz tudo por si.
      .where((c) => c.isNotEmpty && !c.contains('('))
      .toSet();
}

/// Chaves `row['x']` lidas por um parser.
Set<String> _chavesLidas(String fonte, String parser) {
  final corpo = _corpoDoMetodo(fonte, parser);
  return RegExp(
    r"row\['([a-z_]+)'\]",
  ).allMatches(corpo).map((m) => m.group(1)!).toSet();
}

/// Recorta o corpo de um método, seja bloco (`{ … }`) ou seta (`=> … ;`).
///
/// Grosseiro de propósito: é análise de texto, não compilador. O que ele
/// precisa acertar é achar o fim do corpo sem se confundir com os parênteses
/// da própria assinatura.
String _corpoDoMetodo(String fonte, String assinatura) {
  final inicio = fonte.indexOf(assinatura);
  expect(inicio, isNot(-1), reason: 'não achei $assinatura');

  // Pula a lista de parâmetros da assinatura.
  var i = fonte.indexOf('(', inicio);
  var parens = 0;
  for (; i < fonte.length; i++) {
    if (fonte[i] == '(') parens++;
    if (fonte[i] == ')') {
      parens--;
      if (parens == 0) break;
    }
  }

  final chave = fonte.indexOf('{', i);
  final seta = fonte.indexOf('=>', i);
  final blocoPrimeiro = chave != -1 && (seta == -1 || chave < seta);

  if (blocoPrimeiro) {
    var profundidade = 0;
    for (var j = chave; j < fonte.length; j++) {
      if (fonte[j] == '{') profundidade++;
      if (fonte[j] == '}') {
        profundidade--;
        if (profundidade == 0) return fonte.substring(inicio, j + 1);
      }
    }
    return fonte.substring(inicio);
  }

  // Corpo de seta: vai até o `;` fora de parênteses.
  var profundidade = 0;
  for (var j = seta; j < fonte.length; j++) {
    if (fonte[j] == '(') profundidade++;
    if (fonte[j] == ')') profundidade--;
    if (fonte[j] == ';' && profundidade == 0) {
      return fonte.substring(inicio, j + 1);
    }
  }
  return fonte.substring(inicio);
}

void main() {
  test('o select de planos pede toda coluna que o parser lê', () {
    // O BUG QUE ISTO TRAVA: o select pedia
    //   'code, name, max_lawyers, monthly_price_cents, sort_order'
    // e o parser lia row['annual_price_cents']. A coluna chegava NULA, sem
    // erro, sem log, sem exceção. Na tela, a chave Mensal/Anual não mudava
    // preço nem mostrava desconto, e nada no app dizia por quê.
    //
    // Nenhum teste de widget pegaria isso: todos injetam repositório fake,
    // que devolve objetos prontos e pula a query inteira. A lista de colunas
    // só é exercitada contra o banco de verdade, ou aqui.
    final repositorio = File(
      'lib/repositories/license_repository.dart',
    ).readAsStringSync();
    final modelo = File(
      'lib/models/law_firm_license.dart',
    ).readAsStringSync();

    final pedidas = _colunasDoSelect(repositorio, 'Future<List<LicensePlan>> fetchPlans');
    final lidas = _chavesLidas(modelo, 'factory LicensePlan.fromRow');

    expect(lidas, isNotEmpty, reason: 'o parser não lê chave nenhuma?');
    expect(
      lidas.difference(pedidas),
      isEmpty,
      reason:
          'LicensePlan.fromRow lê coluna que fetchPlans não pede. '
          'Ela chegaria nula em silêncio.',
    );
  });

  test('a assinatura é lida com "*", então não some coluna nova', () {
    // fetchMyLicense e fetchFirmLicense usam select('*, ...(*)'): coluna nova
    // na tabela chega sozinha. Se um dia virar lista explícita, este teste
    // avisa que o teste de cobertura acima precisa cobrir esses dois também.
    final repositorio = File(
      'lib/repositories/license_repository.dart',
    ).readAsStringSync();

    final selects = RegExp(
      r"\.select\(\s*'([^']*)'",
    ).allMatches(repositorio).map((m) => m.group(1)!).toList();

    final daAssinatura = selects.where((s) => s.contains('law_firm_license_plans('));
    expect(daAssinatura, hasLength(2), reason: 'fetchMyLicense e fetchFirmLicense');
    for (final s in daAssinatura) {
      expect(
        s.startsWith('*'),
        isTrue,
        reason:
            'virou lista explícita: acrescente a checagem de cobertura para '
            'LicenseSubscription.fromRow, senão coluna nova some em silêncio',
      );
    }
  });
}
