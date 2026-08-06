import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/practice_area_selector.dart';

void main() {
  Widget app({
    required List<String> selecionadas,
    List<String> herdadas = const [],
    ValueChanged<List<String>>? onChanged,
  }) {
    var atuais = selecionadas;
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: PracticeAreaSelector(
              selectedAreas: atuais,
              extraAreas: herdadas,
              showError: false,
              onChanged: (novas) {
                onChanged?.call(novas);
                setState(() => atuais = novas);
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> buscar(WidgetTester tester, String termo) async {
    await tester.enterText(find.byKey(const Key('practice_area_search')), termo);
    await tester.pumpAndSettle();
  }

  testWidgets('a busca filtra os chips', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(selecionadas: const []));
    await tester.pumpAndSettle();

    // São 39 áreas: sem filtro o formulário é uma parede de chips, e quem
    // procura a sua rola até desistir.
    expect(find.text('Direito Ambiental'), findsOneWidget);

    await buscar(tester, 'ambiental');

    expect(find.text('Direito Ambiental'), findsOneWidget);
    expect(find.text('Direito Trabalhista'), findsNothing);
  });

  testWidgets('acha a área pelo que ela resolve, não só pelo nome', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(selecionadas: const []));
    await tester.pumpAndSettle();

    // Quem faz inventário não procura por "sucessões"; procura por
    // "inventário". Casar só pelo rótulo exigiria decorar a taxonomia.
    await buscar(tester, 'inventário');
    expect(find.text('Direito das Sucessões'), findsOneWidget);

    await buscar(tester, 'seguradora');
    expect(find.text('Direito Securitário'), findsOneWidget);
  });

  testWidgets('o que está marcado NÃO some com o filtro', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(selecionadas: const ['Direito Trabalhista']));
    await tester.pumpAndSettle();

    await buscar(tester, 'ambiental');

    // Esconder a própria escolha atrás de um filtro faz a pessoa achar que
    // desmarcou — e remarcar duplicaria nada, mas desmarcaria de verdade.
    expect(find.text('Direito Trabalhista'), findsOneWidget);
    expect(find.text('Direito Ambiental'), findsOneWidget);
    expect(find.text('Direito Cível'), findsNothing);
  });

  testWidgets('busca sem resultado explica em vez de mostrar vazio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(selecionadas: const []));
    await tester.pumpAndSettle();

    await buscar(tester, 'zzzzzz');

    expect(find.text('Nenhuma área com esse nome.'), findsOneWidget);
  });

  testWidgets('área herdada aparece marcada e some depois de removida', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    List<String>? ultimo;
    await tester.pumpWidget(
      app(
        selecionadas: const ['Especialidade Antiga'],
        herdadas: const ['Especialidade Antiga'],
        onChanged: (novas) => ultimo = novas,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Especialidade Antiga'), findsOneWidget);
    expect(find.text('1 área marcada'), findsOneWidget);

    await tester.tap(find.text('Especialidade Antiga'));
    await tester.pumpAndSettle();

    expect(ultimo, isEmpty);
    // Uma vez removida não volta: o vocabulário novo é o canônico.
    expect(find.text('Especialidade Antiga'), findsNothing);
  });

  testWidgets('o contador conta o que está marcado', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      app(selecionadas: const ['Direito Cível', 'Direito Trabalhista']),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 áreas marcadas'), findsOneWidget);
  });
}
