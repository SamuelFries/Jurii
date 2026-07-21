import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Selo das posições patrocinadas na descoberta.
///
/// Transparência: quem paga por destaque é identificado como tal — o selo
/// acompanha todo profissional destacado, inclusive quando ele aparece fora
/// dos slots do topo (há teto de posições patrocinadas por lista, mas o selo
/// não tem teto). Paleta lightGold + textPrimary, o mesmo par do _InfoChip dos
/// perfis, seguro nos dois temas.
class FeaturedBadge extends StatelessWidget {
  const FeaturedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.lightGold,
        border: Border.all(color: colors.lightGoldBorder),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Destaque',
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
