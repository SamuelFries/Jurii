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
    // Em produção o timeLabel deriva do starts_at (repositório); o fixture
    // espelha isso para o teste não mentir sobre o horário.
    timeLabel: startsAt == null
        ? '10:00'
        : '${startsAt.hour.toString().padLeft(2, '0')}:'
              '${startsAt.minute.toString().padLeft(2, '0')}',
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

  group('agendaSummary', () {
    test('conta os de hoje e aponta o próximo ainda por vir', () {
      final summary = agendaSummary([
        // Já começou (8h < now 9h): conta em "hoje" mas não é o próximo.
        _appointment('a', startsAt: DateTime(2026, 8, 2, 8)),
        _appointment('b', startsAt: DateTime(2026, 8, 2, 14)),
        _appointment('c', startsAt: DateTime(2026, 8, 3, 10)),
      ], now: now, isLawyer: true);

      expect(summary.title, '2 compromissos hoje');
      expect(summary.subtitle, 'Próximo: Hoje às 14:00 · Compromisso b');
    });

    test('singular no título com um só compromisso hoje', () {
      final summary = agendaSummary([
        _appointment('a', startsAt: DateTime(2026, 8, 2, 15)),
      ], now: now, isLawyer: true);

      expect(summary.title, '1 compromisso hoje');
    });

    test('sem nada hoje, o próximo pode ser de outro dia', () {
      final summary = agendaSummary([
        _appointment('a', startsAt: DateTime(2026, 8, 7, 11)),
      ], now: now, isLawyer: false);

      expect(summary.title, 'Nenhum compromisso hoje');
      expect(
        summary.subtitle,
        'Próximo: Sex · 07/08 às 11:00 · Compromisso a',
      );
    });

    test('todos de hoje já começaram: sem copy de agenda vazia', () {
      // 18h; os dois compromissos do dia já começaram e não há futuros.
      final evening = DateTime(2026, 8, 2, 18);
      final summary = agendaSummary([
        _appointment('a', startsAt: DateTime(2026, 8, 2, 8)),
        _appointment('b', startsAt: DateTime(2026, 8, 2, 14)),
      ], now: evening, isLawyer: true);

      expect(summary.title, '2 compromissos hoje');
      expect(summary.subtitle, 'Sem mais compromissos por vir hoje.');
    });

    test('lista vazia usa a chamada por papel', () {
      final lawyer = agendaSummary(const [], now: now, isLawyer: true);
      final client = agendaSummary(const [], now: now, isLawyer: false);

      expect(lawyer.title, 'Nenhum compromisso hoje');
      expect(lawyer.subtitle, contains('Novo compromisso'));
      expect(client.subtitle, contains('aparecerá aqui'));
    });

    test('demo sem horários usa dateLabel e o primeiro da lista', () {
      final summary = agendaSummary([
        _appointment('a', dateLabel: 'Hoje'),
        _appointment('b', dateLabel: 'Hoje'),
        _appointment('c', dateLabel: 'Amanhã'),
      ], now: now, isLawyer: true);

      expect(summary.title, '2 compromissos hoje');
      expect(summary.subtitle, 'Próximo: Hoje às 10:00 · Compromisso a');
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
