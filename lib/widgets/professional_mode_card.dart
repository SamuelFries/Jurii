import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ProfessionalModeCard extends StatelessWidget {
  const ProfessionalModeCard({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.accent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accent.withValues(alpha: 0.24),
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
                  color: AppTheme.card.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.card.withValues(alpha: 0.45),
                  ),
                ),
                child: const Icon(
                  Icons.business_center_outlined,
                  color: AppTheme.card,
                  size: 24,
                ),
              ),

              const SizedBox(width: 14),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ativar Modo Profissional',
                      style: TextStyle(
                        color: AppTheme.card,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Atenda clientes pela plataforma',
                      style: TextStyle(
                        color: AppTheme.card,
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
                  color: AppTheme.card.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chevron_right,
                  color: AppTheme.card,
                  size: 26,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
