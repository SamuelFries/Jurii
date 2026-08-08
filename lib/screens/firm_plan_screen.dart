import 'package:flutter/material.dart';

import '../models/law_firm_license.dart';
import '../models/law_firm_verification.dart';
import '../models/user_profile.dart';
import '../repositories/license_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/jurii_error_state.dart';
import '../widgets/jurii_motion.dart';
import 'law_firm_verification_screen.dart';

/// A paywall do escritório: escolha do plano ANTES da verificação.
///
/// Todos os planos incluem tudo — o que muda é o teto de advogados. Essa é a
/// frase inteira do modelo de preço, e a tela a diz textualmente: paywall que
/// precisa de tabela comparativa está escondendo alguma coisa.
///
/// A tela é só o convite; o portão de verdade é a policy do banco, que recusa
/// verificação de quem não tem assinatura.
class FirmPlanScreen extends StatefulWidget {
  /// Fluxo de entrada: escolher plano e seguir para a verificação.
  const FirmPlanScreen({
    super.key,
    required this.user,
    this.onVerificationSubmitted,
    this.repository = const LicenseRepository(),
  }) : upgradeDe = null;

  /// Troca de plano de quem já assina (aberta pelo perfil do escritório).
  const FirmPlanScreen.upgrade({
    super.key,
    required String this.upgradeDe,
    this.repository = const LicenseRepository(),
  }) : user = null,
       onVerificationSubmitted = null;

  final UserProfile? user;
  final ValueChanged<LawFirmVerification>? onVerificationSubmitted;
  final LicenseRepository repository;

  /// Código do plano atual quando a tela abre para troca.
  final String? upgradeDe;

  bool get _isUpgrade => upgradeDe != null;

  @override
  State<FirmPlanScreen> createState() => _FirmPlanScreenState();
}

class _FirmPlanScreenState extends State<FirmPlanScreen> {
  /// O plano do meio é o recomendado: cobre o escritório brasileiro típico e
  /// dá espaço para crescer sem troca imediata.
  static const _recomendado = 'escritorio';

  List<LicensePlan>? _planos;
  bool _falhou = false;
  String? _selecionado;
  bool _confirmando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _planos = null;
      _falhou = false;
    });
    try {
      final planos = await widget.repository.fetchPlans();
      if (!mounted) return;
      setState(() {
        _planos = planos;
        // Pré-seleção: o recomendado no fluxo de entrada; o plano ATUAL não,
        // na troca — pré-selecionar o atual deixaria o botão morto sem
        // explicar por quê.
        _selecionado ??= widget._isUpgrade
            ? null
            : planos.any((p) => p.code == _recomendado)
            ? _recomendado
            : planos.firstOrNull?.code;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _falhou = true);
    }
  }

  Future<void> _confirmar() async {
    final escolhido = _selecionado;
    if (escolhido == null || _confirmando) return;

    setState(() => _confirmando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final assinatura = await widget.repository.choosePlan(escolhido);
      if (!mounted) return;

      if (widget._isUpgrade) {
        Navigator.of(context).pop(assinatura);
        messenger.showSnackBar(
          const SnackBar(content: Text('Plano atualizado.')),
        );
        return;
      }

      // Substitui a paywall na pilha: voltar da verificação não pode cair na
      // escolha de plano de novo — o plano já está escolhido.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LawFirmVerificationScreen(
            user: widget.user!,
            onVerificationSubmitted: widget.onVerificationSubmitted,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _confirmando = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error.toString().contains('Firm already has a subscription')
                ? 'Este escritório já tem um plano contratado por outra '
                      'pessoa.'
                : 'Não foi possível confirmar o plano. Tente novamente.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final planos = _planos;
    final podeConfirmar =
        _selecionado != null &&
        !_confirmando &&
        (!widget._isUpgrade || _selecionado != widget.upgradeDe);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        title: Text(widget._isUpgrade ? 'Trocar de plano' : 'Escolha o plano'),
      ),
      body: SafeArea(
        child: _falhou
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: JuriiErrorState(
                  title: 'Não foi possível carregar os planos.',
                  onRetry: _carregar,
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      children: [
                        Text(
                          'Todos os planos incluem tudo.',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Descoberta, perfil completo, equipe, mensagens, '
                          'casos e painel de alcance. O que muda é o tamanho '
                          'da equipe.',
                          style: TextStyle(
                            color: colors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (planos == null)
                          const JuriiSkeletonList(
                            itemCount: 3,
                            itemHeight: 96,
                            gap: 12,
                          )
                        else ...[
                          for (var i = 0; i < planos.length; i++) ...[
                            JuriiStaggeredItem(
                              index: i,
                              child: _CartaoDePlano(
                                plano: planos[i],
                                selecionado: _selecionado == planos[i].code,
                                recomendado: planos[i].code == _recomendado,
                                atual: planos[i].code == widget.upgradeDe,
                                onTap: () => setState(
                                  () => _selecionado = planos[i].code,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          const SizedBox(height: 4),
                          if (!widget._isUpgrade)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colors.successSurface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.card_giftcard_outlined,
                                    size: 18,
                                    color: colors.success,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '30 dias grátis, sem cartão. A cobrança '
                                      'é combinada fora do aplicativo, ao fim '
                                      'do teste.',
                                      style: TextStyle(
                                        color: colors.textPrimary,
                                        fontSize: 12.5,
                                        height: 1.4,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            'Mais de 25 advogados? Fale com a gente pelo '
                            'suporte — montamos um plano sob medida.',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    decoration: BoxDecoration(
                      color: colors.background,
                      border: Border(top: BorderSide(color: colors.divider)),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        key: const Key('confirmar_plano'),
                        onPressed: podeConfirmar ? _confirmar : null,
                        child: _confirmando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                widget._isUpgrade
                                    ? 'Trocar de plano'
                                    : 'Começar teste grátis',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CartaoDePlano extends StatelessWidget {
  const _CartaoDePlano({
    required this.plano,
    required this.selecionado,
    required this.recomendado,
    required this.atual,
    required this.onTap,
  });

  final LicensePlan plano;
  final bool selecionado;
  final bool recomendado;
  final bool atual;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final cor = colors.officePurple;

    return JuriiPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      semanticLabel:
          '${plano.name}, ${plano.teamLabel}, ${plano.priceLabel} por mês'
          '${atual ? ', plano atual' : ''}',
      semanticSelected: selecionado,
      child: AnimatedContainer(
        duration: JuriiMotion.fast,
        curve: JuriiMotion.ease,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selecionado ? cor.withValues(alpha: 0.06) : colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selecionado ? cor : colors.officePurpleBorder,
            width: selecionado ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Wrap, não Row: em tela estreita o preço e o rádio
                  // comem a largura, e um badge rígido estourava a linha por
                  // ~1,4px (o teste de overflow pegou). No Wrap o badge desce
                  // de linha em vez de estourar.
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        plano.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      if (recomendado)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.lightGold,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: colors.lightGoldBorder),
                          ),
                          child: Text(
                            'Recomendado',
                            style: TextStyle(
                              color: colors.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      if (atual)
                        Text(
                          'Plano atual',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    plano.teamLabel,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (plano.perLawyerLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      plano.perLawyerLabel!,
                      style: TextStyle(
                        color: colors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  plano.priceLabel,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '/mês',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Icon(
              selecionado
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: selecionado ? cor : colors.muted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
