import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/jurii_notification.dart';
import 'package:jurii/models/lawyer_case.dart';
import 'package:jurii/services/notification_router.dart';

void main() {
  group('derivação do estado do caso do advogado', () {
    test('closed do banco vence tudo', () {
      expect(
        deriveLawyerCaseStatus(status: 'closed'),
        LawyerCaseStatus.closed,
      );
    });

    test('new_message do banco vira novidade', () {
      expect(
        deriveLawyerCaseStatus(status: 'new_message'),
        LawyerCaseStatus.newMessage,
      );
    });

    test('qualquer outro status cai no padrão', () {
      // O prazo manual saiu (migration 20260804120000): não há mais estado
      // derivado de data. 'deadline' segue no enum do banco, sem escritor.
      expect(deriveLawyerCaseStatus(status: 'open'), LawyerCaseStatus.updated);
      expect(deriveLawyerCaseStatus(status: null), LawyerCaseStatus.updated);
      expect(
        deriveLawyerCaseStatus(status: 'deadline'),
        LawyerCaseStatus.updated,
      );
    });
  });

  test('o resumo do caso é do advogado, não do cliente', () {
    // create_case_request exige conversation.lawyer_id = auth.uid(), então
    // legal_cases.description é o texto que o ADVOGADO escreveu ao propor o
    // caso. Rotular como "relato do cliente" atribuiria a fala à pessoa
    // errada para os dois lados que leem o mesmo campo.
    final fonte = File('lib/screens/case_details_screen.dart').readAsStringSync();
    expect(fonte.contains('Relato do cliente'), isFalse);
    expect(fonte.contains("'Resumo do caso'"), isTrue);
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

  group('movimentação do processo avisa os dois lados', () {
    // Mesmo fato, dois tipos: o sino filtra por ESCOPO e o escopo deriva do
    // TIPO (infer_notification_scope). Reusar case_update para o advogado
    // jogaria o aviso no sino do cliente.
    JuriiNotification build({required String type, required NotificationScope scope}) {
      return JuriiNotification(
        id: 'n-$type',
        title: 'Movimentação',
        body: 'corpo',
        type: type,
        scope: scope,
        createdAt: DateTime(2026, 8, 4),
        metadata: const {'case_id': 'k1'},
      );
    }

    test('aviso do cliente (case_update) abre o caso', () {
      expect(
        destinationFor(
          build(type: 'case_update', scope: NotificationScope.client),
        ),
        NotificationDestinationKind.legalCase,
      );
    });

    test('aviso do advogado (case_movement) abre o caso', () {
      expect(
        destinationFor(
          build(type: 'case_movement', scope: NotificationScope.lawyer),
        ),
        NotificationDestinationKind.legalCase,
      );
    });
  });
}
