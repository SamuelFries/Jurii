class FirmCaseOverview {
  final String id;
  final String title;
  final String clientName;
  final String clientInitials;
  final String assignedLawyer;
  final String area;
  final String statusLabel;
  final String nextStep;
  final bool urgent;

  const FirmCaseOverview({
    required this.id,
    required this.title,
    required this.clientName,
    required this.clientInitials,
    required this.assignedLawyer,
    required this.area,
    required this.statusLabel,
    required this.nextStep,
    required this.urgent,
  });
}
