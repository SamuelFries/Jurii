/// Detalhe completo de um caso (RPC fetch_case_for_current_user). O servidor
/// decide o que o usuário pode fazer (can_manage) e devolve o relato do
/// cliente, o prazo e o status cru — a tela nunca deriva permissão sozinha.
class CaseDetails {
  const CaseDetails({
    required this.id,
    required this.title,
    required this.area,
    required this.status,
    required this.statusLabel,
    required this.clientName,
    required this.viewerIsClient,
    required this.canManage,
    required this.canManageLifecycle,
    this.cnjNumber,
    this.description,
    this.deadlineAt,
    this.createdAt,
    this.assignedLawyerId,
    this.lawFirmId,
  });

  final String id;
  final String title;
  final String area;

  /// Status cru do banco: open | new_message | deadline | closed.
  final String status;
  final String statusLabel;
  final String clientName;
  final bool viewerIsClient;

  /// Pode adicionar atualizações manuais (advogado responsável).
  final bool canManage;

  /// Pode encerrar/reabrir e definir prazo: advogado responsável OU gestor
  /// ativo do escritório — espelho exato do gate de escrita no servidor.
  final bool canManageLifecycle;
  final String? cnjNumber;

  /// Resumo do caso escrito pelo advogado ao propô-lo (create_case_request
  /// só aceita o advogado da conversa). Visível para os dois lados.
  final String? description;
  final DateTime? deadlineAt;
  final DateTime? createdAt;
  final String? assignedLawyerId;
  final String? lawFirmId;

  bool get isClosed => status == 'closed';
}
