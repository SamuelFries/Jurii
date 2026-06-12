import 'package:flutter/material.dart';

import '../models/law_firm_verification.dart';
import '../models/law_firm_verification_status.dart';
import '../theme/app_theme.dart';

class LawFirmModeCard extends StatelessWidget {
  const LawFirmModeCard({
    super.key,
    required this.verification,
    required this.onTap,
  });

  final LawFirmVerification verification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isApproved =
        verification.status == LawFirmVerificationStatus.approved;
    final title = isApproved ? 'Área do Escritório' : 'Escritório em análise';
    final subtitle = isApproved
        ? 'Acesse leads, equipe e casos'
        : 'Estamos verificando ${verification.firmName}';
    final icon = isApproved
        ? Icons.dashboard_customize_outlined
        : Icons.schedule_outlined;
    final cardColor = isApproved ? AppTheme.officePurple : AppTheme.muted;

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
                color: cardColor.withValues(alpha: 0.22),
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
                child: Icon(icon, color: AppTheme.card, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.card,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.card,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
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
