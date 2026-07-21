class LawyerProfileSummary {
  final String id;
  final String name;
  final String initials;
  final String oabNumber;
  final String oabState;
  final String primaryArea;
  final List<String> practiceAreas;
  final String bio;
  final double rating;
  final int reviews;
  final String avatarType;

  /// Foto profissional (bucket público), quando o advogado já enviou uma na
  /// verificação. Nula para quem se cadastrou antes disso — aí vale o avatar
  /// de iniciais.
  final String? photoUrl;

  /// Posição patrocinada ativa na descoberta (destaque pago/cortesia).
  /// Vem de `is_featured` nos RPCs de descoberta; default false para os mocks
  /// e para RPCs que não expõem o campo (ex.: fetch_law_firm_lawyers).
  final bool isFeatured;

  const LawyerProfileSummary({
    required this.id,
    required this.name,
    required this.initials,
    required this.oabNumber,
    required this.oabState,
    required this.primaryArea,
    required this.practiceAreas,
    required this.bio,
    required this.rating,
    required this.reviews,
    required this.avatarType,
    this.photoUrl,
    this.isFeatured = false,
  });

  String get oabLabel => 'OAB/$oabState $oabNumber';
}
