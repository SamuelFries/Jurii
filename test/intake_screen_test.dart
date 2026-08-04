import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jurii/models/intake_session.dart';
import 'package:jurii/models/intake_summary.dart';
import 'package:jurii/screens/intake_screen.dart';
import 'package:jurii/services/intake_ai_service.dart';
import 'package:jurii/theme/app_theme.dart';

/// Serviço de triagem falso e determinístico: fica pronto após a 1ª mensagem do
/// cliente. Permite testar a UI sem depender da lógica rule-based nem do
/// Supabase.
class FakeIntakeService implements IntakeAIService {
  FakeIntakeService({required this.categories});

  final List<SuggestedLegalCategory> categories;
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
        IntakeMessage(
          id: 'a1',
          sender: IntakeMessageSender.assistant,
          body: 'Obrigada, já tenho o suficiente.',
          sentAt: _fixed,
        ),
      ],
    );
  }

  @override
  Future<IntakeSummary> buildSummary(ClientIntakeSession session) async {
    return IntakeSummary(
      sessionId: session.id,
      caseSummary: 'Cliente relata um problema jurídico.',
      suggestedCategories: categories,
      urgency: UrgencyLevel.medium,
      urgencyReason: 'Caso identificado, sem prazo imediato.',
      keyPoints: const ['Aconteceu na semana passada.'],
      recommendedDocuments: const [
        RecommendedDocument(title: 'Documento de identidade', reason: 'Base.'),
      ],
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

/// Host que abre a IntakeScreen como o chat faria e captura o resultado.
Widget _host(
  IntakeAIService service,
  void Function(IntakeChatResult?) onResult, {
  String counterpartLabel = 'advogado',
}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final result = await Navigator.of(context).push<IntakeChatResult>(
                MaterialPageRoute(
                  builder: (_) => IntakeScreen(
                    service: service,
                    counterpartLabel: counterpartLabel,
                  ),
                ),
              );
              onResult(result);
            },
            child: const Text('abrir triagem'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('mostra saudação e disclaimer de não-aconselhamento ao abrir', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: IntakeScreen(service: FakeIntakeService(categories: const [])),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Olá, vamos começar sua triagem.'), findsOneWidget);
    expect(
      find.textContaining('não é aconselhamento jurídico'),
      findsOneWidget,
    );
  });

  testWidgets('conversa vira resumo e enviar devolve o overview ao chat', (
    tester,
  ) async {
    IntakeChatResult? captured;
    await tester.pumpWidget(
      _host(
        FakeIntakeService(
          categories: const [
            SuggestedLegalCategory(
              practiceArea: 'Direito Trabalhista',
              confidence: 1.0,
            ),
          ],
        ),
        (result) => captured = result,
      ),
    );
    await tester.tap(find.text('abrir triagem'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'meu chefe não me pagou');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('Resumo da sua triagem'), findsOneWidget);
    expect(find.textContaining('Direito Trabalhista'), findsWidgets);

    await tester.ensureVisible(find.text('Enviar resumo ao advogado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar resumo ao advogado'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.overviewText, contains('Resumo do caso'));
    // Voltou para o host após enviar.
    expect(find.text('abrir triagem'), findsOneWidget);
  });

  testWidgets('resumo sem área identificada não quebra e ainda permite envio', (
    tester,
  ) async {
    IntakeChatResult? captured;
    await tester.pumpWidget(
      _host(
        FakeIntakeService(categories: const []),
        (result) => captured = result,
        counterpartLabel: 'escritório',
      ),
    );
    await tester.tap(find.text('abrir triagem'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'preciso de ajuda');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Não identificamos uma área específica'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Enviar resumo ao escritório'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar resumo ao escritório'));
    await tester.pumpAndSettle();
    expect(captured, isNotNull);
  });

  testWidgets('"Agora não" volta ao chat sem enviar nada', (tester) async {
    var callbackRan = false;
    IntakeChatResult? captured;
    await tester.pumpWidget(
      _host(FakeIntakeService(categories: const []), (result) {
        callbackRan = true;
        captured = result;
      }),
    );
    await tester.tap(find.text('abrir triagem'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'relato qualquer');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Agora não'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agora não'));
    await tester.pumpAndSettle();

    expect(callbackRan, isTrue);
    expect(captured, isNull);
    expect(find.text('abrir triagem'), findsOneWidget);
  });
}
