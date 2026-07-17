import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../repositories/calendar_feed_repository.dart';
import '../theme/app_colors.dart';
import 'jurii_form_motion.dart';

/// Folha "Sincronizar com meu calendário": ativa/mostra/revoga o feed .ics que
/// leva os compromissos da Jurii para o Google/Apple/Outlook do advogado.
Future<void> showCalendarSyncSheet(
  BuildContext context, {
  CalendarFeedRepository repository = const CalendarFeedRepository(),
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CalendarSyncSheet(repository: repository),
  );
}

class CalendarSyncSheet extends StatefulWidget {
  const CalendarSyncSheet({
    super.key,
    this.repository = const CalendarFeedRepository(),
  });

  final CalendarFeedRepository repository;

  @override
  State<CalendarSyncSheet> createState() => _CalendarSyncSheetState();
}

class _CalendarSyncSheetState extends State<CalendarSyncSheet> {
  String? _token;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final token = await widget.repository.fetchToken();
      if (!mounted) return;
      setState(() {
        _token = token;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) _snack('Não foi possível concluir. Tente novamente.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable() =>
      _run(() async {
        final token = await widget.repository.enable();
        if (mounted) setState(() => _token = token);
      });

  Future<void> _reset() =>
      _run(() async {
        final token = await widget.repository.reset();
        if (mounted) setState(() => _token = token);
        _snack('Novo link gerado. O link anterior parou de funcionar.');
      });

  Future<void> _disable() =>
      _run(() async {
        await widget.repository.disable();
        if (mounted) setState(() => _token = null);
      });

  Future<void> _copy() async {
    final token = _token;
    if (token == null) return;
    await Clipboard.setData(
      ClipboardData(text: widget.repository.feedUrl(token)),
    );
    _snack('Link copiado.');
  }

  Future<void> _openInCalendar() async {
    final token = _token;
    if (token == null) return;
    final uri = Uri.parse(widget.repository.webcalUrl(token));
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _snack('Nenhum app de calendário respondeu. Copie o link e adicione manualmente.');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return JuriiModalSheetScaffold(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sincronizar com meu calendário',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Assine sua agenda da Jurii no Google, Apple ou Outlook. Todo '
            'compromisso aparece lá automaticamente.',
            style: TextStyle(color: colors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_token == null)
            JuriiLoadingButton(
              label: 'Ativar sincronização',
              isLoading: _busy,
              shadow: false,
              onPressed: _busy ? null : _enable,
            )
          else
            _activeState(colors),
        ],
      ),
    );
  }

  Widget _activeState(AppColors colors) {
    final url = widget.repository.feedUrl(_token!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.lightBlue,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.lightBlueBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: _copy,
                icon: const Icon(Icons.copy_outlined),
                tooltip: 'Copiar link',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        JuriiLoadingButton(
          label: 'Abrir no meu calendário',
          shadow: false,
          onPressed: _busy ? null : _openInCalendar,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(Icons.lock_outline, size: 15, color: colors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Qualquer pessoa com este link vê seus compromissos. '
                'Gere um novo link para revogar o acesso.',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _busy ? null : _reset,
                child: const Text('Gerar novo link'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: _busy ? null : _disable,
                style: TextButton.styleFrom(foregroundColor: colors.danger),
                child: const Text('Desativar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
