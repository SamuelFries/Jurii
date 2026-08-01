import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/screens/help_center_screen.dart';
import 'package:jurii/theme/app_theme.dart';

void main() {
  Future<void> pumpHelp(WidgetTester tester) {
    return tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const HelpCenterScreen()),
    );
  }

  testWidgets('central de ajuda mostra as três seções e o suporte', (
    tester,
  ) async {
    await pumpHelp(tester);

    expect(find.text('PARA CLIENTES'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('PARA ADVOGADOS E ESCRITÓRIOS'),
      200,
    );
    await tester.scrollUntilVisible(find.text('CONTA E PRIVACIDADE'), 200);
    await tester.scrollUntilVisible(find.text('Falar com o suporte'), 200);
    expect(find.text('Falar com o suporte'), findsOneWidget);
  });

  testWidgets('tocar numa pergunta expande a resposta', (tester) async {
    await pumpHelp(tester);

    const pergunta = 'A Jurii tem acesso à minha localização?';
    await tester.scrollUntilVisible(find.text(pergunta), 200);
    await tester.tap(find.text(pergunta));
    await tester.pumpAndSettle();

    expect(find.textContaining('calculada no seu aparelho'), findsOneWidget);
  });
}
