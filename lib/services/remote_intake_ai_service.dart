import 'package:flutter/foundation.dart';

import '../data/legal_practice_areas.dart';
import '../models/intake_session.dart';
import '../models/intake_summary.dart';
import 'intake_ai_service.dart';
import 'supabase_config.dart';

/// Assinatura da chamada à Edge Function, injetável para teste.
typedef IntakeInvoke =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> body);

/// A triagem com IA de verdade (Sonnet 5), pela Edge Function `intake-chat`.
///
/// A chave da API vive só no servidor; o app manda o histórico da sessão e
/// recebe de volta a próxima pergunta ou o resumo estruturado. Arquitetura e
/// desenho de segurança em docs/ai-intake.md.
///
/// TRÊS DECISÕES DELIBERADAS:
///
///  - Falha cai no [RuleBasedIntakeAIService], POR TURNO: API fora do ar,
///    limite de chamadas atingido ou resposta malformada nunca travam a
///    triagem; o cliente segue no roteiro local sem perceber a costura. Se a
///    API voltar no turno seguinte, volta-se a usá-la (o histórico inteiro
///    viaja a cada chamada, então não há estado para dessincronizar).
///
///  - O aviso de risco (190/180) e o encerramento são os textos FIXOS de
///    [intakeSafetyNotice] e [intakeWrapUp]: a IA só sinaliza booleanos, e
///    conteúdo de emergência nunca é texto gerado.
///
///  - O teto de perguntas vale nas duas pontas: aqui (nem chama a API depois
///    da quarta) e no servidor (o system prompt encerra). Cinto e
///    suspensório, porque cada chamada custa dinheiro.
class RemoteIntakeAIService implements IntakeAIService {
  RemoteIntakeAIService({
    this.maxFollowUpQuestions = 4,
    IntakeInvoke? invoke,
    RuleBasedIntakeAIService? fallback,
  }) : _invoke = invoke ?? _invokeEdgeFunction,
       _fallback =
           fallback ??
           RuleBasedIntakeAIService(maxFollowUpQuestions: maxFollowUpQuestions);

  final int maxFollowUpQuestions;
  final IntakeInvoke _invoke;
  final RuleBasedIntakeAIService _fallback;
  int _idCounter = 0;

  static Future<Map<String, dynamic>> _invokeEdgeFunction(
    Map<String, dynamic> body,
  ) async {
    final response = await SupabaseConfig.client.functions.invoke(
      'intake-chat',
      body: body,
    );
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw StateError('intake-chat: resposta inesperada');
  }

  @override
  Future<ClientIntakeSession> startSession({required String clientId}) {
    // A saudação é fixa e local: não se gasta uma chamada de IA para dizer
    // olá, e a sessão nasce igual nas duas implementações.
    return _fallback.startSession(clientId: clientId);
  }

