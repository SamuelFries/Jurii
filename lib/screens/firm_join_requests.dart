import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/invite_link.dart';
import '../repositories/invite_link_repository.dart';
import '../theme/app_colors.dart';
import '../utils/invite_link.dart';
import '../widgets/jurii_form_motion.dart';

/// A parte da Equipe que trata de QUEM ESTÁ PEDINDO PARA ENTRAR e dos links
/// abertos: pedidos pendentes com Aprovar/Recusar e links vivos com Cancelar.
///
/// Mora num widget só para servir dois lugares sem duplicar: inline na aba
/// Equipe e como tela inteira ([JoinRequestsScreen]) quando o roteador de
/// notificações abre um pedido de entrada.
///
/// SÓ APARECE QUANDO HÁ O QUE MOSTRAR (a não ser em tela cheia): a maioria
/// dos dias não tem pedido nenhum, e um bloco vazio "sem pedidos" só roubaria
/// espaço da lista de membros.
class FirmJoinRequestsSection extends StatefulWidget {
  const FirmJoinRequestsSection({
    super.key,
    required this.lawFirmId,
    this.repository = const InviteLinkRepository(),
    this.versao = 0,
    this.onMembroEntrou,
    this.telaCheia = false,
  });

  final String lawFirmId;
  final InviteLinkRepository repository;

  /// Muda quando a Equipe fez algo que altera a lista (gerou link). O widget
  /// recarrega em `didUpdateWidget` sem precisar de um canal próprio.
  final int versao;

  /// Aprovar coloca alguém na equipe: quem hospeda recarrega o workspace.
  final VoidCallback? onMembroEntrou;

  /// Em tela cheia o vazio se explica em vez de sumir.
  final bool telaCheia;

  @override
  State<FirmJoinRequestsSection> createState() =>
      _FirmJoinRequestsSectionState();
}

