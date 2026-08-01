import 'package:flutter/material.dart';

import '../models/firm_operation_metrics.dart';
import '../models/firm_workspace.dart';
import '../models/jurii_notification.dart';
import '../repositories/firm_workspace_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../widgets/jurii_error_state.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/notification_bell.dart';
import '../widgets/profile_avatar.dart';

class FirmHomeScreen extends StatefulWidget {
  const FirmHomeScreen({
    super.key,
    this.workspace,
    this.repository = const FirmWorkspaceRepository(),
    required this.onOpenMessages,
    required this.onOpenTeam,
    required this.onOpenCases,
  });

  final FirmWorkspace? workspace;
  final FirmWorkspaceRepository repository;
  final VoidCallback onOpenMessages;
  final VoidCallback onOpenTeam;
  final VoidCallback onOpenCases;

  @override
  State<FirmHomeScreen> createState() => _FirmHomeScreenState();
}

class _FirmHomeScreenState extends State<FirmHomeScreen> {
  late Future<FirmOperationMetrics> _metricsFuture;

  @override
  void initState() {
    super.initState();
    _metricsFuture = _loadMetrics();
  }

  @override
  void didUpdateWidget(covariant FirmHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace?.firm.id != widget.workspace?.firm.id) {
      _metricsFuture = _loadMetrics();
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

  Future<void> _reloadMetrics() async {
    final nextMetrics = _loadMetrics();
    setState(() {
      _metricsFuture = nextMetrics;
    });
    try {
      await nextMetrics;
    } catch (_) {
      // O FutureBuilder exibe o estado de erro.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final workspaceName = widget.workspace?.firm.name ?? 'Escritório';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
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
            child: Row(
              children: [
                ProfileAvatar(
                  imageUrl: widget.workspace?.firm.avatarUrl,
                  initials: widget.workspace?.firm.initials ?? 'JE',
                  size: 48,
                  backgroundColor: colors.card.withValues(alpha: 0.14),
                  foregroundColor: colors.card,
                  borderRadius: BorderRadius.circular(14),
                  fontSize: 16,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        workspaceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.card,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        widget.workspace?.fromSupabase == true
                            ? 'Área do escritório'
                            : 'Área do escritório em preparação',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.card,
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
                  lawFirmId: widget.workspace?.firm.id,
                  iconColor: colors.officePurple,
                  backgroundColor: colors.card,
                  borderColor: colors.officePurpleBorder,
                  onChanged: _reloadMetrics,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.chat_bubble_outline,
                  label: 'Mensagens',
                  onTap: widget.onOpenMessages,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  icon: Icons.group_outlined,
                  label: 'Equipe',
                  onTap: widget.onOpenTeam,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  icon: Icons.folder_outlined,
                  label: 'Casos',
                  onTap: widget.onOpenCases,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Operação',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<FirmOperationMetrics>(
            future: _metricsFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: JuriiErrorState(
                    title: 'Não foi possível carregar as métricas.',
                    onRetry: _reloadMetrics,
                  ),
                );
              }

              final metrics =
                  snapshot.data ??
                  FirmOperationMetrics.empty(
                    teamMembers:
                        widget.workspace?.teamMembers
                            .where((member) => member.available)
                            .length ??
                        0,
                  );

              return Column(
                children: [
                  _OperationMetrics(metrics: metrics),
                  const SizedBox(height: 24),
                  _TodayOverview(metrics: metrics),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OperationMetrics extends StatelessWidget {
  const _OperationMetrics({required this.metrics});

  final FirmOperationMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.75,
      ),
      children: [
        _MetricCard(
          value: '${metrics.clientMessages}',
          label: 'Conversas com clientes',
          icon: Icons.mark_chat_unread_outlined,
        ),
        _MetricCard(
          value: '${metrics.teamMessages}',
          label: 'Conversas internas',
          icon: Icons.forum_outlined,
        ),
        _MetricCard(
          value: '${metrics.activeCases}',
          label: 'Casos ativos',
          icon: Icons.folder_copy_outlined,
        ),
        _MetricCard(
          value: '${metrics.teamMembers}',
          label: 'Membros ativos',
          icon: Icons.badge_outlined,
        ),
      ],
    );
  }
}

class _TodayOverview extends StatelessWidget {
  const _TodayOverview({required this.metrics});

  final FirmOperationMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hoje',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        _TodayItem(
          icon: Icons.mail_outline,
          title: metrics.clientMessages > 0
              ? 'Conversas com clientes'
              : 'Sem novas conversas',
          subtitle: metrics.clientMessages > 0
              ? '${metrics.clientMessages} conversas ativas com clientes do escritório'
              : 'As conversas aparecerão aqui após a primeira mensagem real.',
          color: colors.officePurple,
        ),
        const SizedBox(height: 10),
        _TodayItem(
          icon: Icons.folder_copy_outlined,
          title: metrics.activeCases > 0
              ? 'Casos em andamento'
              : 'Sem casos ativos',
          subtitle: metrics.activeCases > 0
              ? '${metrics.activeCases} casos vinculados ao escritório'
              : 'Casos aceitos por advogados do escritório aparecerão aqui.',
          color: metrics.activeCases > 0
              ? colors.primary
              : colors.textSecondary,
        ),
        const SizedBox(height: 10),
        _TodayItem(
          icon: Icons.groups_outlined,
          title: 'Equipe ativa',
          subtitle:
              '${metrics.teamMembers} membros ativos vinculados ao escritório',
          color: colors.accent,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return JuriiPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      semanticLabel: label,
      child: Container(
        height: 84,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.card,
          border: Border.all(color: colors.officePurpleBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: colors.officePurple, size: 22),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final parsedValue = int.tryParse(value);
    final valueStyle = TextStyle(
      color: colors.textPrimary,
      fontSize: 20,
      fontWeight: FontWeight.w900,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.officePurpleBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colors.officePurpleSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: colors.officePurple, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                parsedValue == null
                    ? Text(value, style: valueStyle)
                    : JuriiAnimatedCounter(
                        value: parsedValue,
                        style: valueStyle,
                      ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayItem extends StatelessWidget {
  const _TodayItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.divider),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
