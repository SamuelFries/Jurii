class JuriiNotification {
  final String id;
  final String title;
  final String body;
  final String type;
  final DateTime createdAt;
  final DateTime? readAt;
  final Map<String, dynamic> metadata;

  const JuriiNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.readAt,
    this.metadata = const {},
  });

  bool get isUnread => readAt == null;

  String? get membershipId => metadata['membership_id'] as String?;

  String? get inviteStatus => metadata['invite_status'] as String?;

  bool get isPendingTeamInvite {
    return type == 'team_invite' &&
        membershipId != null &&
        inviteStatus == null &&
        isUnread;
  }
}
