import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/data/mock/mock_users.dart';
import 'package:jurii/models/law_firm_verification.dart';
import 'package:jurii/models/law_firm_verification_status.dart';
import 'package:jurii/screens/client_profile_screen.dart';
import 'package:jurii/screens/profile_screen.dart';
import 'package:jurii/theme/app_theme.dart';

Widget _testApp(Widget child) {
  return MaterialApp(theme: AppTheme.lightTheme, home: child);
}

void main() {
  testWidgets('perfil da contraparte mantém o e-mail dentro da Jurii', (
    tester,
  ) async {
    const email = 'cliente@exemplo.com';
    final profile = mockCurrentUser.copyWith(email: email);

    await tester.pumpWidget(_testApp(ClientProfileScreen(profile: profile)));

    expect(find.text(email), findsNothing);
    expect(
      find.text('Contato mantido dentro da conversa da Jurii'),
      findsOneWidget,
    );
  });

  testWidgets('verificação aprovada sem vínculo ativo não abre escritório', (
    tester,
  ) async {
    const verification = LawFirmVerification(
      ownerProfileId: 'former_owner',
      firmName: 'Fries Advogados',
      cnpj: '12.345.678/0001-90',
      phone: '11999999999',
      email: 'contato@friesadvogados.com',
      address: 'Avenida Paulista, 1000',
      practiceAreas: ['Direito Trabalhista'],
      documents: [],
      status: LawFirmVerificationStatus.approved,
    );

    await tester.pumpWidget(
      _testApp(
        Scaffold(
          body: ProfileScreen(
            user: mockCurrentUser,
            lawFirmVerification: verification,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Área do Escritório'));
    await tester.pump();

    expect(
      find.text('Você não possui um vínculo ativo com este escritório.'),
      findsOneWidget,
    );
  });
}
