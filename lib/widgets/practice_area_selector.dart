import 'package:flutter/material.dart';

import '../data/legal_practice_areas.dart';
import '../theme/app_theme.dart';
import 'jurii_motion.dart';

class PracticeAreaSelector extends StatelessWidget {
  const PracticeAreaSelector({
    super.key,
    required this.selectedAreas,
    required this.onChanged,
    required this.showError,
    this.label = 'Áreas de atuação',
    this.errorText = 'Selecione pelo menos uma área',
    this.selectedColor = AppTheme.primary,
  });

  final List<String> selectedAreas;
  final ValueChanged<List<String>> onChanged;
  final bool showError;
  final String label;
  final String errorText;
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    final hasError = showError && selectedAreas.isEmpty;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        errorText: hasError ? errorText : null,
        contentPadding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: legalPracticeAreas.map((area) {
          final selected = selectedAreas.contains(area);
          return _PracticeAreaChip(
            area: area,
            selected: selected,
            selectedColor: selectedColor,
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
  });

  final String area;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return JuriiPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      pressedScale: 0.96,
      semanticLabel: area,
      child: AnimatedContainer(
        duration: JuriiMotion.fast,
        curve: JuriiMotion.ease,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? selectedColor.withValues(alpha: 0.14)
              : AppTheme.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? selectedColor : AppTheme.lightBlueBorder,
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
            AnimatedSize(
              duration: JuriiMotion.fast,
              curve: JuriiMotion.ease,
              child: selected
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
                color: selected ? selectedColor : AppTheme.textSecondary,
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
