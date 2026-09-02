import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/intake_session.dart';
import 'package:jurii/models/intake_summary.dart';
import 'package:jurii/services/intake_ai_service.dart';
import 'package:jurii/services/remote_intake_ai_service.dart';

/// A triagem remota (Edge Function `intake-chat`).
///
/// O que este arquivo trava: a costura com a IA real nunca piora a triagem.
/// Falha de rede, limite atingido ou resposta estranha caem no rule-based; o
/// aviso de risco e o encerramento são sempre os textos fixos do app; o teto
/// de perguntas vale no cliente antes de gastar chamada; e o resumo mapeia o
/// contrato da função para o IntakeSummary sem inventar nada.
void main() {
  Future<ClientIntakeSession> comecaComRelato(
    RemoteIntakeAIService service,
    String relato,
  ) async {
    final sessao = await service.startSession(clientId: 'cliente-1');
    return service.sendClientMessage(sessao, relato);
  }

  test('pergunta da IA entra na sessão e o índice avança', () async {
    final chamadas = <Map<String, dynamic>>[];
    final service = RemoteIntakeAIService(
      invoke: (body) async {
        chamadas.add(body);
        return {
          'acao': 'perguntar',
          'pergunta': 'Quando isso aconteceu?',
          'risco_pessoal': false,
        };
      },
    );

    final sessao = await comecaComRelato(
      service,
      'Fui demitido sem receber as verbas.',
    );

    expect(sessao.messages.last.body, 'Quando isso aconteceu?');
    expect(sessao.messages.last.sender, IntakeMessageSender.assistant);
    expect(sessao.nextQuestionIndex, 1);
    expect(sessao.status, IntakeSessionStatus.collecting);
    // O histórico enviado tem a saudação e NÃO tem a mensagem nova (ela vai
    // no campo próprio): o servidor remonta a conversa inteira.
    expect(chamadas.single['acao'], 'pergunta');
    expect(chamadas.single['mensagem'], 'Fui demitido sem receber as verbas.');
    final historico = chamadas.single['historico'] as List;
    expect(historico, hasLength(1));
    expect((historico.single as Map)['papel'], 'assistente');
  });

  test('encerrar vira o texto FIXO de encerramento e status ready', () async {
    final service = RemoteIntakeAIService(
      invoke: (body) async => {
        'acao': 'encerrar',
        'pergunta': 'texto que deve ser ignorado',
        'risco_pessoal': false,
      },
    );

    final sessao = await comecaComRelato(service, 'Quero encerrar um caso.');

    expect(sessao.status, IntakeSessionStatus.ready);
    expect(sessao.messages.last.body, intakeWrapUp);
    expect(
      sessao.messages.any((m) => m.body.contains('ignorado')),
      isFalse,
      reason: 'no encerramento, nenhum texto da IA aparece na tela',
    );
  });

  test('risco pessoal mostra o aviso FIXO (190/180), uma vez só', () async {
    var chamadas = 0;
    final service = RemoteIntakeAIService(
      invoke: (body) async {
        chamadas++;
        return {
          'acao': 'perguntar',
          'pergunta': 'Você está em local seguro agora?',
          'risco_pessoal': true,
        };
      },
    );

    var sessao = await comecaComRelato(service, 'Ele ameaçou me machucar.');
    expect(
      sessao.messages.map((m) => m.body),
      contains(intakeSafetyNotice),
    );

    sessao = await service.sendClientMessage(sessao, 'Estou na casa de amiga.');
    final avisos = sessao.messages
        .where((m) => m.body == intakeSafetyNotice)
        .length;
    expect(avisos, 1, reason: 'o aviso não se repete a cada turno');
    expect(chamadas, 2);
  });

  test('falha da função cai no rule-based e a triagem segue', () async {
    final service = RemoteIntakeAIService(
      invoke: (body) async => throw StateError('api fora do ar'),
    );

    final sessao = await comecaComRelato(
      service,
      'Comprei um produto com defeito e a loja não resolve.',
    );

    // O rule-based assume: mensagem do cliente entra e a assistente segue
    // com uma pergunta do roteiro (qualquer uma). Nada trava.
    expect(sessao.messages.last.sender, IntakeMessageSender.assistant);
    expect(sessao.messages.last.body, isNotEmpty);
    expect(sessao.status, IntakeSessionStatus.collecting);
    expect(
      sessao.clientStatements,
      contains('Comprei um produto com defeito e a loja não resolve.'),
    );
  });

  test('depois do teto local de perguntas, nem se gasta chamada', () async {
    var chamadas = 0;
    final service = RemoteIntakeAIService(
      maxFollowUpQuestions: 1,
      invoke: (body) async {
        chamadas++;
        return {
          'acao': 'perguntar',
          'pergunta': 'Só mais uma coisa?',
          'risco_pessoal': false,
        };
      },
    );

    var sessao = await comecaComRelato(service, 'Problema com aluguel.');
    expect(chamadas, 1);

    // Segunda mensagem: o teto (1) já foi atingido; o encerramento vem do
    // fluxo local, sem nova chamada.
    sessao = await service.sendClientMessage(sessao, 'O dono não devolve.');
    expect(chamadas, 1, reason: 'teto local economiza a chamada');
    expect(sessao.status, IntakeSessionStatus.ready);
    expect(sessao.messages.last.body, intakeWrapUp);
  });

  test('o resumo remoto vira IntakeSummary fiel ao contrato', () async {
    final service = RemoteIntakeAIService(
      invoke: (body) async {
        expect(body['acao'], 'resumo');
        return {
          'resumo_do_caso': 'Cliente relata demissão sem verbas rescisórias.',
          'categorias': [
            {'area': 'Direito Trabalhista', 'confianca': 0.9},
            {'area': 'Direito Cível', 'confianca': 2.5},
          ],
          'urgencia': 'alta',
          'motivo_da_urgencia': 'Prazo prescricional em curso.',
          'pontos_chave': ['Demissão em 01/07', 'Sem homologação'],
          'documentos_recomendados': [
            {'titulo': 'CTPS', 'motivo': 'Comprova o vínculo.'},
          ],
          'perguntas_pendentes': ['Havia contrato escrito?'],
        };
      },
    );

    final sessao = await comecaComRelato(service, 'Fui demitido.');
    final resumo = await service.buildSummary(sessao);

    expect(resumo.caseSummary, contains('verbas rescisórias'));
    expect(resumo.suggestedCategories, hasLength(2));
    expect(resumo.suggestedCategories.first.practiceArea, 'Direito Trabalhista');
    expect(
      resumo.suggestedCategories[1].confidence,
      1.0,
      reason: 'confiança fora de 0..1 é presa no intervalo',
    );
    expect(resumo.urgency, UrgencyLevel.high);
    expect(resumo.keyPoints, hasLength(2));
    expect(resumo.recommendedDocuments.single.title, 'CTPS');
    expect(resumo.pendingQuestions.single.text, 'Havia contrato escrito?');
    expect(resumo.sessionId, sessao.id);
  });

  test('urgência desconhecida não decide sozinha: vira média', () async {
    final service = RemoteIntakeAIService(
      invoke: (body) async => body['acao'] == 'resumo'
          ? {
              'resumo_do_caso': 'x',
              'categorias': <Object>[],
              'urgencia': 'apocaliptica',
              'motivo_da_urgencia': '',
              'pontos_chave': <Object>[],
              'documentos_recomendados': <Object>[],
              'perguntas_pendentes': <Object>[],
            }
          : {'acao': 'perguntar', 'pergunta': 'Ok?', 'risco_pessoal': false},
    );

    final sessao = await comecaComRelato(service, 'Relato qualquer.');
    final resumo = await service.buildSummary(sessao);
    expect(resumo.urgency, UrgencyLevel.medium);
  });

  test('falha no resumo cai no rule-based e entrega resumo local', () async {
    final service = RemoteIntakeAIService(
      invoke: (body) async {
        if (body['acao'] == 'resumo') throw StateError('quota');
        return {
          'acao': 'perguntar',
          'pergunta': 'Certo, e depois?',
          'risco_pessoal': false,
        };
      },
    );

    final sessao = await comecaComRelato(
      service,
      'Fui demitido sem justa causa e não recebi as verbas.',
    );
    final resumo = await service.buildSummary(sessao);

    expect(resumo.caseSummary, isNotEmpty);
    expect(resumo.sessionId, sessao.id);
  });
}
