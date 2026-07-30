import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/jurii_notification.dart';
import 'package:jurii/utils/relative_time.dart';

JuriiNotification notificationWith(Map<String, dynamic> metadata) {
  return JuriiNotification(
    id: 'n1',
    title: 'Título',
    body: 'Corpo',
    type: 'case_request',
    createdAt: DateTime(2026, 7, 29, 10),
    metadata: metadata,
  );
}

void main() {
  group('formatRelativeTime', () {
    final now = DateTime(2026, 7, 29, 15, 30);

    test('minutos e horas recentes', () {
      expect(formatRelativeTime(now, now: now), 'agora');
      expect(
        formatRelativeTime(now.subtract(const Duration(seconds: 40)), now: now),
        'agora',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 5)), now: now),
        'há 5 min',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 3)), now: now),
        'há 3 h',
      );
    });

    test('ontem e dias da semana', () {
      expect(formatRelativeTime(DateTime(2026, 7, 28, 15), now: now), 'ontem');
      expect(
        formatRelativeTime(DateTime(2026, 7, 26, 15), now: now),
        'há 3 dias',
      );
    });

    test('vira data a partir de uma semana, com ano só quando difere', () {
      expect(formatRelativeTime(DateTime(2026, 7, 10, 9), now: now), '10/07');
      expect(
        formatRelativeTime(DateTime(2025, 12, 3, 9), now: now),
        '03/12/2025',
      );
    });

    test('data no futuro (relógio adiantado) não vira texto negativo', () {
      expect(
        formatRelativeTime(now.add(const Duration(minutes: 10)), now: now),
        'agora',
      );
    });
  });

  group('JuriiNotification: destino do toque', () {
    test('conversationId vem do metadata quando existe', () {
      expect(
        notificationWith(const {'conversation_id': 'c1'}).conversationId,
        'c1',
      );
      expect(notificationWith(const {}).conversationId, isNull);
    });

    test('caseId aceita os dois nomes que o servidor grava', () {
      // firm_case_started e case_update gravam 'case_id';
      // case_request_response (aceito) grava 'legal_case_id'.
      expect(notificationWith(const {'case_id': 'k1'}).caseId, 'k1');
      expect(notificationWith(const {'legal_case_id': 'k2'}).caseId, 'k2');
      expect(notificationWith(const {}).caseId, isNull);
    });

    test('hasDestination só quando há conversa de origem', () {
      expect(notificationWith(const {'conversation_id': 'c1'}).hasDestination,
          isTrue);
      expect(notificationWith(const {'case_id': 'k1'}).hasDestination, isFalse);
    });
  });
}
