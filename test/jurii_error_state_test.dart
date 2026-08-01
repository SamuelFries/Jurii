import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/jurii_error_state.dart';

void main() {
  testWidgets('estado de erro mostra título, orientação e retry', (
    tester,
  ) async {
    var retried = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: JuriiErrorState(
            title: 'Não foi possível carregar suas conversas.',
            onRetry: () => retried++,
          ),
        ),
      ),
    );

    expect(
      find.text('Não foi possível carregar suas conversas.'),
      findsOneWidget,
    );
    expect(
      find.text('Verifique sua conexão e tente novamente.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Tentar novamente'));
    expect(retried, 1);
  });
}
