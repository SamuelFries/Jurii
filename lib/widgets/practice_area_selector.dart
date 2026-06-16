import 'package:flutter/material.dart';

import '../data/legal_practice_areas.dart';
import '../theme/app_theme.dart';

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
        contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: legalPracticeAreas.map((area) {
          final selected = selectedAreas.contains(area);
          return FilterChip(
            label: Text(area),
            selected: selected,
            showCheckmark: false,
            selectedColor: selectedColor.withValues(alpha: 0.14),
            backgroundColor: AppTheme.card,
            side: BorderSide(
              color: selected ? selectedColor : AppTheme.lightBlueBorder,
            ),
            labelStyle: TextStyle(
              color: selected ? selectedColor : AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
            onSelected: (_) => _toggleArea(area),
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
