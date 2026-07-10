import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'jurii_motion.dart';

class OfficeCard extends StatelessWidget {
  final String initials;
  final String officeName;
  final double rating;
  final String distance;
  final String specialty;
  final int reviews;
  final String avatarType;
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
    this.onTap,
  });

  Color get _avatarColor => switch (avatarType) {
    'navy' => AppTheme.primary,
    'gold' => AppTheme.accent,
    _ => AppTheme.lightBlue,
  };

  Color get _avatarTextColor => switch (avatarType) {
    'navy' || 'gold' => AppTheme.card,
    _ => AppTheme.primary,
  };

  @override
  Widget build(BuildContext context) {
    return JuriiPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      semanticLabel: officeName,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.lightBlueBorder),
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
                  initials,
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
                    officeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    specialty,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 14, color: AppTheme.accent),
                      const SizedBox(width: 4),
                      Text(
                        '$rating',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '($reviews avaliações)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        distance,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
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
    );
  }
}
