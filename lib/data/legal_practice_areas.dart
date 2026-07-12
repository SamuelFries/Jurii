const legalPracticeAreas = [
  'Direito Trabalhista',
  'Direito de Família',
  'Direito do Consumidor',
  'Direito Previdenciário',
  'Direito Imobiliário',
  'Direito Criminal',
  'Direito Empresarial',
  'Direito Tributário',
  'Direito Cível',
  'Direito Digital',
  'Acidente de Trânsito',
];

class LegalSearchIntentRule {
  const LegalSearchIntentRule({
    required this.practiceAreas,
    required this.terms,
  });

  final List<String> practiceAreas;
  final List<String> terms;
}

const legalSearchIntentRules = [
  LegalSearchIntentRule(
    practiceAreas: ['Direito Criminal'],
    terms: [
      'advogado criminal',
      'advogado criminalista',
      'direito penal',
      'processo criminal',
      'processo penal',
      'acusado',
      'acusação',
      'acusaram',
      'réu',
      'réu primário',
      'vítima de crime',
      'crime',
      'crime grave',
      'denúncia criminal',
      'queixa crime',
      'Maria da Penha',
      'Lei Maria da Penha',
      'violência doméstica',
      'violência contra mulher',
      'violência contra a mulher',
      'violência familiar',
      'mulher agredida',
      'apanhei do marido',
      'marido bateu',
      'marido me bateu',
      'meu marido me bateu',
      'namorado me bateu',
      'ex me bateu',
      'ex me ameaça',
      'ex me ameaçou',
      'meu ex me persegue',
      'perseguição',
      'stalking',
      'medida protetiva',
      'descumpriu medida protetiva',
      'quebrou medida protetiva',
      'estupro',
      'estupro de vulnerável',
      'abuso sexual',
      'assédio sexual',
      'importunação sexual',
      'crime sexual',
      'violência sexual',
      'toque sem consentimento',
      'fui abusada',
      'fui abusado',
      'ameaça',
      'ameaçaram',
      'fui ameaçado',
      'fui ameaçada',
      'ameaça pelo whatsapp',
      'agressão',
      'agressão física',
      'fui agredido',
      'fui agredida',
      'me bateram',
      'lesão corporal',
      'homicídio',
      'tentativa de homicídio',
      'briga',
      'briga de rua',
      'roubo',
      'furto',
      'assalto',
      'fui assaltado',
      'fui assaltada',
      'me roubaram',
      'roubaram meu celular',
      'invadiram minha casa',
      'arrombamento',
      'receptação',
      'estelionato',
      'golpe',
      'caí em golpe',
      'fraude',
      'extorsão',
      'chantagem',
      'sequestro',
      'cárcere privado',
      'prisão',
      'preso',
      'foi preso',
      'prenderam',
      'flagrante',
      'prisão em flagrante',
      'audiência de custódia',
      'habeas corpus',
      'fiança',
      'tornozeleira eletrônica',
      'regime aberto',
      'regime semiaberto',
      'execução penal',
      'delegacia',
      'intimação policial',
      'depoimento na delegacia',
      'inquérito policial',
      'boletim de ocorrência',
      'b o',
      'fazer boletim',
      'trafico de drogas',
      'tráfico de drogas',
      'porte de droga',
      'porte de maconha',
      'drogas',
      'lei seca',
      'embriaguez ao volante',
      'calúnia',
      'injúria',
      'difamação',
      'falsa acusação',
      'nudes vazados',
      'vazaram nudes',
      'pornografia de vingança',
    ],
  ),
  LegalSearchIntentRule(
    practiceAreas: ['Direito de Família'],
    terms: [
      'advogado de família',
      'direito de família',
      'divórcio',
      'divorciar',
      'quero divorciar',
      'quero me separar',
      'separação',
      'separação amigável',
      'separação litigiosa',
      'divórcio amigável',
      'divórcio litigioso',
      'fim do casamento',
      'casamento acabou',
      'pensão alimentícia',
      'pensão',
      'pensão atrasada',
      'não paga pensão',
      'não pagou pensão',
      'pai não paga pensão',
      'mãe não paga pensão',
      'aumentar pensão',
      'diminuir pensão',
      'revisão de pensão',
      'execução de alimentos',
      'alimentos',
      'alimentos gravídicos',
      'guarda',
      'guarda compartilhada',
      'guarda unilateral',
      'guarda dos filhos',
      'pegar guarda',
      'perder guarda',
      'visitas',
      'direito de visita',
      'regulamentação de visitas',
      'mãe não deixa ver filho',
      'pai não deixa ver filho',
      'não consigo ver meu filho',
      'união estável',
      'dissolução de união estável',
      'contrato de união estável',
      'alienação parental',
      'partilha',
      'partilha de bens',
      'dividir bens',
      'bens do casal',
      'regime de bens',
      'pacto antenupcial',
      'paternidade',
      'reconhecimento de paternidade',
      'exame de dna',
      'dna',
      'nome do pai',
      'adoção',
      'adotar',
      'tutela',
      'curatela',
      'interdição familiar',
      'inventário familiar',
      'herança de família',
      'briga de herança',
      'testamento da família',
    ],
  ),
  LegalSearchIntentRule(
    practiceAreas: ['Direito Trabalhista'],
    terms: [
      'advogado trabalhista',
      'direito trabalhista',
      'trabalho',
      'emprego',
      'patrão',
      'empresa não pagou',
      'patrão não pagou',
      'chefe',
      'demissão',
      'fui demitido',
      'fui demitida',
      'me mandaram embora',
      'mandaram embora',
      'demitido sem receber',
      'demitida sem receber',
      'não recebi acerto',
      'acerto trabalhista',
      'acordo trabalhista',
      'rescisão',
      'rescisão trabalhista',
      'fgts',
      'fgts atrasado',
      'fgts não depositado',
      'não depositaram fgts',
      'horas extras',
      'hora extra',
      'banco de horas',
      'jornada de trabalho',
      'intervalo',
      'não tenho intervalo',
      'trabalho demais',
      'assédio moral',
      'humilhação no trabalho',
      'chefe humilha',
      'chefe grita',
      'perseguição no trabalho',
      'assédio sexual no trabalho',
      'chefe me assedia',
      'salário atrasado',
      'salário não pago',
      'pagamento atrasado',
      'décimo terceiro',
      '13 atrasado',
      'férias',
      'férias vencidas',
      'férias não pagas',
      'verbas rescisórias',
      'justa causa',
      'demissão por justa causa',
      'reverter justa causa',
      'carteira assinada',
      'trabalho sem carteira',
      'não assinaram carteira',
      'vínculo empregatício',
      'pejotização',
      'mei obrigado',
      'sou mei mas sou empregado',
      'autônomo mas empregado',
      'desvio de função',
      'acúmulo de função',
      'equiparação salarial',
      'adicional noturno',
      'periculosidade',
      'insalubridade',
      'acidente de trabalho',
      'doença ocupacional',
      'estabilidade gestante',
      'licença maternidade',
      'cipa',
      'sindicato',
      'doméstica',
      'empregada doméstica',
      'diarista',
      'motorista de aplicativo',
      'entregador de aplicativo',
      'processo trabalhista',
      'reclamação trabalhista',
    ],
  ),
  LegalSearchIntentRule(
    practiceAreas: ['Direito do Consumidor'],
    terms: [
      'advogado consumidor',
      'direito do consumidor',
      'procon',
      'juizado consumidor',
      'pequenas causas consumidor',
      'produto defeituoso',
      'produto com defeito',
      'produto quebrado',
      'comprei e não chegou',
      'compra não chegou',
      'pedido não chegou',
      'loja não entregou',
      'atraso na entrega',
      'loja não troca',
      'troca negada',
      'garantia',
      'garantia negada',
      'cobrança indevida',
      'cobraram errado',
      'boleto indevido',
      'fatura errada',
      'cobrança abusiva',
      'juros abusivos',
      'nome sujo',
      'negativação',
      'negativação indevida',
      'serasa',
      'spc',
      'protesto indevido',
      'cartão de crédito',
      'cartão clonado',
      'plano de saúde',
      'convênio médico',
      'plano negou cirurgia',
      'plano negou tratamento',
      'plano negou exame',
      'cirurgia negada',
      'tratamento negado',
      'banco',
      'banco bloqueou conta',
      'conta bloqueada',
      'empréstimo não contratado',
      'empréstimo consignado',
      'desconto indevido',
      'financiamento',
      'consórcio',
      'seguro',
      'seguradora não paga',
      'viagem cancelada',
      'passagem cancelada',
      'voo cancelado',
      'voo atrasado',
      'bagagem extraviada',
      'overbooking',
      'hotel cancelado',
      'mensalidade',
      'faculdade',
      'escola',
      'curso online',
      'assinatura',
      'cancelar assinatura',
      'cobrança de assinatura',
      'telefone',
      'internet',
      'operadora',
      'energia elétrica',
      'conta de luz',
      'água',
      'conta de água',
      'marketplace',
      'app de entrega',
      'compra online',
      'propaganda enganosa',
      'fraude bancária',
      'pix errado',
      'golpe do pix',
    ],
  ),
  LegalSearchIntentRule(
    practiceAreas: ['Direito Previdenciário'],
    terms: [
      'advogado previdenciário',
      'direito previdenciário',
      'previdência',
      'inss',
      'meu inss',
      'aposentadoria',
      'aposentadoria negada',
      'aposentar',
      'aposentadoria por idade',
      'aposentadoria por tempo',
      'aposentadoria especial',
      'tempo de contribuição',
      'revisão da aposentadoria',
      'revisão da vida toda',
      'auxílio doença',
      'auxílio por incapacidade',
      'benefício por incapacidade',
      'bpc',
      'loas',
      'benefício negado',
      'benefício cortado',
      'meu benefício foi cortado',
      'pente fino',
      'perícia',
      'perícia negada',
      'perícia médica',
      'laudo médico',
      'incapacidade',
      'auxílio acidente',
      'pensão por morte',
      'salário maternidade',
      'salario maternidade',
      'recurso inss',
      'indeferido inss',
      'pedido indeferido',
      'cnis',
      'contribuição não aparece',
      'tempo rural',
      'trabalhador rural',
      'segurado especial',
      'ppp',
      'insalubridade inss',
      'aposentadoria rural',
      'deficiente',
      'idoso bpc',
      'aposentadoria pessoa com deficiência',
    ],
  ),
  LegalSearchIntentRule(
    practiceAreas: ['Direito Imobiliário'],
    terms: [
      'advogado imobiliário',
      'direito imobiliário',
      'imóvel',
      'casa',
      'apartamento',
      'terreno',
      'lote',
      'aluguel',
      'aluguel atrasado',
      'contrato de aluguel',
      'despejo',
      'ordem de despejo',
      'ação de despejo',
      'inquilino não paga',
      'inquilino não sai',
      'proprietário',
      'locador',
      'locatário',
      'condomínio',
      'taxa de condomínio',
      'síndico',
      'locação',
      'compra de imóvel',
      'venda de imóvel',
      'escritura',
      'registro de imóvel',
      'matrícula do imóvel',
      'regularizar imóvel',
      'habite-se',
      'usucapião',
      'posse',
      'posse de terreno',
      'invasão de terreno',
      'invasão de imóvel',
      'construtora',
      'obra atrasada',
      'atraso na obra',
      'imóvel na planta',
      'distrato imobiliário',
      'financiamento imobiliário',
      'financiamento caixa',
      'corretor',
      'comissão de corretagem',
      'caução',
      'fiador',
      'vistoria',
      'infiltração',
      'vício construtivo',
      'reforma',
      'vizinho barulhento',
      'barulho de vizinho',
    ],
  ),
  LegalSearchIntentRule(
    practiceAreas: ['Acidente de Trânsito'],
    terms: [
      'advogado de trânsito',
      'direito de trânsito',
      'acidente de trânsito',
      'batida',
      'bati o carro',
      'bateram no meu carro',
      'bateram na minha moto',
      'colisão',
      'engavetamento',
      'acidente de carro',
      'acidente de moto',
      'acidente de ônibus',
      'acidente com uber',
      'acidente aplicativo',
      'atropelamento',
      'fui atropelado',
      'fui atropelada',
      'trânsito',
      'seguradora',
      'seguro do carro',
      'seguro não pagou',
      'indenização acidente',
      'danos no carro',
      'conserto do carro',
      'perda total',
      'dpvat',
      'boletim de acidente',
      'culpa no acidente',
      'motorista bêbado',
      'multa de trânsito',
      'multa de transito',
      'cnh suspensa',
      'cnh cassada',
      'pontos na carteira',
      'bafômetro',
      'recusei bafômetro',
      'lei seca',
      'carro apreendido',
      'guincho',
      'licenciamento',
      'recurso de multa',
    ],
  ),
  LegalSearchIntentRule(
    practiceAreas: ['Direito Empresarial'],
    terms: [
      'advogado empresarial',
      'direito empresarial',
      'empresa',
      'abrir empresa',
      'fechar empresa',
      'cnpj',
      'contrato social',
      'alteração contrato social',
      'alterar contrato social',
      'sócio',
      'sócios',
      'briga de sócios',
      'briga com sócio',
      'tirar sócio',
      'retirada de sócio',
      'entrada de sócio',
      'empresa',
      'sociedade',
      'dissolução de sociedade',
      'acordo de sócios',
      'quotas',
      'ltda',
      'mei',
      'microempresa',
      'holding',
      'startup',
      'franquia',
      'contrato empresarial',
      'fornecedor',
      'cliente não pagou empresa',
      'cobrança empresarial',
      'recuperação judicial',
      'falência',
      'marca',
      'registro de marca',
      'pro labore',
      'compliance',
      'licitação',
      'contrato de prestação de serviço',
      'contrato com fornecedor',
      'contrato de parceria',
      'distribuição',
      'representação comercial',
    ],
  ),
  LegalSearchIntentRule(
    practiceAreas: ['Direito Tributário'],
    terms: [
      'advogado tributário',
      'direito tributário',
      'imposto',
      'impostos',
      'tributo',
      'tributos',
      'dívida ativa',
      'execução fiscal',
      'cobrança da prefeitura',
      'cobrança do estado',
      'cobrança da receita',
      'iptu',
      'ipva',
      'icms',
      'iss',
      'irpf',
      'irpj',
      'imposto de renda',
      'receita federal',
      'malha fina',
      'simples nacional',
      'mei imposto',
      'pis',
      'cofins',
      'darf',
      // 'das' (guia do MEI) removido: colide com a contração "das" ("fotos das
      // agressões"), gerando falso positivo de Tributário. Cobertura de MEI
      // fica por 'mei imposto' / 'simples nacional'.
      'parcelamento fiscal',
      'multa fiscal',
      'autuação fiscal',
      'fiscalização',
      'nota fiscal',
      'sonegação',
      'cnd',
      'certidão negativa',
      'recuperar imposto',
      'restituição',
      'taxa',
      'itcmd',
      'itbi',
      'protesto da prefeitura',
      'regularizar imposto',
    ],
  ),
  LegalSearchIntentRule(
    practiceAreas: ['Direito Cível'],
    terms: [
      'advogado cível',
      'direito civil',
      'processo civil',
      'juizado especial',
      'pequenas causas',
      'indenização',
      'danos morais',
      'dano moral',
      'danos materiais',
      'dano material',
      'cobrança',
      'cobrar dívida',
      'alguém me deve',
      'me devem dinheiro',
      'calote',
      'levei calote',
      'emprestei dinheiro',
      'não me pagaram',
      'contrato',
      'quebra de contrato',
      'descumprimento de contrato',
      'rescisão de contrato',
      'responsabilidade civil',
      'erro médico',
      'erro odontológico',
      'acidente em loja',
      'queda em estabelecimento',
      'queda no mercado',
      'herança',
      'inventário',
      'testamento',
      'partilha de herança',
      'briga de herança',
      'registro civil',
      'alterar nome',
      'alteração de nome',
      'retificar documento',
      'retificação de registro',
      'interdição',
      'curatela',
      'vizinho',
      'briga com vizinho',
      'barulho de vizinho',
      'direito de imagem',
      'uso indevido de imagem',
      'calúnia',
      'injúria',
      'difamação',
      'cobrança judicial',
      'notificação extrajudicial',
      'contrato de compra e venda',
      'contrato de prestação de serviço',
    ],
  ),
  LegalSearchIntentRule(
    practiceAreas: ['Direito Digital'],
    terms: [
      'advogado digital',
      'direito digital',
      'crime virtual',
      'crime na internet',
      'internet',
      'rede social',
      'lgpd',
      'vazamento de dados',
      'dados vazados',
      'privacidade',
      'proteção de dados',
      'perfil hackeado',
      'conta hackeada',
      'instagram hackeado',
      'facebook hackeado',
      'whatsapp clonado',
      'clonaram whatsapp',
      'conta invadida',
      'golpe do pix',
      'pix',
      'pix errado',
      'internet',
      'fraude online',
      'golpe online',
      'loja falsa',
      'site falso',
      'cyberbullying',
      'nudes vazados',
      'vazaram nudes',
      'fotos vazadas',
      'vídeo vazado',
      'pornografia de vingança',
      'difamação na internet',
      'post ofensivo',
      'comentário ofensivo',
      'fake news',
      'deepfake',
      'remover conteúdo',
      'tirar conteúdo do ar',
      'remover foto',
      'remover vídeo',
      'uso indevido de imagem',
      'direito autoral',
      'plágio',
      'software',
      'contrato de software',
      'aplicativo',
      'termos de uso',
      'e-commerce',
    ],
  ),
];

