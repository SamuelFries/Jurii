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

  JuriiNotification copyWith({
    String? id,
    String? title,
    String? body,
    String? type,
    NotificationScope? scope,
    DateTime? createdAt,
    DateTime? readAt,
    Map<String, dynamic>? metadata,
  }) {
    return JuriiNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      scope: scope ?? this.scope,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
      metadata: metadata ?? this.metadata,
    );
  }

  String? get membershipId => metadata['membership_id'] as String?;

  String? get inviteStatus => metadata['invite_status'] as String?;

  String? get caseRequestId => metadata['case_request_id'] as String?;

  String? get caseRequestStatus => metadata['request_status'] as String?;

  /// Conversa de origem, quando a notificação nasceu de uma (solicitação de
  /// caso, resposta, indicação de advogado, caso iniciado no escritório).
  String? get conversationId => metadata['conversation_id'] as String?;

  /// Caso vinculado. O servidor grava com dois nomes conforme a origem
  /// (`legal_case_id` na resposta de solicitação, `case_id` no caso do
  /// escritório e no andamento processual); aqui vale o primeiro que existir.
  String? get caseId =>
      (metadata['case_id'] ?? metadata['legal_case_id']) as String?;

  /// A notificação leva a algum lugar quando tocada.
  bool get hasDestination => conversationId != null;

  bool get isPendingTeamInvite {
    return type == 'team_invite' &&
        membershipId != null &&
        inviteStatus == null;
  }

  bool get isPendingCaseRequest {
    return type == 'case_request' &&
        caseRequestId != null &&
        caseRequestStatus == 'pending';
  }
}
