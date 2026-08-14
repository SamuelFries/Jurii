import 'package:flutter/material.dart';

import '../models/firm_operation_metrics.dart';
import '../models/firm_membership.dart';
import '../models/firm_role.dart';
import '../models/firm_team_member.dart';
import '../models/firm_workspace.dart';
import '../models/jurii_notification.dart';
import '../models/professional_reach.dart';
import '../repositories/discovery_metrics_repository.dart';
import '../repositories/firm_workspace_repository.dart';
import '../repositories/professional_reach_repository.dart';
import '../screens/professional_reach_screen.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../widgets/jurii_error_state.dart';
import '../widgets/jurii_list_card.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/firm_switcher_sheet.dart';
import '../widgets/notification_bell.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/reach_chart.dart';

/// Home do escritório: o que mudou, quem está disponível e onde crescer.
///
/// A estrutura espelha a home do advogado (cabeçalho-identidade com chips,
/// seções com título e "Ver tudo", linhas com pílula de contagem, tiles de
/// pessoas) vestida com a pele do fluxo roxo (raio 14, officePurpleBorder,
/// avatar roxo/cinza por disponibilidade — as mesmas escolhas da aba Equipe).
/// Quem transita entre os dois fluxos encontra a mesma casa com outra cor.
///
/// O que ela NÃO tem, de propósito:
/// - Botões-atalho para Mensagens/Equipe/Casos — a bottom nav já mostra os
///   três, sempre visíveis. Blocos quadrados de atalho gastavam a primeira
///   dobra com navegação em vez de informação. Quem navega pelos números
///   agora navega tocando NELES: cada linha da operação abre a aba que a
///   explica.
/// - Uma seção "Hoje" — era os mesmos três números da grade reescritos em
///   frase, logo abaixo dela. Duas vezes o mesmo dado não é resumo, é eco.
class FirmHomeScreen extends StatefulWidget {
  const FirmHomeScreen({
    super.key,
    this.workspace,
    this.repository = const FirmWorkspaceRepository(),
    this.reachRepository = const ProfessionalReachRepository(),
    required this.onOpenMessages,
    required this.onOpenTeam,
    required this.onOpenCases,
    this.memberships = const [],
    this.onSelectFirm,
  });

  final FirmWorkspace? workspace;
  /// Todos os vínculos, para o seletor no cabeçalho. Vazio ou com um só, o
  /// cabeçalho não vira botão.
  final List<FirmMembership> memberships;
  final ValueChanged<String>? onSelectFirm;
  final FirmWorkspaceRepository repository;
  final ProfessionalReachRepository reachRepository;
  final VoidCallback onOpenMessages;
  final VoidCallback onOpenTeam;
  final VoidCallback onOpenCases;

  @override
  State<FirmHomeScreen> createState() => _FirmHomeScreenState();
}

class _FirmHomeScreenState extends State<FirmHomeScreen> {
  late Future<FirmOperationMetrics> _metricsFuture;
  ReachSummary? _alcance;
  bool _alcanceIndisponivel = false;

  /// Alcance é assunto de quem fala pelo escritório (mesmo portão do painel
  /// completo e do servidor). Buscar para uma secretária só renderia um erro
  /// de permissão que ela não tem como resolver.
  bool get _podeVerAlcance {
    final roles = widget.workspace?.effectiveCurrentUserRoles ?? const [];
    return widget.workspace?.fromSupabase == true &&
        roles.canManageFirmMembers;
  }

  @override
  void initState() {
    super.initState();
    _metricsFuture = _loadMetrics();
    _loadAlcance();
  }