String practiceAreaForCategory({required String id, required String title}) {
  final normalizedId = normalizePracticeAreaQuery(id);
  final normalizedTitle = normalizePracticeAreaQuery(title);

  if (normalizedId.contains('divorcio') ||
      normalizedTitle.contains('divorcio') ||
      normalizedId.contains('pensao') ||
      normalizedTitle.contains('pensao')) {
    return 'Direito de Família';
  }
  if (normalizedId.contains('consumidor') ||
      normalizedTitle.contains('consumidor')) {
    return 'Direito do Consumidor';
  }
  if (normalizedId.contains('trabalhista') ||
      normalizedTitle.contains('trabalhista')) {
    return 'Direito Trabalhista';
  }
  if (normalizedId.contains('imobiliario') ||
      normalizedTitle.contains('imobiliario')) {
    return 'Direito Imobiliário';
  }
  if (normalizedId.contains('acidente') ||
      normalizedTitle.contains('acidente')) {
    return 'Acidente de Trânsito';
  }

  return title.replaceAll('\n', ' ').trim();
}

String primaryPracticeArea(List<String> practiceAreas) {
  if (practiceAreas.isEmpty) return 'Atendimento jurídico';
  return practiceAreas.first;
}

String practiceAreaSummary(List<String> practiceAreas) {
  if (practiceAreas.isEmpty) return 'Atendimento jurídico';
  if (practiceAreas.length == 1) return practiceAreas.first;
  return '${practiceAreas.first} +${practiceAreas.length - 1}';
}

