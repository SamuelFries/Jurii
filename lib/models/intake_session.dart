enum IntakeSessionStatus { collecting, ready, delivered, abandoned }

enum IntakeMessageSender { assistant, client }

class IntakeMessage {
  final String id;
  final IntakeMessageSender sender;
  final String body;
  final DateTime sentAt;

  const IntakeMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.sentAt,
  });

  factory IntakeMessage.fromJson(Map<String, dynamic> json) {
    return IntakeMessage(
      id: json['id'] as String,
      sender: json['sender'] == 'assistant'
          ? IntakeMessageSender.assistant
          : IntakeMessageSender.client,
      body: json['body'] as String,
      sentAt: DateTime.parse(json['sent_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender': sender == IntakeMessageSender.assistant
          ? 'assistant'
          : 'client',
      'body': body,
      'sent_at': sentAt.toIso8601String(),
    };
  }
}

/// Sessão de triagem assistida entre o cliente e a IA da Jurii, executada
/// antes do primeiro contato com o advogado.
///
/// A sessão é imutável: cada interação produz uma nova instância via
/// [copyWith], no mesmo estilo dos demais models do app.
class ClientIntakeSession {
  final String id;
  final String clientId;
  final IntakeSessionStatus status;
  final List<IntakeMessage> messages;

  /// Áreas do direito inferidas até o momento a partir do relato.
  final List<String> inferredPracticeAreas;

  /// Índice da próxima pergunta do roteiro (controle do fluxo rule-based).
  final int nextQuestionIndex;

  final DateTime startedAt;

  const ClientIntakeSession({
    required this.id,
    required this.clientId,
    required this.status,
    required this.messages,
    required this.inferredPracticeAreas,
    required this.nextQuestionIndex,
    required this.startedAt,
  });

  bool get isReadyForSummary => status == IntakeSessionStatus.ready;

  /// Apenas o que o cliente escreveu — insumo do resumo para o advogado.
  List<String> get clientStatements => messages
      .where((message) => message.sender == IntakeMessageSender.client)
      .map((message) => message.body)
      .toList(growable: false);

  ClientIntakeSession copyWith({
    IntakeSessionStatus? status,
    List<IntakeMessage>? messages,
    List<String>? inferredPracticeAreas,
    int? nextQuestionIndex,
  }) {
    return ClientIntakeSession(
      id: id,
      clientId: clientId,
      status: status ?? this.status,
      messages: messages ?? this.messages,
      inferredPracticeAreas:
          inferredPracticeAreas ?? this.inferredPracticeAreas,
      nextQuestionIndex: nextQuestionIndex ?? this.nextQuestionIndex,
      startedAt: startedAt,
    );
  }
}
