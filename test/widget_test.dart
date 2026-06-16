import 'package:flutter/material.dart';
import 'package:jurii/data/legal_practice_areas.dart';
import 'package:jurii/data/mock/mock_users.dart';
import 'package:jurii/models/firm_role.dart';
import 'package:jurii/models/firm_workspace.dart';
import 'package:jurii/models/law_firm.dart';
import 'package:jurii/models/law_firm_verification.dart';
import 'package:jurii/models/law_firm_verification_status.dart';
import 'package:jurii/models/lawyer_case.dart';
import 'package:jurii/models/lawyer_status.dart';
import 'package:jurii/models/lawyer_verification.dart';
import 'package:jurii/models/conversation.dart';
import 'package:jurii/repositories/case_repository.dart';
import 'package:jurii/repositories/messaging_repository.dart';
import 'package:jurii/screens/chat_screen.dart';
import 'package:jurii/screens/lawyer_home_screen.dart';
import 'package:jurii/screens/profile_screen.dart';
import 'package:jurii/screens/register_screen.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/types/auth_callbacks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final clientUser = mockCurrentUser.copyWith(
    lawyerStatus: LawyerStatus.client,
  );
  final lawyerUser = mockCurrentUser.copyWith(
    lawyerStatus: LawyerStatus.approved,
    oabNumber: 'OAB/SP 123456',
  );
  const firmWorkspace = FirmWorkspace(
    firm: LawFirm(
      id: 'firm_fries_advogados',
      name: 'Fries Advogados',
      initials: 'FA',
      rating: 0,
      distance: '',
      specialty: 'Escritório jurídico',
      practiceAreas: ['Direito Trabalhista'],
      reviews: 0,
      avatarType: 'purple',
    ),
    currentUserRole: FirmRole.owner,
    teamMembers: [],
    fromSupabase: true,
  );

  Future<RegisterResult> registerStub({
    required String fullName,
    required String email,
    required String cpf,
    required String password,
  }) async {
    return RegisterResult.signedIn;
  }

  test('legal search infers practice areas from client language', () {
    const examples = {
      'Preciso de ajuda com Maria da Penha': 'Direito Criminal',
      'meu marido me bateu': 'Direito Criminal',
      'estupro': 'Direito Criminal',
      'não consigo ver meu filho': 'Direito de Família',
      'pai não pagou pensão': 'Direito de Família',
      'fui demitido sem receber': 'Direito Trabalhista',
      'minha compra não chegou': 'Direito do Consumidor',
      'meu benefício do INSS foi cortado': 'Direito Previdenciário',
      'inquilino não paga aluguel': 'Direito Imobiliário',
      'bateram no meu carro': 'Acidente de Trânsito',
      'briga com sócio da empresa': 'Direito Empresarial',
      'cobrança da Receita Federal': 'Direito Tributário',
      'levei calote': 'Direito Cível',
      'whatsapp clonado': 'Direito Digital',
    };

    for (final entry in examples.entries) {
      expect(
        inferPracticeAreasForSearch(entry.key),
        contains(entry.value),
        reason: '"${entry.key}" should infer ${entry.value}',
      );
    }

    expect(
      matchesPracticeAreaSearch(
        practiceAreas: const ['Direito Trabalhista'],
        query: 'Maria da Penha',
      ),
      isFalse,
    );
  });

  testWidgets('shows the register screen', (WidgetTester tester) async {
    await tester.pumpWidget(_testApp(RegisterScreen(onRegister: registerStub)));

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
    await tester.pumpWidget(_testApp(RegisterScreen(onRegister: registerStub)));

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
    await tester.pumpWidget(_testApp(RegisterScreen(onRegister: registerStub)));

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

  testWidgets('law firm registration item opens verification screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        Scaffold(
          body: ProfileScreen(
            user: clientUser,
            onVerificationSubmitted: (_) {},
            onLawFirmVerificationSubmitted: (_) {},
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Cadastrar escritório'));
    await tester.tap(find.text('Cadastrar escritório'));
    await tester.pumpAndSettle();

    expect(find.text('Cadastre seu\nEscritório'), findsOneWidget);
    expect(find.text('Começar cadastro'), findsOneWidget);
  });

  testWidgets('submitting law firm verification emits pending verification', (
    WidgetTester tester,
  ) async {
    LawFirmVerification? submittedVerification;

    await tester.pumpWidget(
      _testApp(
        Scaffold(
          body: ProfileScreen(
            user: clientUser,
            onVerificationSubmitted: (_) {},
            onLawFirmVerificationSubmitted: (verification) {
              submittedVerification = verification;
            },
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Cadastrar escritório'));
    await tester.tap(find.text('Cadastrar escritório'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Começar cadastro'));
    await tester.tap(find.text('Começar cadastro'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Fries Advogados');
    await tester.enterText(find.byType(TextField).at(1), '12345678000190');
    await tester.enterText(find.byType(TextField).at(2), '11999999999');
    await tester.enterText(
      find.byType(TextField).at(3),
      'contato@friesadvogados.com',
    );
    await tester.enterText(
      find.byType(TextField).at(4),
      'Avenida Paulista, 1000',
    );
    await tester.enterText(find.byType(TextField).at(5), '4');
    await tester.pump();
    await tester.ensureVisible(find.text('Direito Trabalhista'));
    await tester.tap(find.text('Direito Trabalhista'));
    await tester.pump();

    while (find.text('Selecionar').evaluate().isNotEmpty) {
      await tester.ensureVisible(find.text('Selecionar').first);
      await tester.tap(find.text('Selecionar').first);
      await tester.pump();
    }

    await tester.ensureVisible(find.text('Enviar para análise'));
    await tester.tap(find.text('Enviar para análise'));
    await tester.pumpAndSettle();

    expect(submittedVerification, isNotNull);
    expect(submittedVerification!.status, LawFirmVerificationStatus.pending);
    expect(find.text('Cadastro enviado'), findsOneWidget);
  });

  testWidgets('pending law firm verification shows office status card', (
    WidgetTester tester,
  ) async {
    const verification = LawFirmVerification(
      ownerProfileId: 'user_joao_silva',
      firmName: 'Fries Advogados',
      cnpj: '12.345.678/0001-90',
      phone: '11999999999',
      email: 'contato@friesadvogados.com',
      address: 'Avenida Paulista, 1000',
      lawyersCount: 4,
      practiceAreas: ['Direito Trabalhista'],
      documents: [],
      status: LawFirmVerificationStatus.pending,
    );

    await tester.pumpWidget(
      _testApp(
        Scaffold(
          body: ProfileScreen(
            user: clientUser,
            lawFirmVerification: verification,
            onVerificationSubmitted: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Escritório em análise'), findsOneWidget);
    expect(find.text('Estamos verificando Fries Advogados'), findsOneWidget);
  });

  testWidgets('approved law firm card opens firm area callback', (
    WidgetTester tester,
  ) async {
    var openedFirmArea = false;
    const verification = LawFirmVerification(
      ownerProfileId: 'user_joao_silva',
      firmName: 'Fries Advogados',
      cnpj: '12.345.678/0001-90',
      phone: '11999999999',
      email: 'contato@friesadvogados.com',
      address: 'Avenida Paulista, 1000',
      lawyersCount: 4,
      practiceAreas: ['Direito Trabalhista'],
      documents: [],
      status: LawFirmVerificationStatus.approved,
    );

    await tester.pumpWidget(
      _testApp(
        Scaffold(
          body: ProfileScreen(
            user: clientUser,
            lawFirmVerification: verification,
            onVerificationSubmitted: (_) {},
            onOpenLawFirmArea: () {
              openedFirmArea = true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Área do Escritório'));
    await tester.pump();

    expect(openedFirmArea, isTrue);
  });

  testWidgets('professional profile shows firm area only with workspace', (
    WidgetTester tester,
  ) async {
    var openedFirmArea = false;

    await tester.pumpWidget(
      _testApp(
        Scaffold(
          body: ProfileScreen(
            user: lawyerUser,
            firmWorkspace: firmWorkspace,
            onSwitchToClient: () {},
            onOpenLawFirmArea: () {
              openedFirmArea = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Área do Escritório'), findsOneWidget);
    expect(find.text('Acesse Fries Advogados'), findsOneWidget);

    await tester.tap(find.text('Área do Escritório'));
    await tester.pump();

    expect(openedFirmArea, isTrue);
  });

  testWidgets('professional profile hides firm area without workspace', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        Scaffold(
          body: ProfileScreen(
            user: lawyerUser,
            onSwitchToClient: () {},
            onOpenLawFirmArea: () {},
          ),
        ),
      ),
    );

    expect(find.text('Área do Escritório'), findsNothing);
  });

  testWidgets('lawyer home shows real client metrics from repositories', (
    WidgetTester tester,
  ) async {
    final caseRepository = _FakeCaseRepository(
      List.generate(
        7,
        (index) => LawyerCase(
          id: 'case_real_$index',
          title: 'Caso real $index',
          clientName: 'Cliente $index',
          clientInitials: 'C$index',
          area: 'Direito Trabalhista',
          lastUpdate: 'Atualizado hoje',
          status: LawyerCaseStatus.updated,
        ),
      ),
    );
    const messagingRepository = _FakeMessagingRepository([
      Conversation(
        id: 'conversation_real_01',
        initials: 'MR',
        officeName: 'Marina Real',
        specialty: 'Direito Trabalhista',
        lastMessage: 'Preciso de ajuda com uma rescisão.',
        time: '10:20',
        unreadCount: 0,
        type: 'client_lawyer',
        clientId: 'client_marina',
      ),
      Conversation(
        id: 'conversation_real_02',
        initials: 'RB',
        officeName: 'Rafael Banco',
        specialty: 'Direito Bancário',
        lastMessage: 'Tenho dúvidas sobre uma cobrança.',
        time: '09:45',
        unreadCount: 0,
        type: 'client_lawyer',
        clientId: 'client_rafael',
      ),
    ]);

    await tester.pumpWidget(
      _testApp(
        LawyerHomeScreen(
          user: lawyerUser,
          caseRepository: caseRepository,
          messagingRepository: messagingRepository,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('7'), findsOneWidget);
    expect(find.text('8'), findsNothing);
    expect(find.text('Marina Real'), findsOneWidget);
    expect(find.text('Rafael Banco'), findsOneWidget);
    expect(find.text('Ana Pereira'), findsNothing);
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
    await tester.ensureVisible(find.text('Direito Trabalhista'));
    await tester.tap(find.text('Direito Trabalhista'));
    await tester.pump();

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

  testWidgets('chat keeps chronological order without refresh action', (
    WidgetTester tester,
  ) async {
    const conversation = Conversation(
      initials: 'FA',
      officeName: 'Fries Advogados',
      specialty: 'Direito Trabalhista',
      lastMessage: 'Conversa iniciada.',
      time: 'Agora',
      unreadCount: 0,
    );

    await tester.pumpWidget(
      _testApp(const ChatScreen(conversation: conversation, isLawyer: false)),
    );
    await tester.pumpAndSettle();

    final firstMessage = find.text(
      'Olá, João. Recebemos sua solicitação e podemos ajudar com a análise trabalhista.',
    );
    final latestMessage = find.text(
      'Contrato, últimos contracheques e a comunicação de desligamento já são suficientes para começar.',
    );

    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(firstMessage, findsOneWidget);
    expect(latestMessage, findsOneWidget);
    expect(
      tester.getTopLeft(firstMessage).dy,
      lessThan(tester.getTopLeft(latestMessage).dy),
    );
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(theme: AppTheme.lightTheme, home: child);
}

class _FakeMessagingRepository extends MessagingRepository {
  final List<Conversation> conversations;

  const _FakeMessagingRepository(this.conversations);

  @override
  Future<List<Conversation>> fetchConversations({
    required ConversationScope scope,
    String? lawFirmId,
  }) async {
    return conversations;
  }
}

class _FakeCaseRepository extends CaseRepository {
  final List<LawyerCase> cases;

  const _FakeCaseRepository(this.cases);

  @override
  Future<List<LawyerCase>> fetchLawyerCases() async {
    return cases;
  }
}
