class LawyerCase {
  final String id;
  final String title;
  final String clientName;
  final String clientInitials;
  final String area;
  final String lastUpdate;
  final LawyerCaseStatus status;

  const LawyerCase({
    required this.id,
    required this.title,
    required this.clientName,
    required this.clientInitials,
    required this.area,
    required this.lastUpdate,
    required this.status,
  });
}

enum LawyerCaseStatus {
  updated,
  newMessage,
  deadline,
}