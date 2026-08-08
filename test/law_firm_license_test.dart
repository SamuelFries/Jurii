import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/law_firm_license.dart';

void main() {
  group('preço do plano', () {
    test('preço redondo sai sem centavos, como preço de plano se escreve', () {
      const plano = LicensePlan(
        code: 'escritorio',
        name: 'Escritório',
        maxLawyers: 10,
        monthlyPriceCents: 34900,
      );
      expect(plano.priceLabel, 'R\$ 349');
    });

    test('centavos aparecem quando existem, e milhar ganha ponto', () {
      const quebrado = LicensePlan(
        code: 'x',
        name: 'X',
        maxLawyers: 5,
        monthlyPriceCents: 129990,
      );
      expect(quebrado.priceLabel, 'R\$ 1.299,90');
    });

    test('o preço por advogado é o argumento de crescer sem punição', () {
      const banca = LicensePlan(
        code: 'banca',
        name: 'Banca',
        maxLawyers: 25,
        monthlyPriceCents: 69900,
      );
      expect(banca.perLawyerLabel, '~R\$ 28 por advogado');
      expect(banca.teamLabel, 'Até 25 advogados');
    });

    test('plano sem teto não divide por zero nem mente rótulo', () {
      const semTeto = LicensePlan(
        code: 'custom',
        name: 'Sob medida',
        maxLawyers: null,
        monthlyPriceCents: 100000,
      );
      expect(semTeto.perLawyerLabel, isNull);
      expect(semTeto.teamLabel, 'Sem limite de advogados');
    });
  });

  group('assinatura', () {
    LicenseSubscription assinatura({
      LicenseStatus status = LicenseStatus.trialing,
      DateTime? fimDoTeste,
    }) => LicenseSubscription(
      id: 's1',
      ownerProfileId: 'u1',
      planCode: 'escritorio',
      status: status,
      trialEndsAt: fimDoTeste,
      plan: const LicensePlan(
        code: 'escritorio',
        name: 'Escritório',
        maxLawyers: 10,
        monthlyPriceCents: 34900,
      ),
    );

    test('trialing e active dão passagem; past_due e canceled não', () {
      // Mesma regra do portão no banco (has_law_firm_license).
      expect(assinatura(status: LicenseStatus.trialing).ativa, isTrue);
      expect(assinatura(status: LicenseStatus.active).ativa, isTrue);
      expect(assinatura(status: LicenseStatus.pastDue).ativa, isFalse);
      expect(assinatura(status: LicenseStatus.canceled).ativa, isFalse);
    });

    test('dias restantes nunca ficam negativos', () {
      final agora = DateTime(2026, 8, 8);
      final vencida = assinatura(fimDoTeste: DateTime(2026, 8, 1));
      // "faltam -7 dias" não é frase.
      expect(vencida.diasRestantesDeTeste(agora), 0);

      final valida = assinatura(fimDoTeste: DateTime(2026, 8, 31));
      expect(valida.diasRestantesDeTeste(agora), 23);
    });

    test('o rótulo do perfil fala como gente', () {
      final agora = DateTime(2026, 8, 8);
      expect(
        assinatura(fimDoTeste: DateTime(2026, 8, 31)).statusLabel(agora),
        'Escritório · teste grátis, 23 dias restantes',
      );
      expect(
        assinatura(status: LicenseStatus.active).statusLabel(agora),
        'Escritório · ativo',
      );
      expect(
        assinatura(status: LicenseStatus.pastDue).statusLabel(agora),
        'Escritório · pagamento pendente',
      );
    });

    test('status desconhecido do servidor cai em trialing, não em crash', () {
      expect(LicenseStatus.fromValue('coisa_nova'), LicenseStatus.trialing);
      expect(LicenseStatus.fromValue(null), LicenseStatus.trialing);
    });
  });
}
