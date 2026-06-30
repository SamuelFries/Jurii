import '../../models/jurii_notification.dart';

final mockNotifications = [
  JuriiNotification(
    id: 'notification_team_invite',
    title: 'Convite para escritorio',
    body: 'Voce tem um convite pendente para integrar uma equipe.',
    type: 'team_invite',
    scope: NotificationScope.lawyer,
    createdAt: DateTime(2026, 6, 30, 10, 30),
    metadata: const {'membership_id': 'mock_membership_invite'},
  ),
  JuriiNotification(
    id: 'notification_message',
    title: 'Nova mensagem',
    body: 'Dra. Marina respondeu sua conversa sobre a minuta.',
    type: 'message',
    scope: NotificationScope.client,
    createdAt: DateTime(2026, 6, 30, 9, 45),
  ),
  JuriiNotification(
    id: 'notification_case_request',
    title: 'Solicitacao de caso',
    body: 'Fries Advogados pediu seu aceite para abrir um novo caso.',
    type: 'case_request',
    scope: NotificationScope.client,
    createdAt: DateTime(2026, 6, 30, 9, 12),
    metadata: const {
      'case_request_id': 'request_demo_01',
      'request_status': 'pending',
    },
  ),
  JuriiNotification(
    id: 'notification_case',
    title: 'Atualizacao de caso',
    body: 'A triagem trabalhista recebeu uma nova movimentacao.',
    type: 'case_update',
    scope: NotificationScope.client,
    createdAt: DateTime(2026, 6, 29, 17, 20),
    readAt: DateTime(2026, 6, 29, 18),
  ),
  JuriiNotification(
    id: 'notification_lawyer_message',
    title: 'Cliente aguardando resposta',
    body: 'Beatriz Ramos enviou comprovantes para analise.',
    type: 'message',
    scope: NotificationScope.lawyer,
    createdAt: DateTime(2026, 6, 30, 10, 48),
  ),
  JuriiNotification(
    id: 'notification_firm_case',
    title: 'Caso atribuido',
    body: 'Rescisao trabalhista foi atribuida ao Dr. Rafael Lima.',
    type: 'case_assignment',
    scope: NotificationScope.firm,
    createdAt: DateTime(2026, 6, 30, 8, 50),
  ),
];
