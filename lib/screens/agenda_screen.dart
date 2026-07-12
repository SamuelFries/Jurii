import 'package:flutter/material.dart';

import '../data/mock/mock_appointments.dart';
import '../models/appointment.dart';
import '../repositories/appointment_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../widgets/jurii_empty_state.dart';
import '../widgets/jurii_list_card.dart';
import '../widgets/jurii_motion.dart';

class AgendaScreen extends StatefulWidget {
  final AppointmentRole role;
  final AppointmentRepository repository;

  const AgendaScreen({
    super.key,
    required this.role,
    this.repository = const AppointmentRepository(),
  });

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  late Future<List<Appointment>> _appointmentsFuture;

  @override
  void initState() {
    super.initState();
    _appointmentsFuture = _loadAppointments();
  }

  Future<List<Appointment>> _loadAppointments() async {
    final fallback = widget.role == AppointmentRole.lawyer
        ? mockLawyerAppointments
        : mockClientAppointments;

    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return fallback;
    }

    try {
      return await widget.repository.fetchAppointments(widget.role);
    } catch (error) {
      debugPrint('Supabase appointments fetch failed: $error');
      rethrow;
    }
  }

  void _retry() {
    setState(() => _appointmentsFuture = _loadAppointments());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final isLawyer = widget.role == AppointmentRole.lawyer;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Agenda'),
        backgroundColor: colors.background,
      ),
      body: SafeArea(
        child: FutureBuilder<List<Appointment>>(
          future: _appointmentsFuture,
          builder: (context, snapshot) {
            final appointments = snapshot.data;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                _AgendaHero(isLawyer: isLawyer),
                const SizedBox(height: 20),
                const _DateSelector(),
                const SizedBox(height: 24),
                Text(
                  isLawyer ? 'Compromissos profissionais' : 'Seus compromissos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    appointments == null)
                  const JuriiSkeletonList(itemCount: 3, itemHeight: 112)
                else if (snapshot.hasError && appointments == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      children: [
                        Text(
                          'Não foi possível carregar seus compromissos.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _retry,
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  )
                else if (appointments == null || appointments.isEmpty)
                  _EmptyAgendaState(isLawyer: isLawyer)
                else
                  for (var index = 0; index < appointments.length; index++) ...[
                    JuriiStaggeredItem(
                      index: index,
                      child: _AppointmentCard(appointment: appointments[index]),
                    ),
                    if (index < appointments.length - 1)
                      const SizedBox(height: 12),
                  ],
                const SizedBox(height: 24),
                _AvailabilityCard(isLawyer: isLawyer),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AgendaHero extends StatelessWidget {
  final bool isLawyer;

  const _AgendaHero({required this.isLawyer});

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.card.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.calendar_month_outlined, color: colors.card),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLawyer
                      ? 'Organize seus atendimentos'
                      : 'Acompanhe suas reuniões',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.card,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isLawyer
                      ? 'Consultas, prazos e retornos em uma visão clara.'
                      : 'Veja horários confirmados e pendências de envio.',
                  style: TextStyle(
                    color: colors.card.withValues(alpha: 0.72),
                    height: 1.35,
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

class _DateSelector extends StatelessWidget {
  const _DateSelector();

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final now = DateTime.now();
    final days = List.generate(4, (index) {
      final date = now.add(Duration(days: index));
      return (
        label: switch (index) {
          0 => 'Hoje',
          1 => 'Amanhã',
          _ => _weekdayLabel(date.weekday),
        },
        day: date.day.toString().padLeft(2, '0'),
      );
    });

    return Row(
      children: [
        for (var index = 0; index < days.length; index++) ...[
          Expanded(
            child: Container(
              height: 68,
              decoration: BoxDecoration(
                color: index == 0 ? colors.lightGold : colors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: index == 0
                      ? colors.lightGoldBorder
                      : colors.lightBlueBorder,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    days[index].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: index == 0 ? colors.accent : colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    days[index].day,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (index < days.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }

  String _weekdayLabel(int weekday) {
    return const {
      DateTime.monday: 'Seg',
      DateTime.tuesday: 'Ter',
      DateTime.wednesday: 'Qua',
      DateTime.thursday: 'Qui',
      DateTime.friday: 'Sex',
      DateTime.saturday: 'Sáb',
      DateTime.sunday: 'Dom',
    }[weekday]!;
  }
}

class _AppointmentCard extends StatelessWidget {
  final Appointment appointment;

  const _AppointmentCard({required this.appointment});

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final status = _statusStyle(appointment.status, colors);

    // Sem onTap: o card ainda não tem ação; ripple em card inerte confunde.
    return JuriiListCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            child: Text(
              appointment.timeLabel,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: status.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(status.icon, color: status.color, size: 21),
          ),
          const SizedBox(width: 12),
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
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${appointment.counterpartName} · ${appointment.area}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _Pill(label: appointment.dateLabel),
                    _Pill(label: appointment.location),
                    _Pill(label: status.label, color: status.color),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ({Color color, IconData icon, String label}) _statusStyle(
    AppointmentStatus status,
    AppColors colors,
  ) {
    return switch (status) {
      AppointmentStatus.confirmed => (
        color: colors.success,
        icon: Icons.check_circle_outline,
        label: 'Confirmado',
      ),
      AppointmentStatus.pending => (
        color: colors.warning,
        icon: Icons.schedule_outlined,
        label: 'Pendente',
      ),
      AppointmentStatus.done => (
        color: colors.textSecondary,
        icon: Icons.done_all,
        label: 'Concluído',
      ),
    };
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color? color;

  const _Pill({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final pillColor = color ?? colors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: pillColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: pillColor,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyAgendaState extends StatelessWidget {
  const _EmptyAgendaState({required this.isLawyer});

  final bool isLawyer;

  @override
  Widget build(BuildContext context) {
    return JuriiEmptyState(
      icon: Icons.calendar_today_outlined,
      title: isLawyer ? 'Agenda profissional livre' : 'Nenhum compromisso',
      message: isLawyer
          ? 'Quando houver compromissos profissionais, eles aparecerão aqui.'
          : 'Quando um atendimento for agendado, ele aparecerá aqui.',
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  final bool isLawyer;

  const _AvailabilityCard({required this.isLawyer});

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.warningSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.warningBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.tune_outlined, color: colors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isLawyer
                  ? 'Disponibilidade editável será conectada ao backend na próxima etapa.'
                  : 'Reagendamentos e confirmações serão ativados na integração.',
              style: TextStyle(
                color: colors.warningText,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
