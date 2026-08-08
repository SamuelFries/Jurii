import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/data/mock/mock_license_plans.dart';
import 'package:jurii/data/mock/mock_users.dart';
import 'package:jurii/models/law_firm_license.dart';
import 'package:jurii/repositories/license_repository.dart';
import 'package:jurii/screens/firm_benefits_screen.dart';
import 'package:jurii/screens/firm_plan_screen.dart';
import 'package:jurii/theme/app_theme.dart';

class _FakeLicenseRepository implements LicenseRepository {
  _FakeLicenseRepository({
    this.minha,
    this.erroAoEscolher,
    this.falhaAoListar = false,
  });

  final LicenseSubscription? minha;
  final List<LicensePlan> planos = mockLicensePlans;
  final Object? erroAoEscolher;
  final bool falhaAoListar;

  String? escolhido;
  String? cicloEscolhido;

  @override
  Future<List<LicensePlan>> fetchPlans() async {
    if (falhaAoListar) throw Exception('offline');
    return planos;
  }

  @override
  Future<LicenseSubscription?> fetchMyLicense() async => minha;

  @override
  Future<LicenseSubscription?> fetchFirmLicense(String lawFirmId) async =>
      minha;

  @override
  Future<LicenseSubscription> choosePlan(
    String planCode, {
    String billingCycle = 'monthly',
  }) async {
    escolhido = planCode;
    cicloEscolhido = billingCycle;
    if (erroAoEscolher != null) throw erroAoEscolher!;
    return LicenseSubscription(
      id: 's1',
      ownerProfileId: 'u1',
      planCode: planCode,
      status: LicenseStatus.trialing,
      trialEndsAt: DateTime.now().add(const Duration(days: 30)),
    );
  }
}

LicenseSubscription _assinaturaAtiva() => LicenseSubscription(
  id: 's1',
  ownerProfileId: 'u1',
  planCode: 'essencial',
  status: LicenseStatus.trialing,
  trialEndsAt: DateTime.now().add(const Duration(days: 20)),
);

