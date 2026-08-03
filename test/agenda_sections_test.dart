import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/appointment.dart';
import 'package:jurii/repositories/appointment_repository.dart';
import 'package:jurii/utils/agenda_sections.dart';

Appointment _appointment(String id, {DateTime? startsAt, String dateLabel = ''}) {
  return Appointment(
    id: id,
    role: AppointmentRole.lawyer,
    title: 'Compromisso $id',
    counterpartName: 'Fulano',
    area: 'Cível',
    dateLabel: dateLabel,
    timeLabel: '10:00',
    location: 'Fórum',
    status: AppointmentStatus.confirmed,
    startsAt: startsAt,
    endsAt: startsAt?.add(const Duration(hours: 1)),
  );
}

void main() {
  // 02/08/2026 é domingo.
  final now = DateTime(2026, 8, 2, 9);

  group('agendaDayLabel', () {
    test('hoje, amanhã e ontem', () {
      expect(agendaDayLabel(DateTime(2026, 8, 2, 23), now: now), 'Hoje');
      expect(agendaDayLabel(DateTime(2026, 8, 3), now: now), 'Amanhã');
      expect(agendaDayLabel(DateTime(2026, 8, 1), now: now), 'Ontem');
    });

    test('withDate anexa a data aos dias relativos (modo cabeçalho)', () {
      expect(
        agendaDayLabel(DateTime(2026, 8, 2, 23), now: now, withDate: true),
        'Hoje · 02/08',
      );
      expect(
        agendaDayLabel(DateTime(2026, 8, 3), now: now, withDate: true),
        'Amanhã · 03/08',
      );
    });

    test('dia comum vira "Sex · 07/08"', () {
      expect(agendaDayLabel(DateTime(2026, 8, 7), now: now), 'Sex · 07/08');
      expect(agendaDayLabel(DateTime(2026, 8, 4), now: now), 'Ter · 04/08');
    });

    test('outro ano carrega o ano — audiência de março não parece passada', () {
      expect(
        agendaDayLabel(DateTime(2027, 3, 20), now: now),
        'Sáb · 20/03/2027',
      );
    });
  });

  group('buildAgendaSections', () {
    test('agrupa por dia preservando a ordem do fetch', () {
      final sections = buildAgendaSections([
        _appointment('a', startsAt: DateTime(2026, 8, 2, 9, 30)),
        _appointment('b', startsAt: DateTime(2026, 8, 2, 14)),
        _appointment('c', startsAt: DateTime(2026, 8, 3, 16, 30)),
        _appointment('d', startsAt: DateTime(2026, 8, 7, 11)),
      ], now: now);

      // Cabeçalhos carregam a data: sem a pill por card, é aqui que a data
      // de hoje existe na tela.
      expect(sections.map((s) => s.label).toList(), [
        'Hoje · 02/08',
        'Amanhã · 03/08',
        'Sex · 07/08',
      ]);
      expect(sections.first.appointments.map((a) => a.id).toList(), [
        'a',
        'b',
      ]);
      expect(sections.last.appointments.single.id, 'd');
    });

    test('demo sem startsAt usa o dateLabel pronto', () {
      final sections = buildAgendaSections([
        _appointment('a', dateLabel: 'Hoje'),
        _appointment('b', dateLabel: 'Hoje'),
        _appointment('c', dateLabel: 'Amanhã'),
      ], now: now);

      expect(sections.map((s) => s.label).toList(), ['Hoje', 'Amanhã']);
      expect(sections.first.appointments.length, 2);
    });

    test('lista vazia não produz seções', () {
      expect(buildAgendaSections(const [], now: now), isEmpty);
    });
  });

  group('AppointmentRepository.queryPlan', () {
    test('próximos: ascendente, corte no início de hoje convertido a UTC', () {
      final plan = AppointmentRepository.queryPlan(
        past: false,
        now: DateTime(2026, 8, 2, 9, 30),
      );
      expect(plan.ascending, isTrue);
      final cutoff = DateTime.parse(plan.cutoffIso);
      expect(cutoff.isUtc, isTrue);
      // Independente do fuso da máquina: o corte é a meia-noite LOCAL.
      expect(cutoff.toLocal(), DateTime(2026, 8, 2));
    });

    test('anteriores: descendente, mesmo corte', () {
      final plan = AppointmentRepository.queryPlan(
        past: true,
        now: DateTime(2026, 8, 2, 23, 59),
      );
      expect(plan.ascending, isFalse);
      expect(DateTime.parse(plan.cutoffIso).toLocal(), DateTime(2026, 8, 2));
    });
  });

  test('fetch ordena ascendente explicitamente e tem teto', () {
    // No postgrest-dart, order() é DESCENDENTE por padrão (ascending: false),
    // ao contrário do client JS. Um .order('starts_at') puro já pôs o
    // compromisso mais distante no topo da agenda; este teste trava a fonte
    // para o padrão silencioso não voltar.
    final fonte = File(
      'lib/repositories/appointment_repository.dart',
    ).readAsStringSync();
    expect(fonte.contains(".order('starts_at')"), isFalse);
    expect(fonte.contains('ascending:'), isTrue);
    expect(fonte.contains('.limit('), isTrue);
  });
}
