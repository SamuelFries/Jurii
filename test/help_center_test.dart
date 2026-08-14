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

    // A resposta mudou junto com o produto: desde que a ordenacao por
    // distancia passou para o servidor, a posicao SAI do aparelho quando a
    // pessoa pede essa ordenacao. O teste ancora no que a resposta precisa
    // dizer para ser verdadeira, e nao numa frase bonita.
    expect(find.textContaining('Ordenando por "Distância"'), findsOneWidget);
    expect(find.textContaining('não fica guardada'), findsOneWidget);
  });
}
