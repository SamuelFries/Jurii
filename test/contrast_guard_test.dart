import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/theme/app_colors.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/legal_agreement_notice.dart';

/// Razão de contraste WCAG (1.0 a 21.0) entre duas cores opacas.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('barreira de contraste AA (4.5:1) — texto corrente', () {
    // O aviso legal do cadastro chegou a ficar em 1.8:1 (cor muted) — texto
    // de consentimento que o usuário não conseguia ler. Estes testes prendem
    // os pares de tokens realmente usados como texto sobre as superfícies.
    for (final (nome, colors) in [
      ('claro', AppColors.light),
      ('escuro', AppColors.dark),
    ]) {
      test('tema $nome: textPrimary legível nas superfícies', () {
        expect(_contrast(colors.textPrimary, colors.background),
            greaterThanOrEqualTo(4.5));
        expect(_contrast(colors.textPrimary, colors.card),
            greaterThanOrEqualTo(4.5));
      });

      test('tema $nome: textSecondary legível nas superfícies', () {
        expect(_contrast(colors.textSecondary, colors.background),
            greaterThanOrEqualTo(4.5));
        expect(_contrast(colors.textSecondary, colors.card),
            greaterThanOrEqualTo(4.5));
        expect(_contrast(colors.textSecondary, colors.lightBlue),
            greaterThanOrEqualTo(4.5));
      });
    }

    test('constante legada AppTheme.textSecondary acompanha o token', () {
      // Telas não migradas ainda leem AppTheme.*; divergir daqui criaria dois
      // cinzas diferentes na mesma tela.
      expect(AppTheme.textSecondary, AppColors.light.textSecondary);
    });
  });

  group('aviso legal do cadastro', () {
    testWidgets('usa textSecondary, nunca muted', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: LegalAgreementNotice(
              prefix: 'Ao continuar, você concorda com os',
            ),
          ),
        ),
      );

      final prefixo = tester.widget<Text>(
        find.text('Ao continuar, você concorda com os'),
      );
      expect(prefixo.style?.color, AppColors.light.textSecondary);
      expect(
        _contrast(prefixo.style!.color!, AppColors.light.background),
        greaterThanOrEqualTo(4.5),
      );
    });
  });
}
