import '../data/legal_practice_areas.dart';
import '../models/intake_session.dart';
import '../models/intake_summary.dart';

/// Contrato da IA de triagem (primeiro contato cliente → advogado).
///
/// A implementação real conversará com um backend seguro (Supabase Edge
/// Function que guarda a chave da API de IA — a chave nunca entra no app).
/// Enquanto isso, [RuleBasedIntakeAIService] entrega o mesmo contrato de
/// forma 100% local, usando a taxonomia de busca jurídica já existente.
///
/// Ver docs/ai-intake.md para a arquitetura completa.
abstract class IntakeAIService {
  Future<ClientIntakeSession> startSession({required String clientId});

  Future<ClientIntakeSession> sendClientMessage(
    ClientIntakeSession session,
    String text,
  );

  Future<IntakeSummary> buildSummary(ClientIntakeSession session);

  LawyerOverview buildLawyerOverview(IntakeSummary summary);
}

/// Implementação local e determinística da triagem.
///
/// Não usa nenhuma API externa: infere a área do direito com as mesmas
/// regras de palavras-chave da busca (lib/data/legal_practice_areas.dart),
/// segue um roteiro de perguntas por área e monta o resumo para o advogado.
class RuleBasedIntakeAIService implements IntakeAIService {
  RuleBasedIntakeAIService({this.maxFollowUpQuestions = 4});

  final int maxFollowUpQuestions;
  int _idCounter = 0;

  static const _greeting =
      'Olá! Sou a assistente da Jurii. Antes de conectar você a um '
      'profissional, vou fazer algumas perguntas rápidas para que o advogado '
      'já receba seu caso organizado.\n\n'
      'Para começar: me conte, com suas palavras, o que aconteceu.';

  static const _wrapUp =
      'Obrigada! Já tenho o suficiente para organizar seu relato. '
      'Vou preparar um resumo para o profissional — você poderá revisar '
      'tudo antes do envio.';

  static const _safetyNotice =
      'Percebi que sua situação pode envolver risco à sua segurança. '
      'Se você estiver em perigo agora, ligue 190 (Polícia Militar) ou '
      '180 (Central de Atendimento à Mulher). Seguimos com o atendimento '
      'aqui também.';

  @override
  Future<ClientIntakeSession> startSession({required String clientId}) async {
    final now = DateTime.now();
    return ClientIntakeSession(
      id: _nextId('intake'),
      clientId: clientId,
      status: IntakeSessionStatus.collecting,
      messages: [
        IntakeMessage(
          id: _nextId('msg'),
          sender: IntakeMessageSender.assistant,
          body: _greeting,
          sentAt: now,
        ),
      ],
      inferredPracticeAreas: const [],
      nextQuestionIndex: 0,
      startedAt: now,
    );
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

    final messages = [
      ...session.messages,
      IntakeMessage(
        id: _nextId('msg'),
        sender: IntakeMessageSender.client,
        body: trimmed,
        sentAt: DateTime.now(),
      ),
    ];

    final statements = [...session.clientStatements, trimmed].join('\n');
    final inferredAreas = inferPracticeAreasForSearch(statements);

    final needsSafetyNotice =
        _detectUrgency(statements).$1 == UrgencyLevel.critical &&
        !session.messages.any((message) => message.body == _safetyNotice);
    if (needsSafetyNotice) {
      messages.add(
        IntakeMessage(
          id: _nextId('msg'),
          sender: IntakeMessageSender.assistant,
          body: _safetyNotice,
          sentAt: DateTime.now(),
        ),
      );
    }

    final answeredCount = session.nextQuestionIndex;
    final nextQuestion = answeredCount < maxFollowUpQuestions
        ? _pickNextQuestion(inferredAreas, answeredCount)
        : null;

    if (nextQuestion == null) {
      messages.add(
        IntakeMessage(
          id: _nextId('msg'),
          sender: IntakeMessageSender.assistant,
          body: _wrapUp,
          sentAt: DateTime.now(),
        ),
      );
      return session.copyWith(
        status: IntakeSessionStatus.ready,
        messages: messages,
        inferredPracticeAreas: inferredAreas,
        nextQuestionIndex: answeredCount,
      );
    }

    messages.add(
      IntakeMessage(
        id: _nextId('msg'),
        sender: IntakeMessageSender.assistant,
        body: nextQuestion.text,
        sentAt: DateTime.now(),
      ),
    );
    return session.copyWith(
      messages: messages,
      inferredPracticeAreas: inferredAreas,
      nextQuestionIndex: answeredCount + 1,
    );
  }

