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

    test('o anual mostra só o equivalente mensal, com desconto calculado', () {
      const plano = LicensePlan(
        code: 'escritorio',
        name: 'Escritório',
        maxLawyers: 10,
        monthlyPriceCents: 34900,
        annualPriceCents: 348000,
      );
      // Só o por mês: o total do ano não aparece na tela, para dois números
      // não competirem no mesmo cartão.
      expect(plano.annualMonthlyLabel, 'R\$ 290');
      // Calculado, não declarado: mudou o preço na tabela, o selo acompanha.
      expect(plano.annualDiscountPercent, 17);
    });

    test('os três planos fecham no MESMO desconto', () {
      // O selo mostra o MENOR desconto entre os planos. Se um deles cair para
      // 16%, o selo inteiro cai junto e a promessa muda sem ninguém notar.
      const planos = [
        LicensePlan(
          code: 'essencial',
          name: 'Essencial',
          maxLawyers: 3,
          monthlyPriceCents: 14900,
          annualPriceCents: 148800,
        ),
        LicensePlan(
          code: 'escritorio',
          name: 'Escritório',
          maxLawyers: 10,
          monthlyPriceCents: 34900,
          annualPriceCents: 348000,
        ),
        LicensePlan(
          code: 'banca',
          name: 'Banca',
          maxLawyers: 25,
          monthlyPriceCents: 69900,
          annualPriceCents: 696000,
        ),
      ];
      for (final plano in planos) {
        expect(
          plano.annualDiscountPercent,
          17,
          reason: '${plano.code} não fecha em 17%',
        );
        // Equivalente mensal em reais inteiros: é o número que a tela mostra.
        expect(plano.annualPriceCents! % 1200, 0);
      }
    });

    test('plano sem preço anual não inventa rótulo nem desconto', () {
      const soMensal = LicensePlan(
        code: 'x',
        name: 'X',
        maxLawyers: 5,
        monthlyPriceCents: 10000,
      );
      expect(soMensal.annualMonthlyLabel, isNull);
      expect(soMensal.annualDiscountPercent, isNull);
    });

    test('o ciclo anual aparece no rótulo do perfil', () {
      final anual = LicenseSubscription(
        id: 's1',
        ownerProfileId: 'u1',
        planCode: 'banca',
        billingCycle: 'annual',
        status: LicenseStatus.active,
        plan: const LicensePlan(
          code: 'banca',
          name: 'Banca',
          maxLawyers: 25,
          monthlyPriceCents: 69900,
          annualPriceCents: 696000,
        ),
      );
      expect(anual.statusLabel(DateTime(2026, 8, 8)), 'Banca · anual · ativo');
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
      // Mesma regra de assinatura_esta_viva no banco.
      final agora = DateTime(2026, 8, 8);
      final futuro = DateTime(2026, 8, 31);
      expect(
        assinatura(
          status: LicenseStatus.trialing,
          fimDoTeste: futuro,
        ).vivaEm(agora),
        isTrue,
      );
      expect(assinatura(status: LicenseStatus.active).vivaEm(agora), isTrue);
      expect(assinatura(status: LicenseStatus.pastDue).vivaEm(agora), isFalse);
      expect(assinatura(status: LicenseStatus.canceled).vivaEm(agora), isFalse);
    });

    test('teste VENCIDO não dá passagem, por mais que o status diga trialing', () {
      // O furo que a 20260906120000 fechou, do lado do app: 'trialing' nunca
      // vencia, então trinta dias eram para sempre.
      final agora = DateTime(2026, 8, 8);
      final vencida = assinatura(fimDoTeste: DateTime(2026, 8, 1));
      expect(vencida.status, LicenseStatus.trialing);
      expect(vencida.testeVencido(agora), isTrue);
      expect(vencida.vivaEm(agora), isFalse);

      // E o dia exato do vencimento já conta como vencido: o teste é DE 30
      // dias, e não de 30 dias mais um pedaço.
      final noMinuto = assinatura(fimDoTeste: agora);
      expect(noMinuto.vivaEm(agora), isFalse);
    });

    test('teste sem data de fim vale como vencido, e não como eterno', () {
      // Entre errar para o lado de cobrar e errar para o lado de liberar para
      // sempre, este é o lado seguro. Mesma escolha do banco.
      final semData = assinatura(fimDoTeste: null);
      expect(semData.vivaEm(DateTime(2026, 8, 8)), isFalse);
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
      // TESTE VENCIDO TEM NOME PRÓPRIO. Antes o rótulo dizia "teste grátis,
      // 0 dias restantes" para sempre, no exato momento em que a pessoa
      // precisa entender por que o escritório parou de convidar advogados.
      expect(
        assinatura(fimDoTeste: DateTime(2026, 8, 1)).statusLabel(agora),
        'Escritório · teste encerrado',
      );
      expect(
        assinatura(fimDoTeste: DateTime(2026, 8, 8, 20)).statusLabel(agora),
        'Escritório · teste grátis, último dia',
      );
    });

    test('status desconhecido do servidor cai em trialing, não em crash', () {
      expect(LicenseStatus.fromValue('coisa_nova'), LicenseStatus.trialing);
      expect(LicenseStatus.fromValue(null), LicenseStatus.trialing);
    });
  });
}
