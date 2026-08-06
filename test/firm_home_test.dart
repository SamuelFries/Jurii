import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/firm_role.dart';
import 'package:jurii/models/firm_team_member.dart';
import 'package:jurii/models/firm_workspace.dart';
import 'package:jurii/models/law_firm.dart';
import 'package:jurii/models/professional_reach.dart';
import 'package:jurii/repositories/discovery_metrics_repository.dart';
import 'package:jurii/repositories/professional_reach_repository.dart';
import 'package:jurii/screens/firm_home_screen.dart';
import 'package:jurii/theme/app_theme.dart';

const _firm = LawFirm(
  id: 'f1',
  name: 'Weber e Silva',
  initials: 'WS',
  rating: 4.9,
  distance: '',
  specialty: 'Direito Cível',
  practiceAreas: ['Direito Cível'],
  reviews: 8,
  avatarType: 'blue',
);

FirmTeamMember _member(
  String id, {
  required bool available,
  String specialty = 'Direito Cível',
}) => FirmTeamMember(
  id: id,
  name: 'Advogado $id',
  initials: 'A$id',
  role: FirmRole.lawyer,
  specialty: specialty,
  activeCases: 0,
  responseHours: 2,
  rating: 5,
  available: available,
);

FirmWorkspace _workspace({
  List<FirmRole> roles = const [FirmRole.owner],
  List<FirmTeamMember> team = const [],
  bool fromSupabase = true,
}) => FirmWorkspace(
  firm: _firm,
  currentUserRole: roles.first,
  currentUserRoles: roles,
  teamMembers: team,
  fromSupabase: fromSupabase,
);

class _FakeReachRepository implements ProfessionalReachRepository {
  _FakeReachRepository(this.resumo);

  final ReachSummary resumo;
  int chamadas = 0;

  @override
  Future<ReachSummary> fetchReach({
    required DiscoveryTarget target,
    required String targetId,
    int windowDays = 30,
  }) async {
    chamadas++;
    return resumo;
  }
}

/// 14 dias: 7 antigos com 1/dia (base da variação) e 7 recentes com 3/dia.
ReachSummary _resumoComMovimento() {
  final hoje = DateTime(2026, 8, 6);
  return summarizeReach([
    for (var i = 13; i >= 0; i--)
      ReachDay(
        day: hoje.subtract(Duration(days: i)),
        reach: i >= 7 ? 1 : 3,
        sponsoredReach: 0,
        profileViews: 1,
        conversations: 0,
      ),
  ], 7);
}

