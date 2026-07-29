class LegalCase {
  final String id;
  final String title;
  final String area;
  final String status;
  final String lastUpdate;

  /// Número do processo no padrão CNJ (20 dígitos, sem máscara). Nulo quando
  /// o caso ainda não virou processo judicial, o que é normal.
  final String? cnjNumber;

  const LegalCase({
    required this.id,
    required this.title,
    required this.status,
    this.area = 'Atendimento jurídico',
    this.lastUpdate = 'Atualizado hoje',
    this.cnjNumber,
  });
}
