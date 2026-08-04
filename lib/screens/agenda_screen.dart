import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/mock/mock_appointments.dart';
import '../models/appointment.dart';
import '../repositories/appointment_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../utils/agenda_sections.dart';
import '../widgets/appointment_form_sheet.dart';
import '../widgets/calendar_sync_sheet.dart';
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
  // Estado explicito (em vez de FutureBuilder) para o realtime atualizar a lista
  // sem piscar o skeleton a cada evento.
  List<Appointment>? _appointments;
  bool _loadFailed = false;
  RealtimeChannel? _channel;
  bool _hasSubscribedOnce = false;

  /// Visão atual: próximos (padrão) ou anteriores. O corte é feito no fetch
  /// (início de hoje), não em memória — o histórico não viaja à toa.
  bool _showPast = false;

  /// Geração do fetch: cada disparo incrementa; respostas de gerações
  /// antigas são descartadas. Sem isso, alternar de aba com um fetch em
  /// voo pintaria a lista de PRÓXIMOS sob o rótulo de Anteriores (ou o
  /// contrário) quando a resposta atrasada chegasse por último.
  int _loadGeneration = 0;

  /// Dia para o qual o corte do fetch valeu. Se um rebuild acontecer depois
  /// da meia-noite, o corte ficou velho — recarrega em silêncio.
  DateTime _fetchDay = DateTime.now();

  bool get _isLawyer => widget.role == AppointmentRole.lawyer;

  /// Criar/editar só faz sentido para o advogado, na própria agenda, com
  /// Supabase ativo (o modo demo é somente leitura de mocks).
  bool get _canManage => _isLawyer && SupabaseConfig.isReady;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null && SupabaseConfig.isReady) {
      SupabaseConfig.client.removeChannel(channel);
    }
    super.dispose();
  }

  Future<List<Appointment>> _fetchOrMock() {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      // Demo só tem futuro: os mocks são Hoje/Amanhã, então Anteriores fica
      // vazio — o que também é o estado honesto.
      if (_showPast) return Future.value(const <Appointment>[]);
      return Future.value(
        _isLawyer ? mockLawyerAppointments : mockClientAppointments,
      );
    }
    return widget.repository.fetchAppointments(widget.role, past: _showPast);
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() => _loadFailed = false);
    try {
      final list = await _fetchOrMock();
      if (!mounted || generation != _loadGeneration) return;
      _fetchDay = DateTime.now();
      setState(() => _appointments = list);
    } catch (error) {
      debugPrint('Supabase appointments fetch failed: $error');
      if (!mounted || generation != _loadGeneration) return;
      // Só vira tela de erro se nunca carregou; com dados na tela, mantém.
      setState(() => _loadFailed = _appointments == null);
    }
  }

  /// Recarrega mantendo a lista atual visível (sem skeleton). Usado pelo
  /// realtime e depois de criar/editar/cancelar.
  Future<void> _reloadSilently() async {
    final generation = ++_loadGeneration;
    try {
      final list = await _fetchOrMock();
      if (!mounted || generation != _loadGeneration) return;
      _fetchDay = DateTime.now();
      setState(() {
        _appointments = list;
        _loadFailed = false;
      });
    } catch (error) {
      debugPrint('Supabase appointments reload failed: $error');
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _subscribeToRealtime() {
    final userId = SupabaseConfig.isReady
        ? SupabaseConfig.client.auth.currentUser?.id
        : null;
    if (userId == null) return;

    // RLS ja restringe as linhas ao usuario; o filtro por coluna corta o
    // trafego para so o que interessa nesta agenda (advogado x cliente).
    final column = _isLawyer ? 'lawyer_id' : 'client_id';

    _channel = SupabaseConfig.client
        .channel('agenda_appointments:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'appointments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: column,
            value: userId,
          ),
          callback: (_) => unawaited(_reloadSilently()),
        )
        .subscribe((status, [error]) {
          // Reassinou depois de uma queda: refaz o fetch para não perder o que
          // mudou enquanto o canal esteve fora.
          if (status == RealtimeSubscribeStatus.subscribed) {
            if (_hasSubscribedOnce) unawaited(_reloadSilently());
            _hasSubscribedOnce = true;
          }
        });
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
      _reloadSilently();
    } catch (error) {
      if (!mounted) return;
      _showSnack(_friendlyError(error));
    }
  }

  Future<void> _editAppointment(Appointment appointment) async {
    final draft = await showAppointmentFormSheet(
      context,
      existing: appointment,
    );
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
      _reloadSilently();
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
      _reloadSilently();
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
                onTap: () => Navigator.of(context).pop(_AppointmentAction.edit),
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

  void _setShowPast(bool value) {
    if (_showPast == value) return;
    setState(() {
      _showPast = value;
      // A lista trocou de natureza: skeleton de novo em vez de exibir os
      // próximos sob o rótulo de anteriores enquanto o fetch corre.
      _appointments = null;
      _loadFailed = false;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Agenda'),
        backgroundColor: colors.background,
        actions: [
          if (_canManage)
            IconButton(
              onPressed: () => showCalendarSyncSheet(context),
              icon: const Icon(Icons.calendar_month_outlined),
              tooltip: 'Sincronizar com meu calendário',
            ),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _createAppointment,
              icon: const Icon(Icons.add),
              label: const Text('Novo compromisso'),
            )
          : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            // Resumo com dado real no lugar de copy de vitrine. Só na visão
            // de próximos e só com a lista carregada — durante o skeleton um
            // "nenhum compromisso hoje" seria chute.
            if (!_showPast && _appointments != null) ...[
              _AgendaSummaryCard(
                summary: agendaSummary(
                  _appointments!,
                  now: DateTime.now(),
                  isLawyer: _isLawyer,
                ),
              ),
              const SizedBox(height: 20),
            ],
            Text(
              _isLawyer ? 'Compromissos profissionais' : 'Seus compromissos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _PeriodToggle(showPast: _showPast, onChanged: _setShowPast),
            const SizedBox(height: 4),
            ..._buildList(colors),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildList(AppColors colors) {
    final appointments = _appointments;

    // Virada de meia-noite com a tela aberta: o corte do fetch ficou de
    // ontem e os rótulos reclassificariam ("ONTEM" dentro de Próximos).
    // Marca o dia já aqui para não reagendar a cada rebuild.
    final now = DateTime.now();
    if (appointments != null && !_sameDay(now, _fetchDay)) {
      _fetchDay = now;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reloadSilently();
      });
    }

    if (appointments == null && !_loadFailed) {
      return const [JuriiSkeletonList(itemCount: 3, itemHeight: 112)];
    }

    if (_loadFailed && appointments == null) {
      return [
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
                onPressed: _load,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ];
    }

    if (appointments == null || appointments.isEmpty) {
      return [_EmptyAgendaState(isLawyer: _isLawyer, showPast: _showPast)];
    }

    // Cabeçalho por dia (HOJE, AMANHÃ, SEX · 07/08): a lista responde "o que
    // eu tenho e quando" sem o leitor caçar a data pill a pill.
    final sections = buildAgendaSections(appointments, now: DateTime.now());
    final widgets = <Widget>[];
    var index = 0;
    for (final section in sections) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
          child: Text(
            section.label.toUpperCase(),
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ),
      );
      for (final appointment in section.appointments) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: JuriiStaggeredItem(
              index: index,
              child: _AppointmentCard(
                appointment: appointment,
                // Histórico é só leitura: editar um compromisso passado
                // estoura o assert do showDatePicker (initialDate < firstDate)
                // e cancelar apagaria o registro do próprio histórico (o
                // fetch filtra status cancelled).
                onTap: !_showPast && _canManage && appointment.isEditable
                    ? () => _showActions(appointment)
                    : null,
              ),
            ),
          ),
        );
        index++;
      }
    }

    // Bateu o teto do fetch: dizer que o corte existe. Sem isto, o 101º
    // compromisso simplesmente não existiria em visão nenhuma e o usuário
    // concluiria que nunca foi marcado.
    if (appointments.length >= AppointmentRepository.fetchLimit) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            _showPast
                ? 'Mostrando os ${AppointmentRepository.fetchLimit} mais recentes.'
                : 'Mostrando os próximos ${AppointmentRepository.fetchLimit} compromissos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
        ),
      );
    }
    return widgets;
  }
}

