import 'package:flutter/material.dart';
import 'package:jurii/screens/profile_screen.dart';
import 'package:jurii/screens/register_screen.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the register screen', (WidgetTester tester) async {
    await tester.pumpWidget(_testApp(const RegisterScreen()));

    expect(
      find.text('Crie sua conta e encontre o suporte\njurídico que você precisa.'),
      findsOneWidget,
    );
    expect(find.text('Nome completo'), findsOneWidget);
    expect(find.text('Seu e-mail'), findsOneWidget);
    expect(find.text('Seu CPF'), findsOneWidget);
    expect(find.text('Crie uma senha'), findsOneWidget);
    expect(find.text('Confirme sua senha'), findsOneWidget);

    expect(find.text('Criar conta'), findsOneWidget);
  });

  testWidgets('updates password strength while typing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp(const RegisterScreen()));

    expect(find.text('Senha fraca'), findsNothing);
    expect(find.text('Senha média'), findsNothing);
    expect(find.text('Senha forte'), findsNothing);

    final passwordField = find.byType(TextFormField).at(3);

    await tester.enterText(passwordField, 'abc');
    await tester.pump();

    expect(find.text('Senha fraca'), findsOneWidget);

    await tester.enterText(passwordField, 'Abcdefgh');
    await tester.pump();

    expect(find.text('Senha média'), findsOneWidget);

    await tester.enterText(passwordField, 'Abcdefgh1!');
    await tester.pump();

    expect(find.text('Senha forte'), findsOneWidget);
  });

  testWidgets('formats cpf while typing only digits', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp(const RegisterScreen()));

    final cpfField = find.byType(TextFormField).at(2);

    await tester.enterText(cpfField, '123abc45678900');
    await tester.pump();

    expect(find.text('123.456.789-00'), findsOneWidget);
  });

  testWidgets('professional mode button opens verification screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const Scaffold(
          body: ProfileScreen(),
        ),
      ),
    );

    await tester.tap(find.text('Ativar Modo Profissional'));
    await tester.pumpAndSettle();

    expect(find.text('Verificação profissional'), findsOneWidget);
    expect(find.text('Vamos validar seu cadastro na OAB'), findsOneWidget);
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: child,
  );
}
