import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/list_search.dart';

/// Um filtro de lista com a contagem do que ele alcança.
class JuriiListFilter {
  const JuriiListFilter({
    required this.label,
    required this.matches,
    required this.selected,
    required this.onToggle,
  });

  final String label;

  /// Quantos itens da lista COMPLETA este filtro alcança. É o número que
  /// decide se o chip merece existir, e o que aparece no rótulo.
  final int matches;

  final bool selected;
  final VoidCallback onToggle;
}

/// A fileira de chips de filtro das listas.
///
/// A regra de existir está em [filterChipIsUseful]: chip que alcança tudo não
/// filtra nada, e chip que não alcança nada só serve para esvaziar a tela e
/// assustar. Nos dois casos ele é ruído permanente, então some.
///
/// Um chip SELECIONADO nunca some, mesmo que a contagem mude: o controle que
/// desfaz o filtro tem que continuar alcançável, senão a pessoa fica presa
/// numa lista filtrada sem enxergar o que a filtrou.
class JuriiFilterChipRow extends StatelessWidget {
  const JuriiFilterChipRow({
    super.key,
    required this.filters,
    required this.total,
  });

  final List<JuriiListFilter> filters;

  /// Tamanho da lista completa, antes de qualquer filtro.
  final int total;

  List<JuriiListFilter> get _visible => filters
      .where(
        (filter) =>
            filter.selected ||
            filterChipIsUseful(matches: filter.matches, total: total),
      )
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final visible = _visible;
    if (visible.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in visible)
          FilterChip(
            key: ValueKey('list_filter_${filter.label}'),
            label: Text('${filter.label} (${filter.matches})'),
            selected: filter.selected,
            showCheckmark: false,
            selectedColor: colors.lightGold,
            backgroundColor: colors.card,
            side: BorderSide(
              color: filter.selected ? colors.accent : colors.lightBlueBorder,
            ),
            labelStyle: TextStyle(
              color: filter.selected ? colors.accent : colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
            onSelected: (_) => filter.onToggle(),
          ),
      ],
    );
  }
}
