class Conversation {
  final String? id;
  final String initials;
  final String officeName;
  final String specialty;
  final String lastMessage;
  final String time;
  final int unreadCount;
  final String type;
  final String? lawFirmId;

  const Conversation({
    this.id,
    required this.initials,
    required this.officeName,
    required this.specialty,
    required this.lastMessage,
    required this.time,
    required this.unreadCount,
    this.type = 'mock',
    this.lawFirmId,
  });

  bool get isFromSupabase => id != null;
}
