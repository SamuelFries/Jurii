import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/cases.dart';
import 'package:jurii/models/case_request.dart';
import 'package:jurii/models/firm_case_overview.dart';
import 'package:jurii/models/firm_role.dart';
import 'package:jurii/models/firm_workspace.dart';
import 'package:jurii/models/law_firm.dart';
import 'package:jurii/models/lawyer_case.dart';
import 'package:jurii/repositories/case_repository.dart';
import 'package:jurii/screens/cases_screen.dart';
import 'package:jurii/screens/firm_cases_screen.dart';
import 'package:jurii/screens/lawyer_cases_screen.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/jurii_search_field.dart';

/// A FIAÇÃO, não a regra.
///
/// test/inbox_filters_test.dart prova que as funções puras filtram certo.
/// Isso não prova NADA sobre a tela: ela pode ter o campo de busca desligado,
/// filtrar a lista e desenhar a original, ou nem chamar o filtro. Já
/// aconteceu nesta base (um teste injetou a tela direto e a sabotagem passou
/// verde). Aqui as telas de verdade são montadas, o texto é digitado no campo
/// de verdade, e o que se mede é o que sobrou na tela.

class _FakeCaseRepository implements CaseRepository {
  _FakeCaseRepository({
    this.clientCases = const [],
    this.requests = const [],
    this.lawyerCases = const [],
    this.firmCases = const [],
  });

  final List<LegalCase> clientCases;
  final List<CaseRequest> requests;
  final List<LawyerCase> lawyerCases;
  final List<FirmCaseOverview> firmCases;

  @override
  Future<List<LegalCase>> fetchClientCases() async => clientCases;

  @override
  Future<List<CaseRequest>> fetchClientCaseRequests() async => requests;

  @override
  Future<List<LawyerCase>> fetchLawyerCases() async => lawyerCases;

  @override
  Future<List<FirmCaseOverview>> fetchLawFirmCases(String lawFirmId) async =>
      firmCases;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LawyerCase _casoDoAdvogado(String cliente, {String? cnj}) => LawyerCase(
  id: cliente,
  title: 'Caso de $cliente',
  clientName: cliente,
  clientInitials: 'CL',
  area: 'Direito Trabalhista',
  lastUpdate: 'hoje',
  status: LawyerCaseStatus.updated,
  cnjNumber: cnj,
);

FirmCaseOverview _casoDoEscritorio(
  String cliente, {
  String? advogadoId,
  String advogado = 'Sem advogado definido',
}) => FirmCaseOverview(
  id: cliente,
  title: 'Caso de $cliente',
  clientName: cliente,
  clientInitials: 'CL',
  assignedLawyerId: advogadoId,
  assignedLawyer: advogado,
  area: 'Direito Cível',
  statusLabel: 'Em andamento',
  nextStep: 'Aguardando',
  urgent: false,
);

Widget _host(Widget child) =>
    MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: child));