  @override
  void didUpdateWidget(covariant FirmHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace?.firm.id != widget.workspace?.firm.id) {
      _metricsFuture = _loadMetrics();
      _alcance = null;
      _alcanceIndisponivel = false;
      _loadAlcance();
    }
  }

  Future<FirmOperationMetrics> _loadMetrics() async {
    final lawFirmId = widget.workspace?.firm.id;
    final localTeamCount =
        widget.workspace?.teamMembers
            .where((member) => member.available)
            .length ??
        0;

    if (!SupabaseConfig.isReady ||
        lawFirmId == null ||
        widget.workspace?.fromSupabase != true) {
      return FirmOperationMetrics.empty(teamMembers: localTeamCount);
    }

    try {
      return await widget.repository.fetchLawFirmOperationMetrics(lawFirmId);
    } catch (error) {
      // Erro sobe para o FutureBuilder: zeros em falha de rede parecem
      // métrica real — e métrica errada é pior que métrica ausente.
      debugPrint('Supabase firm operation metrics fetch failed: $error');
      rethrow;
    }
  }

  Future<void> _loadAlcance() async {
    final lawFirmId = widget.workspace?.firm.id;
    if (lawFirmId == null || !_podeVerAlcance) return;

    try {
      final resumo = await widget.reachRepository.fetchReach(
        target: DiscoveryTarget.lawFirm,
        targetId: lawFirmId,
        windowDays: 7,
      );
      if (!mounted) return;
      setState(() => _alcance = resumo);
    } catch (error) {
      // O chamariz some em silêncio: a entrada com estado de erro e retry
      // continua existindo no Perfil. Um cartão-resumo quebrado na home só
      // ensinaria a ignorar cartões.
      debugPrint('Firm reach teaser fetch failed: $error');
      if (!mounted) return;
      setState(() => _alcanceIndisponivel = true);
    }
  }

  Future<void> _reload() async {
    final nextMetrics = _loadMetrics();
    setState(() {
      _metricsFuture = nextMetrics;
      _alcanceIndisponivel = false;
    });
    try {
      await Future.wait([nextMetrics, _loadAlcance()]);
    } catch (_) {
      // O FutureBuilder exibe o estado de erro.
    }
  }

  void _abrirPainelDeAlcance() {
    final lawFirmId = widget.workspace?.firm.id;
    if (lawFirmId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfessionalReachScreen.lawFirm(lawFirmId: lawFirmId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    final sections = <Widget>[
      _HeaderCard(
        workspace: widget.workspace,
        onBellChanged: _reload,
        memberships: widget.memberships,
        onSelectFirm: widget.onSelectFirm,
      ),
      _OperationSection(
        metricsFuture: _metricsFuture,
        onRetry: _reload,
        onOpenMessages: widget.onOpenMessages,
        onOpenTeam: widget.onOpenTeam,
        onOpenCases: widget.onOpenCases,
      ),
      _TeamSection(
        members: widget.workspace?.teamMembers ?? const [],
        onOpenTeam: widget.onOpenTeam,
      ),
      if (_podeVerAlcance && !_alcanceIndisponivel)
        _ReachSection(resumo: _alcance, onOpen: _abrirPainelDeAlcance),
    ];

    return SafeArea(
      child: RefreshIndicator(
        color: colors.officePurple,
        onRefresh: _reload,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          itemCount: sections.length,
          separatorBuilder: (context, index) => const SizedBox(height: 24),
          itemBuilder: (context, index) => JuriiStaggeredItem(
            index: index,
            child: sections[index],
          ),
        ),
      ),
    );
  }
}

/// Cabeçalho-identidade, espelho do cabeçalho do advogado: nome grande,
/// credencial embaixo, sino à direita e chips de status dentro do cartão.
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.workspace,
    required this.onBellChanged,
    required this.memberships,
    required this.onSelectFirm,
  });

  final FirmWorkspace? workspace;
  final Future<void> Function() onBellChanged;
  final List<FirmMembership> memberships;
  final ValueChanged<String>? onSelectFirm;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final name = workspace?.firm.name ?? 'Escritório';
    final roles = workspace?.effectiveCurrentUserRoles ?? const <FirmRole>[];
    final ready = workspace?.fromSupabase == true;
    final specialty = workspace?.firm.specialty.trim() ?? '';
    final podeTrocar =
        onSelectFirm != null && shouldShowFirmSwitcher(memberships);

    // O papel de quem olha muda o que a tela significa — sócio lê estes
    // números como dono; advogado, como parte da equipe. "Área do escritório"
    // como subtítulo não dizia nada: a moldura inteira já é roxa.
    final subtitle = ready && roles.isNotEmpty
        ? 'Você atua como ${roles.labels}'
        : 'Área do escritório em preparação';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.officePurple,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: colors.officePurple.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProfileAvatar(
                imageUrl: workspace?.firm.avatarUrl,
                initials: workspace?.firm.initials ?? 'JE',
                size: 46,
                backgroundColor: colors.card.withValues(alpha: 0.14),
                foregroundColor: colors.card,
                borderRadius: BorderRadius.circular(12),
                fontSize: 15,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Com dois ou mais vínculos, o NOME é o seletor: quem
                    // atua em duas bancas procura a troca onde o escritório
                    // está escrito, e não num menu escondido. Com um só, ele
                    // continua sendo texto, porque um botão que abre uma
                    // lista de um item é um botão que mente.
                    if (podeTrocar)
                      InkWell(
                        onTap: () => showFirmSwitcher(
                          context,
                          memberships: memberships,
                          currentFirmId: workspace?.firm.id,
                          onSelect: onSelectFirm!,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.card,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  height: 1.1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.expand_more,
                              color: colors.card,
                              size: 22,
                            ),
                          ],
                        ),
                      )
                    else
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.card,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.card.withValues(alpha: 0.78),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              NotificationBell(
                scope: NotificationScope.firm,
                lawFirmId: workspace?.firm.id,
                iconColor: colors.officePurple,
                backgroundColor: colors.card,
                borderColor: colors.officePurpleBorder,
                onChanged: onBellChanged,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(
                icon: ready
                    ? Icons.verified_outlined
                    : Icons.schedule_outlined,
                label: ready ? 'Escritório verificado' : 'Em preparação',
              ),
              if (specialty.isNotEmpty)
                _StatusChip(icon: Icons.balance_outlined, label: specialty),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mesmo desenho do chip do cabeçalho do advogado: vidro sobre o fill, ícone
/// dourado (lightGold — accent some sobre fills claros no tema escuro).
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.card.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.card.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.lightGold),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: colors.card,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Título de seção no mesmo desenho da home do advogado: titleLarge à
/// esquerda, ação discreta à direita — só que na cor do fluxo.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(
              actionLabel ?? 'Ver tudo',
              style: TextStyle(
                color: colors.officePurple,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }
}