/// Alterna entre a agenda que vem (padrão) e o histórico. Duas pílulas no
/// estilo dos chips da casa; o dia selecionado usa o dourado de destaque.
class _PeriodToggle extends StatelessWidget {
  final bool showPast;
  final ValueChanged<bool> onChanged;

  const _PeriodToggle({required this.showPast, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    Widget pill({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: InkWell(
            // A pílula já selecionada não é acionável: sem ripple mentindo
            // que o toque fez alguma coisa.
            onTap: selected ? null : onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              // 48dp: mínimo de alvo de toque do Material.
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? colors.lightGold : colors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? colors.lightGoldBorder
                      : colors.lightBlueBorder,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? colors.accent : colors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        pill(
          label: 'Próximos',
          selected: !showPast,
          onTap: () => onChanged(false),
        ),
        const SizedBox(width: 8),
        pill(
          label: 'Anteriores',
          selected: showPast,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }
}

enum _AppointmentAction { edit, cancel }

/// Cartão de resumo: mesmo visual do antigo hero, mas com dado real
/// (contagem de hoje + próximo compromisso) no lugar de copy fixa.
class _AgendaSummaryCard extends StatelessWidget {
  final ({String title, String subtitle}) summary;

  const _AgendaSummaryCard({required this.summary});

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
                  summary.title,
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
                  summary.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
                // Sem pill de data: o cabeçalho da seção (HOJE, AMANHÃ...)
                // já diz o dia — repetir em cada card era o que a escondia.
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
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
  const _EmptyAgendaState({required this.isLawyer, required this.showPast});

  final bool isLawyer;
  final bool showPast;

  @override
  Widget build(BuildContext context) {
    if (showPast) {
      return const JuriiEmptyState(
        icon: Icons.history,
        title: 'Nenhum compromisso anterior',
        message: 'Compromissos que já aconteceram aparecerão aqui.',
      );
    }
    return JuriiEmptyState(
      icon: Icons.calendar_today_outlined,
      title: isLawyer ? 'Agenda profissional livre' : 'Nenhum compromisso',
      message: isLawyer
          ? 'Toque em Novo compromisso para agendar seu primeiro atendimento, audiência ou prazo.'
          : 'Quando um atendimento for agendado, ele aparecerá aqui.',
    );
  }
}