  @override
  Future<IntakeSummary> buildSummary(ClientIntakeSession session) async {
    final statements = session.clientStatements.join('\n');
    final relevantAreas = _relevantScoredAreas(
      scorePracticeAreasForSearch(statements),
    );
    final areas = relevantAreas
        .map((inferred) => inferred.area)
        .toList(growable: false);

    final (urgency, urgencyReason) = _detectUrgency(statements);

    final topScore = relevantAreas.isEmpty ? 1 : relevantAreas.first.matchCount;
    final categories = [
      for (final inferred in relevantAreas)
        SuggestedLegalCategory(
          practiceArea: inferred.area,
          // Confiança proporcional à força do casamento (nº de termos que
          // bateram), não mais um valor fixo.
          confidence: (inferred.matchCount / topScore).clamp(0.3, 1.0),
        ),
    ];

    final askedQuestionIds = _askedQuestionIds(session);
    final relevantQuestions = _questionsForAreas(areas);
    final pendingQuestions = relevantQuestions
        .where((question) => !askedQuestionIds.contains(question.id))
        .take(4)
        .toList(growable: false);

    return IntakeSummary(
      sessionId: session.id,
      caseSummary: _buildCaseSummary(session, areas),
      suggestedCategories: categories,
      urgency: urgency,
      urgencyReason: urgencyReason,
      keyPoints: _buildKeyPoints(session),
      recommendedDocuments: _documentsForAreas(areas),
      pendingQuestions: pendingQuestions,
      generatedAt: DateTime.now(),
    );
  }

  @override
  LawyerOverview buildLawyerOverview(IntakeSummary summary) {
    final buffer = StringBuffer()
      ..writeln('Resumo do caso:')
      ..writeln(summary.caseSummary)
      ..writeln()
      ..writeln('Categoria provável:')
      ..writeln(
        summary.suggestedCategories.isEmpty
            ? 'Não identificada — triagem manual recomendada.'
            : summary.suggestedCategories
                  .map((category) => category.practiceArea)
                  .join(', '),
      )
      ..writeln()
      ..writeln('Urgência:')
      ..writeln('${summary.urgency.label} — ${summary.urgencyReason}');

    if (summary.keyPoints.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Pontos importantes:');
      for (final point in summary.keyPoints) {
        buffer.writeln('- $point');
      }
    }

    if (summary.recommendedDocuments.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Documentos recomendados:');
      for (final document in summary.recommendedDocuments) {
        buffer.writeln('- ${document.title}');
      }
    }

    if (summary.pendingQuestions.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Perguntas pendentes:');
      for (final question in summary.pendingQuestions) {
        buffer.writeln('- ${question.text}');
      }
    }

    return LawyerOverview(
      sessionId: summary.sessionId,
      formattedText: buffer.toString().trimRight(),
      generatedAt: summary.generatedAt,
    );
  }

  String _nextId(String prefix) {
    _idCounter += 1;
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_idCounter';
  }

  /// Mantém a área mais forte e as que tiveram pelo menos dois termos batendo;
  /// descarta secundárias de sinal fraco (um único termo, muitas vezes
  /// tangencial) para o resumo do advogado não vir poluído.
  List<InferredPracticeArea> _relevantScoredAreas(
    List<InferredPracticeArea> scored,
  ) {
    if (scored.isEmpty) return const [];
    final topScore = scored.first.matchCount;
    return [
      for (final inferred in scored)
        if (inferred.matchCount == topScore || inferred.matchCount >= 2)
          inferred,
    ];
  }

