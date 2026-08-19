/// O link de convite de equipe: como ele é montado e como é lido.
///
/// O LINK É UM SÓ, o do webapp: `https://app.jurii.com.br/convite/TOKEN`.
/// O app não inventa um segundo formato; ele só aprende a RECONHECER esse. E
/// aceita também `jurii://convite/<token>` para o caso do sistema entregar
/// pelo esquema próprio (o mesmo esquema do OAuth), sem que isso seja um
/// formato que se gera ou se divulga.
///
/// Sem App Link publicado, o Android abre a URL no navegador e o webapp
/// resolve o convite inteiro; com o App Link, a mesma URL abre o app. Nunca
/// existe estado em que o link morre porque o app não abriu.
library;

/// O host canônico do webapp. É o mesmo host que o webapp usa ao gerar o
/// link (x-forwarded-host em produção), então o que ele copia é o que o app
/// reconhece.
const String inviteLinkHost = 'app.jurii.com.br';

/// Monta o link canônico. O token é hex de 48 caracteres, e o link é a URL
/// crua: nada de encurtador, nada de query.
String buildInviteLink(String token) =>
    'https://$inviteLinkHost/convite/$token';

/// O token de um link de convite, ou nulo quando a URL não é um convite.
///
/// Aceita:
///   `https://app.jurii.com.br/convite/TOKEN`
///   `https://app.jurii.com.br/convite/TOKEN?qualquer=coisa`
///   `jurii://convite/TOKEN`
///
/// Recusa qualquer outra rota do mesmo host (login-callback, /entrar, etc.) e
/// token fora do formato (48 hex): token com forma errada não chega nem a
/// virar chamada ao servidor.
String? inviteTokenFromUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  List<String> segments;
  if (scheme == 'https' || scheme == 'http') {
    if (uri.host.toLowerCase() != inviteLinkHost) return null;
    segments = uri.pathSegments;
  } else if (scheme == 'jurii') {
    // jurii://convite/<token>: o host é "convite" e o path é o token.
    if (uri.host.toLowerCase() != 'convite') return null;
    segments = ['convite', ...uri.pathSegments];
  } else {
    return null;
  }
  if (segments.length < 2 || segments[0] != 'convite') return null;
  final token = segments[1];
  return _tokenValido.hasMatch(token) ? token : null;
}

final RegExp _tokenValido = RegExp(r'^[0-9a-f]{48}$');

/// Traduz o erro que o banco levanta nos RPCs do convite por link para a
/// frase que a pessoa lê. Cada `raise exception` das migrations
/// `convite_por_link` e `o_link_pede_em_vez_de_conceder` tem a sua; o resto
/// cai numa frase genérica que não inventa causa.
String traduzErroDoConvite(Object error) {
  final message = error.toString();
  if (message.contains('User must be authenticated')) {
    return 'Entre na sua conta para continuar.';
  }
  if (message.contains('Only active office owners and admins')) {
    return 'Apenas sócios e admins ativos podem fazer isso.';
  }
  if (message.contains('Invite links are for secretary or intern roles')) {
    return 'O convite por link é só para secretária ou estagiário. '
        'Advogados entram pela OAB.';
  }
  if (message.contains('Subscription is not active')) {
    return 'A assinatura do escritório está pendente. Enquanto isso, '
        'ninguém novo entra na equipe.';
  }
  if (message.contains('Too many invite attempts')) {
    return 'Muitos convites em pouco tempo. Aguarde antes de gerar outro.';
  }
  if (message.contains('Invite link not found')) {
    return 'Convite não encontrado. Confira o link ou peça um novo.';
  }
  if (message.contains('Invite link was revoked')) {
    return 'Este convite foi cancelado pelo escritório.';
  }
  if (message.contains('Invite link already used')) {
    return 'Este convite já foi utilizado.';
  }
  if (message.contains('Invite link expired')) {
    return 'Este convite venceu. Peça um novo link a quem convidou.';
  }
  if (message.contains('Already a member of this firm')) {
    return 'Você já faz parte deste escritório.';
  }
  if (message.contains('Join request not found')) {
    return 'Pedido não encontrado.';
  }
  if (message.contains('Join request already decided by')) {
    return 'Este pedido já foi decidido por outra pessoa da equipe.';
  }
  if (message.contains('Join request expired')) {
    return 'Este pedido venceu sem resposta. A pessoa precisa de um novo '
        'convite.';
  }
  return 'Não foi possível concluir agora. Tente novamente.';
}
