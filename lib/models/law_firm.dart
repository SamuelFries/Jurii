class LawFirm {
  final String id;
  final String name;
  final String initials;
  final double rating;
  final String distance;
  final String specialty;
  final List<String> practiceAreas;
  final int reviews;
  final String avatarType;
  final String? avatarUrl;
  final String? description;
  final String? phone;
  final String? email;
  final String? websiteUrl;
  final String? address;

  /// Posição patrocinada ativa na descoberta (destaque pago/cortesia).
  /// Vem de `is_featured` no RPC de descoberta; default false para mocks e
  /// para caminhos que não expõem o campo (ex.: fallback de leitura direta).
  final bool isFeatured;

  const LawFirm({
    required this.id,
    required this.name,
    required this.initials,
    required this.rating,
    required this.distance,
    required this.specialty,
    required this.practiceAreas,
    required this.reviews,
    required this.avatarType,
    this.avatarUrl,
    this.description,
    this.phone,
    this.email,
    this.websiteUrl,
    this.address,
    this.isFeatured = false,
  });
}