bool matchesPracticeAreaSearch({
  required List<String> practiceAreas,
  required String query,
  Iterable<String> extraFields = const [],
}) {
  final normalizedTerms = expandPracticeAreaSearchTerms(
    query,
  ).map(normalizePracticeAreaQuery).where((value) => value.isNotEmpty).toSet();
  if (normalizedTerms.isEmpty) return true;

  return [...practiceAreas, ...extraFields].any((value) {
    final normalizedValue = normalizePracticeAreaQuery(value);
    return normalizedTerms.any(
      (term) =>
          normalizedValue.contains(term) || term.contains(normalizedValue),
    );
  });
}

bool isPracticeAreaSelectedForQuery({
  required String area,
  required String query,
}) {
  final normalizedArea = normalizePracticeAreaQuery(area);
  final normalizedQuery = normalizePracticeAreaQuery(query);
  if (normalizedArea.isEmpty || normalizedQuery.isEmpty) return false;
  if (normalizedQuery == normalizedArea) return true;

  return inferPracticeAreasForSearch(query).any(
    (inferredArea) =>
        normalizePracticeAreaQuery(inferredArea) == normalizedArea,
  );
}

List<String> expandPracticeAreaSearchTerms(String query) {
  final normalizedQuery = normalizePracticeAreaQuery(query);
  if (normalizedQuery.isEmpty) return const [];

  return {query, ...inferPracticeAreasForSearch(query)}.toList(growable: false);
}

