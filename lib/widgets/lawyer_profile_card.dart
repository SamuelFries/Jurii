import 'package:flutter/material.dart';

import '../data/legal_practice_areas.dart';
import '../models/lawyer_profile_summary.dart';
import '../theme/app_colors.dart';
import 'jurii_list_card.dart';

class LawyerProfileCard extends StatelessWidget {
  const LawyerProfileCard({super.key, required this.lawyer, this.onTap});

  final LawyerProfileSummary lawyer;
  final VoidCallback? onTap;

  Color _avatarColor(AppColors colors) => switch (lawyer.avatarType) {
    'gold' => colors.accent,
    'navy' => colors.primary,
    _ => colors.lightBlue,
  };

  Color _avatarTextColor(AppColors colors) => switch (lawyer.avatarType) {
    'gold' || 'navy' => colors.card,
    _ => colors.primary,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return JuriiListCard(
      onTap: onTap,
      semanticLabel: lawyer.name,
      borderColor: colors.lightGoldBorder,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _avatarColor(colors),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                lawyer.initials,
                style: TextStyle(
                  color: _avatarTextColor(colors),
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
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  practiceAreaSummary(lawyer.practiceAreas),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.workspace_premium_outlined,
                      size: 14,
                      color: colors.accent,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        lawyer.oabLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (lawyer.reviews == 0)
                      Text(
                        'Novo',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else ...[
                      Icon(Icons.star, size: 14, color: colors.accent),
                      const SizedBox(width: 4),
                      Text(
                        '${lawyer.rating}',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: colors.textSecondary),
        ],
      ),
    );
  }
}
