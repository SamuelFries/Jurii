/// Casamento de texto para as buscas de lista (conversas e casos).
///
/// Existe como função pura, fora de widget, porque a mesma regra roda em seis
/// telas e precisa ser testável sem montar tela nenhuma. Widget de tela com
/// repositório falso pula a filtragem inteira; aqui a regra é exercitada de
/// verdade.
library;

/// Texto pronto para comparar: minúsculo, sem acento, sem pontuação.
///
/// Quem procura "jose" tem que achar "José", e quem procura "acao" tem que
/// achar "Ação". A mesma normalização vale para o termo digitado e para o
/// campo do modelo, senão a comparação mede coisas diferentes.
String normalizeSearchText(String value) {
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

/// Só os dígitos, para comparar número de processo.
///
/// O banco guarda o CNJ com 20 dígitos e sem máscara; o PJe e o cliente
/// entregam "0801234-56.2026.8.26.0100". Sem isto, colar o número copiado do
/// tribunal não acha nada.
String onlyDigits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

/// A busca de [query] casa com algum de [fields]?
///
/// Termo vazio casa com tudo (lista sem filtro). Cada palavra do termo tem
/// que aparecer em ALGUM campo: digitar "ana trabalhista" acha a conversa da
/// Ana sobre matéria trabalhista mesmo com o nome num campo e a área em
/// outro. Campo nulo é ignorado, e não tratado como string vazia que casaria
/// com qualquer coisa.
bool searchTextMatches(String query, Iterable<String?> fields) {
  final terms = normalizeSearchText(query).split(' ')
    ..removeWhere((term) => term.isEmpty);
  if (terms.isEmpty) return true;

  final haystack = fields
      .whereType<String>()
      .map(normalizeSearchText)
      .where((field) => field.isNotEmpty)
      .join(' ');
  if (haystack.isEmpty) return false;

  return terms.every(haystack.contains);
}

/// A busca casa com o número do processo?
///
/// Separado de [searchTextMatches] porque a comparação é por dígitos: a
/// normalização de texto transformaria "0801234-56" em "0801234 56" e o
/// pedaço colado deixaria de casar com os 20 dígitos corridos do banco.
/// Termo sem dígito nenhum não consulta o CNJ, senão a busca por nome
/// passaria a casar com qualquer processo.
bool cnjMatches(String query, String? cnjNumber) {
  if (cnjNumber == null) return false;
  final digits = onlyDigits(query);
  if (digits.isEmpty) return false;
  return onlyDigits(cnjNumber).contains(digits);
}

/// Um chip de filtro só merece espaço se mudar o que está na tela.
///
/// Chip que casa com tudo (`matches == total`) não filtra nada, e chip que
/// não casa com nada devolve lista vazia e faz a pessoa achar que perdeu
/// dados. Os dois são ruído permanente numa tela pequena.
bool filterChipIsUseful({required int matches, required int total}) =>
    matches > 0 && matches < total;
