import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/data/mock/mock_users.dart';
import 'package:jurii/models/law_firm_verification.dart';
import 'package:jurii/models/law_firm_verification_status.dart';
import 'package:jurii/screens/law_firm_verification_form_screen.dart';
import 'package:jurii/theme/app_theme.dart';

Widget _testApp({ValueChanged<LawFirmVerification>? onVerificationSubmitted}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: LawFirmVerificationFormScreen(
      user: mockCurrentUser,
      onVerificationSubmitted: onVerificationSubmitted,
    ),
  );
}

Future<void> _fillRequiredFirmData(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('firm_verification_name_field')), 'Fries Advogados');
  await tester.enterText(find.byKey(const Key('firm_verification_cnpj_field')), '12345678000190');
  await tester.enterText(find.byKey(const Key('firm_verification_phone_field')), '11999999999');
  await tester.enterText(
    find.byKey(const Key('firm_verification_email_field')),
    'contato@friesadvogados.com',
  );
  await tester.enterText(
    find.byKey(const Key('firm_verification_address_field')),
    'Avenida Paulista, 1000',
  );
  await tester.enterText(find.byKey(const Key('firm_verification_cep_field')), '01310100');

  await tester.ensureVisible(find.text('Direito Trabalhista'));
  await tester.tap(find.text('Direito Trabalhista'));
  await tester.pump();
}

Future<void> _attachFourRequiredDocuments(WidgetTester tester) async {
  for (var index = 0; index < 4; index++) {
    final selectButton = find
        .widgetWithText(OutlinedButton, 'Selecionar')
        .first;
    await tester.ensureVisible(selectButton);
    await tester.tap(selectButton);
    await tester.pump();
  }
}

void main() {
  testWidgets('foto do escritório aparece como documento opcional', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());

    expect(find.text('Foto de perfil do escritório'), findsOneWidget);
    expect(find.text('Opcional'), findsOneWidget);
    expect(find.text('Adicionar foto'), findsOneWidget);
    // 11 passos desde o CEP obrigatório (7 dados + 4 documentos).
    expect(find.text('0/11'), findsOneWidget);
  });

  testWidgets('envia verificação completa sem selecionar a foto opcional', (
    tester,
  ) async {
    LawFirmVerification? submittedVerification;

    await tester.pumpWidget(
      _testApp(
        onVerificationSubmitted: (verification) {
          submittedVerification = verification;
        },
      ),
    );

    await _fillRequiredFirmData(tester);
    await _attachFourRequiredDocuments(tester);

    expect(find.text('Tudo pronto para análise'), findsOneWidget);
    expect(find.text('11/11'), findsOneWidget);
    expect(find.text('Adicionar foto'), findsOneWidget);

    await tester.ensureVisible(find.text('Enviar para análise'));
    await tester.tap(find.text('Enviar para análise'));
    await tester.pumpAndSettle();

    expect(submittedVerification, isNotNull);
    expect(submittedVerification!.status, LawFirmVerificationStatus.pending);
    expect(submittedVerification!.avatarStoragePath, isNull);
    expect(find.text('Cadastro enviado'), findsOneWidget);
  });

  testWidgets('anexar foto opcional não altera o progresso obrigatório', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());

    // 11 passos desde o CEP obrigatório (7 dados + 4 documentos).
    expect(find.text('0/11'), findsOneWidget);

    await tester.ensureVisible(find.text('Adicionar foto'));
    await tester.tap(find.text('Adicionar foto'));
    await tester.pump();

    expect(find.text('Adicionar foto'), findsNothing);
    expect(find.text('Foto adicionada'), findsOneWidget);
    expect(find.text('Trocar foto'), findsOneWidget);
    // 11 passos desde o CEP obrigatório (7 dados + 4 documentos).
    expect(find.text('0/11'), findsOneWidget);
  });
}
