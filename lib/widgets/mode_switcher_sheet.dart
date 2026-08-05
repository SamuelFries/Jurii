import 'package:flutter/material.dart';

import '../models/app_mode.dart';
import '../models/jurii_notification.dart';
import '../repositories/notification_repository.dart';
import '../theme/app_colors.dart';
import 'jurii_motion.dart';

/// Um modo disponível para o usuário, e o que fazer ao escolhê-lo.
class ModeOption {
  const ModeOption({required this.mode, required this.onSelect});

  final AppMode mode;

  /// Nulo quando o modo existe para esta pessoa mas não está liberado agora
  /// (verificação em análise, vínculo inativo): aparece na lista, explicado,
  /// em vez de sumir sem dizer por quê.
  final VoidCallback? onSelect;

  bool get isAvailable => onSelect != null;
}

/// Monta a lista de áreas que ESTA pessoa tem.
///
/// Cliente entra sempre — é o piso de toda conta. Profissional e escritório só
/// aparecem quando existem para ela: um cliente comum não precisa ver duas
/// linhas cinzas explicando áreas que nunca pediu.
List<ModeOption> buildModeOptions({
  VoidCallback? onClient,
  VoidCallback? onLawyer,
  VoidCallback? onFirm,
  required bool hasLawyerMode,
  required bool hasFirmMode,
}) {
  return [
    ModeOption(mode: AppMode.client, onSelect: onClient),
    if (hasLawyerMode) ModeOption(mode: AppMode.lawyer, onSelect: onLawyer),
    if (hasFirmMode) ModeOption(mode: AppMode.firm, onSelect: onFirm),
  ];
}

/// O seletor só faz sentido com mais de uma área: para quem só é cliente, ele
/// seria um botão que abre uma lista de um item só.
bool shouldShowModeSwitcher(List<ModeOption> options) => options.length > 1;

/// Seletor de fluxo, igual nos três modos.
///
/// Antes, trocar de fluxo tinha três aparências e três lugares diferentes:
/// cartão no topo do perfil (cliente e advogado), item de menu no meio
/// (advogado para escritório) e botão no rodapé, DEPOIS de "excluir conta"
/// (escritório). Quem usa os três reaprendia onde procurar a cada troca.
///
/// O contador ao lado de cada modo é a parte que resolve mais que estética: o
/// sino conta só o escopo do modo aberto, então uma solicitação de caso que
/// chega no fluxo profissional é invisível para quem está no fluxo cliente.
Future<void> showModeSwitcher(
  BuildContext context, {
  required AppMode current,
  required List<ModeOption> options,
  NotificationRepository repository = const NotificationRepository(),
  String? lawFirmId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ModeSwitcherSheet(
      current: current,
      options: options,
      repository: repository,
      lawFirmId: lawFirmId,
    ),
  );
}

class _ModeSwitcherSheet extends StatefulWidget {
  const _ModeSwitcherSheet({
    required this.current,
    required this.options,
    required this.repository,
    required this.lawFirmId,
  });

  final AppMode current;
  final List<ModeOption> options;
  final NotificationRepository repository;
  final String? lawFirmId;

  @override
  State<_ModeSwitcherSheet> createState() => _ModeSwitcherSheetState();
}

class _ModeSwitcherSheetState extends State<_ModeSwitcherSheet> {
  Map<NotificationScope, int> _pendentes = const {};

  @override
  void initState() {
    super.initState();
    _carregarPendencias();
  }

  Future<void> _carregarPendencias() async {
    final contagem = await widget.repository.fetchUnreadCountsByScope(
      lawFirmId: widget.lawFirmId,
    );
    if (!mounted) return;
    setState(() => _pendentes = contagem);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          color: colors.card,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: colors.divider),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text(
                  'Trocar de área',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Sua conta atende por mais de um lado. Cada área tem suas '
                  'próprias conversas e notificações.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
              for (final option in widget.options)
                _ModeRow(
                  option: option,
                  isCurrent: option.mode == widget.current,
                  pending: _pendentes[option.mode.notificationScope] ?? 0,
                  onTap: () {
                    Navigator.of(context).pop();
                    option.onSelect?.call();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.option,
    required this.isCurrent,
    required this.pending,
    required this.onTap,
  });

  final ModeOption option;
  final bool isCurrent;
  final int pending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final mode = option.mode;
    final cor = switch (mode) {
      AppMode.client => colors.primary,
      AppMode.lawyer => colors.accent,
      AppMode.firm => colors.officePurple,
    };

    return ListTile(
      // O modo atual não é toque morto: fica marcado e não navega.
      onTap: isCurrent || !option.isAvailable ? null : onTap,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(switch (mode) {
          AppMode.client => Icons.person_outline,
          AppMode.lawyer => Icons.balance_outlined,
          AppMode.firm => Icons.apartment_outlined,
        }, color: cor),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              mode.label,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (isCurrent) ...[
            const SizedBox(width: 8),
            _Etiqueta(texto: 'Você está aqui', cor: cor),
          ],
        ],
      ),
      subtitle: Text(
        // O modo ATUAL não tem callback de troca (não se navega para onde já
        // se está), e sem esta ressalva a linha onde a pessoa está diria
        // "ainda não liberado".
        isCurrent || option.isAvailable
            ? mode.description
            // Modo que existe mas não abriu: some o motivo em vez de sumir a
            // linha, senão a pessoa procura por algo que ela lembra de ter.
            : 'Ainda não liberado para sua conta',
        style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
      ),
      trailing: isCurrent
          ? Icon(Icons.check_circle, color: cor)
          : pending > 0
          // O ponto do seletor inteiro: mostrar que há algo esperando do
          // outro lado, que o sino do modo atual nunca mostraria.
          ? _ContadorPendente(quantidade: pending)
          : Icon(Icons.chevron_right, color: colors.muted),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto, required this.cor});

  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: TextStyle(color: cor, fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ContadorPendente extends StatelessWidget {
  const _ContadorPendente({required this.quantidade});

  final int quantidade;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Semantics(
      label: quantidade == 1
          ? '1 novidade nesta área'
          : '$quantidade novidades nesta área',
      child: AnimatedContainer(
        duration: JuriiMotion.fast,
        curve: JuriiMotion.ease,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colors.danger,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          quantidade > 9 ? '9+' : '$quantidade',
          style: TextStyle(
            color: colors.card,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
