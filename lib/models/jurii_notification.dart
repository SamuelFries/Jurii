enum NotificationScope {
  client('client'),
  lawyer('lawyer'),
  firm('firm');

  const NotificationScope(this.databaseValue);

  final String databaseValue;

  static NotificationScope fromDatabase(String? value) {
    return switch (value) {
      'lawyer' => NotificationScope.lawyer,
      'firm' => NotificationScope.firm,
      _ => NotificationScope.client,
    };
  }
}

class JuriiNotification {
  final String id;
  final String title;
  final String body;
  final String type;
  final NotificationScope scope;
  final DateTime createdAt;
  final DateTime? readAt;
  final Map<String, dynamic> metadata;

  const JuriiNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.scope = NotificationScope.client,
    required this.createdAt,
    this.readAt,
    this.metadata = const {},
  });

  bool get isUnread => readAt == null;

  String? get membershipId => metadata['membership_id'] as String?;

  String? get inviteStatus => metadata['invite_status'] as String?;

  String? get caseRequestId => metadata['case_request_id'] as String?;

  String? get caseRequestStatus => metadata['request_status'] as String?;

  bool get isPendingTeamInvite {
    return type == 'team_invite' &&
        membershipId != null &&
        inviteStatus == null &&
        isUnread;
  }

  bool get isPendingCaseRequest {
    return type == 'case_request' &&
        caseRequestId != null &&
        caseRequestStatus == 'pending';
  }
}
