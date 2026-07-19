import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'jurii_list_card.dart';
import 'profile_avatar.dart';

class OfficeCard extends StatelessWidget {
  final String initials;
  final String officeName;
  final double rating;
  final String distance;
  final String specialty;
  final int reviews;
  final String avatarType;
  final String? avatarUrl;
  final VoidCallback? onTap;

  const OfficeCard({
    super.key,
    required this.initials,
    required this.officeName,
    required this.rating,
    required this.distance,
    required this.specialty,
    required this.reviews,
    required this.avatarType,
    this.avatarUrl,
    this.onTap,
  });

  Color _avatarColor(AppColors colors) => switch (avatarType) {
    'navy' => colors.primary,
    'gold' => colors.accent,
    _ => colors.lightBlue,
  };

  Color _avatarTextColor(AppColors colors) => switch (avatarType) {
    'navy' || 'gold' => colors.card,
    _ => colors.primary,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return JuriiListCard(
      onTap: onTap,
      semanticLabel: officeName,
      child: Row(
        children: [
          ProfileAvatar(
            imageUrl: avatarUrl,
            initials: initials,
            size: 48,
            backgroundColor: _avatarColor(colors),
            foregroundColor: _avatarTextColor(colors),
            borderRadius: BorderRadius.circular(12),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  officeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  specialty,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (reviews == 0)
                      Text(
                        'Novo',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                        ),
                      )
                    else ...[
                      Icon(Icons.star, size: 14, color: colors.accent),
                      const SizedBox(width: 4),
                      Text(
                        '$rating',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '($reviews avaliações)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      distance,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
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
