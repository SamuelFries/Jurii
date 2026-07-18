class Conversation {
  final String? id;
  final String initials;
  final String? avatarUrl;
  final String officeName;
  final String specialty;
  final String lastMessage;
  final String time;
  final int unreadCount;
  final String type;
  final String? lawFirmId;
  final String? clientId;
  final String? lawyerId;

  const Conversation({
    this.id,
    required this.initials,
    this.avatarUrl,
    required this.officeName,
    required this.specialty,
    required this.lastMessage,
    required this.time,
    required this.unreadCount,
    this.type = 'mock',
    this.lawFirmId,
    this.clientId,
    this.lawyerId,
  });

  bool get isFromSupabase => id != null;
}