  @override
  Future<ClientIntakeSession> sendClientMessage(
    ClientIntakeSession session,
    String text,
  ) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || session.status != IntakeSessionStatus.collecting) {
      return session;
    }

    // Teto local primeiro: depois da última pergunta respondida, o destino
    // é o encerramento; gastar uma chamada para o servidor dizer o mesmo
    // seria pagar para ouvir o que já se sabe.
    if (session.nextQuestionIndex >= maxFollowUpQuestions) {
      return _fallback.sendClientMessage(session, text);
    }

    Map<String, dynamic> resposta;
    try {
      resposta = await _invoke({
        'acao': 'pergunta',
        'historico': _historico(session),
        'mensagem': trimmed,
      });
    } catch (error) {
      debugPrint('RemoteIntakeAIService: caiu para o rule-based: $error');
      return _fallback.sendClientMessage(session, text);
    }

    final agora = DateTime.now();
    final mensagens = [
      ...session.messages,
      IntakeMessage(
        id: _nextId('msg'),
        sender: IntakeMessageSender.client,
        body: trimmed,
        sentAt: agora,
      ),
    ];

    // O sinal vem da IA; o texto é o nosso, e nunca se repete na sessão.
    final jaAvisou = session.messages.any(
      (m) => m.body == intakeSafetyNotice,
    );
    if (resposta['risco_pessoal'] == true && !jaAvisou) {
      mensagens.add(
        IntakeMessage(
          id: _nextId('msg'),
          sender: IntakeMessageSender.assistant,
          body: intakeSafetyNotice,
          sentAt: agora,
        ),
      );
    }

    // As áreas inferidas continuam sendo calculadas localmente, com a mesma
    // taxonomia da busca: alimentam o resumo de fallback e não custam nada.
    final inferidas = inferPracticeAreasForSearch(
      [...session.clientStatements, trimmed].join('\n'),
    );

    final pergunta = (resposta['pergunta'] as String? ?? '').trim();
    final encerrar = resposta['acao'] == 'encerrar' || pergunta.isEmpty;

    if (encerrar) {
      mensagens.add(
        IntakeMessage(
          id: _nextId('msg'),
          sender: IntakeMessageSender.assistant,
          body: intakeWrapUp,
          sentAt: agora,
        ),
      );
      return session.copyWith(
        status: IntakeSessionStatus.ready,
        messages: mensagens,
        inferredPracticeAreas: inferidas,
      );
    }

    mensagens.add(
      IntakeMessage(
        id: _nextId('msg'),
        sender: IntakeMessageSender.assistant,
        body: pergunta,
        sentAt: agora,
      ),
    );
    return session.copyWith(
      messages: mensagens,
      inferredPracticeAreas: inferidas,
      nextQuestionIndex: session.nextQuestionIndex + 1,
    );
  }

  @override
  Future<IntakeSummary> buildSummary(ClientIntakeSession session) async {
    Map<String, dynamic> resposta;
    try {
      resposta = await _invoke({
        'acao': 'resumo',
        'historico': _historico(session),
      });
    } catch (error) {
      debugPrint('RemoteIntakeAIService: resumo caiu para o rule-based: $error');
      return _fallback.buildSummary(session);
    }

    final categorias = (resposta['categorias'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (c) => SuggestedLegalCategory(
            practiceArea: c['area'] as String? ?? '',
            confidence: ((c['confianca'] as num?) ?? 0).toDouble().clamp(0, 1),
          ),
        )
        .where((c) => c.practiceArea.isNotEmpty)
        .toList(growable: false);

    final documentos =
        (resposta['documentos_recomendados'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (d) => RecommendedDocument(
                title: d['titulo'] as String? ?? '',
                reason: d['motivo'] as String? ?? '',
              ),
            )
            .where((d) => d.title.isNotEmpty)
            .toList(growable: false);

    var indicePendente = 0;
    final pendentes = (resposta['perguntas_pendentes'] as List? ?? const [])
        .whereType<String>()
        .where((texto) => texto.trim().isNotEmpty)
        .map(
          (texto) => IntakeQuestion(
            id: 'pendente-${++indicePendente}',
            text: texto.trim(),
          ),
        )
        .toList(growable: false);

    return IntakeSummary(
      sessionId: session.id,
      caseSummary: resposta['resumo_do_caso'] as String? ?? '',
      suggestedCategories: categorias,
      urgency: _urgencia(resposta['urgencia']),
      urgencyReason: resposta['motivo_da_urgencia'] as String? ?? '',
      keyPoints: (resposta['pontos_chave'] as List? ?? const [])
          .whereType<String>()
          .where((p) => p.trim().isNotEmpty)
          .toList(growable: false),
      recommendedDocuments: documentos,
      pendingQuestions: pendentes,
      generatedAt: DateTime.now(),
    );
  }

  @override
  LawyerOverview buildLawyerOverview(IntakeSummary summary) {
    // Formatação local pura: idêntica nas duas implementações.
    return _fallback.buildLawyerOverview(summary);
  }

  List<Map<String, String>> _historico(ClientIntakeSession session) {
    return session.messages
        .map(
          (m) => {
            'papel': m.sender == IntakeMessageSender.assistant
                ? 'assistente'
                : 'cliente',
            'texto': m.body,
          },
        )
        .toList(growable: false);
  }

  UrgencyLevel _urgencia(Object? valor) => switch (valor) {
    'baixa' => UrgencyLevel.low,
    'media' => UrgencyLevel.medium,
    'alta' => UrgencyLevel.high,
    'critica' => UrgencyLevel.critical,
    // Valor estranho não decide urgência de caso jurídico: fica no meio e o
    // advogado avalia.
    _ => UrgencyLevel.medium,
  };

  String _nextId(String prefix) =>
      '$prefix-remoto-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';
}
