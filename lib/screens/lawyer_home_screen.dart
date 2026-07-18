import 'package:flutter/material.dart';
import '../models/appointment.dart';
import '../models/conversation.dart';
import '../models/firm_workspace.dart';
import '../models/jurii_notification.dart';
import '../models/lawyer_case.dart';
import '../models/user_profile.dart';
import '../repositories/appointment_repository.dart';
import '../repositories/case_repository.dart';
import '../repositories/messaging_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../widgets/jurii_list_card.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/notification_bell.dart';
import '../widgets/profile_avatar.dart';

class LawyerHomeScreen extends StatefulWidget {
  final UserProfile user;
  final FirmWorkspace? workspace;
  final CaseRepository caseRepository;
  final MessagingRepository messagingRepository;
  final AppointmentRepository appointmentRepository;
  final VoidCallback? onOpenMessages;
  final VoidCallback? onOpenCases;
  final VoidCallback? onOpenAgenda;
  final Future<void> Function()? onNotificationsChanged;

  const LawyerHomeScreen({
    super.key,
    required this.user,
    this.workspace,
    this.caseRepository = const CaseRepository(),
    this.messagingRepository = const MessagingRepository(),
    this.appointmentRepository = const AppointmentRepository(),
    this.onOpenMessages,
    this.onOpenCases,
    this.onOpenAgenda,
    this.onNotificationsChanged,
  });

  @override
  State<LawyerHomeScreen> createState() => _LawyerHomeScreenState();
}

class _LawyerHomeScreenState extends State<LawyerHomeScreen> {
  late Future<List<LawyerCase>> _activeCasesFuture;
  late Future<List<Conversation>> _newContactsFuture;
  late Future<List<Appointment>> _todayAppointmentsFuture;

  @override
  void initState() {
    super.initState();
    _activeCasesFuture = _loadActiveCases();
    _newContactsFuture = _loadNewContacts();
    _todayAppointmentsFuture = _loadTodayAppointments();
  }

