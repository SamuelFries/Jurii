/// Sugestão de advogado feita pelo escritório dentro da conversa com o cliente.
///
/// Vive na metadata da mensagem: um retrato do advogado gravado pelo servidor
/// no momento da sugestão (nome, OAB e foto). Só o [lawyerId] serve para agir —
/// é ele que abre a conversa, e o banco revalida o advogado nesse clique.
class LawyerRecommendation {
  final String lawyerId;
  final String name;
  final String initials;
  final String oabLabel;
  final String? primaryArea;
  final String? photoUrl;
  final String? note;

  const LawyerRecommendation({
    required this.lawyerId,
    required this.name,
    required this.initials,
    required this.oabLabel,
    this.primaryArea,
    this.photoUrl,
    this.note,
  });

  static const metadataType = 'lawyer_recommendation';

  /// Retorna `null` quando a metadata não é uma sugestão válida — sem advogado
  /// para abrir conversa, o card não teria o que fazer.
  static LawyerRecommendation? fromMetadata(Map<String, dynamic> metadata) {
    if (metadata['type'] != metadataType) return null;

    final lawyerId = _text(metadata['lawyer_id']);
    if (lawyerId == null) return null;

    final name = _text(metadata['lawyer_name']) ?? 'Advogado';

    return LawyerRecommendation(
      lawyerId: lawyerId,
      name: name,
      initials: _text(metadata['lawyer_initials']) ?? _initialsFor(name),
      oabLabel: _text(metadata['oab_label']) ?? 'OAB verificada',
      primaryArea: _text(metadata['primary_area']),
      photoUrl: _text(metadata['avatar_url']),
      note: _text(metadata['note']),
    );
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _initialsFor(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'AJ';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
