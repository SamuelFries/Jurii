import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/data/legal_practice_areas.dart';
import 'package:jurii/data/mock/mock_categories.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/categories_section.dart';
import 'package:jurii/widgets/category_card.dart';

void main() {
  // O DEFEITO QUE ISTO TRAVA: tocar num cartão e digitar as mesmas palavras
  // davam respostas diferentes. "Plano de Saúde" tocado filtrava Direito
  // Médico e da Saúde (1 advogado); "plano de saúde" digitado pescava
  // Direito do Consumidor (4). O atalho entregava menos que o caminho longo,
  // porque legal_categories e as regras de intenção discordavam sobre onde o
  // termo mora.
  //
  // Desde então o toque manda o TÍTULO para a caixa de busca, e este teste
  // garante a ponte: todo título, lido como busca, tem que pescar a própria
  // área do cartão. Categoria nova que falhar aqui precisa de termo novo nas
  // regras de intenção (e no seed de legal_search_intents, que o
  // practice_areas_sync_test força a andar junto).

  test('todo título de categoria, digitado como busca, pesca a própria área', () {
    for (final categoria in mockCategories) {
      final area = categoria.practiceArea;
      expect(
        area,
        isNotNull,
        reason:
            '${categoria.title} sem practice_area cai no fallback por título '
            'e vira busca que não casa com área nenhuma: zero resultado, '
            'sem erro, sem log',
      );
      final inferidas = inferPracticeAreasForSearch(categoria.title);
      expect(
        inferidas,
        contains(area),
        reason:
            'tocar "${categoria.title}" manda o título para a busca, e o '
            'título não pesca $area: o cartão promete uma área que o filtro '
            'não inclui. Acrescente o termo nas regras de intenção.',
      );
    }
  });

  test('toda área de categoria existe na taxonomia canônica', () {
    for (final categoria in mockCategories) {
      expect(
        legalPracticeAreas,
        contains(categoria.practiceArea),
        reason:
            '${categoria.title} aponta para "${categoria.practiceArea}", '
            'que não é nenhuma das ${legalPracticeAreas.length} áreas. '
            'Filtro por ela devolve sempre vazio.',
      );
    }
  });

  test('nenhuma área tem dois cartões', () {
    // Dois cartões para a mesma área é duplicação de curadoria: gastam duas
    // das nove vagas dizendo a mesma coisa.
    final porArea = <String, List<String>>{};
    for (final categoria in mockCategories) {
      porArea.putIfAbsent(categoria.practiceArea!, () => []).add(categoria.title);
    }
    final duplicadas = porArea.entries.where((e) => e.value.length > 1);
    expect(
      duplicadas,
      isEmpty,
      reason: 'cartões dividindo a mesma área: '
          '${duplicadas.map((e) => '${e.key} <- ${e.value}').join('; ')}',
    );
  });

  test('nenhum título normaliza igual a outro', () {
    // O aceso do cartão e o toggle do toque comparam títulos NORMALIZADOS.
    // Dois títulos que normalizam igual acenderiam e apagariam juntos.
    final vistos = <String, String>{};
    for (final categoria in mockCategories) {
      final normalizado = normalizePracticeAreaQuery(categoria.title);
      expect(
        vistos,
        isNot(contains(normalizado)),
        reason:
            '"${categoria.title}" e "${vistos[normalizado]}" normalizam '
            'ambos para "$normalizado"',
      );
      vistos[normalizado] = categoria.title;
    }
  });

  testWidgets('cartão acende por identidade de título, nunca por inferência', (
    tester,
  ) async {
    // O DEFEITO QUE ISTO TRAVA: o aceso era decidido por inferência de área
    // sobre o texto da busca. "Inventário e Herança" infere Direito Cível
    // JUNTO de Direito das Sucessões, então tocar um cartão acendia o outro
    // par. Aceso significa "foi isto que você tocou", nada além.
    Future<void> monta(String query) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CategoriesSection(searchQuery: query),
          ),
        ),
      ),
    );

    Iterable<String> acesos() => tester
        .widgetList<CategoryCard>(find.byType(CategoryCard))
        .where((cartao) => cartao.selected)
        .map((cartao) => cartao.title);

    // O caso do par: o título que infere DUAS áreas acende só a si mesmo.
    await monta('Inventário e Herança');
    await tester.pumpAndSettle();
    expect(acesos(), ['Inventário e Herança']);

    // Busca digitada que infere áreas com cartão não acende cartão nenhum:
    // a pessoa não tocou em nada.
    await monta('plano de saúde negou cirurgia');
    await tester.pumpAndSettle();
    expect(acesos(), isEmpty);

    // Identidade sobrevive a caixa e acento.
    await monta('divórcio e pensão');
    await tester.pumpAndSettle();
    expect(acesos(), ['Divórcio e Pensão']);
  });

  test('o espelho Dart e o seed do banco têm as mesmas categorias', () {
    // mock_categories é o initialData do FutureBuilder: se divergir do seed,
    // o cartão TROCA debaixo do dedo da pessoa quando o fetch chega.
    // O seed mais novo vence, mesma regra do practice_areas_sync_test.
    final migrations =
        Directory('supabase/migrations')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final linhaDeSeed = RegExp(
      r"^  \('([a-z0-9-]+)', '((?:[^']|'')+)', '[a-z0-9_]+',\n"
      r"^   '((?:[^']|'')+)', (?:true|false), \d+\),?$",
      multiLine: true,
    );

    Map<String, String>? doBanco;
    final idParaArea = <String, String>{};
    for (final migration in migrations) {
      final fonte = migration.readAsStringSync();
      if (!fonte.contains('public.legal_categories')) continue;
      // Upsert: o arquivo mais novo sobrepõe id a id, sem apagar o resto.
      for (final linha in linhaDeSeed.allMatches(fonte)) {
        (doBanco ??= {})[linha.group(1)!] =
            linha.group(2)!.replaceAll("''", "'");
        idParaArea[linha.group(1)!] = linha.group(3)!.replaceAll("''", "'");
      }
      // Delete derruba inclusive o que um arquivo ANTERIOR semeou.
      for (final removida in RegExp(
        r"delete from public\.legal_categories where id = '([a-z0-9-]+)'",
      ).allMatches(fonte)) {
        doBanco?.remove(removida.group(1));
        idParaArea.remove(removida.group(1));
      }
    }

    expect(doBanco, isNotNull, reason: 'seed de legal_categories não achado');

    final doApp = {
      for (final categoria in mockCategories) categoria.id: categoria.title,
    };
    expect(doApp, doBanco, reason: 'id ou título divergem entre app e banco');
    for (final categoria in mockCategories) {
      expect(
        idParaArea[categoria.id],
        categoria.practiceArea,
        reason: 'practice_area de ${categoria.id} diverge entre app e banco',
      );
    }
  });
}
