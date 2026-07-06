class LegalCategory {
  final String id;
  final String title;
  final bool isGold;

  /// Nome do ícone Material vindo de legal_categories.icon_name
  /// (ex.: 'family_restroom'). Nulo em dados antigos/mock — a UI cai na
  /// heurística por título.
  final String? iconName;

  const LegalCategory({
    required this.id,
    required this.title,
    required this.isGold,
    this.iconName,
  });
}