  IntakeQuestion? _pickNextQuestion(List<String> areas, int answeredCount) {
    final askedTexts = <String>{};
    final candidates = _questionsForAreas(areas);
    var remaining = answeredCount;
    for (final question in candidates) {
      if (askedTexts.contains(question.text)) continue;
      askedTexts.add(question.text);
      if (remaining == 0) return question;
      remaining -= 1;
    }
    return null;
  }

  Set<String> _askedQuestionIds(ClientIntakeSession session) {
    final assistantBodies = session.messages
        .where((message) => message.sender == IntakeMessageSender.assistant)
        .map((message) => message.body)
        .toSet();
    return _allQuestions
        .where((question) => assistantBodies.contains(question.text))
        .map((question) => question.id)
        .toSet();
  }

  List<IntakeQuestion> _questionsForAreas(List<String> areas) {
    final areaQuestions = _allQuestions.where(
      (question) =>
          question.practiceAreas.isNotEmpty &&
          question.practiceAreas.any(areas.contains),
    );
    final generalQuestions = _allQuestions.where(
      (question) => question.practiceAreas.isEmpty,
    );
    return [...areaQuestions, ...generalQuestions];
  }

  List<RecommendedDocument> _documentsForAreas(List<String> areas) {
    final documents = <String, RecommendedDocument>{};
    for (final area in areas) {
      for (final document in _documentBank[area] ?? const []) {
        documents.putIfAbsent(document.title, () => document);
      }
    }
    if (documents.isEmpty) {
      for (final document in _generalDocuments) {
        documents.putIfAbsent(document.title, () => document);
      }
    }
    return documents.values.take(8).toList(growable: false);
  }

  String _buildCaseSummary(ClientIntakeSession session, List<String> areas) {
    final firstStatement = session.clientStatements.isEmpty
        ? ''
        : session.clientStatements.first.trim();
    if (firstStatement.isEmpty) {
      return 'Cliente iniciou a triagem, mas ainda não descreveu o caso.';
    }

    final normalized = firstStatement.length > 280
        ? '${firstStatement.substring(0, 277)}...'
        : firstStatement;
    final areaSuffix = areas.isEmpty
        ? ''
        : ' Indícios de caso de ${areas.first}.';
    return 'Cliente relata: "$normalized".$areaSuffix';
  }

  List<String> _buildKeyPoints(ClientIntakeSession session) {
    final statements = session.clientStatements;
    if (statements.length <= 1) return const [];

    // As respostas às perguntas do roteiro (a partir da 2ª mensagem) viram
    // pontos objetivos para o advogado.
    return statements
        .skip(1)
        .map((statement) => statement.trim())
        .where((statement) => statement.isNotEmpty)
        .map(
          (statement) => statement.length > 160
              ? '${statement.substring(0, 157)}...'
              : statement,
        )
        .toList(growable: false);
  }

  (UrgencyLevel, String) _detectUrgency(String statements) {
    final normalized = normalizePracticeAreaQuery(statements);
    if (normalized.isEmpty) {
      return (UrgencyLevel.low, 'Relato ainda não fornecido.');
    }

    for (final keyword in _criticalUrgencyKeywords) {
      if (normalized.contains(keyword)) {
        return (
          UrgencyLevel.critical,
          'Relato indica possível risco pessoal ou privação de liberdade.',
        );
      }
    }
    for (final keyword in _highUrgencyKeywords) {
      if (normalized.contains(keyword)) {
        return (
          UrgencyLevel.high,
          'Relato menciona prazo, ordem judicial ou bloqueio em andamento.',
        );
      }
    }
    if (inferPracticeAreasForSearch(statements).isNotEmpty) {
      return (
        UrgencyLevel.medium,
        'Caso identificado, sem indicação de prazo imediato.',
      );
    }
    return (UrgencyLevel.low, 'Relato ainda genérico, sem urgência aparente.');
  }

