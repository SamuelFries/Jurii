class LawyerCase {
  final String id;
  final String title;
  final String clientName;
  final String clientInitials;
  final String area;
  final String lastUpdate;
  final LawyerCaseStatus status;

  /// Número do processo no padrão CNJ (20 dígitos, sem máscara). Nulo quando
  /// o caso ainda não virou processo judicial, o que é normal.
  final String? cnjNumber;

  /// O caso tem prazo registrado mas ainda não tem número de processo:
  /// sinal de processo em andamento sem o número informado. Indicativo
  /// neutro, nunca alerta.
  final bool needsCnjNumber;

  const LawyerCase({
    required this.id,
    required this.title,
    required this.clientName,
    required this.clientInitials,
    required this.area,
    required this.lastUpdate,
    required this.status,
    this.cnjNumber,
    this.needsCnjNumber = false,
  });
}

enum LawyerCaseStatus { updated, newMessage, deadline, closed }

/// Deriva o estado exibido: 'closed' vem do banco; a urgência de prazo vem
/// da DATA real (prazo em até 7 dias, inclusive vencido) — o status
/// 'deadline' do enum do banco nunca é escrito por ninguém.
///
/// A comparação é a MESMA do `urgent` do painel do escritório
/// (`deadline_at <= now() + 7 dias`, migration 20260801150000): inDays
/// truncaria e faria as duas superfícies divergirem perto da borda.
LawyerCaseStatus deriveLawyerCaseStatus({
  required String? status,
  required DateTime? deadlineAt,
  DateTime? now,
}) {
  if (status == 'closed') return LawyerCaseStatus.closed;
  if (status == 'new_message') return LawyerCaseStatus.newMessage;

  final reference = now ?? DateTime.now();
  if (deadlineAt != null &&
      !deadlineAt.isAfter(reference.add(const Duration(days: 7)))) {
    return LawyerCaseStatus.deadline;
  }
  return LawyerCaseStatus.updated;
}
