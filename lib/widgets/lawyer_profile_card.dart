import 'package:flutter/material.dart';

import '../data/legal_practice_areas.dart';
import '../models/lawyer_profile_summary.dart';
import '../theme/app_theme.dart';
import 'jurii_motion.dart';

class LawyerProfileCard extends StatelessWidget {
  const LawyerProfileCard({super.key, required this.lawyer, this.onTap});

  final LawyerProfileSummary lawyer;
  final VoidCallback? onTap;

  Color get _avatarColor => switch (lawyer.avatarType) {
    'gold' => AppTheme.accent,
    'navy' => AppTheme.primary,
    _ => AppTheme.lightBlue,
  };

  Color get _avatarTextColor => switch (lawyer.avatarType) {
    'gold' || 'navy' => AppTheme.card,
    _ => AppTheme.primary,
  };

  @override
  Widget build(BuildContext context) {
    return JuriiPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      semanticLabel: lawyer.name,
      child: Material(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.lightGoldBorder),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _avatarColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    lawyer.initials,
                    style: TextStyle(
                      color: _avatarTextColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lawyer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      practiceAreaSummary(lawyer.practiceAreas),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.workspace_premium_outlined,
                          size: 14,
                          color: AppTheme.accent,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            lawyer.oabLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.star,
                          size: 14,
                          color: AppTheme.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${lawyer.rating}',
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
