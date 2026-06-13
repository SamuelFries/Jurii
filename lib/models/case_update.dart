class CaseUpdate {
  final String id;
  final String caseId;
  final String title;
  final String body;
  final String authorName;
  final String authorInitials;
  final String createdAtLabel;

  const CaseUpdate({
    required this.id,
    required this.caseId,
    required this.title,
    required this.body,
    required this.authorName,
    required this.authorInitials,
    required this.createdAtLabel,
  });
}
