import 'package:flutter/material.dart';

import '../models/business_hours.dart';
import '../repositories/business_hours_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/jurii_error_state.dart';
import '../widgets/jurii_motion.dart';

/// Editor dos horários de atendimento do escritório.
///
/// Um intervalo por dia na tela. O banco guarda linhas, então dois intervalos
/// no mesmo dia (fecha para almoço) cabem sem mudar esquema — mas a tela
/// começa simples de propósito: sete dias com dois relógios cada já é o
/// suficiente para a pessoa desistir se não for direto ao ponto.
class BusinessHoursScreen extends StatefulWidget {
  const BusinessHoursScreen({
    super.key,
    required this.lawFirmId,
    this.repository = const BusinessHoursRepository(),
  });

  final String lawFirmId;
  final BusinessHoursRepository repository;

  @override
  State<BusinessHoursScreen> createState() => _BusinessHoursScreenState();
}

/// O estado de UM dia enquanto se edita.
class _Dia {
  _Dia({required this.weekday, this.aberto = false, int? abre, int? fecha})
    : abreEm = abre ?? _padraoAbre,
      fechaEm = fecha ?? _padraoFecha;

  static const _padraoAbre = 9 * 60;
  static const _padraoFecha = 18 * 60;

  final int weekday;
  bool aberto;
  int abreEm;
  int fechaEm;

  bool get valido => fechaEm > abreEm;

  _Dia copia() =>
      _Dia(weekday: weekday, aberto: aberto, abre: abreEm, fecha: fechaEm);
}

class _BusinessHoursScreenState extends State<BusinessHoursScreen> {
  List<_Dia> _dias = [for (var d = 1; d <= 7; d++) _Dia(weekday: d)];
  List<_Dia> _originais = const [];

