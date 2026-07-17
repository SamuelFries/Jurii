enum AppointmentRole { client, lawyer }

enum AppointmentStatus { confirmed, pending, done, cancelled }

class Appointment {
  final String id;
  final AppointmentRole role;
  final String title;
  final String counterpartName;
  final String area;
  final String dateLabel;
  final String timeLabel;
  final String location;
  final AppointmentStatus status;

  /// Valores reais do compromisso. Só vêm preenchidos quando a linha veio do
  /// Supabase — o modo demo (mocks const) usa apenas os labels acima, então
  /// aqui ficam nulos e a edição não é oferecida.
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? caseId;

  const Appointment({
    required this.id,
    required this.role,
    required this.title,
    required this.counterpartName,
    required this.area,
    required this.dateLabel,
    required this.timeLabel,
    required this.location,
    required this.status,
    this.startsAt,
    this.endsAt,
    this.caseId,
  });

  /// Editável só quando temos os horários reais (compromisso do backend).
  bool get isEditable => startsAt != null && endsAt != null;
}
