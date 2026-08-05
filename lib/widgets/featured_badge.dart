import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Selo das posições patrocinadas na descoberta.
///
/// Diz "Patrocinado", e não "Destaque", pelo mesmo motivo que o Google escreve
/// "Patrocinado" nos anúncios dele: "destaque" o cliente lê como mérito — "esse
/// é bom" —, não como "esse pagou". O CDC (art. 36) exige que o consumidor
/// identifique publicidade fácil e imediatamente, e num app cujo público são
/// advogados a distinção não passa despercebida.
///
/// O selo acompanha TODO profissional patrocinado, inclusive quando ele aparece
/// fora das vagas do topo: há teto de vagas por lista, o selo não tem teto.
/// Paleta lightGold + textPrimary, o mesmo par do _InfoChip dos perfis, seguro
/// nos dois temas.
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
        'Patrocinado',
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