  @override
  void didUpdateWidget(covariant LawyerHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.caseRepository != widget.caseRepository) {
      _activeCasesFuture = _loadActiveCases();
    }
    if (oldWidget.messagingRepository != widget.messagingRepository) {
      _newContactsFuture = _loadNewContacts();
    }
    if (oldWidget.appointmentRepository != widget.appointmentRepository) {
      _todayAppointmentsFuture = _loadTodayAppointments();
    }
  }

  Future<List<Appointment>> _loadTodayAppointments() async {
    if (!SupabaseConfig.isReady) return const [];

    try {
      final appointments = await widget.appointmentRepository.fetchAppointments(
        AppointmentRole.lawyer,
      );
      return appointments
          .where(
            (appointment) =>
                appointment.dateLabel == 'Hoje' &&
                appointment.status != AppointmentStatus.done,
          )
          .toList(growable: false);
    } catch (error) {
      debugPrint('Supabase lawyer today appointments fetch failed: $error');
      return const [];
    }
  }

  Future<List<LawyerCase>> _loadActiveCases() async {
    try {
      final cases = await widget.caseRepository.fetchLawyerCases();

      if (cases.isNotEmpty || SupabaseConfig.isReady) {
        return cases;
      }
    } catch (error) {
      debugPrint('Supabase lawyer active cases fetch failed: $error');
      if (SupabaseConfig.isReady) return const [];
    }

    return const [];
  }

  Future<List<Conversation>> _loadNewContacts() async {
    try {
      final conversations = await widget.messagingRepository.fetchConversations(
        scope: ConversationScope.lawyer,
      );

      if (conversations.isNotEmpty || SupabaseConfig.isReady) {
        return conversations;
      }
    } catch (error) {
      debugPrint('Supabase lawyer contacts fetch failed: $error');
      if (SupabaseConfig.isReady) return const [];
    }

    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final firstName = widget.user.name.split(' ').first;

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
                oabNumber: widget.user.oabNumber ?? 'OAB em revisão',
                firmName: widget.workspace?.firm.name,
                onNotificationsChanged: widget.onNotificationsChanged,
              ),
              const SizedBox(height: 20),
              _QuickActions(
                onOpenMessages: widget.onOpenMessages,
                onOpenCases: widget.onOpenCases,
                onOpenAgenda: widget.onOpenAgenda,
              ),
              const SizedBox(height: 24),
              _MetricsOverview(
                activeCasesFuture: _activeCasesFuture,
                newContactsFuture: _newContactsFuture,
              ),
              const SizedBox(height: 24),
              _TodayAgenda(
                appointmentsFuture: _todayAppointmentsFuture,
                activeCasesFuture: _activeCasesFuture,
                conversationsFuture: _newContactsFuture,
                onOpenAgenda: widget.onOpenAgenda,
              ),
              const SizedBox(height: 24),
              _PriorityCases(
                casesFuture: _activeCasesFuture,
                onOpenCases: widget.onOpenCases,
              ),
              const SizedBox(height: 24),
              _NewContacts(
                conversationsFuture: _newContactsFuture,
                onOpenMessages: widget.onOpenMessages,
              ),
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
    final colors = context.jColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: colors.softShadow,
            blurRadius: 18,
            offset: const Offset(0, 10),
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
                  color: colors.card.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colors.card.withValues(alpha: 0.24),
                  ),
                ),
                child: Icon(
                  Icons.balance_outlined,
                  color: colors.card,
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
                      style: TextStyle(
                        color: colors.card,
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
                        color: colors.card.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              NotificationBell(
                scope: NotificationScope.lawyer,
                iconColor: colors.primary,
                backgroundColor: colors.card,
                borderColor: colors.softBorder,
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
          // lightGold (não accent): sobre o header primary, accent some no
          // tema escuro (dourado e azul-claro têm a mesma luminância).
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
    final colors = context.jColors;
    return JuriiPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      semanticLabel: label,
      child: Container(
        height: 82,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.lightBlueBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: colors.primary, size: 24),
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

class _MetricsOverview extends StatelessWidget {
  final Future<List<LawyerCase>> activeCasesFuture;
  final Future<List<Conversation>> newContactsFuture;

  const _MetricsOverview({
    required this.activeCasesFuture,
    required this.newContactsFuture,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Clientes'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                FutureBuilder<List<LawyerCase>>(
                  future: activeCasesFuture,
                  builder: (context, snapshot) {
                    final activeCasesValue = snapshot.hasData
                        ? '${snapshot.data!.length}'
                        : '...';

                    return _MetricCard(
                      width: constraints.maxWidth,
                      icon: Icons.work_outline,
                      label: 'Casos ativos',
                      value: activeCasesValue,
                      accentColor: context.jColors.primary,
                    );
                  },
                ),
                const SizedBox(height: 10),
                FutureBuilder<List<Conversation>>(
                  future: newContactsFuture,
                  builder: (context, snapshot) {
                    final newContactsValue = snapshot.hasData
                        ? '${snapshot.data!.length}'
                        : '...';

                    return _MetricCard(
                      width: constraints.maxWidth,
                      icon: Icons.mark_chat_unread_outlined,
                      label: 'Novos contatos',
                      value: newContactsValue,
                      accentColor: context.jColors.accent,
                    );
                  },
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
    final colors = context.jColors;
    final parsedValue = int.tryParse(value);
    final valueStyle = TextStyle(
      color: colors.textPrimary,
      fontSize: 20,
      fontWeight: FontWeight.w900,
    );

    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.lightBlueBorder),
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
                  parsedValue == null
                      ? Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: valueStyle,
                        )
                      : JuriiAnimatedCounter(
                          value: parsedValue,
                          style: valueStyle,
                        ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
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
  const _TodayAgenda({
    required this.appointmentsFuture,
    required this.activeCasesFuture,
    required this.conversationsFuture,
    this.onOpenAgenda,
  });

  final Future<List<Appointment>> appointmentsFuture;
  final Future<List<LawyerCase>> activeCasesFuture;
  final Future<List<Conversation>> conversationsFuture;
  final VoidCallback? onOpenAgenda;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Hoje', onTap: onOpenAgenda),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.lightBlueBorder),
          ),
          child: FutureBuilder<List<Object>>(
            future: Future.wait<Object>([
              appointmentsFuture,
              activeCasesFuture,
              conversationsFuture,
            ]),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const JuriiSkeletonList(
                  itemCount: 3,
                  itemHeight: 36,
                  gap: 12,
                );
              }

              final data = snapshot.data;
              final appointments = data == null
                  ? const <Appointment>[]
                  : data[0] as List<Appointment>;
              final cases = data == null
                  ? const <LawyerCase>[]
                  : data[1] as List<LawyerCase>;
              final conversations = data == null
                  ? const <Conversation>[]
                  : data[2] as List<Conversation>;
              final deadlineCases = cases
                  .where((item) => item.status == LawyerCaseStatus.deadline)
                  .length;

              return Column(
                children: [
                  _AttentionRow(
                    icon: Icons.chat_bubble_outline,
                    label: 'Conversas ativas',
                    value: '${conversations.length}',
                    color: colors.primary,
                  ),
                  const SizedBox(height: 12),
                  _AttentionRow(
                    icon: Icons.video_call_outlined,
                    label: 'Compromissos hoje',
                    value: '${appointments.length}',
                    color: colors.accent,
                  ),
                  const SizedBox(height: 12),
                  _AttentionRow(
                    icon: Icons.timer_outlined,
                    label: 'Casos com prazo',
                    value: '$deadlineCases',
                    color: colors.danger,
                  ),
                  const SizedBox(height: 16),
                  Divider(height: 1, color: colors.divider),
                  const SizedBox(height: 14),
                  if (appointments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Nenhum compromisso para hoje.',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    for (
                      var index = 0;
                      index < appointments.length;
                      index++
                    ) ...[
                      _ScheduleItem(appointment: appointments[index]),
                      if (index < appointments.length - 1)
                        const SizedBox(height: 12),
                    ],
                ],
              );
            },
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
    final parsedValue = int.tryParse(value);

    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: context.jColors.textPrimary,
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
          child: parsedValue == null
              ? Text(
                  value,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                )
              : JuriiAnimatedCounter(
                  value: parsedValue,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
        ),
      ],
    );
  }
}

