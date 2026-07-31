/// O necessário para abrir a tela de detalhe de um caso quando só se tem o id
/// (toque numa notificação). Montado no repositório a partir da RPC
/// `fetch_case_for_current_user`.
///
/// `canAddUpdates` vem do SERVIDOR (`can_manage_case_updates`), e não de um
/// palpite da tela: quem chega por notificação não tem o contexto de papel que
/// as listas de casos têm.
class CaseOpenTarget {
  final String id;
  final String title;
  final String subtitle;
  final bool canAddUpdates;
  final String? cnjNumber;

  const CaseOpenTarget({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.canAddUpdates,
    this.cnjNumber,
  });
}
