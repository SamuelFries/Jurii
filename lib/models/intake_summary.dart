enum UrgencyLevel { low, medium, high, critical }

extension UrgencyLevelLabel on UrgencyLevel {
  String get label => switch (this) {
    UrgencyLevel.low => 'Baixa',
    UrgencyLevel.medium => 'Média',
    UrgencyLevel.high => 'Alta',
    UrgencyLevel.critical => 'Crítica',
  };
}

/// Categoria jurídica sugerida pela triagem, com grau de confiança 0–1.
class SuggestedLegalCategory {
  final String practiceArea;
  final double confidence;

  const SuggestedLegalCategory({
    required this.practiceArea,
    required this.confidence,
  });
}

/// Documento que o cliente deve reunir antes do atendimento.
class RecommendedDocument {
  final String title;
  final String reason;

  const RecommendedDocument({required this.title, required this.reason});
}

/// Pergunta do roteiro de triagem. As perguntas ainda não respondidas ao
/// final da sessão viram "perguntas pendentes" na visão do advogado.
class IntakeQuestion {
  final String id;
  final String text;

  /// Quando não vazia, a pergunta só é feita se uma destas áreas foi inferida.
  final List<String> practiceAreas;

  const IntakeQuestion({
    required this.id,
    required this.text,
    this.practiceAreas = const [],
  });
}

/// Resultado consolidado da triagem: o caso "mastigado" para o advogado.
class IntakeSummary {
  final String sessionId;
  final String caseSummary;
  final List<SuggestedLegalCategory> suggestedCategories;
  final UrgencyLevel urgency;
  final String urgencyReason;
  final List<String> keyPoints;
  final List<RecommendedDocument> recommendedDocuments;
  final List<IntakeQuestion> pendingQuestions;
  final DateTime generatedAt;

  const IntakeSummary({
    required this.sessionId,
    required this.caseSummary,
    required this.suggestedCategories,
    required this.urgency,
    required this.urgencyReason,
    required this.keyPoints,
    required this.recommendedDocuments,
    required this.pendingQuestions,
    required this.generatedAt,
  });

  SuggestedLegalCategory? get primaryCategory =>
      suggestedCategories.isEmpty ? null : suggestedCategories.first;
}

/// Overview textual pronta para o advogado, gerada a partir do [IntakeSummary].
class LawyerOverview {
  final String sessionId;
  final String formattedText;
  final DateTime generatedAt;

  const LawyerOverview({
    required this.sessionId,
    required this.formattedText,
    required this.generatedAt,
  });
}
