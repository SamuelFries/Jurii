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
  final normalizedQuery = normalizePracticeAreaQuery(query);
  if (normalizedQuery.isEmpty) return true;

  return [
    ...practiceAreas,
    ...extraFields,
  ].any((value) => normalizePracticeAreaQuery(value).contains(normalizedQuery));
}

String normalizePracticeAreaQuery(String value) {
  return value
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
}