  // Palavras-chave já normalizadas (sem acentos) — ver
  // normalizePracticeAreaQuery em lib/data/legal_practice_areas.dart.
  static const _criticalUrgencyKeywords = [
    'medida protetiva',
    'violencia',
    'agressao',
    'agrediu',
    'me bateu',
    'me bateram',
    'ameaca',
    'ameacou',
    'estupro',
    'abuso',
    'flagrante',
    'foi preso',
    'esta preso',
    'fui presa',
    'fui preso',
    'sequestro',
    'carcere privado',
  ];

  static const _highUrgencyKeywords = [
    'prazo',
    'audiencia',
    'intimacao',
    'intimado',
    'intimada',
    'citacao',
    'liminar',
    'despejo',
    'leilao',
    'penhora',
    'bloquearam',
    'bloqueio',
    'conta bloqueada',
    'amanha',
    'urgente',
    'hoje',
    'cirurgia negada',
    'beneficio cortado',
  ];

  static const _allQuestions = [
    // Direito Trabalhista
    IntakeQuestion(
      id: 'trabalhista_data',
      text: 'Quando aconteceu a demissão ou o problema no trabalho?',
      practiceAreas: ['Direito Trabalhista'],
    ),
    IntakeQuestion(
      id: 'trabalhista_carteira',
      text: 'Você trabalhava com carteira assinada? Por quanto tempo?',
      practiceAreas: ['Direito Trabalhista'],
    ),
    IntakeQuestion(
      id: 'trabalhista_verbas',
      text:
          'A empresa pagou alguma verba (acerto, FGTS, aviso prévio) ou nada foi pago?',
      practiceAreas: ['Direito Trabalhista'],
    ),
    // Direito de Família
    IntakeQuestion(
      id: 'familia_filhos',
      text: 'Há filhos menores envolvidos? Quantos e com quem moram hoje?',
      practiceAreas: ['Direito de Família'],
    ),
    IntakeQuestion(
      id: 'familia_vinculo',
      text: 'Vocês são casados no papel ou viviam em união estável?',
      practiceAreas: ['Direito de Família'],
    ),
    IntakeQuestion(
      id: 'familia_acordo',
      text:
          'Existe chance de acordo entre as partes ou o conflito está aberto?',
      practiceAreas: ['Direito de Família'],
    ),
    // Direito do Consumidor
    IntakeQuestion(
      id: 'consumidor_quando',
      text: 'Quando ocorreu a compra ou a cobrança? Qual o valor envolvido?',
      practiceAreas: ['Direito do Consumidor'],
    ),
    IntakeQuestion(
      id: 'consumidor_protocolo',
      text:
          'Você já tentou resolver com a empresa? Tem número de protocolo ou prints do atendimento?',
      practiceAreas: ['Direito do Consumidor'],
    ),
    // Direito Criminal
    IntakeQuestion(
      id: 'criminal_bo',
      text: 'Já foi registrado boletim de ocorrência? Se sim, quando e onde?',
      practiceAreas: ['Direito Criminal'],
    ),
    IntakeQuestion(
      id: 'criminal_seguranca',
      text: 'Você está em segurança neste momento?',
      practiceAreas: ['Direito Criminal'],
    ),
    // Direito Previdenciário
    IntakeQuestion(
      id: 'previdenciario_negativa',
      text: 'O INSS já negou algum pedido seu? Você tem a carta de decisão?',
      practiceAreas: ['Direito Previdenciário'],
    ),
    IntakeQuestion(
      id: 'previdenciario_laudos',
      text: 'Você possui laudos ou atestados médicos recentes?',
      practiceAreas: ['Direito Previdenciário'],
    ),
    // Direito Imobiliário
    IntakeQuestion(
      id: 'imobiliario_contrato',
      text: 'Existe contrato por escrito? Você tem uma cópia?',
      practiceAreas: ['Direito Imobiliário'],
    ),
    IntakeQuestion(
      id: 'imobiliario_atraso',
      text: 'Há valores em atraso? Desde quando?',
      practiceAreas: ['Direito Imobiliário'],
    ),
    // Acidente de Trânsito
    IntakeQuestion(
      id: 'transito_bo',
      text: 'Foi feito boletim de ocorrência do acidente? Houve feridos?',
      practiceAreas: ['Acidente de Trânsito'],
    ),
    // Direito Digital
    IntakeQuestion(
      id: 'digital_provas',
      text:
          'Você guardou prints, links ou comprovantes do que aconteceu online?',
      practiceAreas: ['Direito Digital'],
    ),
    // Gerais (qualquer área)
    IntakeQuestion(
      id: 'geral_desde_quando',
      text: 'Desde quando essa situação está acontecendo?',
    ),
    IntakeQuestion(
      id: 'geral_provas',
      text:
          'Você tem documentos, conversas ou comprovantes relacionados ao caso?',
    ),
    IntakeQuestion(
      id: 'geral_objetivo',
      text:
          'Qual é o seu principal objetivo? (ex.: receber um valor, fazer um acordo, se defender)',
    ),
    IntakeQuestion(
      id: 'geral_outro_advogado',
      text:
          'Você já procurou outro advogado ou algum órgão público sobre isso?',
    ),
  ];

