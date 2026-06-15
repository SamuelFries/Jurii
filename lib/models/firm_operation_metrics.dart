class FirmOperationMetrics {
  final int clientMessages;
  final int teamMessages;
  final int activeCases;
  final int teamMembers;

  const FirmOperationMetrics({
    required this.clientMessages,
    required this.teamMessages,
    required this.activeCases,
    required this.teamMembers,
  });

  const FirmOperationMetrics.empty({this.teamMembers = 0})
    : clientMessages = 0,
      teamMessages = 0,
      activeCases = 0;
}
