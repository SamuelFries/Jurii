import 'package:flutter/material.dart';

import '../models/firm_operation_metrics.dart';
import '../models/firm_workspace.dart';
import '../models/jurii_notification.dart';
import '../repositories/firm_workspace_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_theme.dart';
import '../widgets/notification_bell.dart';

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

    if (!SupabaseConfig.isReady || lawFirmId == null) {
      return FirmOperationMetrics.empty(teamMembers: localTeamCount);
    }

    try {
      return await widget.repository.fetchLawFirmOperationMetrics(lawFirmId);
    } catch (error) {
      debugPrint('Supabase firm operation metrics fetch failed: $error');
      return FirmOperationMetrics.empty(teamMembers: localTeamCount);
    }
  }

  Future<void> _reloadMetrics() async {
    final nextMetrics = _loadMetrics();
    setState(() {
      _metricsFuture = nextMetrics;
    });
    await nextMetrics;
  }

  @override
  Widget build(BuildContext context) {
    final workspaceName = widget.workspace?.firm.name ?? 'Escritório';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.officePurple,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.officePurple.withValues(alpha: 0.22),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.card.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.card.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Icon(
                    Icons.apartment_outlined,
                    color: AppTheme.card,
                  ),
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
                        style: const TextStyle(
                          color: AppTheme.card,
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
                        style: const TextStyle(
                          color: AppTheme.card,
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
                  iconColor: AppTheme.officePurple,
                  backgroundColor: AppTheme.card,
                  borderColor: AppTheme.officePurpleBorder,
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
          const Text(
            'Operação',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<FirmOperationMetrics>(
            future: _metricsFuture,
            builder: (context, snapshot) {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Hoje',
          style: TextStyle(
            color: AppTheme.textPrimary,
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
          color: AppTheme.officePurple,
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
              ? AppTheme.primary
              : AppTheme.textSecondary,
        ),
        const SizedBox(height: 10),
        _TodayItem(
          icon: Icons.groups_outlined,
          title: 'Equipe ativa',
          subtitle:
              '${metrics.teamMembers} membros ativos vinculados ao escritório',
          color: AppTheme.accent,
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
    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 84,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.officePurpleBorder),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppTheme.officePurple, size: 22),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        border: Border.all(color: AppTheme.officePurpleBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.officePurpleSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.officePurple, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        border: Border.all(color: AppTheme.divider),
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
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
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
