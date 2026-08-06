import 'package:flutter/material.dart';

import '../data/legal_practice_areas.dart';
import '../theme/app_colors.dart';
import 'jurii_motion.dart';

class PracticeAreaSelector extends StatefulWidget {
  const PracticeAreaSelector({
    super.key,
    required this.selectedAreas,
    required this.onChanged,
    required this.showError,
    this.label = 'Áreas de atuação',
    this.errorText = 'Selecione pelo menos uma área',
    this.selectedColor,
    this.extraAreas = const [],
  });

  final List<String> selectedAreas;
  final ValueChanged<List<String>> onChanged;
  final bool showError;
  final String label;
  final String errorText;

  /// Cor do chip selecionado; quando nula, segue a paleta do tema ativo.
  final Color? selectedColor;

  /// Áreas que existem no cadastro mas NÃO estão no vocabulário canônico.
  ///
  /// Escritórios cadastrados antes da lista existir têm área em texto livre
  /// ("Direito do Trabalho", "Direito Bancário"). Sem mostrá-las, o seletor
  /// mentiria: os chips apareceriam todos desmarcados enquanto o cadastro
  /// carrega áreas invisíveis — que iam junto no salvamento e voltavam
  /// recusadas, sem a pessoa poder sequer ver a culpada.
  ///
  /// Elas aparecem marcadas e podem ser removidas. Uma vez removidas, não
  /// voltam: o vocabulário novo é o canônico.
  final List<String> extraAreas;

  @override
  State<PracticeAreaSelector> createState() => _PracticeAreaSelectorState();
}

class _PracticeAreaSelectorState extends State<PracticeAreaSelector> {
  final _buscaController = TextEditingController();
  String _busca = '';

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  /// Canônicas primeiro, depois as herdadas que ainda estão marcadas.
  List<String> get _areasVisiveis => [
    ...legalPracticeAreas,
    ...widget.extraAreas.where(
      (area) =>
          !legalPracticeAreas.contains(area) &&
          widget.selectedAreas.contains(area),
    ),
  ];

  /// O que a busca deixa passar.
  ///
  /// O que está SELECIONADO nunca some, filtrando ou não: esconder a própria
  /// escolha atrás de um filtro faz a pessoa achar que desmarcou.
  List<String> get _areasFiltradas {
    final termo = _busca.trim();
    if (termo.isEmpty) return _areasVisiveis;

    final normalizado = normalizePracticeAreaQuery(termo);
    return _areasVisiveis.where((area) {
      if (widget.selectedAreas.contains(area)) return true;
      if (normalizePracticeAreaQuery(area).contains(normalizado)) return true;
      // Casa também pelo que a área RESOLVE, não só pelo nome: quem digita
      // "trabalho", "seguro" ou "inventário" acha a área certa sem saber como
      // a lista a chama.
      return isPracticeAreaSelectedForQuery(area: area, query: termo);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final hasError = widget.showError && widget.selectedAreas.isEmpty;
    final effectiveSelectedColor = widget.selectedColor ?? colors.primary;
    final filtradas = _areasFiltradas;
    final marcadas = widget.selectedAreas.length;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: hasError ? widget.errorText : null,
        contentPadding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // São 39 áreas. Sem filtro, o formulário vira uma parede de chips e
          // quem procura a sua rola até desistir — e cadastro que cansa é
          // cadastro abandonado no meio.
          TextField(
            key: const Key('practice_area_search'),
            controller: _buscaController,
            onChanged: (value) => setState(() => _busca = value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar área',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _busca.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Limpar busca',
                      onPressed: () {
                        _buscaController.clear();
                        setState(() => _busca = '');
                      },
                    ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          if (marcadas > 0) ...[
            const SizedBox(height: 10),
            Text(
              marcadas == 1 ? '1 área marcada' : '$marcadas áreas marcadas',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (filtradas.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Nenhuma área com esse nome.',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: filtradas.map((area) {
                final selected = widget.selectedAreas.contains(area);
                return _PracticeAreaChip(
                  area: area,
                  selected: selected,
                  // Herdada fica visualmente distinta: é área que continua
                  // valendo, mas que o cadastro novo não oferece mais.
                  legacy: !legalPracticeAreas.contains(area),
                  selectedColor: effectiveSelectedColor,
                  onTap: () => _toggleArea(area),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  void _toggleArea(String area) {
    if (widget.selectedAreas.contains(area)) {
      widget.onChanged(
        widget.selectedAreas.where((item) => item != area).toList(),
      );
      return;
    }

    widget.onChanged([...widget.selectedAreas, area]);
  }
}

class _PracticeAreaChip extends StatelessWidget {
  const _PracticeAreaChip({
    required this.area,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
    this.legacy = false,
  });

  final String area;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  /// Área herdada de um cadastro anterior à lista canônica.
  final bool legacy;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return JuriiPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      pressedScale: 0.96,
      semanticLabel: legacy ? '$area, área herdada do cadastro antigo' : area,
      child: AnimatedContainer(
        duration: JuriiMotion.fast,
        curve: JuriiMotion.ease,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? selectedColor.withValues(alpha: 0.14) : colors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? selectedColor : colors.lightBlueBorder,
            width: selected ? 1.4 : 1,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: selectedColor.withValues(alpha: 0.10),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (legacy)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(Icons.history, color: colors.muted, size: 14),
              ),
            AnimatedSize(
              duration: JuriiMotion.fast,
              curve: JuriiMotion.ease,
              child: selected && !legacy
                  ? Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.check, color: selectedColor, size: 14),
                    )
                  : const SizedBox.shrink(),
            ),
            AnimatedDefaultTextStyle(
              duration: JuriiMotion.fast,
              curve: JuriiMotion.ease,
              style: TextStyle(
                color: selected ? selectedColor : colors.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
              ),
              child: Text(area),
            ),
          ],
        ),
      ),
    );
  }
}
