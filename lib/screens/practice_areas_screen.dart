import 'package:flutter/material.dart';

import '../data/legal_practice_areas.dart';
import '../repositories/practice_areas_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/jurii_error_state.dart';
import '../widgets/practice_area_selector.dart';

/// Onde o advogado troca as próprias áreas de atuação.
///
/// A RPC existia desde a 20260805180000 e nenhuma tela a chamava: quem foi
/// aprovado com "Direito Cível" ficava com "Direito Cível" para sempre. Isso
/// virou bloqueio quando a taxonomia foi de 10 para 39 áreas — sem esta tela,
/// as 29 áreas novas só valeriam para quem se cadastrasse depois.
class PracticeAreasScreen extends StatefulWidget {
  const PracticeAreasScreen({
    super.key,
    this.repository = const PracticeAreasRepository(),
  });

  final PracticeAreasRepository repository;

  @override
  State<PracticeAreasScreen> createState() => _PracticeAreasScreenState();
}

class _PracticeAreasScreenState extends State<PracticeAreasScreen> {
  List<String> _selecionadas = const [];
  String? _principal;

  List<String> _originais = const [];
  String? _principalOriginal;

  /// Áreas do cadastro que não estão no vocabulário canônico. Sem passá-las ao
  /// seletor, ele mostraria os chips todos desmarcados enquanto o perfil
  /// carrega áreas invisíveis.
  List<String> _herdadas = const [];

  bool _carregando = true;
  bool _falhouCarregar = false;
  bool _salvando = false;
  bool _mostrarErro = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _falhouCarregar = false;
    });
    try {
      final atual = await widget.repository.fetchMine();
      if (!mounted) return;
      setState(() {
        _selecionadas = atual.areas;
        _originais = atual.areas;
        _principal = atual.primaryArea ?? atual.areas.firstOrNull;
        _principalOriginal = _principal;
        _herdadas = atual.areas
            .where((area) => !legalPracticeAreas.contains(area))
            .toList();
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _falhouCarregar = true;
      });
    }
  }

  bool get _mudou {
    if (_principal != _principalOriginal) return true;
    if (_selecionadas.length != _originais.length) return true;
    final atual = [..._selecionadas]..sort();
    final antes = [..._originais]..sort();
    for (var i = 0; i < atual.length; i++) {
      if (atual[i] != antes[i]) return true;
    }
    return false;
  }

  void _onAreasChanged(List<String> areas) {
    setState(() {
      _selecionadas = areas;
      // Tirar da lista a área que era a principal não pode deixar o perfil com
      // uma principal que ele não atende — o servidor recusaria, e o erro
      // apareceria só no salvamento.
      if (_principal == null || !areas.contains(_principal)) {
        _principal = areas.firstOrNull;
      }
    });
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    if (_selecionadas.isEmpty || _principal == null) {
      setState(() => _mostrarErro = true);
      return;
    }

    setState(() {
      _salvando = true;
      _mostrarErro = false;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final gravadas = await widget.repository.save(
        primaryArea: _principal!,
        areas: _selecionadas,
      );
      if (!mounted) return;
      Navigator.of(context).pop(gravadas);
      messenger.showSnackBar(
        const SnackBar(content: Text('Áreas de atuação salvas.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _salvando = false);
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyPracticeAreaError(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Áreas de atuação'),
        backgroundColor: colors.background,
      ),
      body: SafeArea(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _falhouCarregar
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: JuriiErrorState(
                  title: 'Não foi possível carregar suas áreas.',
                  onRetry: _carregar,
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: [
                  Text(
                    'O que você atende',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'É por aqui que o cliente encontra você na busca e nas '
                    'categorias. Marque tudo que você realmente atende — não há '
                    'limite de quantidade.',
                    style: TextStyle(color: colors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  PracticeAreaSelector(
                    selectedAreas: _selecionadas,
                    onChanged: _onAreasChanged,
                    showError: _mostrarErro,
                    extraAreas: _herdadas,
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    key: const Key('primary_area_field'),
                    initialValue: _selecionadas.contains(_principal)
                        ? _principal
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Área principal',
                    ),
                    items: [
                      for (final area in _selecionadas)
                        DropdownMenuItem(value: area, child: Text(area)),
                    ],
                    onChanged: (value) => setState(() => _principal = value),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    // Não é enfeite: entre dois advogados relevantes, quem tem '
                    // a área buscada como principal aparece primeiro.
                    'Na busca por essa área, quem a tem como principal aparece '
                    'antes de quem apenas a inclui na lista.',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      key: const Key('save_practice_areas'),
                      onPressed: _salvando || !_mudou ? null : _salvar,
                      child: _salvando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Salvar áreas'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
