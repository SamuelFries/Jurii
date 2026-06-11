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
    return Appointment(
      id: row['id'] as String,
      role: row['role'] == 'lawyer'
          ? AppointmentRole.lawyer
          : AppointmentRole.client,
      title: row['title'] as String,
      counterpartName: row['counterpart_name'] as String,
      area: row['area'] as String,
      dateLabel: '',
      timeLabel: '',
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
}
