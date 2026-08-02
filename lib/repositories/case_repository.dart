import '../models/case_details.dart';
import '../models/case_movement.dart';
import '../models/case_open_target.dart';
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
      return const [];
    }

    final rows = await SupabaseConfig.client.rpc('fetch_client_cases');

    final cases = (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map<LegalCase>(_clientCaseFromRow)
        .toList();
    // Encerrados no fim: a lista de trabalho vem primeiro (sort estável do
    // servidor por updated_at é preservado dentro de cada grupo).
    return [
      ...cases.where((item) => !item.isClosed),
      ...cases.where((item) => item.isClosed),
    ];
  }

  Future<List<LawyerCase>> fetchLawyerCases() async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return const [];
    }

    final rows = await SupabaseConfig.client.rpc('fetch_lawyer_cases');

    final cases = (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map<LawyerCase>(_lawyerCaseFromRow)
        .toList();
    return [
      ...cases.where((item) => item.status != LawyerCaseStatus.closed),
      ...cases.where((item) => item.status == LawyerCaseStatus.closed),
    ];
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

    final cases = (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map<FirmCaseOverview>(_firmCaseFromRow)
        .toList();
    return [
      ...cases.where((item) => !item.isClosed),
      ...cases.where((item) => item.isClosed),
    ];
  }

  Future<void> assignLawFirmCase({
    required String lawFirmId,
    required String caseId,
    required String lawyerProfileId,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      throw StateError('A conexão com o Supabase não está ativa.');
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
      return const [];
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
    await SupabaseConfig.client.rpc(
      'respond_to_case_request',
      params: {'request_id_value': requestId, 'accepted_value': accepted},
    );
  }

  Future<List<CaseUpdate>> fetchCaseUpdates(String caseId) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return const [];
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
    await SupabaseConfig.client.rpc(
      'add_case_update',
      params: {
        'case_id_value': caseId,
        'title_value': title,
        'body_value': body,
      },
    );
  }

  /// Abre um caso a partir só do id (destino do toque na notificação).
  /// Devolve nulo quando o caso não existe ou o usuário não participa dele.
  Future<CaseOpenTarget?> fetchCaseById(String caseId) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return null;
    }

    final rows = await SupabaseConfig.client.rpc(
      'fetch_case_for_current_user',
      params: {'case_id_value': caseId},
    );

    final list = (rows as List<dynamic>).cast<Map<String, dynamic>>();
    if (list.isEmpty) return null;

    final row = list.first;
    final title = row['title'] as String? ?? 'Caso jurídico';
    final area = row['area'] as String? ?? 'Atendimento jurídico';
    final statusLabel = row['status_label'] as String? ?? 'Em andamento';
    final clientName = row['client_name'] as String? ?? 'Cliente';
    final viewerIsClient = row['viewer_is_client'] as bool? ?? false;

    return CaseOpenTarget(
      id: row['id'].toString(),
      title: title,
      // Mesmo subtítulo que as listas montam para cada papel.
      subtitle: viewerIsClient ? '$area · $statusLabel' : '$clientName · $area',
      canAddUpdates: row['can_manage'] as bool? ?? false,
      cnjNumber: row['cnj_number'] as String?,
    );
  }

  /// Timeline do andamento processual (DataJud), já traduzida pelo banco.
  Future<List<CaseMovement>> fetchCaseMovements(String caseId) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return const [];
    }

    final rows = await SupabaseConfig.client.rpc(
      'fetch_case_movements',
      params: {'case_id_value': caseId},
    );

    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map<CaseMovement>(_caseMovementFromRow)
        .toList();
  }

  /// Grava o número CNJ do processo (só advogado/escritório do caso; o banco
  /// valida papel e dígito verificador). Passar nulo limpa o número.
  Future<void> setCaseCnjNumber({
    required String caseId,
    required String? cnjNumber,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      throw StateError('A conexão com o Supabase não está ativa.');
    }

    await SupabaseConfig.client.rpc(
      'set_case_cnj_number',
      params: {'case_id_value': caseId, 'cnj_value': cnjNumber},
    );
  }

  /// Detalhe completo do caso; nulo quando não existe ou o usuário não
  /// participa (mesma RPC do destino de notificação, colunas a mais).
  Future<CaseDetails?> fetchCaseDetails(String caseId) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return null;
    }

    final rows = await SupabaseConfig.client.rpc(
      'fetch_case_for_current_user',
      params: {'case_id_value': caseId},
    );

    final list = (rows as List<dynamic>).cast<Map<String, dynamic>>();
    if (list.isEmpty) return null;

    final row = list.first;
    return CaseDetails(
      id: row['id'].toString(),
      title: row['title'] as String? ?? 'Caso jurídico',
      area: row['area'] as String? ?? 'Atendimento jurídico',
      status: row['status'] as String? ?? 'open',
      statusLabel: row['status_label'] as String? ?? 'Em andamento',
      clientName: row['client_name'] as String? ?? 'Cliente',
      viewerIsClient: row['viewer_is_client'] as bool? ?? false,
      canManage: row['can_manage'] as bool? ?? false,
      canManageLifecycle: row['can_manage_lifecycle'] as bool? ?? false,
      cnjNumber: row['cnj_number'] as String?,
      description: (row['description'] as String?)?.trim().isEmpty ?? true
          ? null
          : (row['description'] as String).trim(),
      deadlineAt: _parseDate(row['deadline_at'] as String?),
      createdAt: _parseDate(row['created_at'] as String?),
      assignedLawyerId: row['assigned_lawyer_id']?.toString(),
      lawFirmId: row['law_firm_id']?.toString(),
    );
  }

  Future<void> closeCase(String caseId) async {
    await SupabaseConfig.client.rpc(
      'close_legal_case',
      params: {'case_id_value': caseId},
    );
  }

  Future<void> reopenCase(String caseId) async {
    await SupabaseConfig.client.rpc(
      'reopen_legal_case',
      params: {'case_id_value': caseId},
    );
  }

  /// Grava (ou limpa, com nulo) o prazo do caso. O banco valida o papel.
  Future<void> setCaseDeadline({
    required String caseId,
    required DateTime? deadline,
  }) async {
    await SupabaseConfig.client.rpc(
      'set_case_deadline',
      params: {
        'case_id_value': caseId,
        'deadline_value': deadline?.toUtc().toIso8601String(),
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
      cnjNumber: row['cnj_number'] as String?,
      isClosed: (row['status'] as String?) == 'closed',
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
      status: deriveLawyerCaseStatus(
        status: row['status'] as String?,
        deadlineAt: _parseDate(row['deadline_at'] as String?),
      ),
      cnjNumber: row['cnj_number'] as String?,
      needsCnjNumber: row['needs_cnj_number'] as bool? ?? false,
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
      cnjNumber: row['cnj_number'] as String?,
      needsCnjNumber: row['needs_cnj_number'] as bool? ?? false,
      isClosed: (row['status'] as String?) == 'closed',
    );
  }

  CaseMovement _caseMovementFromRow(Map<String, dynamic> row) {
    return CaseMovement(
      id: row['id'].toString(),
      title: row['title'] as String? ?? 'Movimentação',
      body: row['body'] as String? ?? '',
      dateLabel: _movementDate(row['occurred_at'] as String?),
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

  DateTime? _parseDate(String? value) {
    return DateTime.tryParse(value ?? '')?.toLocal();
  }

  /// Data completa (dd/MM/aaaa): movimentos processuais podem ter anos, o
  /// formato relativo de [_relativeTime] esconderia o ano.
  String _movementDate(String? value) {
    final date = DateTime.tryParse(value ?? '')?.toLocal();
    if (date == null) return '';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
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
