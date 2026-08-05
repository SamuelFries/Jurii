import 'package:flutter/material.dart';

import '../models/professional_reach.dart';
import '../repositories/discovery_metrics_repository.dart';
import '../repositories/professional_reach_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/jurii_error_state.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/reach_chart.dart';

/// Painel de alcance do profissional.
///
/// Existe para TODO profissional aprovado, e não só para quem já contratou
/// patrocínio — de propósito. O painel é o vendedor: um advogado que abre e vê
/// "38 pessoas viram você" descobre sozinho que tem um problema, sem ninguém
/// precisar ligar para ele. Se ele só aparecesse depois da compra, seria
/// preciso convencer no escuro.
///
/// O funil é o que a caixa de entrada nunca conta: onde ele está perdendo
/// gente. Muita visualização e pouca visita é problema de cartão; muita visita
/// e pouca conversa é problema de perfil; pouca visualização é problema de
/// alcance — e é só nesse caso que patrocinar resolve.
class ProfessionalReachScreen extends StatefulWidget {
  const ProfessionalReachScreen.lawyer({
    super.key,
    required String lawyerId,
    this.repository = const ProfessionalReachRepository(),
  }) : targetId = lawyerId,
       target = DiscoveryTarget.lawyer;

  const ProfessionalReachScreen.lawFirm({
    super.key,
    required String lawFirmId,
    this.repository = const ProfessionalReachRepository(),
  }) : targetId = lawFirmId,
       target = DiscoveryTarget.lawFirm;

  final String targetId;
  final DiscoveryTarget target;
  final ProfessionalReachRepository repository;

  @override
  State<ProfessionalReachScreen> createState() =>
      _ProfessionalReachScreenState();
}

class _ProfessionalReachScreenState extends State<ProfessionalReachScreen> {
  static const _janelas = [7, 30];

  int _janela = 30;
  ReachSummary? _resumo;
  bool _carregando = true;
  bool _falhou = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _falhou = false;
    });
    try {
      final resumo = await widget.repository.fetchReach(
        target: widget.target,
        targetId: widget.targetId,
        windowDays: _janela,
      );
      if (!mounted) return;
      setState(() {
        _resumo = resumo;
        _carregando = false;
      });
    } catch (error) {
      debugPrint('Reach fetch failed: $error');
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _falhou = true;
      });
    }
  }

  void _trocarJanela(int dias) {
    if (dias == _janela) return;
    setState(() => _janela = dias);
    _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        title: const Text('Seu alcance'),
      ),
      body: SafeArea(
        child: _falhou
            ? JuriiErrorState(
                title: 'Não foi possível carregar seus números.',
                onRetry: _carregar,
              )
            : RefreshIndicator(
                onRefresh: _carregar,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    _SeletorDeJanela(
                      janelas: _janelas,
                      selecionada: _janela,
                      onChanged: _carregando ? null : _trocarJanela,
                    ),
                    const SizedBox(height: 18),
                    if (_carregando)
                      const _EsqueletoDoPainel()
                    else if (_resumo != null)
                      ..._conteudo(_resumo!, colors),
                  ],
                ),
              ),
      ),
    );
  }

  List<Widget> _conteudo(ReachSummary resumo, AppColors colors) {
    return [
      _CartaoDeAlcance(resumo: resumo, janela: _janela),
      const SizedBox(height: 14),
      _CartaoDoFunil(resumo: resumo),
      const SizedBox(height: 14),
      _CartaoDePatrocinio(resumo: resumo),
    ];
  }
}

class _SeletorDeJanela extends StatelessWidget {
  const _SeletorDeJanela({
    required this.janelas,
    required this.selecionada,
    required this.onChanged,
  });

