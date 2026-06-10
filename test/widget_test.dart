import 'package:flutter/material.dart';
import 'package:jurii/data/mock/mock_users.dart';
import 'package:jurii/models/lawyer_status.dart';
import 'package:jurii/models/lawyer_verification.dart';
import 'package:jurii/screens/profile_screen.dart';
import 'package:jurii/screens/register_screen.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final clientUser = mockCurrentUser.copyWith(
    lawyerStatus: LawyerStatus.client,
  );

  testWidgets('shows the register screen', (WidgetTester tester) async {
    await tester.pumpWidget(_testApp(RegisterScreen(onLogin: () {})));

    expect(
      find.text(
        'Crie sua conta e encontre o suporte\njurídico que você precisa.',
      ),
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
    await tester.pumpWidget(_testApp(RegisterScreen(onLogin: () {})));

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
    await tester.pumpWidget(_testApp(RegisterScreen(onLogin: () {})));

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
        Scaffold(
          body: ProfileScreen(
            user: clientUser,
            onVerificationSubmitted: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ativar Modo Profissional'));
    await tester.pumpAndSettle();

    expect(find.text('Ative seu Perfil\nProfissional'), findsOneWidget);
    expect(find.text('Começar Verificação'), findsOneWidget);
  });

  testWidgets('submitting verification emits pending verification', (
    WidgetTester tester,
  ) async {
    LawyerVerification? submittedVerification;

    await tester.pumpWidget(
      _testApp(
        Scaffold(
          body: ProfileScreen(
            user: clientUser,
            onVerificationSubmitted: (verification) {
              submittedVerification = verification;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ativar Modo Profissional'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Começar Verificação'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Começar Verificação'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '123456');
    await tester.ensureVisible(find.text('Estado da OAB'));
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AC').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Área de atuação'));
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Direito Civil').last);
    await tester.pumpAndSettle();

    while (find.text('Selecionar').evaluate().isNotEmpty) {
      await tester.ensureVisible(find.text('Selecionar').first);
      await tester.tap(find.text('Selecionar').first);
      await tester.pump();
    }

    await tester.ensureVisible(find.text('Enviar para análise'));
    await tester.tap(find.text('Enviar para análise'));
    await tester.pumpAndSettle();

    expect(submittedVerification, isNotNull);
    expect(find.text('Solicitação enviada'), findsOneWidget);
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(theme: AppTheme.lightTheme, home: child);
}
