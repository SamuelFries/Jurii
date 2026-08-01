import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jurii/models/conversation.dart';
import 'package:jurii/models/intake_session.dart';
import 'package:jurii/models/intake_summary.dart';
import 'package:jurii/screens/chat_screen.dart';
import 'package:jurii/services/intake_ai_service.dart';
import 'package:jurii/theme/app_theme.dart';

/// Fake determinístico (mesmo contrato do intake_screen_test): pronto após a
/// primeira mensagem do cliente.
class FakeIntakeService implements IntakeAIService {
  final DateTime _fixed = DateTime(2026, 1, 1);

  @override
  Future<ClientIntakeSession> startSession({required String clientId}) async {
    return ClientIntakeSession(
      id: 'test-session',
      clientId: clientId,
      status: IntakeSessionStatus.collecting,
      messages: [
        IntakeMessage(
          id: 'a0',
          sender: IntakeMessageSender.assistant,
          body: 'Olá, vamos começar sua triagem.',
          sentAt: _fixed,
        ),
      ],
      inferredPracticeAreas: const [],
      nextQuestionIndex: 0,
      startedAt: _fixed,
    );
  }

  @override
  Future<ClientIntakeSession> sendClientMessage(
    ClientIntakeSession session,
    String text,
  ) async {
    return session.copyWith(
      status: IntakeSessionStatus.ready,
      messages: [
        ...session.messages,
        IntakeMessage(
          id: 'c1',
          sender: IntakeMessageSender.client,
          body: text,
          sentAt: _fixed,
        ),
      ],
    );
  }

  @override
  Future<IntakeSummary> buildSummary(ClientIntakeSession session) async {
    return IntakeSummary(
      sessionId: session.id,
      caseSummary: 'Cliente relata rescisão sem verbas.',
      suggestedCategories: const [
        SuggestedLegalCategory(
          practiceArea: 'Direito Trabalhista',
          confidence: 1.0,
        ),
      ],
      urgency: UrgencyLevel.medium,
      urgencyReason: 'Caso identificado.',
      keyPoints: const [],
      recommendedDocuments: const [],
      pendingQuestions: const [],
      generatedAt: session.startedAt,
    );
  }

  @override
  LawyerOverview buildLawyerOverview(IntakeSummary summary) {
    return LawyerOverview(
      sessionId: summary.sessionId,
      formattedText: 'Resumo do caso:\n${summary.caseSummary}',
      generatedAt: summary.generatedAt,
    );
  }
}

// Conversa "nova": sem id (modo local) e sem mensagens mock associadas.
const _newConversation = Conversation(
  initials: 'EN',
  officeName: 'Escritório Novo',
  specialty: 'Direito Trabalhista',
  lastMessage: '',
  time: 'Agora',
  unreadCount: 0,
);

Widget _app(Widget child) =>
    MaterialApp(theme: AppTheme.lightTheme, home: child);

void main() {
  testWidgets('chat novo mostra o banner de triagem para o cliente', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ChatScreen(
          conversation: _newConversation,
          isLawyer: false,
          intakeService: FakeIntakeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Comece com uma triagem guiada'), findsOneWidget);
    expect(find.textContaining('para o escritório avaliar'), findsOneWidget);
  });

  testWidgets('advogado não vê banner nem opção de triagem no menu "+"', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const ChatScreen(conversation: _newConversation, isLawyer: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Comece com uma triagem guiada'), findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Anexar arquivo'), findsOneWidget);
    expect(find.text('Triagem com IA'), findsNothing);
  });

  testWidgets('botão "+" abre menu com anexo e triagem para o cliente', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ChatScreen(
          conversation: _newConversation,
          isLawyer: false,
          intakeService: FakeIntakeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Fechado: opções fora da árvore.
    expect(find.text('Triagem com IA'), findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Anexar arquivo'), findsOneWidget);
    expect(find.text('Tirar foto'), findsOneWidget);
    expect(find.text('Enviar foto'), findsOneWidget);
    expect(find.text('Triagem com IA'), findsOneWidget);

    // Fecha de novo com slide reverso.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('Triagem com IA'), findsNothing);
  });

  testWidgets(
    'cliente que ignora o banner e envia mensagem vê a dica do botão "+"',
    (tester) async {
      await tester.pumpWidget(
        _app(
          ChatScreen(
            conversation: _newConversation,
            isLawyer: false,
            intakeService: FakeIntakeService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'olá, preciso de ajuda');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Banner saiu; dica entrou.
      expect(find.text('Comece com uma triagem guiada'), findsNothing);
      expect(
        find.text('A triagem com a assistente está no botão +'),
        findsOneWidget,
      );

      // A dica é transitória.
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(
        find.text('A triagem com a assistente está no botão +'),
        findsNothing,
      );
    },
  );

  testWidgets('chat de equipe do escritório não expõe a triagem', (
    tester,
  ) async {
    // Contexto de escritório abre com isLawyer=false no segmento Equipe,
    // mas allowTriage=false — banner e opção de triagem não podem aparecer.
    await tester.pumpWidget(
      _app(
        const ChatScreen(
          conversation: _newConversation,
          isLawyer: false,
          allowTriage: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Comece com uma triagem guiada'), findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Anexar arquivo'), findsOneWidget);
    expect(find.text('Triagem com IA'), findsNothing);
  });

  testWidgets('quem já abriu o menu "+" não recebe a dica da triagem depois', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ChatScreen(
          conversation: _newConversation,
          isLawyer: false,
          intakeService: FakeIntakeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Cliente descobre o menu (abre e fecha) antes de mandar mensagem.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'primeira mensagem');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(
      find.text('A triagem com a assistente está no botão +'),
      findsNothing,
    );
  });

  testWidgets('triagem completa pelo banner envia o resumo na conversa', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ChatScreen(
          conversation: _newConversation,
          isLawyer: false,
          intakeService: FakeIntakeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Comece com uma triagem guiada'));
    await tester.pumpAndSettle();

    // Dentro da IntakeScreen.
    expect(find.text('Olá, vamos começar sua triagem.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'fui demitido sem receber');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Enviar resumo ao escritório'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar resumo ao escritório'));
    await tester.pumpAndSettle();

    // De volta ao chat: overview virou mensagem e o banner sumiu.
    expect(
      find.textContaining('Triagem da assistente Jurii'),
      findsOneWidget,
    );
    expect(find.text('Comece com uma triagem guiada'), findsNothing);
    // Usou a triagem — não deve aparecer a dica do "+".
    expect(
      find.text('A triagem com a assistente está no botão +'),
      findsNothing,
    );
  });
}
