// Playground de linha de comando para a IA de triagem (intake).
//
// Conversa com a RuleBasedIntakeAIService no terminal, do jeito que um cliente
// conversaria: você digita o relato, a assistente responde e faz perguntas de
// acompanhamento. Quando a sessão fecha, mostra o resumo consolidado e a
// overview que o advogado receberia.
//
// A IA é 100% local e determinística — não precisa de Supabase nem de chave de
// API. Por isso roda em Dart puro:
//
//   dart run tool/intake_playground.dart
//
// Digite "sair" a qualquer momento para encerrar.

import 'dart:io';

import 'package:jurii/models/intake_session.dart';
import 'package:jurii/models/intake_summary.dart';
import 'package:jurii/services/intake_ai_service.dart';

Future<void> main() async {
  final IntakeAIService service = RuleBasedIntakeAIService();
  var session = await service.startSession(clientId: 'playground');

  _printBanner();
  // A saudação inicial já vem na sessão.
  _printAssistantMessages(session, fromIndex: 0);

  while (session.status == IntakeSessionStatus.collecting) {
    stdout.write('\nvocê › ');
    final input = stdin.readLineSync()?.trim() ?? '';
    if (input.toLowerCase() == 'sair') {
      stdout.writeln('\nEncerrado sem gerar resumo. Até mais!');
      return;
    }
    if (input.isEmpty) continue;

    final previousLength = session.messages.length;
    session = await service.sendClientMessage(session, input);
    // Imprime apenas as mensagens novas da assistente (a última do cliente já
    // apareceu no que você digitou).
    _printAssistantMessages(session, fromIndex: previousLength);
  }

  await _printSummary(service, session);
}

void _printBanner() {
  stdout.writeln('=' * 64);
  stdout.writeln('  Jurii · Playground da IA de triagem (rule-based, local)');
  stdout.writeln('  Digite seu relato como se fosse um cliente. "sair" encerra.');
  stdout.writeln('=' * 64);
}

void _printAssistantMessages(ClientIntakeSession session, {required int fromIndex}) {
  for (var i = fromIndex; i < session.messages.length; i++) {
    final message = session.messages[i];
    if (message.sender != IntakeMessageSender.assistant) continue;
    stdout.writeln('\nassistente › ${message.body}');
  }
  if (session.inferredPracticeAreas.isNotEmpty) {
    stdout.writeln(
      '   [área inferida: ${session.inferredPracticeAreas.join(', ')}]',
    );
  }
}

Future<void> _printSummary(
  IntakeAIService service,
  ClientIntakeSession session,
) async {
  final summary = await service.buildSummary(session);
  final overview = service.buildLawyerOverview(summary);

  stdout.writeln('\n${'-' * 64}');
  stdout.writeln('  RESUMO GERADO (o que a IA entregaria)');
  stdout.writeln('-' * 64);
  stdout.writeln('Urgência: ${summary.urgency.label} — ${summary.urgencyReason}');
  stdout.writeln(
    'Categorias: ${summary.suggestedCategories.map((c) => '${c.practiceArea} (${(c.confidence * 100).round()}%)').join(', ')}',
  );

  stdout.writeln('\n${'-' * 64}');
  stdout.writeln('  OVERVIEW PARA O ADVOGADO');
  stdout.writeln('-' * 64);
  stdout.writeln(overview.formattedText);
  stdout.writeln('-' * 64);
}
