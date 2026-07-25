import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/categories_section.dart';
import 'package:jurii/widgets/category_card.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  testWidgets('grid mostra as 6 categorias canônicas', (tester) async {
    await tester.pumpWidget(_host(const CategoriesSection()));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryCard), findsNWidgets(6));
    expect(find.text('Divórcio e Família'), findsOneWidget);
    expect(find.text('Previdenciário'), findsOneWidget);
    expect(find.text('Toque para filtrar advogados e escritórios.'),
        findsOneWidget);
  });

  testWidgets('tap usa a área canônica do banco, não a heurística',
      (tester) async {
    String? selectedArea;
    await tester.pumpWidget(
      _host(CategoriesSection(onCategorySelected: (area) {
        selectedArea = area;
      })),
    );
    await tester.pumpAndSettle();

    // "Previdenciário" não existe na heurística por título — se o filtro
    // chegar como a área canônica, veio de LegalCategory.practiceArea.
    await tester.tap(find.text('Previdenciário'));
    expect(selectedArea, 'Direito Previdenciário');

    await tester.tap(find.text('Divórcio e Família'));
    expect(selectedArea, 'Direito de Família');
  });

  testWidgets('selecionado é dourado; demais são uniformes', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(const CategoriesSection(searchQuery: 'Direito Trabalhista')),
    );
    await tester.pumpAndSettle();

    AnimatedContainer cardOf(String title) => tester.widget<AnimatedContainer>(
          find
              .ancestor(
                of: find.text(title),
                matching: find.byType(AnimatedContainer),
              )
              .last,
        );

    final selectedBox =
        cardOf('Trabalhista').decoration as BoxDecoration?;
    final normalBox = cardOf('Consumidor').decoration as BoxDecoration?;
    expect(selectedBox, isNotNull);
    expect(normalBox, isNotNull);
    expect(selectedBox!.color, isNot(equals(normalBox!.color)));

    // O rótulo acessível espelha o estado: selecionado oferece "remover".
    // RegExp: o nó mesclado concatena o label com o texto do filho.
    expect(
      find.bySemanticsLabel(RegExp('Remover filtro Trabalhista')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Filtrar por Consumidor')),
      findsOneWidget,
    );

    semantics.dispose();
  });
}