class _ScheduleItem extends StatelessWidget {
  final Appointment appointment;

  const _ScheduleItem({required this.appointment});

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final icon = appointment.status == AppointmentStatus.confirmed
        ? Icons.video_call_outlined
        : Icons.schedule_outlined;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 46,
          child: Text(
            appointment.timeLabel,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colors.lightBlue,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: colors.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appointment.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${appointment.counterpartName} · ${appointment.area}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textSecondary,
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
  final Future<List<LawyerCase>> casesFuture;
  final VoidCallback? onOpenCases;

  const _PriorityCases({required this.casesFuture, this.onOpenCases});

  /// Prioriza prazos, depois casos com mensagem nova, depois os demais.
  static int _priorityRank(LawyerCaseStatus status) => switch (status) {
    LawyerCaseStatus.deadline => 0,
    LawyerCaseStatus.newMessage => 1,
    LawyerCaseStatus.updated => 2,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return FutureBuilder<List<LawyerCase>>(
      future: casesFuture,
      builder: (context, snapshot) {
        final allCases = snapshot.data ?? const <LawyerCase>[];
        final cases = [...allCases]
          ..sort(
            (a, b) =>
                _priorityRank(a.status).compareTo(_priorityRank(b.status)),
          );
        final topCases = cases.take(3).toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title: 'Casos prioritários', onTap: onOpenCases),
            const SizedBox(height: 12),
            if (snapshot.connectionState == ConnectionState.waiting)
              const JuriiSkeletonList(itemCount: 2, itemHeight: 92, gap: 10)
            else if (topCases.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.lightBlueBorder),
                ),
                child: Text(
                  'Nenhum caso ativo no momento. Novos casos aceitos pelos '
                  'clientes aparecem aqui.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              for (var index = 0; index < topCases.length; index++) ...[
                _PriorityCaseCard(
                  lawyerCase: topCases[index],
                  onTap: onOpenCases,
                ),
                if (index < topCases.length - 1) const SizedBox(height: 10),
              ],
          ],
        );
      },
    );
  }
}

