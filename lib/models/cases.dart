class LegalCase {
  final String id;
  final String title;
  final String area;
  final String status;
  final String lastUpdate;

  const LegalCase({
    required this.id,
    required this.title,
    required this.status,
    this.area = 'Atendimento jurídico',
    this.lastUpdate = 'Atualizado hoje',
  });
}
