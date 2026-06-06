class Conversation {
  final String initials;
  final String officeName;
  final String specialty;
  final String lastMessage;
  final String time;
  final int unreadCount;

  const Conversation({
    required this.initials,
    required this.officeName,
    required this.specialty,
    required this.lastMessage,
    required this.time,
    required this.unreadCount,
  });
}