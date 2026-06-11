import '../models/cases.dart';
import '../models/lawyer_case.dart';
import '../services/supabase_config.dart';

class CaseRepository {
  const CaseRepository();

  Future<List<LegalCase>> fetchClientCases() async {
    final rows = await SupabaseConfig.client
        .from('legal_cases')
        .select()
        .order('updated_at', ascending: false);

    return rows.map<LegalCase>(_clientCaseFromRow).toList();
  }

  Future<List<LawyerCase>> fetchLawyerCases() async {
    final rows = await SupabaseConfig.client
        .from('legal_cases')
        .select('*, profiles!legal_cases_client_id_fkey(full_name, initials)')
        .order('updated_at', ascending: false);

    return rows.map<LawyerCase>(_lawyerCaseFromRow).toList();
  }

  LegalCase _clientCaseFromRow(Map<String, dynamic> row) {
    return LegalCase(
      id: row['id'] as String,
      title: row['title'] as String,
      status: row['status'] as String,
    );
  }

  LawyerCase _lawyerCaseFromRow(Map<String, dynamic> row) {
    final client = row['profiles'] as Map<String, dynamic>? ?? {};

    return LawyerCase(
      id: row['id'] as String,
      title: row['title'] as String,
      clientName: client['full_name'] as String? ?? 'Cliente',
      clientInitials: client['initials'] as String? ?? 'CL',
      area: row['area'] as String,
      lastUpdate: row['last_update_label'] as String? ?? 'Atualizado hoje',
      status: _statusFromRow(row['status'] as String?),
    );
  }

  LawyerCaseStatus _statusFromRow(String? status) {
    return switch (status) {
      'new_message' => LawyerCaseStatus.newMessage,
      'deadline' => LawyerCaseStatus.deadline,
      _ => LawyerCaseStatus.updated,
    };
  }
}
