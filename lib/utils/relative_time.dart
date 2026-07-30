/// Rótulo curto de "quando isso aconteceu", no tom do app (pt-BR, sem
/// dependência de intl). Usado nas notificações; a régua é a do leitor
/// olhando a lista: minutos são precisos, o resto vira data.
String formatRelativeTime(DateTime value, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final moment = value.toLocal();
  final difference = reference.difference(moment);

  if (difference.isNegative || difference.inMinutes < 1) return 'agora';
  if (difference.inMinutes < 60) return 'há ${difference.inMinutes} min';
  if (difference.inHours < 24) return 'há ${difference.inHours} h';

  final today = DateTime(reference.year, reference.month, reference.day);
  final day = DateTime(moment.year, moment.month, moment.day);
  final daysApart = today.difference(day).inDays;

  if (daysApart == 1) return 'ontem';
  if (daysApart < 7) return 'há $daysApart dias';

  final dayLabel = moment.day.toString().padLeft(2, '0');
  final monthLabel = moment.month.toString().padLeft(2, '0');
  if (moment.year == reference.year) return '$dayLabel/$monthLabel';
  return '$dayLabel/$monthLabel/${moment.year}';
}
