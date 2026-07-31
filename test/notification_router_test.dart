import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/jurii_notification.dart';
import 'package:jurii/services/notification_router.dart';

JuriiNotification notification({
  required String type,
  NotificationScope scope = NotificationScope.client,
  Map<String, dynamic> metadata = const {},
}) {
  return JuriiNotification(
    id: 'n1',
    title: 'Título',
    body: 'Corpo',
    type: type,
    scope: scope,
    createdAt: DateTime(2026, 7, 30),
    metadata: metadata,
  );
}

void main() {
  group('destino do toque na notificação', () {
    test('andamento processual abre o caso', () {
      // 'case_update' carrega só case_id: era o beco sem saída que motivou
      // esta feature.
      expect(
        destinationFor(
          notification(type: 'case_update', metadata: const {'case_id': 'k1'}),
        ),
        NotificationDestinationKind.legalCase,
      );
    });

    test('indicação de advogado abre a conversa', () {
      expect(
        destinationFor(
          notification(
            type: 'lawyer_recommendation',
            metadata: const {'conversation_id': 'c1'},
          ),
        ),
        NotificationDestinationKind.conversation,
      );
    });

    test('quando há os dois, a conversa vem antes do caso', () {
      // case_request_response carrega conversation_id E legal_case_id; a
      // conversa é onde a pessoa continua o assunto.
      expect(
        destinationFor(
          notification(
            type: 'case_request_response',
            metadata: const {
              'conversation_id': 'c1',
              'legal_case_id': 'k1',
            },
          ),
        ),
        NotificationDestinationKind.conversation,
      );
    });

    test('escopo do escritório não abre conversa, mas abre o caso', () {
      // Abrir o chat com os padrões do ChatScreen reintroduziria propor caso
      // e triagem no contexto do escritório.
      expect(
        destinationFor(
          notification(
            type: 'firm_case_started',
            scope: NotificationScope.firm,
            metadata: const {'conversation_id': 'c1', 'case_id': 'k1'},
          ),
        ),
        NotificationDestinationKind.legalCase,
      );
    });

    test('sem destino não navega (só marca como lida)', () {
      // 'lawyer_recommended' não tem conversation_id de propósito: o advogado
      // indicado não tem acesso àquela conversa do cliente.
      expect(
        destinationFor(notification(type: 'lawyer_recommended')),
        NotificationDestinationKind.none,
      );
      expect(
        destinationFor(
          notification(
            type: 'appointment_reminder',
            scope: NotificationScope.lawyer,
            metadata: const {'appointment_id': 'a1'},
          ),
        ),
        NotificationDestinationKind.none,
      );
    });

    test('convite de equipe resolve pelas ações inline, não por navegação', () {
      expect(
        destinationFor(
          notification(
            type: 'team_invite',
            scope: NotificationScope.lawyer,
            metadata: const {'membership_id': 'm1'},
          ),
        ),
        NotificationDestinationKind.none,
      );
    });
  });
}