class _OperationSection extends StatelessWidget {
  const _OperationSection({
    required this.metricsFuture,
    required this.onRetry,
    required this.onOpenMessages,
    required this.onOpenTeam,
    required this.onOpenCases,
  });

  final Future<FirmOperationMetrics> metricsFuture;
  final Future<void> Function() onRetry;
  final VoidCallback onOpenMessages;
  final VoidCallback onOpenTeam;
  final VoidCallback onOpenCases;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Operação'),
        const SizedBox(height: 12),
        FutureBuilder<FirmOperationMetrics>(
          future: metricsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: JuriiErrorState(
                  title: 'Não foi possível carregar as métricas.',
                  onRetry: onRetry,
                ),
              );
            }

            // Sem dado ainda = esqueleto, não zeros. Zero de verdade e zero
            // de carregamento são estados diferentes, e o primeiro segundo da
            // tela não pode afirmar "nenhuma conversa" sem saber.
            if (!snapshot.hasData) {
              return const JuriiSkeletonList(
                itemCount: 4,
                itemHeight: 52,
                gap: 8,
              );
            }

            final metrics = snapshot.data!;
            // O número levanta a pergunta ("3 casos — quais?"); o toque
            // responde, abrindo a aba que o explica. Métrica que não leva a
            // lugar nenhum é placar, não painel.
            final rows = [
              (
                icon: Icons.mark_chat_unread_outlined,
                label: 'Conversas com clientes',
                value: metrics.clientMessages,
                color: colors.officePurple,
                onTap: onOpenMessages,
              ),
              (
                icon: Icons.forum_outlined,
                label: 'Conversas internas',
                value: metrics.teamMessages,
                color: colors.primary,
                onTap: onOpenMessages,
              ),
              (
                icon: Icons.folder_copy_outlined,
                label: 'Casos ativos',
                value: metrics.activeCases,
                color: colors.accent,
                onTap: onOpenCases,
              ),
              (
                icon: Icons.badge_outlined,
                label: 'Membros ativos',
                value: metrics.teamMembers,
                color: colors.success,
                onTap: onOpenTeam,
              ),
            ];

            return Material(
              color: colors.card,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: colors.officePurpleBorder),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    _OperationRow(
                      icon: rows[i].icon,
                      label: rows[i].label,
                      value: rows[i].value,
                      color: rows[i].color,
                      onTap: rows[i].onTap,
                    ),
                    if (i < rows.length - 1)
                      Divider(height: 1, indent: 64, color: colors.divider),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Linha de operação: o desenho das linhas do cartão "Hoje" do advogado