void main() {
  Future<void> abrir(WidgetTester tester, Widget tela) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: tela),
    );
    await tester.pumpAndSettle();
  }

  group('página de vantagens', () {
    testWidgets('vende só o que existe, e nada de promessa de resultado', (
      tester,
    ) async {
      await abrir(
        tester,
        FirmBenefitsScreen(
          user: mockCurrentUser,
          licenseRepository: _FakeLicenseRepository(),
        ),
      );

      // Cada vantagem mapeia para funcionalidade que EXISTE.
      expect(find.text('Apareça para quem procura'), findsOneWidget);
      expect(find.text('Equipe num lugar só'), findsOneWidget);
      expect(find.text('Números de verdade'), findsOneWidget);

      // Provimento 205/2021: sem promessa de resultado. Se alguém redigir
      // "garanta clientes" aqui, este teste segura.
      expect(find.textContaining('garant'), findsNothing);
      expect(find.textContaining('Garant'), findsNothing);
    });

    testWidgets('sem plano, o CTA leva aos planos', (tester) async {
      await abrir(
        tester,
        FirmBenefitsScreen(
          user: mockCurrentUser,
          licenseRepository: _FakeLicenseRepository(),
        ),
      );

      await tester.tap(find.byKey(const Key('firm_benefits_cta')));
      await tester.pumpAndSettle();

      expect(find.text('Todos os planos incluem tudo.'), findsOneWidget);
    });

    testWidgets('com plano escolhido, a paywall NÃO aparece de novo', (
      tester,
    ) async {
      await abrir(
        tester,
        FirmBenefitsScreen(
          user: mockCurrentUser,
          licenseRepository: _FakeLicenseRepository(minha: _assinaturaAtiva()),
        ),
      );

      // Quem voltou no meio do cadastro (ou vai reenviar depois de recusa)
      // já pagou o pedágio: cobrar de novo é atrito sem função.
      expect(find.text('Continuar cadastro'), findsOneWidget);

      await tester.tap(find.byKey(const Key('firm_benefits_cta')));
      await tester.pumpAndSettle();

      expect(find.text('Cadastre seu\nEscritório'), findsOneWidget);
      expect(find.text('Todos os planos incluem tudo.'), findsNothing);
    });

    testWidgets('quem reentrou com plano escolhido ainda pode trocá-lo', (
      tester,
    ) async {
      await abrir(
        tester,
        FirmBenefitsScreen(
          user: mockCurrentUser,
          licenseRepository: _FakeLicenseRepository(minha: _assinaturaAtiva()),
        ),
      );

      // Sem esta porta, a troca só existiria depois da aprovação.
      await tester.tap(find.byKey(const Key('firm_benefits_trocar_plano')));
      await tester.pumpAndSettle();

      expect(find.text('Plano atual'), findsOneWidget);
    });
  });

  group('paywall (escolha do plano)', () {
    testWidgets('mostra os três planos com preço e teto de equipe', (
      tester,
    ) async {
      await abrir(
        tester,
        FirmPlanScreen(
          user: mockCurrentUser,
          repository: _FakeLicenseRepository(),
        ),
      );

      expect(find.text('Essencial'), findsOneWidget);
      expect(find.text('Escritório'), findsOneWidget);
      expect(find.text('Banca'), findsOneWidget);

      // A chave nasce no ANUAL, com o desconto anunciado nela e o número
      // grande sendo o equivalente POR MÊS (padrão de assinatura de
      // software). O total do ano fica visível logo abaixo, sem esconder.
      expect(find.text('economize 20%'), findsOneWidget);
      expect(find.text('R\$ 119'), findsOneWidget);
      expect(find.text('R\$ 279'), findsOneWidget);
      expect(find.text('R\$ 559'), findsOneWidget);
      expect(find.text('R\$ 3.348/ano'), findsOneWidget);

      // Na mensal, os cheios.
      await tester.tap(find.text('Mensal'));
      await tester.pumpAndSettle();
      expect(find.text('R\$ 149'), findsOneWidget);
      expect(find.text('R\$ 349'), findsOneWidget);
      expect(find.text('R\$ 699'), findsOneWidget);
      expect(find.textContaining('/ano'), findsNothing);

      expect(find.text('Até 10 advogados'), findsOneWidget);
      expect(find.text('Recomendado'), findsOneWidget);
      // Sem cartão e cobrança fora do app: o que o teste grátis significa.
      expect(find.textContaining('30 dias grátis'), findsOneWidget);
    });

    testWidgets('o ciclo escolhido na chave viaja com a confirmação', (
      tester,
    ) async {
      final repo = _FakeLicenseRepository();
      await abrir(
        tester,
        FirmPlanScreen(user: mockCurrentUser, repository: repo),
      );

      // Nasce no anual: confirmar direto contrata o anual.
      await tester.tap(find.byKey(const Key('confirmar_plano')));
      await tester.pumpAndSettle();
      expect(repo.cicloEscolhido, 'annual');

      // Volta, troca para mensal e reconfirma: o ciclo acompanha.
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mensal'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar_plano')));
      await tester.pumpAndSettle();
      expect(repo.cicloEscolhido, 'monthly');
    });

    testWidgets('confirma o plano e VOLTAR devolve a escolha', (
      tester,
    ) async {
      final repo = _FakeLicenseRepository();
      await abrir(
        tester,
        FirmPlanScreen(user: mockCurrentUser, repository: repo),
      );

      // O recomendado já vem selecionado; trocar por outro é um toque.
      await tester.tap(find.text('Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar_plano')));
      await tester.pumpAndSettle();

      expect(repo.escolhido, 'banca');
      expect(find.text('Cadastre seu\nEscritório'), findsOneWidget);

      // Mudar de ideia é caminho legítimo: voltar da verificação devolve a
      // paywall (a primeira versão substituía a tela na pilha e a pessoa
      // ficava presa no plano escolhido).
      // A tela de checklist usa um botão de voltar próprio, não o da AppBar.
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('confirmar_plano')), findsOneWidget);

      await tester.tap(find.text('Essencial'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar_plano')));
      await tester.pumpAndSettle();

      // Reconfirmar troca o plano na mesma assinatura e segue em frente.
      expect(repo.escolhido, 'essencial');
      expect(find.text('Cadastre seu\nEscritório'), findsOneWidget);
    });

    testWidgets('falha ao confirmar vira texto, e a tela não fecha', (
      tester,
    ) async {
      await abrir(
        tester,
        FirmPlanScreen(
          user: mockCurrentUser,
          repository: _FakeLicenseRepository(erroAoEscolher: Exception('x')),
        ),
      );

      await tester.tap(find.byKey(const Key('confirmar_plano')));
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível confirmar o plano. Tente novamente.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('confirmar_plano')), findsOneWidget);
    });

    testWidgets('escritório já assinado por outra pessoa tem erro próprio', (
      tester,
    ) async {
      await abrir(
        tester,
        FirmPlanScreen(
          user: mockCurrentUser,
          repository: _FakeLicenseRepository(
            erroAoEscolher: Exception(
              'PostgrestException(message: Firm already has a subscription)',
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('confirmar_plano')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Este escritório já tem um plano contratado por outra pessoa.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('falha ao carregar mostra retry, não lista vazia', (
      tester,
    ) async {
      await abrir(
        tester,
        FirmPlanScreen(
          user: mockCurrentUser,
          repository: _FakeLicenseRepository(falhaAoListar: true),
        ),
      );

      expect(
        find.text('Não foi possível carregar os planos.'),
        findsOneWidget,
      );
    });

    testWidgets('na troca, o plano atual não é confirmável', (tester) async {
      await abrir(
        tester,
        FirmPlanScreen.upgrade(
          upgradeDe: 'essencial',
          repository: _FakeLicenseRepository(),
        ),
      );

      expect(find.text('Plano atual'), findsOneWidget);

      // Nada selecionado ainda: o botão espera uma escolha.
      final botao = tester.widget<ElevatedButton>(
        find.byKey(const Key('confirmar_plano')),
      );
      expect(botao.onPressed, isNull);

      // Selecionar o PRÓPRIO plano atual continua morto — "trocar" para o
      // mesmo plano não é uma ação.
      await tester.tap(find.text('Essencial'));
      await tester.pumpAndSettle();
      final aindaMorto = tester.widget<ElevatedButton>(
        find.byKey(const Key('confirmar_plano')),
      );
      expect(aindaMorto.onPressed, isNull);

      await tester.tap(find.text('Banca'));
      await tester.pumpAndSettle();
      final vivo = tester.widget<ElevatedButton>(
        find.byKey(const Key('confirmar_plano')),
      );
      expect(vivo.onPressed, isNotNull);
    });
  });

  testWidgets('as duas telas não estouram em celular, nos dois temas', (
    tester,
  ) async {
    // Overflow vira exceção em teste: trava regressão de layout no tamanho
    // REAL de uso — o resto do arquivo roda em viewport largo.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: FirmBenefitsScreen(
            user: mockCurrentUser,
            licenseRepository: _FakeLicenseRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: FirmPlanScreen(
            user: mockCurrentUser,
            repository: _FakeLicenseRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
