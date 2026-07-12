import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ProfileHeaderCard extends StatelessWidget {
  final String name;
  final String email;
  final String initials;
  final String memberSince;
  final VoidCallback? onEditTap;

  const ProfileHeaderCard({
    super.key,
    required this.name,
    required this.email,
    required this.initials,
    required this.memberSince,
    this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(12),
              // Delineia o avatar no tema escuro, onde accent e o header
              // primary têm a mesma luminância.
              border: Border.all(color: colors.card.withValues(alpha: 0.35)),
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  color: colors.card,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: colors.card,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  email,
                  style: TextStyle(
                    color: colors.card.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.card.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        color: colors.card.withValues(alpha: 0.7),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        memberSince,
                        style: TextStyle(
                          color: colors.card.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onEditTap,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.card.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.edit_outlined, color: colors.card, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