void main() {
  Widget app(
    FirmWorkspace? workspace, {
    ProfessionalReachRepository? reach,
    VoidCallback? onOpenMessages,
    VoidCallback? onOpenTeam,
    VoidCallback? onOpenCases,
  }) => MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: FirmHomeScreen(
        workspace: workspace,
        reachRepository: reach ?? _FakeReachRepository(_resumoComMovimento()),
        onOpenMessages: onOpenMessages ?? () {},
        onOpenTeam: onOpenTeam ?? () {},
        onOpenCases: onOpenCases ?? () {},
      ),
    ),
  );

  Future<void> abrir(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  testWidgets('cada linha da operação aparece UMA vez e abre a aba certa', (
    tester,
  ) async {
    var casos = 0;
    var equipe = 0;
    var mensagens = 0;
    await abrir(
      tester,
      app(
        _workspace(team: [_member('1', available: true)]),
        onOpenCases: () => casos++,
        onOpenTeam: () => equipe++,
        onOpenMessages: () => mensagens++,
      ),
    );

    // A antiga seção "Hoje" repetia estes rótulos logo abaixo da grade.
    expect(find.text('Conversas com clientes'), findsOneWidget);
    expect(find.text('Casos ativos'), findsOneWidget);
    expect(find.text('Membros ativos'), findsOneWidget);

    // Métrica que não leva a lugar nenhum é placar, não painel.
    await tester.tap(find.text('Casos ativos'));
    await tester.tap(find.text('Membros ativos'));
    await tester.tap(find.text('Conversas com clientes'));
    expect(casos, 1);
    expect(equipe, 1);
    expect(mensagens, 1);
  });

  testWidgets('os botões gigantes que duplicavam a bottom nav morreram', (
    tester,
  ) async {
    await abrir(tester, app(_workspace()));

    // "Mensagens", "Equipe" e "Casos" como blocos soltos duplicavam a nav —
    // a seção Equipe existe, mas como título de seção com conteúdo, não como
    // botão-atalho.
    expect(find.text('Mensagens'), findsNothing);
    expect(find.text('Casos'), findsNothing);
    expect(find.text('Hoje'), findsNothing);
  });

  testWidgets('o cabeçalho espelha o do advogado: papel e chips de status', (
    tester,
  ) async {
    await abrir(
      tester,
      app(_workspace(roles: const [FirmRole.owner, FirmRole.lawyer])),
    );

    expect(find.text('Weber e Silva'), findsOneWidget);
    expect(find.text('Você atua como Sócio / Advogado'), findsOneWidget);
    // Chips dentro do cartão, como "Perfil verificado" na home do advogado.
    expect(find.text('Escritório verificado'), findsOneWidget);
    expect(find.text('Direito Cível'), findsOneWidget);
  });

  testWidgets('a equipe aparece como tiles, disponíveis primeiro', (
    tester,
  ) async {
    var equipe = 0;
    await abrir(
      tester,
      app(
        _workspace(
          team: [
            _member('1', available: false),
            _member('2', available: true),
            _member('3', available: true),
            _member('4', available: false),
          ],
        ),
        onOpenTeam: () => equipe++,
      ),
    );

    // 4 membros, 3 tiles: quem pode atender agora nunca fica de fora por
    // ordem de cadastro.
    expect(find.text('Advogado 2'), findsOneWidget);
    expect(find.text('Advogado 3'), findsOneWidget);
    expect(find.text('Advogado 4'), findsNothing);
    expect(find.text('2 de 4 disponíveis agora'), findsOneWidget);

    await tester.tap(find.text('Advogado 2'));
    expect(equipe, 1);

    // O "Ver tudo" da seção também leva à aba.
    await tester.tap(find.text('Ver tudo'));
    expect(equipe, 2);
  });

  testWidgets('equipe vazia convida a montar em vez de mostrar zero', (
    tester,
  ) async {
    var equipe = 0;
    await abrir(tester, app(_workspace(), onOpenTeam: () => equipe++));

    // Escritório recém-aprovado: zero membros não é métrica, é próximo passo.
    expect(find.text('Monte sua equipe'), findsOneWidget);

    await tester.tap(find.text('Monte sua equipe'));
    expect(equipe, 1);
  });

  testWidgets('sócio vê o chamariz de alcance com número e variação', (
    tester,
  ) async {
    final reach = _FakeReachRepository(_resumoComMovimento());
    await abrir(tester, app(_workspace(), reach: reach));

    expect(reach.chamadas, 1);
    expect(find.text('Alcance'), findsOneWidget);
    expect(
      find.text('visualizações na busca nos últimos 7 dias'),
      findsOneWidget,
    );
    // 7 dias antigos com 1/dia -> 7; recentes com 3/dia -> 21: subiu 200%.
    expect(find.text('200%'), findsOneWidget);
    expect(find.text('Ver painel'), findsOneWidget);
  });

  testWidgets('secretária NÃO vê o chamariz de alcance', (tester) async {
    final reach = _FakeReachRepository(_resumoComMovimento());
    await abrir(
      tester,
      app(_workspace(roles: const [FirmRole.secretary]), reach: reach),
    );

    // Buscar para quem o servidor recusa só renderia um erro sem saída —
    // mesmo portão do painel completo no Perfil.
    expect(reach.chamadas, 0);
    expect(find.text('Alcance'), findsNothing);
  });

  testWidgets('sem workspace do servidor não há chamariz de alcance', (
    tester,
  ) async {
    final reach = _FakeReachRepository(_resumoComMovimento());
    await abrir(tester, app(_workspace(fromSupabase: false), reach: reach));

    expect(reach.chamadas, 0);
    expect(find.text('Alcance'), findsNothing);
    expect(find.text('Área do escritório em preparação'), findsOneWidget);
    expect(find.text('Em preparação'), findsOneWidget);
  });

  testWidgets('o chamariz abre o painel completo', (tester) async {
    await abrir(tester, app(_workspace()));

    await tester.tap(find.text('Ver painel'));
    await tester.pumpAndSettle();

    // O painel completo tem o próprio título na app bar.
    expect(find.text('Seu alcance'), findsOneWidget);
  });

  testWidgets('não estoura em tela de celular, nos dois temas', (
    tester,
  ) async {
    // Overflow de RenderFlex vira exceção em teste: isto trava regressão de
    // layout no tamanho REAL de uso (o resto da suíte roda em viewport largo).
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final workspace = _workspace(
      roles: const [FirmRole.owner, FirmRole.admin, FirmRole.lawyer],
      team: [
        _member(
          '1',
          available: true,
          specialty: 'Direito Previdenciário e Trabalhista Empresarial',
        ),
        _member('2', available: false),
      ],
    );

    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: FirmHomeScreen(
              workspace: workspace,
              reachRepository: _FakeReachRepository(_resumoComMovimento()),
              onOpenMessages: () {},
              onOpenTeam: () {},
              onOpenCases: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Weber e Silva'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
