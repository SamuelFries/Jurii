import '../models/appointment.dart';

/// Um dia da agenda: rótulo do cabeçalho + compromissos daquele dia, na
/// ordem em que vieram do fetch (que já ordena por horário).
class AgendaSection {
  final String label;
  final List<Appointment> appointments;

  const AgendaSection({required this.label, required this.appointments});
}

const _weekdayLabels = {
  DateTime.monday: 'Seg',
  DateTime.tuesday: 'Ter',
  DateTime.wednesday: 'Qua',
  DateTime.thursday: 'Qui',
  DateTime.friday: 'Sex',
  DateTime.saturday: 'Sáb',
  DateTime.sunday: 'Dom',
};

/// Rótulo humano de um dia: Hoje/Amanhã/Ontem quando colam em [now];
/// senão "Sex · 07/08" (com ano quando não é o ano corrente, para uma
/// audiência marcada para março não parecer que já passou).
///
/// [withDate] anexa a data também aos dias relativos ("Hoje · 02/08"):
/// é o modo dos cabeçalhos de seção, onde a data de hoje precisa existir
/// em algum lugar da tela. O resumo usa a forma curta.
String agendaDayLabel(
  DateTime day, {
  required DateTime now,
  bool withDate = false,
}) {
  // Datas em UTC ANTES do difference: entre meia-noites locais num fuso com
  // horário de verão o dia tem 23h e inDays daria 0 — amanhã viraria "Hoje"
  // e as seções se fundiriam. O Brasil aboliu o DST, o fuso do aparelho não.
  final today = DateTime.utc(now.year, now.month, now.day);
  final target = DateTime.utc(day.year, day.month, day.day);
  final difference = target.difference(today).inDays;

  final dayMonth =
      '${target.day.toString().padLeft(2, '0')}/'
      '${target.month.toString().padLeft(2, '0')}';

  if (difference == 0) return withDate ? 'Hoje · $dayMonth' : 'Hoje';
  if (difference == 1) return withDate ? 'Amanhã · $dayMonth' : 'Amanhã';
  if (difference == -1) return withDate ? 'Ontem · $dayMonth' : 'Ontem';

  final weekday = _weekdayLabels[target.weekday]!;
  if (target.year != today.year) {
    return '$weekday · $dayMonth/${target.year}';
  }
  return '$weekday · $dayMonth';
}

/// Resumo do topo da agenda: quantos compromissos hoje e qual é o próximo.
/// Informação no lugar de copy — a lista já vem ordenada do fetch, então o
/// próximo é o primeiro que ainda não começou.
({String title, String subtitle}) agendaSummary(
  List<Appointment> appointments, {
  required DateTime now,
  required bool isLawyer,
}) {
  final todayCount = appointments.where((appointment) {
    final startsAt = appointment.startsAt;
    // Demo (sem horário real): o dateLabel pronto decide.
    if (startsAt == null) return appointment.dateLabel == 'Hoje';
    return startsAt.year == now.year &&
        startsAt.month == now.month &&
        startsAt.day == now.day;
  }).length;

  final title = switch (todayCount) {
    0 => 'Nenhum compromisso hoje',
    1 => '1 compromisso hoje',
    _ => '$todayCount compromissos hoje',
  };

  Appointment? next;
  for (final appointment in appointments) {
    final startsAt = appointment.startsAt;
    // Demo: lista já vem em ordem, o primeiro é o próximo.
    if (startsAt == null || !startsAt.isBefore(now)) {
      next = appointment;
      break;
    }
  }

  final String subtitle;
  if (next == null) {
    subtitle = isLawyer
        ? 'Toque em Novo compromisso para agendar atendimentos e prazos.'
        : 'Quando um atendimento for agendado, ele aparecerá aqui.';
  } else {
    final startsAt = next.startsAt;
    final day = startsAt == null
        ? next.dateLabel
        : agendaDayLabel(startsAt, now: now);
    subtitle = 'Próximo: $day às ${next.timeLabel} · ${next.title}';
  }

  return (title: title, subtitle: subtitle);
}

/// Agrupa a lista (já ordenada pelo fetch) em seções por dia, preservando a
/// ordem. Compromissos de demo (sem [Appointment.startsAt]) usam o
/// [Appointment.dateLabel] pronto como rótulo.
List<AgendaSection> buildAgendaSections(
  List<Appointment> appointments, {
  required DateTime now,
}) {
  final grouped = <String, List<Appointment>>{};
  for (final appointment in appointments) {
    final startsAt = appointment.startsAt;
    final label = startsAt == null
        ? appointment.dateLabel
        : agendaDayLabel(startsAt, now: now, withDate: true);
    (grouped[label] ??= []).add(appointment);
  }

  return [
    for (final entry in grouped.entries)
      AgendaSection(label: entry.key, appointments: entry.value),
  ];
}
