import '../models/invite_link.dart';
import '../services/supabase_config.dart';

/// O convite por link, pelas MESMAS RPCs que o webapp usa em produção.
///
/// Nenhuma regra mora aqui: gestor, papel, congelamento, uso único, corrida
/// e prazo são do banco. Este arquivo só chama e traduz linhas. Se uma RPC
/// mudar de contrato, é aqui que quebra, num lugar só.
class InviteLinkRepository {
  const InviteLinkRepository();

  bool get _demo => !SupabaseConfig.isReady;

  /// Gera um link. O token volta UMA vez.
  Future<CreatedInviteLink> create({
    required String lawFirmId,
    required String memberRole,
  }) async {
    final rows = await SupabaseConfig.client.rpc(
      'criar_link_de_convite',
      params: {'law_firm_id_value': lawFirmId, 'member_role_value': memberRole},
    );
    final row = (rows as List).first as Map<String, dynamic>;
    return CreatedInviteLink(
      id: (row['id']).toString(),
      token: (row['token']).toString(),
      memberRole: (row['member_role']).toString(),
      expiresAt: DateTime.parse((row['expires_at']).toString()),
    );
  }

  /// O que a página do convite mostra antes do aceite. Roda SEM sessão
  /// (grant para anon), que é o caso de quem ainda vai criar conta.
  Future<InviteLinkPreview> peek(String token) async {
    if (_demo) {
      return const InviteLinkPreview(status: InviteLinkStatus.inexistente);
    }
    final rows = await SupabaseConfig.client.rpc(
      'espiar_link_de_convite',
      params: {'token_value': token},
    );
    final list = rows as List;
    if (list.isEmpty) {
      return const InviteLinkPreview(status: InviteLinkStatus.inexistente);
    }
    return InviteLinkPreview.fromRow(list.first as Map<String, dynamic>);
  }

  /// PEDE entrada (o link não concede: um gestor aprova). Devolve o id do
  /// pedido; erros sobem com a mensagem do banco para a tela traduzir.
  Future<String> requestEntry(String token) async {
    final result = await SupabaseConfig.client.rpc(
      'solicitar_entrada_por_link',
      params: {'token_value': token},
    );
    return (result).toString();
  }

  Future<List<OpenInviteLink>> listOpen(String lawFirmId) async {
    if (_demo) return const [];
    final rows = await SupabaseConfig.client.rpc(
      'listar_links_de_convite',
      params: {'law_firm_id_value': lawFirmId},
    );
    return (rows as List)
        .map((r) => r as Map<String, dynamic>)
        .map(
          (r) => OpenInviteLink(
            id: (r['id']).toString(),
            memberRole: (r['member_role']).toString(),
            createdAt: DateTime.parse((r['created_at']).toString()),
            expiresAt: DateTime.parse((r['expires_at']).toString()),
            createdBy: (r['criado_por'] ?? 'Alguém da equipe').toString(),
          ),
        )
        .toList();
  }

  Future<void> revoke(String linkId) {
    return SupabaseConfig.client.rpc(
      'revogar_link_de_convite',
      params: {'link_id_value': linkId},
    );
  }

  Future<List<JoinRequest>> listRequests(String lawFirmId) async {
    if (_demo) return const [];
    final rows = await SupabaseConfig.client.rpc(
      'listar_pedidos_de_entrada',
      params: {'law_firm_id_value': lawFirmId},
    );
    return (rows as List)
        .map((r) => r as Map<String, dynamic>)
        .map(
          (r) => JoinRequest(
            id: (r['id']).toString(),
            requesterName: (r['requester_name'] ?? 'Sem nome').toString(),
            requesterEmail: (r['requester_email'] ?? '').toString(),
            cpfConfirmado: r['cpf_confirmado'] == true,
            memberRole: (r['member_role']).toString(),
            createdAt: DateTime.parse((r['created_at']).toString()),
            expiresAt: DateTime.parse((r['expires_at']).toString()),
          ),
        )
        .toList();
  }

  /// Aprova ou recusa. A corrida entre dois gestores é do banco (FOR UPDATE);
  /// o segundo ouve "already decided by X" e a tela mostra.
  Future<void> decide({required String requestId, required bool approve}) {
    return SupabaseConfig.client.rpc(
      'decidir_entrada_no_escritorio',
      params: {'request_id_value': requestId, 'aprovar': approve},
    );
  }
}
