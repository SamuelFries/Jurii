import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/appointment.dart';
import 'package:jurii/screens/agenda_screen.dart';
import 'package:jurii/theme/app_theme.dart';

Widget _host(AppointmentRole role) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: AgendaScreen(role: role),
  );
}

void main() {
  // Sem Supabase inicializado o AgendaScreen cai no modo demo (mocks),
  // que é exatamente o caminho que estes testes exercitam.
  testWidgets('agenda agrupa por dia com cabeçalhos', (tester) async {
    // Viewport alto: ListView só monta o que cabe na dobra, e o cabeçalho
    // de amanhã precisa estar montado para o finder enxergá-lo.
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(AppointmentRole.lawyer));
    await tester.pumpAndSettle();

    expect(find.text('HOJE'), findsOneWidget);
    expect(find.text('AMANHÃ'), findsOneWidget);

    // Ordem visual: os de hoje acima do de amanhã.
    final hoje = tester.getTopLeft(find.text('Reunião inicial')).dy;
    final amanha = tester.getTopLeft(find.text('Retorno ao cliente')).dy;
    expect(hoje, lessThan(amanha));

    // Resumo com dado real no lugar da copy de vitrine.
    expect(find.text('2 compromissos hoje'), findsOneWidget);
    expect(
      find.text('Próximo: Hoje às 09:30 · Reunião inicial'),
      findsOneWidget,
    );
    expect(find.text('Organize seus atendimentos'), findsNothing);
  });

  testWidgets('anteriores vazio mostra estado próprio e volta', (
    tester,
  ) async {
    await tester.pumpWidget(_host(AppointmentRole.lawyer));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Anteriores'));
    await tester.pumpAndSettle();

    expect(find.text('Nenhum compromisso anterior'), findsOneWidget);
    expect(find.text('HOJE'), findsNothing);
    // O resumo fala do que vem; em Anteriores ele sai de cena.
    expect(find.text('2 compromissos hoje'), findsNothing);

    await tester.tap(find.text('Próximos'));
    await tester.pumpAndSettle();

    expect(find.text('HOJE'), findsOneWidget);
  });

  testWidgets('cliente também vê cabeçalhos por dia', (tester) async {
    await tester.pumpWidget(_host(AppointmentRole.client));
    await tester.pumpAndSettle();

    expect(find.text('HOJE'), findsOneWidget);
    expect(find.text('Consulta inicial'), findsOneWidget);
  });
}
