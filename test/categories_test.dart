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
  testWidgets('grid mostra as 9 categorias canônicas', (tester) async {
    await tester.pumpWidget(_host(const CategoriesSection()));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryCard), findsNWidgets(9));
    // Rótulo fala a língua de quem tem o problema, não a do jurista.
    expect(find.text('Divórcio e Pensão'), findsOneWidget);
    expect(find.text('INSS e Aposentadoria'), findsOneWidget);
    // A urgência mais alta que o app recebe precisa de porta para quem
    // navega em vez de digitar.
    expect(find.text('Crime ou Agressão'), findsOneWidget);
    expect(
      find.text('Toque para filtrar advogados e escritórios.'),
      findsOneWidget,
    );
  });

  testWidgets('tap manda o TÍTULO, a palavra do cliente', (tester) async {
    String? enviado;
    await tester.pumpWidget(
      _host(
        CategoriesSection(
          onCategorySelected: (titulo) {
            enviado = titulo;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // É o título que vai para a caixa de busca. Se chegar a área canônica
    // ("Direito Previdenciário"), a regressão voltou: a caixa exibiria a
    // palavra do jurista no lugar da que a pessoa tocou.
    await tester.tap(find.text('INSS e Aposentadoria'));
    expect(enviado, 'INSS e Aposentadoria');

    await tester.tap(find.text('Divórcio e Pensão'));
    expect(enviado, 'Divórcio e Pensão');
  });

  testWidgets('selecionado é dourado; demais são uniformes', (tester) async {
    final semantics = tester.ensureSemantics();
    // A query é o TÍTULO porque o aceso é por identidade: é o que a caixa
    // contém depois do toque. Área canônica não acende cartão nenhum.
    await tester.pumpWidget(
      _host(const CategoriesSection(searchQuery: 'Trabalhista')),
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

    final selectedBox = cardOf('Trabalhista').decoration as BoxDecoration?;
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
