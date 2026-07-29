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

enum LawyerCaseStatus { updated, newMessage, deadline }
