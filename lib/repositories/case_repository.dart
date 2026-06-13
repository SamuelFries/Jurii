import '../models/cases.dart';
import '../models/firm_case_overview.dart';
import '../models/lawyer_case.dart';
import '../services/supabase_config.dart';

class CaseRepository {
  const CaseRepository();

  Future<List<LegalCase>> fetchClientCases() async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return const [];
    }

    final rows = await SupabaseConfig.client.rpc('fetch_client_cases');

    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map<LegalCase>(_clientCaseFromRow)
        .toList();
  }

  Future<List<LawyerCase>> fetchLawyerCases() async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return const [];
    }

    final rows = await SupabaseConfig.client.rpc('fetch_lawyer_cases');

    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map<LawyerCase>(_lawyerCaseFromRow)
        .toList();
  }

  Future<List<FirmCaseOverview>> fetchLawFirmCases(String lawFirmId) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return const [];
    }

    final rows = await SupabaseConfig.client.rpc(
      'fetch_law_firm_cases',
      params: {'law_firm_id_value': lawFirmId},
    );

    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map<FirmCaseOverview>(_firmCaseFromRow)
        .toList();
  }

  LegalCase _clientCaseFromRow(Map<String, dynamic> row) {
    return LegalCase(
      id: row['id'].toString(),
      title: row['title'] as String? ?? 'Caso jurídico',
      area: row['area'] as String? ?? 'Atendimento jurídico',
      status: row['status_label'] as String? ?? 'Em andamento',
      lastUpdate: row['last_update_label'] as String? ?? 'Atualizado hoje',
    );
  }

  LawyerCase _lawyerCaseFromRow(Map<String, dynamic> row) {
    return LawyerCase(
      id: row['id'].toString(),
      title: row['title'] as String? ?? 'Caso jurídico',
      clientName: row['client_name'] as String? ?? 'Cliente',
      clientInitials: row['client_initials'] as String? ?? 'CL',
      area: row['area'] as String? ?? 'Atendimento jurídico',
      lastUpdate: row['last_update_label'] as String? ?? 'Atualizado hoje',
      status: _statusFromRow(row['status'] as String?),
    );
  }

  FirmCaseOverview _firmCaseFromRow(Map<String, dynamic> row) {
    return FirmCaseOverview(
      id: row['id'].toString(),
      title: row['title'] as String? ?? 'Caso jurídico',
      clientName: row['client_name'] as String? ?? 'Cliente',
      clientInitials: row['client_initials'] as String? ?? 'CL',
      assignedLawyer:
          row['assigned_lawyer'] as String? ?? 'Sem advogado definido',
      area: row['area'] as String? ?? 'Atendimento jurídico',
      statusLabel: row['status_label'] as String? ?? 'Em andamento',
      nextStep: row['next_step'] as String? ?? 'Atualizado hoje',
      urgent: row['urgent'] as bool? ?? false,
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
