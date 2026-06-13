class CaseRequest {
  final String id;
  final String conversationId;
  final String title;
  final String area;
  final String summary;
  final String requestedBy;
  final String requesterInitials;
  final String createdAtLabel;

  const CaseRequest({
    required this.id,
    required this.conversationId,
    required this.title,
    required this.area,
    required this.summary,
    required this.requestedBy,
    required this.requesterInitials,
    required this.createdAtLabel,
  });
}