/// (ícone, rótulo, pílula de contagem), mas navegável — com o chevron
/// avisando que leva a algum lugar.
class _OperationRow extends StatelessWidget {
  const _OperationRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return InkWell(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: '$value $label. Toque para abrir.',
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.officePurpleSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: colors.officePurple, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 32),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: JuriiAnimatedCounter(
                    value: value,
                    style: TextStyle(color: color, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, color: colors.textSecondary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A equipe, com rosto — um escritório é gente, e a home era só número.
///
/// Tiles no mesmo desenho da aba Equipe (avatar roxo disponível / cinza
/// indisponível, papel + especialidade), então a home ensina a ler a aba.
/// Os dados já estão no workspace: nenhuma ida extra ao servidor.
class _TeamSection extends StatelessWidget {
  const _TeamSection({required this.members, required this.onOpenTeam});

  final List<FirmTeamMember> members;
  final VoidCallback onOpenTeam;

  static const _maxTiles = 3;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    if (members.isEmpty) {
      // Escritório recém-aprovado: zero membros não é métrica, é próximo
      // passo.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'Equipe'),
          const SizedBox(height: 12),
          JuriiListCard(
            onTap: onOpenTeam,
            semanticLabel: 'Monte sua equipe. Toque para convidar advogados.',
            borderRadius: 14,
            backgroundColor: colors.officePurpleSurface,
            borderColor: colors.officePurpleBorder,
            child: Row(
              children: [
                Icon(Icons.group_add_outlined, color: colors.officePurple),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monte sua equipe',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Convide advogados pelo número da OAB.',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.textSecondary),
              ],
            ),
          ),
        ],
      );
    }

    // Disponíveis primeiro: os rostos visíveis são os de quem pode atender
    // agora, não os três primeiros por ordem de cadastro.
    final ordenados = [...members]
      ..sort((a, b) => (b.available ? 1 : 0) - (a.available ? 1 : 0));
    final visiveis = ordenados.take(_maxTiles).toList();
    final disponiveis = members.where((m) => m.available).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Equipe', onAction: onOpenTeam),
        const SizedBox(height: 12),
        Material(
          color: colors.card,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: colors.officePurpleBorder),
          ),
          child: Column(
            children: [
              for (var i = 0; i < visiveis.length; i++) ...[
                _TeamMemberTile(member: visiveis[i], onTap: onOpenTeam),
                if (i < visiveis.length - 1)
                  Divider(height: 1, indent: 68, color: colors.divider),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            disponiveis == members.length
                ? '${members.length} na equipe, todos disponíveis agora'
                : '$disponiveis de ${members.length} disponíveis agora',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _TeamMemberTile extends StatelessWidget {
  const _TeamMemberTile({required this.member, required this.onTap});

  final FirmTeamMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final roleLabel = member.roleLabel;
    final detail = member.specialty.trim().isEmpty ||
            member.specialty == roleLabel
        ? roleLabel
        : '$roleLabel · ${member.specialty}';

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: ProfileAvatar(
        imageUrl: member.avatarUrl,
        initials: member.initials,
        size: 44,
        // Mesmo código de cor da aba Equipe: roxo disponível, cinza não.
        backgroundColor: member.available
            ? colors.officePurple
            : colors.textSecondary,
        foregroundColor: colors.card,
        borderRadius: BorderRadius.circular(12),
        fontSize: 14,
      ),
      title: Text(
        member.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        detail,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.textSecondary, fontSize: 12),
      ),
      trailing: Icon(Icons.chevron_right, color: colors.textSecondary),
    );
  }
}

/// Chamariz do alcance na home — o painel completo continua no Perfil.
///
/// É o vendedor do patrocínio no lugar onde o sócio de fato aterrissa todo
/// dia: quem abre e vê "12 pessoas viram o escritório esta semana" descobre
/// sozinho que tem um problema de alcance, sem ninguém precisar ligar.
class _ReachSection extends StatelessWidget {
  const _ReachSection({required this.resumo, required this.onOpen});

  /// Nulo enquanto carrega — a seção mostra esqueleto no lugar do número.
  final ReachSummary? resumo;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final variacao = resumo?.reachChange;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Alcance',
          actionLabel: 'Ver painel',
          onAction: resumo == null ? null : onOpen,
        ),
        const SizedBox(height: 12),
        if (resumo == null)
          const JuriiSkeletonCard(
            height: 132,
            borderRadius: BorderRadius.all(Radius.circular(14)),
          )
        else
          JuriiListCard(
            onTap: onOpen,
            semanticLabel:
                '${resumo!.reach} visualizações na busca nos últimos 7 dias. '
                'Toque para ver o painel completo.',
            borderRadius: 14,
            borderColor: colors.officePurpleBorder,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    JuriiAnimatedCounter(
                      value: resumo!.reach,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (variacao != null) _VariacaoChip(variacao: variacao),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right,
                      color: colors.textSecondary,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'visualizações na busca nos últimos 7 dias',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                if (resumo!.days.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ReachChart(days: resumo!.days, height: 64),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _VariacaoChip extends StatelessWidget {
  const _VariacaoChip({required this.variacao});

  final double variacao;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final subiu = variacao >= 0;

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
            '${(variacao.abs() * 100).round()}%',
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
