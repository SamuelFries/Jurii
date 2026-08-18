import 'package:flutter/material.dart';

import '../models/invite_link.dart';
import '../repositories/invite_link_repository.dart';
import '../theme/app_colors.dart';
import '../utils/invite_link.dart';
import '../widgets/jurii_form_motion.dart';

/// A tela de quem RECEBEU o link: `https://app.jurii.com.br/convite/<token>`.
///
/// Primeiro espia (o servidor diz o estado sem gastar o link), depois
/// oferece a única ação que existe: pedir para entrar. O papel vem do
/// convite e NÃO se edita aqui; quem escolheu foi o escritório ao gerar o
/// link, e a decisão final é dele na Equipe.
///
/// Todos os estados do servidor têm uma frase própria e nenhuma delas
/// inventa causa: "venceu" é venceu, "cancelado" é cancelado, "já
/// utilizado" é isso. E o "seu pedido" (pendente, aprovado, recusado,
/// vencido) fecha o ciclo para quem volta ao link depois de pedir.
class InviteLinkScreen extends StatefulWidget {
  const InviteLinkScreen({
    super.key,
    required this.token,
    this.repository = const InviteLinkRepository(),
    this.onEntrouNaBanca,
  });

  final String token;
  final InviteLinkRepository repository;

  /// Quando o pedido foi aprovado e a pessoa já é da equipe: quem hospeda
  /// pode levá-la para lá (recarregar o workspace). Opcional.
  final VoidCallback? onEntrouNaBanca;

  @override
  State<InviteLinkScreen> createState() => _InviteLinkScreenState();
}

class _InviteLinkScreenState extends State<InviteLinkScreen> {
  InviteLinkPreview? _preview;
  bool _carregando = true;
  bool _falhou = false;
  bool _pedindo = false;
  String? _erroDoPedido;
  bool _pediuAgora = false;

  @override
  void initState() {
    super.initState();
    _espiar();
  }

