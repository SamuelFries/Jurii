/// O que o convite de equipe é, visto do app.
///
/// Espelha o vocabulário do banco e do webapp, sem tradução própria: a
/// `situacao` que `espiar_link_de_convite` devolve vira um enum aqui, e a
/// tela veste. Se o banco ganhar um estado novo, ele cai em [desconhecida] e
/// a tela diz que não entendeu, em vez de fingir um estado que não é.
enum InviteLinkStatus {
  /// Link vivo: dá para pedir entrada.
  valido,
  inexistente,
  expirado,
  revogado,

  /// Outra pessoa consumiu.
  usado,

  /// Eu pedi e um gestor ainda não decidiu.
  meuPedidoPendente,
  meuPedidoAprovado,
  meuPedidoRecusado,
  meuPedidoExpirado,
  desconhecida;

  static InviteLinkStatus fromServer(String situacao) {
    switch (situacao) {
      case 'valido':
        return InviteLinkStatus.valido;
      case 'inexistente':
        return InviteLinkStatus.inexistente;
      case 'expirado':
        return InviteLinkStatus.expirado;
      case 'revogado':
        return InviteLinkStatus.revogado;
      case 'usado':
        return InviteLinkStatus.usado;
      case 'meu_pedido_pendente':
        return InviteLinkStatus.meuPedidoPendente;
      case 'meu_pedido_aprovado':
        return InviteLinkStatus.meuPedidoAprovado;
      case 'meu_pedido_recusado':
        return InviteLinkStatus.meuPedidoRecusado;
      case 'meu_pedido_expirado':
        return InviteLinkStatus.meuPedidoExpirado;
      default:
        return InviteLinkStatus.desconhecida;
    }
  }

  bool get ehMeuPedido =>
      this == meuPedidoPendente ||
      this == meuPedidoAprovado ||
      this == meuPedidoRecusado ||
      this == meuPedidoExpirado;
}

/// O convite espiado: o que a tela mostra ANTES de qualquer ação.
class InviteLinkPreview {
  const InviteLinkPreview({
    required this.status,
    this.firmName,
    this.firmInitials,
    this.memberRole,
  });

  final InviteLinkStatus status;
  final String? firmName;
  final String? firmInitials;

  /// 'secretary' | 'intern', a chave do banco. O rótulo é da tela.
  final String? memberRole;

  static InviteLinkPreview fromRow(Map<String, dynamic> row) {
    return InviteLinkPreview(
      status: InviteLinkStatus.fromServer((row['situacao'] ?? '').toString()),
      firmName: row['firm_name'] as String?,
      firmInitials: row['firm_initials'] as String?,
      memberRole: row['member_role'] as String?,
    );
  }
}

/// Um link gerado agora: o token só existe neste objeto, uma vez.
class CreatedInviteLink {
  const CreatedInviteLink({
    required this.id,
    required this.token,
    required this.memberRole,
    required this.expiresAt,
  });

  final String id;
  final String token;
  final String memberRole;
  final DateTime expiresAt;
}

/// Um link em aberto (sem token: ele não existe mais, só o hash).
class OpenInviteLink {
  const OpenInviteLink({
    required this.id,
    required this.memberRole,
    required this.createdAt,
    required this.expiresAt,
    required this.createdBy,
  });

  final String id;
  final String memberRole;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String createdBy;
}

/// Um pedido de entrada esperando decisão do gestor.
class JoinRequest {
  const JoinRequest({
    required this.id,
    required this.requesterName,
    required this.requesterEmail,
    required this.cpfConfirmado,
    required this.memberRole,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String requesterName;
  final String requesterEmail;

  /// O dado que faz o gestor RECONHECER a pessoa antes de aprovar.
  final bool cpfConfirmado;
  final String memberRole;
  final DateTime createdAt;
  final DateTime expiresAt;
}

/// Rótulo em português do papel que o link concede. Só os dois que o banco
/// aceita por link; qualquer outro é erro de dado, não de tela.
String rotuloDoPapelDoConvite(String? memberRole) {
  switch (memberRole) {
    case 'secretary':
      return 'Secretária';
    case 'intern':
      return 'Estagiário';
    default:
      return 'Membro da equipe';
  }
}
