import 'package:flutter/material.dart';

import '../data/mock/mock_appointments.dart';
import '../models/appointment.dart';
import '../repositories/appointment_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../widgets/appointment_form_sheet.dart';
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

  bool get _isLawyer => widget.role == AppointmentRole.lawyer;

  /// Criar/editar só faz sentido para o advogado, na própria agenda, com
  /// Supabase ativo (o modo demo é somente leitura de mocks).
  bool get _canManage => _isLawyer && SupabaseConfig.isReady;

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

  void _reload() {
    setState(() => _appointmentsFuture = _loadAppointments());
  }

  Future<void> _createAppointment() async {
    final draft = await showAppointmentFormSheet(context);
    if (draft == null) return;

    try {
      await widget.repository.createAppointment(
        title: draft.title,
        startsAt: draft.startsAt,
        endsAt: draft.endsAt,
        location: draft.location,
        counterpartName: draft.counterpartName,
      );
      if (!mounted) return;
      _showSnack('Compromisso criado.');
      _reload();
    } catch (error) {
      if (!mounted) return;
      _showSnack(_friendlyError(error));
    }
  }

  Future<void> _editAppointment(Appointment appointment) async {
    final draft = await showAppointmentFormSheet(context, existing: appointment);
    if (draft == null) return;

    try {
      await widget.repository.updateAppointment(
        id: appointment.id,
        title: draft.title,
        startsAt: draft.startsAt,
        endsAt: draft.endsAt,
        location: draft.location,
        counterpartName: draft.counterpartName,
      );
      if (!mounted) return;
      _showSnack('Compromisso atualizado.');
      _reload();
    } catch (error) {
      if (!mounted) return;
      _showSnack(_friendlyError(error));
    }
  }

  Future<void> _cancelAppointment(Appointment appointment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar compromisso?'),
        content: Text('"${appointment.title}" será removido da sua agenda.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Voltar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: context.jColors.danger,
            ),
            child: const Text('Cancelar compromisso'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.repository.cancelAppointment(appointment.id);
      if (!mounted) return;
      _showSnack('Compromisso cancelado.');
      _reload();
    } catch (error) {
      if (!mounted) return;
      _showSnack(_friendlyError(error));
    }
  }

  Future<void> _showActions(Appointment appointment) async {
    final action = await showModalBottomSheet<_AppointmentAction>(
      context: context,
      builder: (context) {
        final colors = context.jColors;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.edit_outlined, color: colors.primary),
                title: const Text('Editar'),
                onTap: () =>
                    Navigator.of(context).pop(_AppointmentAction.edit),
              ),
              ListTile(
                leading: Icon(Icons.event_busy_outlined, color: colors.danger),
                title: Text(
                  'Cancelar compromisso',
                  style: TextStyle(color: colors.danger),
                ),
                onTap: () =>
                    Navigator.of(context).pop(_AppointmentAction.cancel),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    switch (action) {
      case _AppointmentAction.edit:
        await _editAppointment(appointment);
      case _AppointmentAction.cancel:
        await _cancelAppointment(appointment);
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('overlaps')) {
      return 'Você já tem um compromisso nesse horário.';
    }
    if (message.contains('end time must be after')) {
      return 'O término deve ser depois do início.';
    }
    if (message.contains('only lawyers')) {
      return 'Apenas advogados podem criar compromissos.';
    }
    return 'Não foi possível salvar o compromisso. Tente novamente.';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Agenda'),
        backgroundColor: colors.background,
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _createAppointment,
              icon: const Icon(Icons.add),
              label: const Text('Novo compromisso'),
            )
          : null,
      body: SafeArea(
        child: FutureBuilder<List<Appointment>>(
          future: _appointmentsFuture,
          builder: (context, snapshot) {
            final appointments = snapshot.data;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                _AgendaHero(isLawyer: _isLawyer),
                const SizedBox(height: 20),
                const _DateSelector(),
                const SizedBox(height: 24),
                Text(
                  _isLawyer ? 'Compromissos profissionais' : 'Seus compromissos',
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
                          onPressed: _reload,
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  )
                else if (appointments == null || appointments.isEmpty)
                  _EmptyAgendaState(isLawyer: _isLawyer)
                else
                  for (var index = 0; index < appointments.length; index++) ...[
                    JuriiStaggeredItem(
                      index: index,
                      child: _AppointmentCard(
                        appointment: appointments[index],
                        onTap: _canManage && appointments[index].isEditable
                            ? () => _showActions(appointments[index])
                            : null,
                      ),
                    ),
                    if (index < appointments.length - 1)
                      const SizedBox(height: 12),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _AppointmentAction { edit, cancel }

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
  final VoidCallback? onTap;

  const _AppointmentCard({required this.appointment, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final status = _statusStyle(appointment.status, colors);

    return JuriiListCard(
      onTap: onTap,
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
                  appointment.counterpartName.isEmpty
                      ? appointment.area.isEmpty
                            ? 'Compromisso'
                            : appointment.area
                      : '${appointment.counterpartName}'
                            '${appointment.area.isEmpty ? '' : ' · ${appointment.area}'}',
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
          if (onTap != null)
            Icon(Icons.more_vert, size: 18, color: colors.textSecondary),
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
      AppointmentStatus.cancelled => (
        color: colors.textSecondary,
        icon: Icons.event_busy_outlined,
        label: 'Cancelado',
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
          ? 'Toque em Novo compromisso para agendar seu primeiro atendimento, audiência ou prazo.'
          : 'Quando um atendimento for agendado, ele aparecerá aqui.',
    );
  }
}