class _FirmJoinRequestsSectionState extends State<FirmJoinRequestsSection> {
  List<JoinRequest> _pedidos = const [];
  List<OpenInviteLink> _links = const [];
  bool _carregando = true;
  bool _falhou = false;
  final Set<String> _decidindo = <String>{};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void didUpdateWidget(covariant FirmJoinRequestsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.versao != widget.versao ||
        oldWidget.lawFirmId != widget.lawFirmId) {
      _carregar();
    }
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _falhou = false;
    });
    try {
      final resultados = await Future.wait([
        widget.repository.listRequests(widget.lawFirmId),
        widget.repository.listOpen(widget.lawFirmId),
      ]);
      if (!mounted) return;
      setState(() {
        _pedidos = resultados[0] as List<JoinRequest>;
        _links = resultados[1] as List<OpenInviteLink>;
        _carregando = false;
      });
    } catch (error) {
      debugPrint('FirmJoinRequestsSection load failed: $error');
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _falhou = true;
      });
    }
  }

  Future<void> _decidir(JoinRequest pedido, {required bool aprovar}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _decidindo.add(pedido.id));
    try {
      await widget.repository.decide(requestId: pedido.id, approve: aprovar);
      if (!mounted) return;
      setState(() {
        _pedidos = _pedidos.where((p) => p.id != pedido.id).toList();
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            aprovar
                ? '${pedido.requesterName} entrou na equipe como '
                      '${rotuloDoPapelDoConvite(pedido.memberRole).toLowerCase()}.'
                : 'Pedido de ${pedido.requesterName} recusado.',
          ),
        ),
      );
      if (aprovar) widget.onMembroEntrou?.call();
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(traduzErroDoConvite(error))),
      );
      // A lista pode ter mudado por baixo (outra pessoa decidiu): recarrega
      // para a tela parar de oferecer um botão que o servidor recusa.
      await _carregar();
    } finally {
      if (mounted) setState(() => _decidindo.remove(pedido.id));
    }
  }

  Future<void> _cancelarLink(OpenInviteLink link) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.revoke(link.id);
      if (!mounted) return;
      setState(() => _links = _links.where((l) => l.id != link.id).toList());
      messenger.showSnackBar(
        const SnackBar(content: Text('Link cancelado. Ele não abre mais.')),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(traduzErroDoConvite(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    if (_carregando && !widget.telaCheia) return const SizedBox.shrink();
    if (_carregando) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_falhou) {
      return _Bloco(
        titulo: 'Pedidos de entrada',
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Não foi possível carregar os pedidos.',
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
            TextButton(onPressed: _carregar, child: const Text('Tentar')),
          ],
        ),
      );
    }
    if (_pedidos.isEmpty && _links.isEmpty) {
      if (!widget.telaCheia) return const SizedBox.shrink();
      return _Bloco(
        titulo: 'Pedidos de entrada',
        child: Text(
          'Nenhum pedido pendente. Quando alguém abrir um link de convite e '
          'pedir para entrar, aparece aqui.',
          style: TextStyle(color: colors.textSecondary, height: 1.4),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_pedidos.isNotEmpty)
          _Bloco(
            titulo: 'Pedidos de entrada',
            child: Column(
              children: [
                for (var i = 0; i < _pedidos.length; i++) ...[
                  _PedidoTile(
                    pedido: _pedidos[i],
                    ocupado: _decidindo.contains(_pedidos[i].id),
                    onAprovar: () => _decidir(_pedidos[i], aprovar: true),
                    onRecusar: () => _decidir(_pedidos[i], aprovar: false),
                  ),
                  if (i < _pedidos.length - 1)
                    Divider(height: 20, color: colors.divider),
                ],
              ],
            ),
          ),
        if (_links.isNotEmpty)
          _Bloco(
            titulo: 'Links de convite abertos',
            child: Column(
              children: [
                for (var i = 0; i < _links.length; i++) ...[
                  _LinkTile(
                    link: _links[i],
                    onCancelar: () => _cancelarLink(_links[i]),
                  ),
                  if (i < _links.length - 1)
                    Divider(height: 16, color: colors.divider),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _Bloco extends StatelessWidget {
  const _Bloco({required this.titulo, required this.child});
  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.officePurpleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _PedidoTile extends StatelessWidget {
  const _PedidoTile({
    required this.pedido,
    required this.ocupado,
    required this.onAprovar,
    required this.onRecusar,
  });

  final JoinRequest pedido;
  final bool ocupado;
  final VoidCallback onAprovar;
  final VoidCallback onRecusar;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          pedido.requesterName,
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${rotuloDoPapelDoConvite(pedido.memberRole)}'
          '${pedido.requesterEmail.isEmpty ? '' : ' · ${pedido.requesterEmail}'}',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 4),
        // O CPF confirmado é o que separa uma conta real de um cadastro
        // vazio; o gestor precisa ver isso ANTES de aprovar. O número em si
        // não vem (nem precisa): só o fato.
        Row(
          children: [
            Icon(
              pedido.cpfConfirmado ? Icons.verified_user : Icons.help_outline,
              size: 14,
              color: pedido.cpfConfirmado ? colors.success : colors.warning,
            ),
            const SizedBox(width: 4),
            Text(
              pedido.cpfConfirmado ? 'CPF confirmado' : 'CPF não informado',
              style: TextStyle(
                color: pedido.cpfConfirmado ? colors.success : colors.warning,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: ocupado ? null : onRecusar,
                child: const Text('Recusar'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: JuriiLoadingButton(
                label: 'Aprovar',
                isLoading: ocupado,
                onPressed: onAprovar,
                height: 44,
                backgroundColor: colors.officePurple,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.link, required this.onCancelar});
  final OpenInviteLink link;
  final VoidCallback onCancelar;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final horasRestantes = link.expiresAt.difference(DateTime.now()).inHours;
    final vence = horasRestantes >= 48
        ? 'vence em ${(horasRestantes / 24).floor()} dias'
        : horasRestantes >= 1
        ? 'vence em $horasRestantes h'
        : 'vence em menos de 1 h';
    return Row(
      children: [
        Icon(Icons.link, size: 18, color: colors.officePurple),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Convite para ${rotuloDoPapelDoConvite(link.memberRole).toLowerCase()}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              Text(
                // O token nunca volta do servidor: o link só é visto na hora
                // em que nasce. Aqui é só o estado.
                'Ainda não usado, $vence',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        TextButton(onPressed: onCancelar, child: const Text('Cancelar')),
      ],
    );
  }
}

/// Tela inteira dos pedidos: é para onde a notificação "Pedido para entrar
/// na equipe" leva. Mesma seção, com o vazio explicado.
class JoinRequestsScreen extends StatelessWidget {
  const JoinRequestsScreen({
    super.key,
    required this.lawFirmId,
    this.repository = const InviteLinkRepository(),
  });

  final String lawFirmId;
  final InviteLinkRepository repository;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('Pedidos de entrada')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FirmJoinRequestsSection(
            lawFirmId: lawFirmId,
            repository: repository,
            telaCheia: true,
          ),
        ],
      ),
    );
  }
}

/// A folha de GERAR o link para secretária ou estagiário.
///
/// Dois momentos: escolher o papel e gerar; depois o link, que só existe
/// AQUI (o servidor guarda o hash, não o token). Por isso o segundo momento
/// insiste em Copiar/Compartilhar antes de fechar: fechou sem copiar, o link
/// se perdeu e é preciso gerar outro (o antigo fica aberto na lista, para
/// cancelar).
class InviteByLinkSheet extends StatefulWidget {
  const InviteByLinkSheet({
    super.key,
    required this.lawFirmId,
    this.repository = const InviteLinkRepository(),
    this.firmName,
  });

  final String lawFirmId;
  final InviteLinkRepository repository;
  final String? firmName;

  @override
  State<InviteByLinkSheet> createState() => _InviteByLinkSheetState();
}

class _InviteByLinkSheetState extends State<InviteByLinkSheet> {
  String _papel = 'secretary';
  bool _gerando = false;
  String? _erro;
  CreatedInviteLink? _criado;
  bool _copiado = false;

  Future<void> _gerar() async {
    setState(() {
      _gerando = true;
      _erro = null;
    });
    try {
      final criado = await widget.repository.create(
        lawFirmId: widget.lawFirmId,
        memberRole: _papel,
      );
      if (!mounted) return;
      setState(() {
        _criado = criado;
        _gerando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _erro = traduzErroDoConvite(error);
        _gerando = false;
      });
    }
  }

  String get _link => buildInviteLink(_criado!.token);

  String get _textoParaCompartilhar {
    final banca = widget.firmName;
    final papel = rotuloDoPapelDoConvite(_criado!.memberRole).toLowerCase();
    return 'Convite para entrar como $papel'
        '${banca == null || banca.isEmpty ? '' : ' em $banca'} na Jurii. '
        'O link é de uso único e vale por 7 dias:\n$_link';
  }

  Future<void> _copiar() async {
    await Clipboard.setData(ClipboardData(text: _link));
    if (!mounted) return;
    setState(() => _copiado = true);
  }

  Future<void> _compartilhar() async {
    // A folha nativa: WhatsApp, e-mail, o que a pessoa usar. Sem plugin não
    // há como abrir a folha do sistema; share_plus é o caminho oficial.
    // O iPad exige a origem (a folha é um popover ancorado no botão); sem
    // ela o share estoura lá. Aqui é sempre passada.
    final box = context.findRenderObject() as RenderBox?;
    final origem = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    await SharePlus.instance.share(
      ShareParams(text: _textoParaCompartilhar, sharePositionOrigin: origem),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return JuriiModalSheetScaffold(
      child: _criado == null ? _passoPapel(colors) : _passoLink(colors),
    );
  }

  Widget _passoPapel(AppColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Convidar por link',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Para secretária ou estagiário, que entram sem OAB. A pessoa abre '
          'o link, pede para entrar, e você aprova aqui na Equipe.',
          style: TextStyle(
            color: colors.textSecondary,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        _OpcaoDePapel(
          valor: 'secretary',
          selecionado: _papel,
          titulo: 'Secretária',
          descricao: 'Atende clientes e organiza a operação.',
          onChanged: _gerando ? null : (v) => setState(() => _papel = v),
        ),
        const SizedBox(height: 8),
        _OpcaoDePapel(
          valor: 'intern',
          selecionado: _papel,
          titulo: 'Estagiário',
          descricao: 'Apoia os advogados nos casos.',
          onChanged: _gerando ? null : (v) => setState(() => _papel = v),
        ),
        JuriiFormErrorBanner(message: _erro),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _gerando ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: JuriiLoadingButton(
                label: 'Gerar link',
                isLoading: _gerando,
                onPressed: _gerar,
                height: 52,
                backgroundColor: colors.officePurple,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _passoLink(AppColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Link pronto',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Uso único, vale por 7 dias. Ele só aparece agora: copie ou '
          'compartilhe antes de fechar.',
          style: TextStyle(
            color: colors.textSecondary,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.officePurpleSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.officePurpleBorder),
          ),
          child: SelectableText(
            _link,
            key: const Key('link-de-convite'),
            style: TextStyle(
              color: colors.officePurpleText,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Papel: ${rotuloDoPapelDoConvite(_criado!.memberRole)}',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _copiar,
                icon: Icon(_copiado ? Icons.check : Icons.copy, size: 18),
                label: Text(_copiado ? 'Copiado' : 'Copiar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _compartilhar,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.officePurple,
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Compartilhar'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Fechar'),
          ),
        ),
      ],
    );
  }
}

class _OpcaoDePapel extends StatelessWidget {
  const _OpcaoDePapel({
    required this.valor,
    required this.selecionado,
    required this.titulo,
    required this.descricao,
    required this.onChanged,
  });

  final String valor;
  final String selecionado;
  final String titulo;
  final String descricao;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final ativo = valor == selecionado;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(valor),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: ativo ? colors.officePurpleSurface : colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ativo ? colors.officePurple : colors.softBorder,
            width: ativo ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              ativo ? Icons.radio_button_checked : Icons.radio_button_off,
              color: ativo ? colors.officePurple : colors.muted,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    descricao,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