/// Área do direito inferida com a força do casamento (quantos termos da regra
/// bateram no texto). Usado para ranquear e para a IA medir confiança.
class InferredPracticeArea {
  const InferredPracticeArea({required this.area, required this.matchCount});

  final String area;
  final int matchCount;
}

/// Infere as áreas de um texto livre, ordenadas da mais forte para a mais
/// fraca, com a contagem de termos que casaram em cada uma.
///
/// A força permite que a busca ranqueie melhor e que a triagem da IA descarte
/// áreas secundárias fracas (antes a ordem vinha só da posição estática da
/// regra, então Criminal sempre saía na frente).
List<InferredPracticeArea> scorePracticeAreasForSearch(String query) {
  final normalizedQuery = normalizePracticeAreaQuery(query);
  if (normalizedQuery.length < 3) return const [];

  final scoreByArea = <String, int>{};
  final firstRuleByArea = <String, int>{};
  for (
    var ruleIndex = 0;
    ruleIndex < legalSearchIntentRules.length;
    ruleIndex++
  ) {
    final rule = legalSearchIntentRules[ruleIndex];
    var matches = 0;
    for (final term in rule.terms) {
      if (_searchIntentTermMatches(
        normalizedQuery,
        normalizePracticeAreaQuery(term),
      )) {
        matches++;
      }
    }
    if (matches == 0) continue;
    for (final area in rule.practiceAreas) {
      scoreByArea[area] = (scoreByArea[area] ?? 0) + matches;
      firstRuleByArea.putIfAbsent(area, () => ruleIndex);
    }
  }

  final orderedAreas = scoreByArea.keys.toList(growable: false)
    ..sort((a, b) {
      final byScore = scoreByArea[b]!.compareTo(scoreByArea[a]!);
      if (byScore != 0) return byScore;
      // Empate: mantém a ordem original das regras (determinístico).
      return firstRuleByArea[a]!.compareTo(firstRuleByArea[b]!);
    });
  return [
    for (final area in orderedAreas)
      InferredPracticeArea(area: area, matchCount: scoreByArea[area]!),
  ];
}

