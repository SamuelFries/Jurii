class LegalCategory {
  final String id;
  final String title;

  /// Nome do ícone Material vindo de legal_categories.icon_name
  /// (ex.: 'family_restroom'). Nulo em dados antigos/mock — a UI cai na
  /// heurística por título.
  final String? iconName;

  /// Área jurídica CANÔNICA (legal_categories.practice_area) que o tap na
  /// categoria aplica como filtro da descoberta. Nula em dados antigos — a
  /// UI cai na heurística por id/título.
  final String? practiceArea;

  const LegalCategory({
    required this.id,
    required this.title,
    this.iconName,
    this.practiceArea,
  });
}