  Future<void> _espiar() async {
    setState(() {
      _carregando = true;
      _falhou = false;
    });
    try {
      final preview = await widget.repository.peek(widget.token);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _carregando = false;
      });
    } catch (error) {
      debugPrint('InviteLinkScreen peek failed: $error');
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _falhou = true;
      });
    }
  }

  Future<void> _pedir() async {
    setState(() {
      _pedindo = true;
      _erroDoPedido = null;
    });
    try {
      await widget.repository.requestEntry(widget.token);
      if (!mounted) return;
      setState(() {
        _pedindo = false;
        _pediuAgora = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pedindo = false;
        _erroDoPedido = traduzErroDoConvite(error);
      });
      // O estado pode ter mudado por baixo (link cancelado enquanto a tela
      // estava aberta): espia de novo para a tela dizer o estado real, e não
      // continuar oferecendo o botão.
      await _espiar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('Convite para a equipe')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _corpo(colors),
            ),
          ),
        ),
      ),
    );
  }

  Widget _corpo(AppColors colors) {
    if (_carregando) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_falhou || _preview == null) {
      return _Cartao(
        icone: Icons.wifi_off,
        cor: colors.warning,
        titulo: 'Não deu para abrir o convite',
        texto: 'Confira sua conexão e tente de novo.',
        acao: OutlinedButton(
          onPressed: _espiar,
          child: const Text('Tentar de novo'),
        ),
      );
    }
    if (_pediuAgora) {
      return _Cartao(
        icone: Icons.hourglass_top,
        cor: colors.officePurple,
        titulo: 'Pedido enviado',
        texto:
            'O escritório ${_preview!.firmName ?? ''} vai analisar seu pedido. '
            'Você recebe a resposta aqui no app, nas notificações.',
        acao: FilledButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Entendi'),
        ),
      );
    }

    final p = _preview!;
    switch (p.status) {
      case InviteLinkStatus.valido:
        return _conviteValido(colors, p);
      case InviteLinkStatus.inexistente:
      case InviteLinkStatus.desconhecida:
        return _Cartao(
          icone: Icons.link_off,
          cor: colors.danger,
          titulo: 'Convite não encontrado',
          texto:
              'Este link não corresponde a nenhum convite. Confira se ele '
              'foi copiado inteiro ou peça um novo a quem convidou.',
        );
      case InviteLinkStatus.expirado:
        return _Cartao(
          icone: Icons.schedule,
          cor: colors.warning,
          titulo: 'Este convite venceu',
          texto:
              'Links de convite valem por 7 dias. Peça um novo link a quem '
              'convidou você${_nomeDaBanca(p, ' para ')}.',
        );
      case InviteLinkStatus.revogado:
        return _Cartao(
          icone: Icons.block,
          cor: colors.warning,
          titulo: 'Convite cancelado',
          texto:
              'O escritório${_nomeDaBanca(p, ' ')} cancelou este convite. '
              'Se foi engano, peça um novo link.',
        );
      case InviteLinkStatus.usado:
        return _Cartao(
          icone: Icons.done_all,
          cor: colors.muted,
          titulo: 'Convite já utilizado',
          texto:
              'Cada link serve para uma pessoa só, e este já foi usado. '
              'Se foi você em outra conta, entre com ela; senão, peça um '
              'novo link.',
        );
      case InviteLinkStatus.meuPedidoPendente:
        return _Cartao(
          icone: Icons.hourglass_top,
          cor: colors.officePurple,
          titulo: 'Seu pedido está em análise',
          texto:
              'Você já pediu para entrar${_nomeDaBanca(p, ' em ')} como '
              '${_papel(p)}. Falta o escritório aprovar. A resposta chega '
              'nas notificações.',
        );
      case InviteLinkStatus.meuPedidoAprovado:
        return _Cartao(
          icone: Icons.check_circle,
          cor: colors.success,
          titulo: 'Você já faz parte da equipe',
          texto:
              'Seu pedido${_nomeDaBanca(p, ' para ')} foi aprovado. '
              'A área do escritório está no seu perfil.',
          acao: widget.onEntrouNaBanca == null
              ? null
              : FilledButton(
                  onPressed: () {
                    widget.onEntrouNaBanca!();
                    Navigator.of(context).maybePop();
                  },
                  child: const Text('Ir para o escritório'),
                ),
        );
      case InviteLinkStatus.meuPedidoRecusado:
        return _Cartao(
          icone: Icons.cancel_outlined,
          cor: colors.danger,
          titulo: 'Pedido não aprovado',
          texto:
              'O escritório${_nomeDaBanca(p, ' ')} não aprovou seu pedido de '
              'entrada. Este link não pode ser usado de novo.',
        );
      case InviteLinkStatus.meuPedidoExpirado:
        return _Cartao(
          icone: Icons.schedule,
          cor: colors.warning,
          titulo: 'Seu pedido venceu sem resposta',
          texto:
              'O escritório não respondeu em 7 dias. Peça um novo link a '
              'quem convidou você.',
        );
    }
  }

  String _nomeDaBanca(InviteLinkPreview p, String prefixo) {
    final nome = p.firmName;
    if (nome == null || nome.isEmpty) return '';
    return '$prefixo$nome';
  }

  String _papel(InviteLinkPreview p) =>
      rotuloDoPapelDoConvite(p.memberRole ?? '').toLowerCase();

  Widget _conviteValido(AppColors colors, InviteLinkPreview p) {
    final nome = p.firmName ?? 'Escritório';
    final iniciais = (p.firmInitials ?? '').isEmpty
        ? nome.substring(0, 1).toUpperCase()
        : p.firmInitials!;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.officePurpleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.officePurpleSurface,
                shape: BoxShape.circle,
                border: Border.all(color: colors.officePurpleBorder),
              ),
              child: Text(
                iniciais,
                style: TextStyle(
                  color: colors.officePurpleText,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            nome,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'convidou você para entrar na equipe como',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 10),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: colors.officePurpleSurface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colors.officePurpleBorder),
              ),
              child: Text(
                rotuloDoPapelDoConvite(p.memberRole ?? ''),
                key: const Key('papel-do-convite'),
                style: TextStyle(
                  color: colors.officePurpleText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Ao pedir, o escritório vê seu nome, e-mail e se seu CPF está '
            'confirmado, e decide na Equipe. Você recebe a resposta nas '
            'notificações.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          JuriiFormErrorBanner(message: _erroDoPedido),
          const SizedBox(height: 16),
          JuriiLoadingButton(
            label: 'Pedir para entrar',
            isLoading: _pedindo,
            onPressed: _pedir,
            height: 52,
            backgroundColor: colors.officePurple,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _pedindo ? null : () => Navigator.of(context).maybePop(),
            child: const Text('Agora não'),
          ),
        ],
      ),
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.texto,
    this.acao,
  });

  final IconData icone;
  final Color cor;
  final String titulo;
  final String texto;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icone, size: 40, color: cor),
          const SizedBox(height: 14),
          Text(
            titulo,
            key: const Key('titulo-do-estado'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, height: 1.4),
          ),
          if (acao != null) ...[const SizedBox(height: 18), acao!],
        ],
      ),
    );
  }
}
