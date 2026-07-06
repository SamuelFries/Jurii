import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/intake_session.dart';
import 'package:jurii/models/intake_summary.dart';
import 'package:jurii/services/intake_ai_service.dart';

void main() {
  group('RuleBasedIntakeAIService', () {
    late RuleBasedIntakeAIService service;

    setUp(() {
      service = RuleBasedIntakeAIService();
    });

    test('inicia sessão com saudação e coleta ativa', () async {
      final session = await service.startSession(clientId: 'client-1');

      expect(session.status, IntakeSessionStatus.collecting);
      expect(session.messages, hasLength(1));
      expect(session.messages.first.sender, IntakeMessageSender.assistant);
    });

    test('caso trabalhista: infere área, faz perguntas e gera resumo',
        () async {
      var session = await service.startSession(clientId: 'client-1');
      session = await service.sendClientMessage(
        session,
        'Fui demitido sem receber as verbas rescisórias e o FGTS está atrasado.',
      );

      expect(session.inferredPracticeAreas, contains('Direito Trabalhista'));
      // A assistente deve ter feito uma pergunta de acompanhamento.
      expect(
        session.messages.last.sender,
        IntakeMessageSender.assistant,
      );

      // Responde até a sessão fechar.
      var guard = 0;
      while (session.status == IntakeSessionStatus.collecting && guard < 10) {
        session = await service.sendClientMessage(
          session,
          'Resposta de acompanhamento $guard',
        );
        guard++;
      }
      expect(session.status, IntakeSessionStatus.ready);

      final summary = await service.buildSummary(session);
      expect(
        summary.suggestedCategories.map((c) => c.practiceArea),
        contains('Direito Trabalhista'),
      );
      expect(summary.urgency, UrgencyLevel.medium);
      expect(
        summary.recommendedDocuments.map((d) => d.title),
        contains('Carteira de trabalho (física ou digital)'),
      );

      final overview = service.buildLawyerOverview(summary);
      expect(overview.formattedText, contains('Resumo do caso:'));
      expect(overview.formattedText, contains('Direito Trabalhista'));
      expect(overview.formattedText, contains('Documentos recomendados:'));
    });

    test('relato com violência doméstica gera urgência crítica e aviso',
        () async {
      var session = await service.startSession(clientId: 'client-2');
      session = await service.sendClientMessage(
        session,
        'Meu marido me bateu e estou com medo, ele descumpriu a medida protetiva.',
      );

      expect(session.inferredPracticeAreas, contains('Direito Criminal'));
      expect(
        session.messages.map((m) => m.body).join(),
        contains('190'),
      );

      final summary = await service.buildSummary(session);
      expect(summary.urgency, UrgencyLevel.critical);
    });

    test('relato com prazo judicial gera urgência alta', () async {
      var session = await service.startSession(clientId: 'client-3');
      session = await service.sendClientMessage(
        session,
        'Recebi uma intimação com prazo de 15 dias para responder.',
      );

      final summary = await service.buildSummary(session);
      expect(summary.urgency, UrgencyLevel.high);
    });

    test('resumo trabalhista não traz categorias tangenciais', () async {
      var session = await service.startSession(clientId: 'client-precisao');
      session = await service.sendClientMessage(
        session,
        'Fui demitido sem receber as verbas rescisórias e o FGTS está '
        'atrasado. Não pagaram nada, nem aviso prévio.',
      );

      var guard = 0;
      while (session.status == IntakeSessionStatus.collecting && guard < 10) {
        session = await service.sendClientMessage(session, 'resposta $guard');
        guard++;
      }

      final summary = await service.buildSummary(session);
      final areas =
          summary.suggestedCategories.map((c) => c.practiceArea).toList();

      expect(areas, contains('Direito Trabalhista'));
      // Antes vinham Tributário ("iss" em "demissao") e Cível ("nao ...
      // pagaram") como ruído — agora são descartados.
      expect(areas, isNot(contains('Direito Tributário')));
      expect(areas, isNot(contains('Direito Cível')));
      // A categoria principal tem confiança máxima.
      expect(summary.suggestedCategories.first.confidence, 1.0);
    });

    test('mensagem vazia não altera a sessão', () async {
      final session = await service.startSession(clientId: 'client-4');
      final after = await service.sendClientMessage(session, '   ');
      expect(after, same(session));
    });

    test('perguntas pendentes excluem as já feitas', () async {
      var session = await service.startSession(clientId: 'client-5');
      session = await service.sendClientMessage(
        session,
        'Comprei um produto com defeito e a loja não troca.',
      );

      final summary = await service.buildSummary(session);
      final askedTexts = session.messages
          .where((m) => m.sender == IntakeMessageSender.assistant)
          .map((m) => m.body)
          .toSet();
      for (final question in summary.pendingQuestions) {
        expect(askedTexts, isNot(contains(question.text)));
      }
    });
  });
}