  static const _generalDocuments = [
    RecommendedDocument(
      title: 'Documento de identidade (RG ou CNH)',
      reason: 'Necessário para qualquer procuração ou petição.',
    ),
    RecommendedDocument(
      title: 'Comprovante de residência',
      reason: 'Define a comarca competente para o caso.',
    ),
    RecommendedDocument(
      title: 'Conversas e comprovantes relacionados ao caso',
      reason: 'Prints e recibos ajudam a comprovar o relato.',
    ),
  ];

  static const _documentBank = <String, List<RecommendedDocument>>{
    'Direito Trabalhista': [
      RecommendedDocument(
        title: 'Carteira de trabalho (física ou digital)',
        reason: 'Comprova o vínculo e as datas de admissão/demissão.',
      ),
      RecommendedDocument(
        title: 'Contrato de trabalho',
        reason: 'Define função, jornada e salário combinados.',
      ),
      RecommendedDocument(
        title: 'Holerites / contracheques',
        reason: 'Base para calcular verbas e diferenças salariais.',
      ),
      RecommendedDocument(
        title: 'Extrato do FGTS',
        reason: 'Mostra se os depósitos foram feitos corretamente.',
      ),
      RecommendedDocument(
        title: 'Conversas com o empregador',
        reason: 'Podem comprovar promessas, cobranças ou assédio.',
      ),
    ],
    'Direito de Família': [
      RecommendedDocument(
        title: 'Certidão de casamento ou prova da união estável',
        reason: 'Documento base para divórcio ou dissolução.',
      ),
      RecommendedDocument(
        title: 'Certidão de nascimento dos filhos',
        reason: 'Necessária para guarda, visitas e pensão.',
      ),
      RecommendedDocument(
        title: 'Comprovantes de renda e despesas',
        reason: 'Base do cálculo de pensão alimentícia.',
      ),
      RecommendedDocument(
        title: 'Documentos dos bens do casal',
        reason: 'Necessários para a partilha.',
      ),
    ],
    'Direito do Consumidor': [
      RecommendedDocument(
        title: 'Nota fiscal ou comprovante da compra',
        reason: 'Comprova a relação de consumo.',
      ),
      RecommendedDocument(
        title: 'Comprovantes de pagamento (fatura, boleto, Pix)',
        reason: 'Demonstram o valor pago ou cobrado indevidamente.',
      ),
      RecommendedDocument(
        title: 'Protocolos de atendimento e prints das conversas',
        reason: 'Mostram as tentativas de resolução com a empresa.',
      ),
    ],
    'Direito Criminal': [
      RecommendedDocument(
        title: 'Boletim de ocorrência',
        reason: 'Registro oficial dos fatos.',
      ),
      RecommendedDocument(
        title: 'Mensagens, fotos ou vídeos relacionados',
        reason: 'Provas do ocorrido ou das ameaças.',
      ),
      RecommendedDocument(
        title: 'Medida protetiva ou decisões existentes',
        reason: 'Situam o advogado sobre o andamento do caso.',
      ),
    ],
    'Direito Previdenciário': [
      RecommendedDocument(
        title: 'Extrato CNIS (Meu INSS)',
        reason: 'Histórico oficial de contribuições.',
      ),
      RecommendedDocument(
        title: 'Carta de indeferimento do INSS',
        reason: 'Mostra o motivo da negativa do benefício.',
      ),
      RecommendedDocument(
        title: 'Laudos e atestados médicos',
        reason: 'Comprovam a incapacidade alegada.',
      ),
    ],
    'Direito Imobiliário': [
      RecommendedDocument(
        title: 'Contrato de aluguel ou de compra e venda',
        reason: 'Documento central da disputa.',
      ),
      RecommendedDocument(
        title: 'Matrícula do imóvel',
        reason: 'Comprova a titularidade e ônus do bem.',
      ),
      RecommendedDocument(
        title: 'Comprovantes de pagamento e notificações',
        reason: 'Demonstram o histórico entre as partes.',
      ),
    ],
    'Acidente de Trânsito': [
      RecommendedDocument(
        title: 'Boletim de ocorrência do acidente',
        reason: 'Registro oficial da dinâmica do acidente.',
      ),
      RecommendedDocument(
        title: 'Fotos dos veículos e do local',
        reason: 'Provas visuais dos danos.',
      ),
      RecommendedDocument(
        title: 'Orçamentos de conserto e apólice de seguro',
        reason: 'Base do valor da indenização.',
      ),
    ],
    'Direito Empresarial': [
      RecommendedDocument(
        title: 'Contrato social e alterações',
        reason: 'Define poderes e participação dos sócios.',
      ),
      RecommendedDocument(
        title: 'Contratos e notas fiscais relacionados',
        reason: 'Documentam a relação comercial em disputa.',
      ),
    ],
    'Direito Tributário': [
      RecommendedDocument(
        title: 'Notificações ou autos de infração',
        reason: 'Identificam a cobrança questionada.',
      ),
      RecommendedDocument(
        title: 'Guias e comprovantes de pagamento',
        reason: 'Mostram o que já foi recolhido.',
      ),
    ],
    'Direito Cível': [
      RecommendedDocument(
        title: 'Contrato ou acordo entre as partes',
        reason: 'Base da obrigação discutida.',
      ),
      RecommendedDocument(
        title: 'Comprovantes de pagamento e conversas',
        reason: 'Demonstram a dívida ou o prejuízo.',
      ),
    ],
    'Direito Digital': [
      RecommendedDocument(
        title: 'Prints com data, hora e URL do conteúdo',
        reason: 'Provas do ocorrido online antes de remoção.',
      ),
      RecommendedDocument(
        title: 'Protocolos de denúncia nas plataformas',
        reason: 'Mostram as tentativas de solução extrajudicial.',
      ),
      RecommendedDocument(
        title: 'Boletim de ocorrência (crimes virtuais)',
        reason: 'Registro oficial para investigação.',
      ),
    ],
    // Áreas acrescentadas com a taxonomia de 39 (20260816120000). Área sem
    // entrada aqui não quebra — cai em [_generalDocuments] —, mas o cliente
    // chega na conversa sem o documento que decide o caso, e a primeira
    // resposta do advogado vira "me manda tal papel".
    'Direito das Sucessões': [
      RecommendedDocument(
        title: 'Certidão de óbito',
        reason: 'Abre o inventário e conta o prazo legal.',
      ),
      RecommendedDocument(
        title: 'Documentos dos bens (matrículas, extratos, veículos)',
        reason: 'Definem o que entra na partilha.',
      ),
      RecommendedDocument(
        title: 'Certidões de nascimento e casamento dos herdeiros',
        reason: 'Provam quem tem direito à herança.',
      ),
      RecommendedDocument(
        title: 'Testamento, se existir',
        reason: 'Muda a forma e o rito do inventário.',
      ),
    ],
    'Direito Bancário': [
      RecommendedDocument(
        title: 'Contrato do empréstimo ou financiamento',
        reason: 'É onde estão os juros e as tarifas discutidos.',
      ),
      RecommendedDocument(
        title: 'Extratos com os descontos questionados',
        reason: 'Mostram o que foi cobrado e desde quando.',
      ),
      RecommendedDocument(
        title: 'Protocolos de atendimento no banco',
        reason: 'Comprovam a tentativa de resolver antes do processo.',
      ),
    ],
    'Direito Médico e da Saúde': [
      RecommendedDocument(
        title: 'Prontuário e exames',
        reason: 'Base técnica de qualquer discussão sobre o atendimento.',
      ),
      RecommendedDocument(
        title: 'Relatório e pedido médico do tratamento',
        reason: 'É o que obriga o plano ou o SUS a responder.',
      ),
      RecommendedDocument(
        title: 'Negativa por escrito do plano de saúde',
        reason: 'Sem ela o plano alega que nunca recusou.',
      ),
      RecommendedDocument(
        title: 'Notas e comprovantes do que você pagou',
        reason: 'Definem o valor a ser reembolsado.',
      ),
    ],
    'Direito Administrativo': [
      RecommendedDocument(
        title: 'Edital e sua inscrição (concursos)',
        reason: 'O edital é a regra que vincula a administração.',
      ),
      RecommendedDocument(
        title: 'Publicação no diário oficial',
        reason: 'Marca a data do ato e conta o prazo.',
      ),
      RecommendedDocument(
        title: 'Processo administrativo ou auto de infração',
        reason: 'Identifica exatamente o ato questionado.',
      ),
    ],
    'Direito Securitário': [
      RecommendedDocument(
        title: 'Apólice completa',
        reason: 'É onde estão as coberturas e as exclusões.',
      ),
      RecommendedDocument(
        title: 'Aviso de sinistro e negativa da seguradora',
        reason: 'Fixam a data do pedido e o motivo da recusa.',
      ),
      RecommendedDocument(
        title: 'Comprovantes de pagamento do prêmio',
        reason: 'Afastam a alegação de contrato suspenso.',
      ),
    ],
    'Direito da Criança e do Adolescente': [
      RecommendedDocument(
        title: 'Certidão de nascimento da criança',
        reason: 'Comprova filiação e idade.',
      ),
      RecommendedDocument(
        title: 'Relatórios do conselho tutelar ou da escola',
        reason: 'Registram o histórico que embasa a medida.',
      ),
      RecommendedDocument(
        title: 'Laudos médicos ou psicológicos',
        reason: 'Sustentam pedidos de proteção com urgência.',
      ),
    ],
    'Direito do Idoso': [
      RecommendedDocument(
        title: 'Documento e comprovante de renda do idoso',
        reason: 'Base de benefícios, prioridade e curatela.',
      ),
      RecommendedDocument(
        title: 'Extratos com descontos ou empréstimos não reconhecidos',
        reason: 'Mostram o abuso financeiro.',
      ),
      RecommendedDocument(
        title: 'Laudos médicos',
        reason: 'Fundamentam curatela e pedidos de tratamento.',
      ),
    ],
    'Direito Ambiental': [
      RecommendedDocument(
        title: 'Auto de infração ou notificação do órgão ambiental',
        reason: 'Define o que foi autuado e o prazo de defesa.',
      ),
      RecommendedDocument(
        title: 'Licenças e CAR da área',
        reason: 'Provam a regularidade do imóvel.',
      ),
      RecommendedDocument(
        title: 'Fotos e imagens de satélite da área',
        reason: 'Documentam o estado do local antes e depois.',
      ),
    ],
    'Direito Agrário': [
      RecommendedDocument(
        title: 'Matrícula do imóvel rural e georreferenciamento',
        reason: 'Definem limites e titularidade da terra.',
      ),
      RecommendedDocument(
        title: 'Contrato de arrendamento ou parceria',
        reason: 'Base da relação discutida.',
      ),
      RecommendedDocument(
        title: 'Notas de safra e contratos de venda',
        reason: 'Comprovam produção e prejuízo.',
      ),
    ],
    'Direito Militar': [
      RecommendedDocument(
        title: 'Boletim interno ou nota de punição',
        reason: 'É o ato que se pretende anular.',
      ),
      RecommendedDocument(
        title: 'Documentos do processo disciplinar',
        reason: 'Mostram se houve defesa e contraditório.',
      ),
      RecommendedDocument(
        title: 'Laudos e juntas médicas',
        reason: 'Base de reforma e incapacidade.',
      ),
    ],
    'Direito Educacional': [
      RecommendedDocument(
        title: 'Contrato de prestação de serviço educacional',
        reason: 'Fixa mensalidade, reajuste e regras do curso.',
      ),
      RecommendedDocument(
        title: 'Histórico escolar e comprovante de matrícula',
        reason: 'Provam a situação acadêmica discutida.',
      ),
      RecommendedDocument(
        title: 'Comunicados da instituição',
        reason: 'Registram a decisão que se quer reverter.',
      ),
    ],
    'Direito Imigratório': [
      RecommendedDocument(
        title: 'Passaporte e vistos anteriores',
        reason: 'Reconstroem o histórico migratório.',
      ),
      RecommendedDocument(
        title: 'Protocolo ou decisão da Polícia Federal',
        reason: 'Identifica o pedido e o motivo da recusa.',
      ),
      RecommendedDocument(
        title: 'Certidões do país de origem, com apostilamento',
        reason: 'Sem apostila o documento estrangeiro não é aceito.',
      ),
    ],
    'Direito da Propriedade Intelectual': [
      RecommendedDocument(
        title: 'Registro ou pedido no INPI',
        reason: 'Define desde quando o direito existe.',
      ),
      RecommendedDocument(
        title: 'Provas do uso indevido (prints, fotos, anúncios)',
        reason: 'Documentam a violação antes que ela suma.',
      ),
      RecommendedDocument(
        title: 'Provas da sua própria autoria e do uso anterior',
        reason: 'Sustentam o direito mesmo sem registro.',
      ),
    ],
    'Direito Sindical': [
      RecommendedDocument(
        title: 'Convenção ou acordo coletivo vigente',
        reason: 'É a norma que rege a categoria.',
      ),
      RecommendedDocument(
        title: 'Atas de assembleia e editais',
        reason: 'Provam a regularidade das decisões sindicais.',
      ),
      RecommendedDocument(
        title: 'Comprovantes de descontos sindicais',
        reason: 'Base da discussão sobre contribuição.',
      ),
    ],
    'Direito Eleitoral': [
      RecommendedDocument(
        title: 'Certidões de quitação eleitoral e criminais',
        reason: 'Definem a elegibilidade.',
      ),
      RecommendedDocument(
        title: 'Prestação de contas e extratos da campanha',
        reason: 'Base da defesa nas contas rejeitadas.',
      ),
      RecommendedDocument(
        title: 'Provas da propaganda questionada',
        reason: 'Registram o material antes de sair do ar.',
      ),
    ],
    'Direito Notarial e Registral': [
      RecommendedDocument(
        title: 'Matrícula atualizada do imóvel',
        reason: 'Mostra o que está registrado hoje.',
      ),
      RecommendedDocument(
        title: 'Escrituras e contratos anteriores',
        reason: 'Reconstroem a cadeia de titularidade.',
      ),
      RecommendedDocument(
        title: 'Nota devolutiva do cartório',
        reason: 'Diz exatamente o que o registro exigiu.',
      ),
    ],
    'Direito Urbanístico': [
      RecommendedDocument(
        title: 'Alvará, projeto aprovado e habite-se',
        reason: 'Provam a regularidade da construção.',
      ),
      RecommendedDocument(
        title: 'Notificação ou embargo da prefeitura',
        reason: 'Define o ato e o prazo de defesa.',
      ),
      RecommendedDocument(
        title: 'Matrícula do imóvel e planta da área',
        reason: 'Base de qualquer discussão sobre uso do solo.',
      ),
    ],
  };
}
