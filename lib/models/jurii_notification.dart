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

  /// A coluna `law_firm_id` da notificação: de qual banca ela é. Nulo nas
  /// que não pertencem a nenhuma. É o que o roteador precisa para levar um
  /// pedido de entrada à Equipe CERTA e para entrar na banca que aprovou.
  final String? lawFirmId;

  const JuriiNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.scope = NotificationScope.client,
    required this.createdAt,
    this.readAt,
    this.metadata = const {},
    this.lawFirmId,
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
    String? lawFirmId,
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
      lawFirmId: lawFirmId ?? this.lawFirmId,
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

  /// O pedido de entrada por link (`firm_join_requested`).
  String? get joinRequestId => metadata['join_request_id'] as String?;

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
