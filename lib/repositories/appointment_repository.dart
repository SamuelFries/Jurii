import '../models/appointment.dart';
import '../services/supabase_config.dart';

class AppointmentRepository {
  const AppointmentRepository();

  /// Teto de segurança, não paginação: 100 compromissos cobrem meses de
  /// agenda. Sem teto, a tela carregaria o histórico inteiro para sempre.
  static const int fetchLimit = 100;

  Future<List<Appointment>> fetchAppointments(
    AppointmentRole role, {
    bool past = false,
  }) async {
    // Corte no início de HOJE (fuso local): o compromisso desta manhã ainda
    // pertence à visão padrão; de ontem para trás vive em "Anteriores".
    final now = DateTime.now();
    final startOfToday = DateTime(
      now.year,
      now.month,
      now.day,
    ).toUtc().toIso8601String();

    var query = SupabaseConfig.client
        .from('appointments')
        .select()
        .eq('role', role == AppointmentRole.lawyer ? 'lawyer' : 'client')
        // Cancelados somem da agenda, mas ficam no banco (histórico + .ics).
        .neq('status', 'cancelled');

    query = past
        ? query.lt('starts_at', startOfToday)
        : query.gte('starts_at', startOfToday);

    // ascending explícito SEMPRE: no postgrest-dart o padrão de order() é
    // DESCENDENTE (ao contrário do client JS) — um order sem ascending já
    // pôs o compromisso mais distante no topo da agenda. Próximos: mais
    // cedo primeiro. Anteriores: mais recente primeiro.
    final rows = await query
        .order('starts_at', ascending: !past)
        .limit(fetchLimit);

    return rows.map<Appointment>(_fromRow).toList();
  }

  Future<String> createAppointment({
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
    String? location,
    String? area,
    String? counterpartName,
    String? caseId,
  }) async {
    _ensureReady();

    final id = await SupabaseConfig.client.rpc(
      'create_appointment',
      params: {
        'title_value': title,
        'starts_at_value': startsAt.toUtc().toIso8601String(),
        'ends_at_value': endsAt.toUtc().toIso8601String(),
        'location_value': location,
        'area_value': area,
        'counterpart_name_value': counterpartName,
        'case_id_value': caseId,
      },
    );

    return id as String;
  }

  Future<void> updateAppointment({
    required String id,
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
    String? location,
    String? area,
    String? counterpartName,
  }) async {
    _ensureReady();

    await SupabaseConfig.client.rpc(
      'update_appointment',
      params: {
        'appointment_id_value': id,
        'title_value': title,
        'starts_at_value': startsAt.toUtc().toIso8601String(),
        'ends_at_value': endsAt.toUtc().toIso8601String(),
        'location_value': location,
        'area_value': area,
        'counterpart_name_value': counterpartName,
      },
    );
  }

  Future<void> cancelAppointment(String id) async {
    _ensureReady();

    await SupabaseConfig.client.rpc(
      'cancel_appointment',
      params: {'appointment_id_value': id},
    );
  }

  void _ensureReady() {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      throw StateError('A conexão com o Supabase não está ativa.');
    }
  }

  Appointment _fromRow(Map<String, dynamic> row) {
    final startsAt = DateTime.tryParse(row['starts_at'] as String? ?? '');
    final endsAt = DateTime.tryParse(row['ends_at'] as String? ?? '');

    return Appointment(
      id: row['id'] as String,
      role: row['role'] == 'lawyer'
          ? AppointmentRole.lawyer
          : AppointmentRole.client,
      title: row['title'] as String,
      counterpartName: row['counterpart_name'] as String,
      area: row['area'] as String? ?? '',
      dateLabel: _dateLabel(startsAt),
      timeLabel: _timeLabel(startsAt),
      location: row['location'] as String,
      status: _statusFromRow(row['status'] as String?),
      startsAt: startsAt?.toLocal(),
      endsAt: endsAt?.toLocal(),
      caseId: row['case_id'] as String?,
    );
  }

  AppointmentStatus _statusFromRow(String? status) {
    return switch (status) {
      'confirmed' => AppointmentStatus.confirmed,
      'done' => AppointmentStatus.done,
      'cancelled' => AppointmentStatus.cancelled,
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
