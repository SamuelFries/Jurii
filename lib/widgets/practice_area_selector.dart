import 'package:flutter/material.dart';

import '../data/legal_practice_areas.dart';
import '../theme/app_colors.dart';
import 'jurii_motion.dart';

class PracticeAreaSelector extends StatelessWidget {
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

  /// Canônicas primeiro, depois as herdadas que ainda estão marcadas.
  List<String> get _areasVisiveis => [
    ...legalPracticeAreas,
    ...extraAreas.where(
      (area) =>
          !legalPracticeAreas.contains(area) && selectedAreas.contains(area),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final hasError = showError && selectedAreas.isEmpty;
    final effectiveSelectedColor = selectedColor ?? context.jColors.primary;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        errorText: hasError ? errorText : null,
        contentPadding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _areasVisiveis.map((area) {
          final selected = selectedAreas.contains(area);
          return _PracticeAreaChip(
            area: area,
            selected: selected,
            // Herdada fica visualmente distinta: é área que continua valendo,
            // mas que o cadastro novo não oferece mais.
            legacy: !legalPracticeAreas.contains(area),
            selectedColor: effectiveSelectedColor,
            onTap: () => _toggleArea(area),
          );
        }).toList(),
      ),
    );
  }

  void _toggleArea(String area) {
    if (selectedAreas.contains(area)) {
      onChanged(selectedAreas.where((item) => item != area).toList());
      return;
    }

    onChanged([...selectedAreas, area]);
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
