import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/main.dart';

void main() {
  testWidgets('sem backend configurado, o selo DEMO aparece em toda tela', (
    tester,
  ) async {
    // No ambiente de teste o Supabase nunca é inicializado — exatamente o
    // estado em que o app cai para dados fictícios.
    await tester.pumpWidget(const JuriiApp());
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Banner && widget.message == 'DEMO',
      ),
      findsOneWidget,
    );
  });
}
