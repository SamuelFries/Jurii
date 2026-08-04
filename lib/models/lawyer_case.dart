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

  const LawyerCase({
    required this.id,
    required this.title,
    required this.clientName,
    required this.clientInitials,
    required this.area,
    required this.lastUpdate,
    required this.status,
    this.cnjNumber,
  });
}

enum LawyerCaseStatus { updated, newMessage, closed }

/// Deriva o estado exibido a partir do status cru do banco.
///
/// Havia um estado `deadline` derivado de `legal_cases.deadline_at`. O prazo
/// manual saiu na migration 20260804120000: exigia manutenção perpétua do
/// advogado (cada novo prazo de cada processo) e não dava para automatizar
/// pelo DataJud com segurança. O enum do banco ainda tem o valor 'deadline',
/// mas nenhum caminho o escreve — cai no padrão, como sempre caiu.
LawyerCaseStatus deriveLawyerCaseStatus({required String? status}) {
  if (status == 'closed') return LawyerCaseStatus.closed;
  if (status == 'new_message') return LawyerCaseStatus.newMessage;
  return LawyerCaseStatus.updated;
}
