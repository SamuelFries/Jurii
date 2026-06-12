import 'package:flutter/material.dart';
import '../data/mock/mock_cases.dart';
import '../data/mock/mock_messages.dart';
import '../data/mock/mock_professional_profile.dart';
import '../models/firm_workspace.dart';
import '../models/lawyer_case.dart';
import '../models/user_profile.dart';
import '../theme/app_theme.dart';
import '../widgets/notification_bell.dart';

class LawyerHomeScreen extends StatelessWidget {
  final UserProfile user;
  final FirmWorkspace? workspace;
  final VoidCallback? onOpenMessages;
  final VoidCallback? onOpenCases;
  final VoidCallback? onOpenAgenda;
  final Future<void> Function()? onNotificationsChanged;

  const LawyerHomeScreen({
    super.key,
    required this.user,
    this.workspace,
    this.onOpenMessages,
    this.onOpenCases,
    this.onOpenAgenda,
    this.onNotificationsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final firstName = user.name.split(' ').first;

    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProfessionalHeader(
                firstName: firstName,
                oabNumber: user.oabNumber ?? 'OAB em revisão',
                firmName: workspace?.firm.name,
                onNotificationsChanged: onNotificationsChanged,
              ),
              const SizedBox(height: 20),
              _QuickActions(
                onOpenMessages: onOpenMessages,
                onOpenCases: onOpenCases,
                onOpenAgenda: onOpenAgenda,
              ),
              const SizedBox(height: 24),
              const _MetricsOverview(),
              const SizedBox(height: 24),
              const _TodayAgenda(),
              const SizedBox(height: 24),
              _PriorityCases(onOpenCases: onOpenCases),
              const SizedBox(height: 24),
              _NewContacts(onOpenMessages: onOpenMessages),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfessionalHeader extends StatelessWidget {
  final String firstName;
  final String oabNumber;
  final String? firmName;
  final Future<void> Function()? onNotificationsChanged;

  const _ProfessionalHeader({
    required this.firstName,
    required this.oabNumber,
    this.firmName,
    this.onNotificationsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.card.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.card.withValues(alpha: 0.24),
                  ),
                ),
                child: const Icon(
                  Icons.balance_outlined,
                  color: AppTheme.card,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bom dia, Dr. $firstName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.card,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      oabNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.card.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              NotificationBell(
                iconColor: AppTheme.primary,
                backgroundColor: AppTheme.card,
                borderColor: AppTheme.softBorder,
                onChanged: onNotificationsChanged,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const _StatusChip(
                icon: Icons.verified_outlined,
                label: 'Perfil verificado',
              ),
              const _StatusChip(icon: Icons.circle, label: 'Disponível hoje'),
              if (firmName != null && firmName!.trim().isNotEmpty)
                _StatusChip(icon: Icons.apartment_outlined, label: firmName!),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatusChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.card.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.card.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.card,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final VoidCallback? onOpenMessages;
  final VoidCallback? onOpenCases;
  final VoidCallback? onOpenAgenda;

  const _QuickActions({
    this.onOpenMessages,
    this.onOpenCases,
    this.onOpenAgenda,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.forum_outlined,
            label: 'Responder',
            onTap: onOpenMessages,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.folder_special_outlined,
            label: 'Casos',
            onTap: onOpenCases,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.calendar_month_outlined,
            label: 'Agenda',
            onTap: onOpenAgenda,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 82,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.lightBlueBorder),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppTheme.primary, size: 24),
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

class _MetricsOverview extends StatelessWidget {
  const _MetricsOverview();

  @override
  Widget build(BuildContext context) {
    final metrics = mockProfessionalMetrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Clientes'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                _MetricCard(
                  width: constraints.maxWidth,
                  icon: Icons.work_outline,
                  label: 'Casos ativos',
                  value: '${metrics.activeCases}',
                  accentColor: AppTheme.primary,
                ),
                const SizedBox(height: 10),
                _MetricCard(
                  width: constraints.maxWidth,
                  icon: Icons.mark_chat_unread_outlined,
                  label: 'Novos contatos',
                  value: '${metrics.newContacts}',
                  accentColor: AppTheme.accent,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final double width;
  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;

  const _MetricCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.lightBlueBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: accentColor, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
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

class _TodayAgenda extends StatelessWidget {
  const _TodayAgenda();

  @override
  Widget build(BuildContext context) {
    final attention = mockAttentionSummary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Hoje'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.lightBlueBorder),
          ),
          child: Column(
            children: [
              _AttentionRow(
                icon: Icons.chat_bubble_outline,
                label: 'Mensagens pendentes',
                value: '${attention.pendingMessages}',
                color: AppTheme.primary,
              ),
              const SizedBox(height: 12),
              _AttentionRow(
                icon: Icons.video_call_outlined,
                label: 'Reuniões agendadas',
                value: '${attention.meetingsToday}',
                color: AppTheme.accent,
              ),
              const SizedBox(height: 12),
              _AttentionRow(
                icon: Icons.timer_outlined,
                label: 'Prazo crítico',
                value: '${attention.upcomingDeadlines}',
                color: AppTheme.danger,
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: AppTheme.divider),
              const SizedBox(height: 14),
              for (
                var index = 0;
                index < mockTodaySchedule.length;
                index++
              ) ...[
                _ScheduleItem(item: mockTodaySchedule[index]),
                if (index < mockTodaySchedule.length - 1)
                  const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AttentionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _AttentionRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 32),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _ScheduleItem extends StatelessWidget {
  final ({String time, String title, String subtitle, String type}) item;

  const _ScheduleItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.type) {
      'video' => Icons.video_call_outlined,
      'deadline' => Icons.assignment_late_outlined,
      _ => Icons.forum_outlined,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 46,
          child: Text(
            item.time,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppTheme.lightBlue,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PriorityCases extends StatelessWidget {
  final VoidCallback? onOpenCases;

  const _PriorityCases({this.onOpenCases});

  @override
  Widget build(BuildContext context) {
    final cases = mockLawyerCases.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Casos prioritários', onTap: onOpenCases),
        const SizedBox(height: 12),
        for (var index = 0; index < cases.length; index++) ...[
          _PriorityCaseCard(lawyerCase: cases[index], onTap: onOpenCases),
          if (index < cases.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _PriorityCaseCard extends StatelessWidget {
  final LawyerCase lawyerCase;
  final VoidCallback? onTap;

  const _PriorityCaseCard({required this.lawyerCase, this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = _caseStatus(lawyerCase.status);

    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.lightBlueBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    lawyerCase.clientInitials,
                    style: TextStyle(
                      color: status.color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lawyerCase.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${lawyerCase.clientName} · ${lawyerCase.area}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Icon(status.icon, color: status.color, size: 14),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            lawyerCase.lastUpdate,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: status.color,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  ({Color color, IconData icon}) _caseStatus(LawyerCaseStatus status) {
    return switch (status) {
      LawyerCaseStatus.newMessage => (
        color: AppTheme.primary,
        icon: Icons.mark_chat_unread_outlined,
      ),
      LawyerCaseStatus.deadline => (
        color: AppTheme.danger,
        icon: Icons.timer_outlined,
      ),
      LawyerCaseStatus.updated => (
        color: AppTheme.success,
        icon: Icons.check_circle_outline,
      ),
    };
  }
}

class _NewContacts extends StatelessWidget {
  final VoidCallback? onOpenMessages;

  const _NewContacts({this.onOpenMessages});

  @override
  Widget build(BuildContext context) {
    final contacts = mockLawyerContacts.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Novos contatos', onTap: onOpenMessages),
        const SizedBox(height: 12),
        Material(
          color: AppTheme.card,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppTheme.lightBlueBorder),
          ),
          child: Column(
            children: [
              for (var index = 0; index < contacts.length; index++) ...[
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: AppTheme.lightGold,
                    child: Text(
                      contacts[index].initials,
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  title: Text(
                    contacts[index].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    contacts[index].description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppTheme.textSecondary,
                  ),
                  onTap: onOpenMessages,
                ),
                if (index < contacts.length - 1)
                  const Divider(height: 1, indent: 68, color: AppTheme.divider),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onTap;

  const _SectionHeader({required this.title, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (onTap != null)
          TextButton(
            onPressed: onTap,
            child: const Text(
              'Ver tudo',
              style: TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }
}