  final List<int> janelas;
  final int selecionada;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Row(
      children: [
        for (final dias in janelas) ...[
          if (dias != janelas.first) const SizedBox(width: 8),
          Expanded(
            child: JuriiPressable(
              onTap: onChanged == null ? null : () => onChanged!(dias),
              borderRadius: BorderRadius.circular(12),
              semanticLabel: 'Últimos $dias dias',
              semanticSelected: dias == selecionada,
              child: AnimatedContainer(
                duration: JuriiMotion.fast,
                curve: JuriiMotion.ease,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: dias == selecionada ? colors.primary : colors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: dias == selecionada
                        ? colors.primary
                        : colors.lightBlueBorder,
                  ),
                ),
                child: Center(
                  child: Text(
                    '$dias dias',
                    style: TextStyle(
                      color: dias == selecionada
                          ? colors.card
                          : colors.textSecondary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CartaoDeAlcance extends StatelessWidget {
  const _CartaoDeAlcance({required this.resumo, required this.janela});

  final ReachSummary resumo;
  final int janela;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final variacao = resumo.reachChange;

    return _Cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PESSOAS QUE VIRAM VOCÊ',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                resumo.reach.toString(),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              if (variacao != null) _ChipDeVariacao(variacao: variacao),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            variacao == null
                // Sem base de comparação: crescer "infinito%" a partir de zero
                // não é informação.
                ? 'nos últimos $janela dias'
                : 'nos últimos $janela dias, contra os $janela anteriores',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ReachChart(days: resumo.days),
          if (resumo.hasSponsoredReach) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'dias em que uma vaga patrocinada estava ativa',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ChipDeVariacao extends StatelessWidget {
  const _ChipDeVariacao({required this.variacao});

  final double variacao;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final subiu = variacao >= 0;
    final porcento = (variacao.abs() * 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: subiu ? colors.successSurface : colors.dangerSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            subiu ? Icons.trending_up : Icons.trending_down,
            size: 13,
            color: subiu ? colors.success : colors.danger,
          ),
          const SizedBox(width: 4),
          Text(
            '$porcento%',
            style: TextStyle(
              color: subiu ? colors.success : colors.danger,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartaoDoFunil extends StatelessWidget {
  const _CartaoDoFunil({required this.resumo});

  final ReachSummary resumo;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return _Cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DO PRIMEIRO OLHAR À CONVERSA',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 16),
          ReachFunnel(steps: resumo.steps),
          if (resumo.isEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Ainda sem movimento no período. Assim que alguém buscar por '
              'sua área, os números começam a aparecer aqui.',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// O gancho do patrocínio. Muda de conversa conforme o estado: quem já tem
/// vaga paga vê o que ela rendeu; quem não tem vê onde está o gargalo dele.
class _CartaoDePatrocinio extends StatelessWidget {
  const _CartaoDePatrocinio({required this.resumo});

  final ReachSummary resumo;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    if (resumo.hasSponsoredReach) {
      final fatia = resumo.reach == 0
          ? 0
          : (resumo.sponsoredReach / resumo.reach * 100).round();
      return _Cartao(
        borderColor: colors.lightGoldBorder,
        background: colors.lightGold,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.campaign_outlined, size: 18, color: colors.accent),
                const SizedBox(width: 8),
                Text(
                  'Patrocínio ativo',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${resumo.sponsoredReach} das ${resumo.reach} pessoas que viram '
              'você chegaram por uma vaga patrocinada — $fatia% do seu alcance '
              'no período.',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return _Cartao(
      borderColor: colors.lightGoldBorder,
      background: colors.lightGold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.campaign_outlined, size: 18, color: colors.accent),
              const SizedBox(width: 8),
              Text(
                'Quer aparecer para mais gente?',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            // Sem promessa de número: ninguém foi patrocinado com medição
            // rodando ainda, então prometer "3x mais" seria invenção. Quando
            // houver histórico, a régua entra aqui.
            'Uma vaga patrocinada coloca seu perfil no topo das buscas da sua '
            'área, com o selo de patrocinado. Fale com a gente para ativar.',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({required this.child, this.borderColor, this.background});

  final Widget child;
  final Color? borderColor;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background ?? colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? colors.divider),
      ),
      child: child,
    );
  }
}

class _EsqueletoDoPainel extends StatelessWidget {
  const _EsqueletoDoPainel();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        JuriiSkeletonCard(height: 250),
        SizedBox(height: 14),
        JuriiSkeletonCard(height: 190),
        SizedBox(height: 14),
        JuriiSkeletonCard(height: 110),
      ],
    );
  }
}
