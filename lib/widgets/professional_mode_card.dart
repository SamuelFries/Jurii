import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../models/lawyer_status.dart';

class ProfessionalModeCard extends StatelessWidget {
  const ProfessionalModeCard({
    super.key,
    required this.onTap,
    required this.lawyerStatus,
  });

  final VoidCallback onTap;
  final LawyerStatus lawyerStatus;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    String title;
    String subtitle;
    Color cardColor;
    IconData icon;

    switch (lawyerStatus) {
      case LawyerStatus.client:
        title = 'Ativar Modo Profissional';
        subtitle = 'Atenda clientes pela plataforma';
        cardColor = colors.accent;
        icon = Icons.business_center_outlined;
        break;

      case LawyerStatus.pending:
        title = 'Verificação em andamento';
        subtitle = 'Sua documentação está sendo analisada';
        cardColor = colors.warning;
        icon = Icons.schedule_outlined;
        break;

      case LawyerStatus.approved:
        title = 'Entrar no Modo Profissional';
        subtitle = 'Acesse sua área profissional';
        cardColor = colors.accent;
        icon = Icons.business_center_outlined;
        break;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: cardColor.withValues(alpha: 0.24),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.card.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colors.card.withValues(alpha: 0.45),
                  ),
                ),
                child: Icon(icon, color: colors.card, size: 24),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.card,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colors.card,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.card.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.chevron_right, color: colors.card, size: 26),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