  bool _carregando = true;
  bool _falhou = false;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _falhou = false;
    });
    try {
      final horarios = await widget.repository.fetch(widget.lawFirmId);
      if (!mounted) return;
      setState(() {
        _dias = [
          for (var d = 1; d <= 7; d++)
            () {
              final doDia = horarios.forWeekday(d);
              if (doDia.isEmpty) {
                // Escritório que ainda não preencheu: seg–sex 9h–18h marcado,
                // fim de semana fechado. É o horário da esmagadora maioria, e
                // sugerir o comum é diferente de gravar por ele — nada vai
                // para o banco sem a pessoa tocar em "Salvar".
                return _Dia(weekday: d, aberto: horarios.isEmpty && d <= 5);
              }
              return _Dia(
                weekday: d,
                aberto: true,
                abre: doDia.first.opensAt,
                fecha: doDia.first.closesAt,
              );
            }(),
        ];
        _originais = [for (final dia in _dias) dia.copia()];
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _falhou = true;
      });
    }
  }

  bool get _mudou {
    if (_originais.length != _dias.length) return true;
    for (var i = 0; i < _dias.length; i++) {
      final a = _dias[i];
      final b = _originais[i];
      if (a.aberto != b.aberto) return true;
      if (a.aberto && (a.abreEm != b.abreEm || a.fechaEm != b.fechaEm)) {
        return true;
      }
    }
    return false;
  }

  bool get _algumInvalido => _dias.any((d) => d.aberto && !d.valido);

  Future<void> _escolherHora(_Dia dia, {required bool abertura}) async {
    final atual = abertura ? dia.abreEm : dia.fechaEm;
    final escolhida = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: atual ~/ 60, minute: atual % 60),
    );
    if (escolhida == null) return;

    setState(() {
      final minutos = escolhida.hour * 60 + escolhida.minute;
      if (abertura) {
        dia.abreEm = minutos;
        // Abertura passando o fechamento não é "fecha no dia seguinte", é
        // engano — o fechamento acompanha, mantendo a duração de antes.
        if (dia.fechaEm <= minutos) {
          dia.fechaEm = (minutos + 60).clamp(0, 23 * 60 + 59);
        }
      } else {
        dia.fechaEm = minutos;
      }
    });
  }

  /// Copia o primeiro dia aberto para todos os outros dias ABERTOS.
  ///
  /// Sem isto, um horário igual em cinco dias custa dez toques em relógio.
  void _replicar() {
    final modelo = _dias.firstWhere(
      (d) => d.aberto,
      orElse: () => _dias.first,
    );
    setState(() {
      for (final dia in _dias) {
        if (!dia.aberto || identical(dia, modelo)) continue;
        dia.abreEm = modelo.abreEm;
        dia.fechaEm = modelo.fechaEm;
      }
    });
  }

  Future<void> _salvar() async {
    if (_salvando || _algumInvalido) return;
    setState(() => _salvando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final gravados = await widget.repository.save(
        lawFirmId: widget.lawFirmId,
        intervals: [
          for (final dia in _dias)
            if (dia.aberto)
              BusinessHourInterval(
                weekday: dia.weekday,
                opensAt: dia.abreEm,
                closesAt: dia.fechaEm,
              ),
        ],
      );
      if (!mounted) return;
      Navigator.of(context).pop(gravados);
      messenger.showSnackBar(
        const SnackBar(content: Text('Horários salvos.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _salvando = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error.toString().toLowerCase().contains('not allowed')
                ? 'Você não tem permissão para editar este escritório.'
                : 'Não foi possível salvar. Tente novamente.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final abertos = _dias.where((d) => d.aberto).length;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        title: const Text('Horários de atendimento'),
      ),
      body: SafeArea(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _falhou
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: JuriiErrorState(
                  title: 'Não foi possível carregar os horários.',
                  onRetry: _carregar,
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: [
                  Text(
                    'Quando o escritório atende',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'O cliente vê isto antes de mandar a primeira mensagem — '
                    'é o que responde "adianta escrever agora?".',
                    style: TextStyle(color: colors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  for (final dia in _dias) ...[
                    _LinhaDoDia(
                      dia: dia,
                      onToggle: (valor) => setState(() => dia.aberto = valor),
                      onAbertura: () => _escolherHora(dia, abertura: true),
                      onFechamento: () => _escolherHora(dia, abertura: false),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (abertos > 1) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('replicar_horario'),
                        onPressed: _replicar,
                        icon: const Icon(Icons.copy_all_outlined, size: 18),
                        label: const Text('Repetir em todos os dias abertos'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (abertos == 0)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.lightGold,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.lightGoldBorder),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: colors.accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sem nenhum dia aberto, o perfil não mostra '
                              'horário — o cliente segue sem saber quando '
                              'você atende.',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      key: const Key('salvar_horarios'),
                      onPressed: _salvando || !_mudou || _algumInvalido
                          ? null
                          : _salvar,
                      child: _salvando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Salvar horários'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _LinhaDoDia extends StatelessWidget {
  const _LinhaDoDia({
    required this.dia,
    required this.onToggle,
    required this.onAbertura,
    required this.onFechamento,
  });

  final _Dia dia;
  final ValueChanged<bool> onToggle;
  final VoidCallback onAbertura;
  final VoidCallback onFechamento;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.officePurpleBorder),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              weekdayName(dia.weekday),
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          Switch(
            key: Key('dia_${dia.weekday}'),
            value: dia.aberto,
            activeThumbColor: colors.officePurple,
            onChanged: onToggle,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: dia.aberto
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _BotaoDeHora(
                        chave: 'abre_${dia.weekday}',
                        minutos: dia.abreEm,
                        onTap: onAbertura,
                      ),
                      Text(
                        ' às ',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      _BotaoDeHora(
                        chave: 'fecha_${dia.weekday}',
                        minutos: dia.fechaEm,
                        onTap: onFechamento,
                        // Fechamento antes da abertura fica visível na hora,
                        // e não só quando o botão de salvar não acende.
                        erro: !dia.valido,
                      ),
                    ],
                  )
                : Text(
                    'Fechado',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _BotaoDeHora extends StatelessWidget {
  const _BotaoDeHora({
    required this.chave,
    required this.minutos,
    required this.onTap,
    this.erro = false,
  });

  final String chave;
  final int minutos;
  final VoidCallback onTap;
  final bool erro;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final cor = erro ? colors.danger : colors.officePurple;

    return JuriiPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      semanticLabel: BusinessHourInterval.label(minutos),
      child: Container(
        key: Key(chave),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: erro ? colors.dangerSurface : colors.officePurpleSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: erro ? colors.dangerBorder : cor),
        ),
        child: Text(
          BusinessHourInterval.label(minutos),
          style: TextStyle(
            color: cor,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
