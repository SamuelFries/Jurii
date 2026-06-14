import '../models/appointment.dart';
import '../services/supabase_config.dart';

class AppointmentRepository {
  const AppointmentRepository();

  Future<List<Appointment>> fetchAppointments(AppointmentRole role) async {
    final rows = await SupabaseConfig.client
        .from('appointments')
        .select()
        .eq('role', role == AppointmentRole.lawyer ? 'lawyer' : 'client')
        .order('starts_at');

    return rows.map<Appointment>(_fromRow).toList();
  }

  Appointment _fromRow(Map<String, dynamic> row) {
    final startsAt = DateTime.tryParse(row['starts_at'] as String? ?? '');

    return Appointment(
      id: row['id'] as String,
      role: row['role'] == 'lawyer'
          ? AppointmentRole.lawyer
          : AppointmentRole.client,
      title: row['title'] as String,
      counterpartName: row['counterpart_name'] as String,
      area: row['area'] as String,
      dateLabel: _dateLabel(startsAt),
      timeLabel: _timeLabel(startsAt),
      location: row['location'] as String,
      status: _statusFromRow(row['status'] as String?),
    );
  }

  AppointmentStatus _statusFromRow(String? status) {
    return switch (status) {
      'confirmed' => AppointmentStatus.confirmed,
      'done' => AppointmentStatus.done,
      _ => AppointmentStatus.pending,
    };
  }

  String _dateLabel(DateTime? value) {
    if (value == null) return 'Data pendente';

    final date = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDay = DateTime(date.year, date.month, date.day);
    final difference = itemDay.difference(today).inDays;

    if (difference == 0) return 'Hoje';
    if (difference == 1) return 'Amanhã';
    if (difference == -1) return 'Ontem';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }

  String _timeLabel(DateTime? value) {
    if (value == null) return '--:--';

    final date = value.toLocal();
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