class _PriorityCaseCard extends StatelessWidget {
  final LawyerCase lawyerCase;
  final VoidCallback? onTap;

  const _PriorityCaseCard({required this.lawyerCase, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final status = _caseStatus(lawyerCase.status, colors);

    return JuriiListCard(
      onTap: onTap,
      semanticLabel: lawyerCase.title,
      borderRadius: 8,
      padding: const EdgeInsets.all(14),
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
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${lawyerCase.clientName} · ${lawyerCase.area}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
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
          Icon(Icons.chevron_right, color: colors.textSecondary),
        ],
      ),
    );
  }

  ({Color color, IconData icon}) _caseStatus(
    LawyerCaseStatus status,
    AppColors colors,
  ) {
    return switch (status) {
      LawyerCaseStatus.newMessage => (
        color: colors.primary,
        icon: Icons.mark_chat_unread_outlined,
      ),
      LawyerCaseStatus.deadline => (
        color: colors.danger,
        icon: Icons.timer_outlined,
      ),
      LawyerCaseStatus.updated => (
        color: colors.success,
        icon: Icons.check_circle_outline,
      ),
    };
  }
}

class _NewContacts extends StatelessWidget {
  final Future<List<Conversation>> conversationsFuture;
  final VoidCallback? onOpenMessages;

  const _NewContacts({required this.conversationsFuture, this.onOpenMessages});

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Novos contatos', onTap: onOpenMessages),
        const SizedBox(height: 12),
        FutureBuilder<List<Conversation>>(
          future: conversationsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const _NewContactsLoadingCard();
            }

            final contacts = (snapshot.data ?? const <Conversation>[])
                .take(3)
                .toList();

            if (contacts.isEmpty) {
              return const _EmptyNewContactsCard();
            }

            return Material(
              color: colors.card,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: colors.lightBlueBorder),
              ),
              child: Column(
                children: [
                  for (var index = 0; index < contacts.length; index++) ...[
                    _NewContactTile(
                      conversation: contacts[index],
                      onTap: onOpenMessages,
                    ),
                    if (index < contacts.length - 1)
                      Divider(height: 1, indent: 68, color: colors.divider),
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

class _NewContactTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback? onTap;

  const _NewContactTile({required this.conversation, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: ProfileAvatar(
        imageUrl: conversation.avatarUrl,
        initials: conversation.initials,
        size: 40,
        backgroundColor: colors.lightGold,
        foregroundColor: colors.accent,
        borderRadius: BorderRadius.circular(20),
      ),
      title: Text(
        conversation.officeName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        _description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(Icons.chevron_right, color: colors.textSecondary),
      onTap: onTap,
    );
  }

  String get _description {
    if (conversation.specialty.trim().isNotEmpty) {
      return conversation.specialty;
    }
    return conversation.lastMessage;
  }
}

class _NewContactsLoadingCard extends StatelessWidget {
  const _NewContactsLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const JuriiSkeletonList(itemCount: 2, itemHeight: 64, gap: 10);
  }
}

class _EmptyNewContactsCard extends StatelessWidget {
  const _EmptyNewContactsCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.lightBlueBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Nenhum novo contato recebido no momento.',
        style: TextStyle(
          color: colors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onTap;

  const _SectionHeader({required this.title, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (onTap != null)
          TextButton(
            onPressed: onTap,
            child: Text(
              'Ver tudo',
              style: TextStyle(
                color: colors.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }
}