List<String> inferPracticeAreasForSearch(String query) =>
    scorePracticeAreasForSearch(
      query,
    ).map((inferred) => inferred.area).toList(growable: false);

bool _searchIntentTermMatches(String normalizedQuery, String normalizedTerm) {
  if (normalizedQuery.isEmpty || normalizedTerm.isEmpty) return false;

  // 1) Termo presente na query respeitando limites de palavra. Cobre termo de
  //    uma palavra ("fgts") e frase inteira ("marido me bateu"), sem deixar
  //    "iss" (imposto) casar dentro de "demissao".
  if (_containsAtWordBoundary(normalizedQuery, normalizedTerm)) return true;

  // 2) Query de palavra única que é o começo de alguma palavra do termo
  //    ("aposenta" -> "aposentadoria"). Restrito a query de uma palavra para
  //    não reintroduzir ruído em frases longas (relato da triagem).
  if (!normalizedQuery.contains(' ') && normalizedQuery.length >= 4) {
    final matchesPrefix = normalizedTerm
        .split(' ')
        .any((token) => token.startsWith(normalizedQuery));
    if (matchesPrefix) return true;
  }

  // 3) Frase cujos tokens significativos (>= 4 letras) aparecem todos como
  //    palavras da query, mesmo fora de ordem ("plano ... negou ... cirurgia").
  //    O piso de 4 letras evita que palavras comuns e curtas ("nao", "com",
  //    "sem") virem sinal — antes "nao ... pagaram" casava o termo cível
  //    "nao me pagaram" num relato puramente trabalhista.
  final queryTokens = normalizedQuery.split(' ').toSet();
  final significantTermTokens = normalizedTerm
      .split(' ')
      .where((token) => token.length >= 4)
      .toList(growable: false);

  return significantTermTokens.length >= 2 &&
      significantTermTokens.every((token) => queryTokens.contains(token));
}

/// `true` se [needle] aparece em [haystack] delimitado por espaços (ou pelas
/// bordas da string) — casamento por palavra inteira, não por substring solta.
bool _containsAtWordBoundary(String haystack, String needle) {
  var start = 0;
  while (start <= haystack.length) {
    final index = haystack.indexOf(needle, start);
    if (index < 0) return false;
    final beforeOk = index == 0 || haystack[index - 1] == ' ';
    final end = index + needle.length;
    final afterOk = end == haystack.length || haystack[end] == ' ';
    if (beforeOk && afterOk) return true;
    start = index + 1;
  }
  return false;
}

String normalizePracticeAreaQuery(String value) {
  final withoutAccents = value
      .toLowerCase()
      .trim()
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ã', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ç', 'c');

  return withoutAccents
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
