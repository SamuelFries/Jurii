class FirmCaseOverview {
  final String id;
  final String title;
  final String clientName;
  final String clientInitials;
  final String? assignedLawyerId;
  final String assignedLawyer;
  final String area;
  final String statusLabel;
  final String nextStep;
  final bool urgent;

  /// Número do processo no padrão CNJ (20 dígitos, sem máscara). Nulo quando
  /// o caso ainda não virou processo judicial, o que é normal.
  final String? cnjNumber;

  /// O caso tem prazo registrado mas ainda não tem número de processo.
  final bool needsCnjNumber;

  const FirmCaseOverview({
    required this.id,
    required this.title,
    required this.clientName,
    required this.clientInitials,
    this.assignedLawyerId,
    required this.assignedLawyer,
    required this.area,
    required this.statusLabel,
    required this.nextStep,
    required this.urgent,
    this.cnjNumber,
    this.needsCnjNumber = false,
  });
}
