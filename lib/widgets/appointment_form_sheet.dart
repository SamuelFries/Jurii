import 'package:flutter/material.dart';

import '../models/appointment.dart';
import '../theme/app_colors.dart';
import 'jurii_form_motion.dart';

/// Dados coletados na folha. A tela é quem chama o repositório — assim a folha
/// não conhece Supabase e fica testável isolada.
class AppointmentDraft {
  final String title;
  final String? counterpartName;
  final String location;
  final DateTime startsAt;
  final DateTime endsAt;

  const AppointmentDraft({
    required this.title,
    required this.counterpartName,
    required this.location,
    required this.startsAt,
    required this.endsAt,
  });
}

/// Abre a folha de criar/editar compromisso. Devolve o rascunho, ou `null` se
/// o advogado desistiu. Passe [existing] para editar.
Future<AppointmentDraft?> showAppointmentFormSheet(
  BuildContext context, {
  Appointment? existing,
}) {
  return showModalBottomSheet<AppointmentDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AppointmentFormSheet(existing: existing),
  );
}

class AppointmentFormSheet extends StatefulWidget {
  const AppointmentFormSheet({super.key, this.existing});

  final Appointment? existing;

  @override
  State<AppointmentFormSheet> createState() => _AppointmentFormSheetState();
}

class _AppointmentFormSheetState extends State<AppointmentFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _counterpartController;
  late final TextEditingController _locationController;

  late DateTime _date;
  late TimeOfDay _start;
  late TimeOfDay _end;
  String? _timeError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final start = existing?.startsAt ?? _nextRoundedHour();
    final end = existing?.endsAt ?? start.add(const Duration(hours: 1));

    _titleController = TextEditingController(text: existing?.title ?? '');
    _counterpartController = TextEditingController(
      text: existing?.counterpartName ?? '',
    );
    _locationController = TextEditingController(text: existing?.location ?? '');
    _date = DateTime(start.year, start.month, start.day);
    _start = TimeOfDay(hour: start.hour, minute: start.minute);
    _end = TimeOfDay(hour: end.hour, minute: end.minute);
  }

  static DateTime _nextRoundedHour() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour + 1);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _counterpartController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  DateTime _combine(TimeOfDay time) {
    return DateTime(_date.year, _date.month, _date.day, time.hour, time.minute);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
        // Fim acompanha o início (mantém 1h) enquanto ainda não for válido.
        if (_minutesOf(_end) <= _minutesOf(_start)) {
          final bumped = _minutesOf(_start) + 60;
          _end = TimeOfDay(hour: (bumped ~/ 60) % 24, minute: bumped % 60);
        }
      } else {
        _end = picked;
      }
      _timeError = null;
    });
  }

  int _minutesOf(TimeOfDay t) => t.hour * 60 + t.minute;

  void _submit() {
    setState(() => _timeError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final startsAt = _combine(_start);
    final endsAt = _combine(_end);
    if (!endsAt.isAfter(startsAt)) {
      setState(() => _timeError = 'O término deve ser depois do início.');
      return;
    }

    Navigator.of(context).pop(
      AppointmentDraft(
        title: _titleController.text.trim(),
        counterpartName: _counterpartController.text.trim().isEmpty
            ? null
            : _counterpartController.text.trim(),
        location: _locationController.text.trim(),
        startsAt: startsAt,
        endsAt: endsAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return JuriiModalSheetScaffold(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEditing ? 'Editar compromisso' : 'Novo compromisso',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Título',
                hintText: 'Ex.: Audiência trabalhista',
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Informe um título' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _counterpartController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Com quem (opcional)',
                hintText: 'Ex.: Ana Pereira',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _locationController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Local (opcional)',
                hintText: 'Ex.: Fórum, Videochamada',
              ),
            ),
            const SizedBox(height: 16),
            _PickerRow(
              icon: Icons.calendar_today_outlined,
              label: 'Data',
              value: _dateLabel(_date),
              onTap: _pickDate,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _PickerRow(
                    icon: Icons.schedule_outlined,
                    label: 'Início',
                    value: _start.format(context),
                    onTap: () => _pickTime(isStart: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PickerRow(
                    icon: Icons.schedule_outlined,
                    label: 'Término',
                    value: _end.format(context),
                    onTap: () => _pickTime(isStart: false),
                  ),
                ),
              ],
            ),
            if (_timeError != null) ...[
              const SizedBox(height: 10),
              Text(
                _timeError!,
                style: TextStyle(
                  color: colors.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 20),
            JuriiLoadingButton(
              label: _isEditing ? 'Salvar' : 'Criar compromisso',
              onPressed: _submit,
              shadow: false,
            ),
          ],
        ),
      ),
    );
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = DateTime(date.year, date.month, date.day).difference(today).inDays;
    if (diff == 0) return 'Hoje';
    if (diff == 1) return 'Amanhã';
    const weekdays = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    final wd = weekdays[date.weekday - 1];
    return '$wd, ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.card,
          border: Border.all(color: colors.lightBlueBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
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
