import 'package:flutter/material.dart';

import '../models/invite_link.dart';
import '../repositories/invite_link_repository.dart';
import '../theme/app_colors.dart';

/// O aviso na tela de login de que HÁ UM CONVITE esperando: quem clicou no
/// link sem estar logado cai aqui e, sem isto, acharia que o link se perdeu.
///
/// Espia o convite (o RPC funciona sem sessão) para dizer QUEM convidou e
/// para quê. Se a espiada falhar, o aviso continua, só sem o nome: o
/// importante é a promessa de que o convite reabre depois de entrar.
class ConviteAguardandoAviso extends StatefulWidget {
  const ConviteAguardandoAviso({
    super.key,
    required this.token,
    this.repository = const InviteLinkRepository(),
  });

  final String token;
  final InviteLinkRepository repository;

  @override
  State<ConviteAguardandoAviso> createState() => _ConviteAguardandoAvisoState();
}

class _ConviteAguardandoAvisoState extends State<ConviteAguardandoAviso> {
  InviteLinkPreview? _preview;

  @override
  void initState() {
    super.initState();
    _espiar();
  }

  @override
  void didUpdateWidget(covariant ConviteAguardandoAviso oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token != widget.token) _espiar();
  }

  Future<void> _espiar() async {
    try {
      final preview = await widget.repository.peek(widget.token);
      if (mounted) setState(() => _preview = preview);
    } catch (error) {
      debugPrint('ConviteAguardandoAviso peek failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final p = _preview;
    final valido = p == null || p.status == InviteLinkStatus.valido;
    final texto = !valido
        ? 'Você abriu um convite de equipe. Entre para ver o estado dele.'
        : p?.firmName == null || p!.firmName!.isEmpty
        ? 'Você abriu um convite de equipe. Entre ou crie sua conta e o '
              'convite reabre sozinho.'
        : '${p.firmName} convidou você para entrar como '
              '${rotuloDoPapelDoConvite(p.memberRole ?? '').toLowerCase()}. '
              'Entre ou crie sua conta e o convite reabre sozinho.';
    return Container(
      key: const Key('convite-aguardando'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.officePurpleSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.officePurpleBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.mail_outline, color: colors.officePurple, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                color: colors.officePurpleText,
                fontWeight: FontWeight.w600,
                height: 1.35,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
