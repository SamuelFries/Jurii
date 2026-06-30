import '../data/mock/mock_cases.dart';
import '../data/mock/mock_firm_workspace.dart';
import '../models/case_request.dart';
import '../models/case_update.dart';
import '../models/cases.dart';
import '../models/firm_case_overview.dart';
import '../models/lawyer_case.dart';
import '../services/supabase_config.dart';

class CaseRepository {
  const CaseRepository();

  Future<List<LegalCase>> fetchClientCases() async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return mockClientCases;
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
      return mockLawyerCases;
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
      return mockFirmCases;
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

  Future<void> assignLawFirmCase({
    required String lawFirmId,
    required String caseId,
    required String lawyerProfileId,
  }) async {
    if (!SupabaseConfig.isReady) return;

    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      throw StateError('A conexÃ£o com o Supabase nÃ£o estÃ¡ ativa.');
    }

    await SupabaseConfig.client.rpc(
      'assign_law_firm_case',
      params: {
        'law_firm_id_value': lawFirmId,
        'case_id_value': caseId,
        'lawyer_profile_id_value': lawyerProfileId,
      },
    );
  }

  Future<void> createCaseRequest({
    required String conversationId,
    required String title,
    required String area,
    required String summary,
  }) async {
    if (!SupabaseConfig.isReady) return;

    await SupabaseConfig.client.rpc(
      'create_case_request',
      params: {
        'conversation_id_value': conversationId,
        'title_value': title,
        'area_value': area,
        'summary_value': summary,
      },
    );
  }

  Future<List<CaseRequest>> fetchClientCaseRequests() async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return mockClientCaseRequests;
    }

    final rows = await SupabaseConfig.client.rpc(
      'fetch_case_requests_for_client',
    );

    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map<CaseRequest>(_caseRequestFromRow)
        .toList();
  }

  Future<void> respondToCaseRequest({
    required String requestId,
    required bool accepted,
  }) async {
    if (!SupabaseConfig.isReady) return;

    await SupabaseConfig.client.rpc(
      'respond_to_case_request',
      params: {'request_id_value': requestId, 'accepted_value': accepted},
    );
  }

  Future<List<CaseUpdate>> fetchCaseUpdates(String caseId) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return mockCaseUpdates;
    }

    final rows = await SupabaseConfig.client.rpc(
      'fetch_case_updates',
      params: {'case_id_value': caseId},
    );

    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map<CaseUpdate>(_caseUpdateFromRow)
        .toList();
  }

  Future<void> addCaseUpdate({
    required String caseId,
    required String title,
    required String body,
  }) async {
    if (!SupabaseConfig.isReady) return;

    await SupabaseConfig.client.rpc(
      'add_case_update',
      params: {
        'case_id_value': caseId,
        'title_value': title,
        'body_value': body,
      },
    );
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
      assignedLawyerId: row['assigned_lawyer_id']?.toString(),
      assignedLawyer:
          row['assigned_lawyer'] as String? ?? 'Sem advogado definido',
      area: row['area'] as String? ?? 'Atendimento jurídico',
      statusLabel: row['status_label'] as String? ?? 'Em andamento',
      nextStep: row['next_step'] as String? ?? 'Atualizado hoje',
      urgent: row['urgent'] as bool? ?? false,
    );
  }

  CaseRequest _caseRequestFromRow(Map<String, dynamic> row) {
    return CaseRequest(
      id: row['id'].toString(),
      conversationId: row['conversation_id'].toString(),
      title: row['title'] as String? ?? 'Solicitação de caso',
      area: row['area'] as String? ?? 'Atendimento jurídico',
      summary: row['summary'] as String? ?? '',
      requestedBy: row['requested_by'] as String? ?? 'Jurii',
      requesterInitials: row['requester_initials'] as String? ?? 'JR',
      createdAtLabel: _relativeTime(row['created_at'] as String?),
    );
  }

  CaseUpdate _caseUpdateFromRow(Map<String, dynamic> row) {
    return CaseUpdate(
      id: row['id'].toString(),
      caseId: row['case_id'].toString(),
      title: row['title'] as String? ?? 'Atualização',
      body: row['body'] as String? ?? '',
      authorName: row['author_name'] as String? ?? 'Jurii',
      authorInitials: row['author_initials'] as String? ?? 'JR',
      createdAtLabel: _relativeTime(row['created_at'] as String?),
    );
  }

  LawyerCaseStatus _statusFromRow(String? status) {
    return switch (status) {
      'new_message' => LawyerCaseStatus.newMessage,
      'deadline' => LawyerCaseStatus.deadline,
      _ => LawyerCaseStatus.updated,
    };
  }

  String _relativeTime(String? value) {
    final date = DateTime.tryParse(value ?? '')?.toLocal();
    if (date == null) return '';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDay = DateTime(date.year, date.month, date.day);
    final difference = today.difference(itemDay).inDays;

    if (difference == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    if (difference == 1) return 'Ontem';
    if (difference < 7) return '${difference}d';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }
}