/// Digita no campo de busca DA TELA e espera o debounce de 250ms passar.
Future<void> _buscar(WidgetTester tester, String termo) async {
  expect(
    find.byType(JuriiSearchField),
    findsOneWidget,
    reason: 'a tela não tem campo de busca',
  );
  await tester.enterText(find.byType(JuriiSearchField), termo);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('casos do cliente: a busca esconde o que não casa', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CasesScreen(
          repository: _FakeCaseRepository(
            clientCases: const [
              LegalCase(
                id: '1',
                title: 'Rescisão indireta',
                area: 'Direito Trabalhista',
                status: 'Em andamento',
                cnjNumber: '08012345620268260100',
              ),
              LegalCase(
                id: '2',
                title: 'Inventário do pai',
                area: 'Direito das Sucessões',
                status: 'Em andamento',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rescisão indireta'), findsOneWidget);
    expect(find.text('Inventário do pai'), findsOneWidget);

    await _buscar(tester, 'inventário');
    expect(find.text('Rescisão indireta'), findsNothing);
    expect(find.text('Inventário do pai'), findsOneWidget);

    // Número colado do tribunal, com máscara, acha o processo.
    await _buscar(tester, '0801234-56.2026.8.26.0100');
    expect(find.text('Rescisão indireta'), findsOneWidget);
    expect(find.text('Inventário do pai'), findsNothing);
  });

  testWidgets('casos do cliente: busca sem resultado diz que nada sumiu', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CasesScreen(
          repository: _FakeCaseRepository(
            clientCases: const [
              LegalCase(
                id: '1',
                title: 'Rescisão indireta',
                area: 'Direito Trabalhista',
                status: 'Em andamento',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _buscar(tester, 'xyzzy');
    // NÃO pode cair no empty state de lista vazia: quem lê "Nenhum caso
    // iniciado" depois de filtrar acha que perdeu os dados.
    expect(find.text('Nenhum caso iniciado'), findsNothing);
    expect(find.text('Nenhum resultado'), findsOneWidget);
    expect(find.textContaining('continuam aqui'), findsOneWidget);

    // E o botão de limpar devolve a lista E esvazia o campo.
    await tester.tap(find.text('Limpar busca'));
    await tester.pumpAndSettle();
    expect(find.text('Rescisão indireta'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
      reason: 'limpou o filtro mas deixou o texto no campo',
    );
  });

  testWidgets('casos do cliente: a busca alcança as solicitações pendentes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CasesScreen(
          repository: _FakeCaseRepository(
            clientCases: const [
              LegalCase(
                id: '1',
                title: 'Rescisão indireta',
                area: 'Direito Trabalhista',
                status: 'Em andamento',
              ),
            ],
            requests: const [
              CaseRequest(
                id: 'p1',
                conversationId: 'c1',
                title: 'Inventário proposto',
                area: 'Direito das Sucessões',
                summary: '',
                requestedBy: 'Ana Souza',
                requesterInitials: 'AS',
                createdAtLabel: 'hoje',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Inventário proposto'), findsOneWidget);

    // Buscando o caso, a solicitação que não casa também tem que sumir: a
    // seção de cima não pode ignorar o que foi digitado.
    await _buscar(tester, 'rescisão');
    expect(find.text('Rescisão indireta'), findsOneWidget);
    expect(find.text('Inventário proposto'), findsNothing);
    expect(find.text('Solicitações pendentes'), findsNothing);
  });

  testWidgets('casos do advogado: busca por nome de cliente e por processo', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        LawyerCasesScreen(
          repository: _FakeCaseRepository(
            lawyerCases: [
              _casoDoAdvogado('Ana Souza', cnj: '08012345620268260100'),
              _casoDoAdvogado('Bruno Lima'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ana Souza'), findsOneWidget);
    expect(find.text('Bruno Lima'), findsOneWidget);

    await _buscar(tester, 'bruno');
    expect(find.text('Ana Souza'), findsNothing);
    expect(find.text('Bruno Lima'), findsOneWidget);

    await _buscar(tester, '0801234');
    expect(find.text('Ana Souza'), findsOneWidget);
    expect(find.text('Bruno Lima'), findsNothing);
  });

  testWidgets('casos do escritório: busca pelo advogado responsável', (
    tester,
  ) async {
    final workspace = FirmWorkspace(
      firm: const LawFirm(
        id: 'f1',
        name: 'Firma',
        initials: 'F',
        rating: 0,
        distance: '',
        specialty: 'Direito Cível',
        practiceAreas: ['Direito Cível'],
        reviews: 0,
        avatarType: 'purple',
      ),
      currentUserRole: FirmRole.owner,
      currentUserRoles: const [FirmRole.owner],
      teamMembers: const [],
      fromSupabase: true,
    );

    await tester.pumpWidget(
      _host(
        FirmCasesScreen(
          workspace: workspace,
          repository: _FakeCaseRepository(
            firmCases: [
              _casoDoEscritorio(
                'Ana Souza',
                advogadoId: 'adv1',
                advogado: 'Dra. Marina Reis',
              ),
              _casoDoEscritorio('Bruno Lima'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Caso de Ana Souza'), findsOneWidget);
    expect(find.text('Caso de Bruno Lima'), findsOneWidget);

    await _buscar(tester, 'marina');
    expect(find.text('Caso de Ana Souza'), findsOneWidget);
    expect(find.text('Caso de Bruno Lima'), findsNothing);

    // "Sem advogado definido" é rótulo do servidor, não gente: buscar por ele
    // não pode devolver o caso órfão como se houvesse um advogado com esse
    // nome.
    await _buscar(tester, 'sem advogado');
    expect(find.text('Caso de Bruno Lima'), findsNothing);
    expect(find.text('Nenhum resultado'), findsOneWidget);
  });
}
