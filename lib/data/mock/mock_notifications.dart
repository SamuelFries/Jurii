import '../../models/jurii_notification.dart';

final mockNotifications = [
  JuriiNotification(
    id: 'notification_team_invite',
    title: 'Convite para escritório',
    body: 'Você tem um convite pendente para integrar uma equipe.',
    type: 'team_invite',
    scope: NotificationScope.lawyer,
    createdAt: DateTime(2026, 6, 12, 10, 30),
    metadata: const {'membership_id': 'mock_membership_invite'},
  ),
  JuriiNotification(
    id: 'notification_message',
    title: 'Nova mensagem',
    body: 'Há uma conversa aguardando resposta.',
    type: 'message',
    scope: NotificationScope.client,
    createdAt: DateTime(2026, 6, 12, 9, 45),
  ),
  JuriiNotification(
    id: 'notification_case',
    title: 'Atualização de caso',
    body: 'Um caso recebeu uma nova movimentação.',
    type: 'case_update',
    scope: NotificationScope.client,
    createdAt: DateTime(2026, 6, 11, 17, 20),
    readAt: DateTime(2026, 6, 11, 18),
  ),
];
