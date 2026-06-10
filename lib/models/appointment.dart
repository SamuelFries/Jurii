enum AppointmentRole { client, lawyer }

enum AppointmentStatus { confirmed, pending, done }

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
  });
}
