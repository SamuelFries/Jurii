import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/jurii_notification.dart';
import 'package:jurii/models/lawyer_case.dart';
import 'package:jurii/services/notification_router.dart';

void main() {
  group('derivação do estado do caso do advogado', () {
    final now = DateTime(2026, 8, 1);

    test('closed do banco vence qualquer prazo', () {
      expect(
        deriveLawyerCaseStatus(
          status: 'closed',
          deadlineAt: now.add(const Duration(days: 2)),
          now: now,
        ),
        LawyerCaseStatus.closed,
      );
    });

    test('prazo em até 7 dias vira urgência — inclusive vencido', () {
      expect(
        deriveLawyerCaseStatus(
          status: 'open',
          deadlineAt: now.add(const Duration(days: 3)),
          now: now,
        ),
        LawyerCaseStatus.deadline,
      );
      expect(
        deriveLawyerCaseStatus(
          status: 'open',
          deadlineAt: now.subtract(const Duration(days: 2)),
          now: now,
        ),
        LawyerCaseStatus.deadline,
      );
    });

    test('borda dos 7 dias: igual à regra do servidor (<= now + 7d)', () {
      // Exatamente 7 dias é urgente; 7 dias e 1 hora não é — mesma semântica
      // do urgent do painel (deadline_at <= now() + interval '7 days').
      expect(
        deriveLawyerCaseStatus(
          status: 'open',
          deadlineAt: now.add(const Duration(days: 7)),
          now: now,
        ),
        LawyerCaseStatus.deadline,
      );
      expect(
        deriveLawyerCaseStatus(
          status: 'open',
          deadlineAt: now.add(const Duration(days: 7, hours: 1)),
          now: now,
        ),
        LawyerCaseStatus.updated,
      );
    });

    test('prazo distante ou ausente não é urgência', () {
      expect(
        deriveLawyerCaseStatus(
          status: 'open',
          deadlineAt: now.add(const Duration(days: 30)),
          now: now,
        ),
        LawyerCaseStatus.updated,
      );
      expect(
        deriveLawyerCaseStatus(status: 'open', deadlineAt: null, now: now),
        LawyerCaseStatus.updated,
      );
    });
  });

  test('convite de avaliação (case_closed) abre o caso', () {
    final notification = JuriiNotification(
      id: 'n1',
      title: 'Caso encerrado',
      body: 'Avalie o atendimento.',
      type: 'case_closed',
      scope: NotificationScope.client,
      createdAt: DateTime(2026, 8, 1),
      metadata: const {'case_id': 'k1'},
    );

    expect(destinationFor(notification), NotificationDestinationKind.legalCase);
  });
}
