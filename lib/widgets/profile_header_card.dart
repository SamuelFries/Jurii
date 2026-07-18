import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ProfileHeaderCard extends StatelessWidget {
  final String name;
  final String email;
  final String initials;
  final String memberSince;
  final String? avatarUrl;
  final VoidCallback? onEditTap;

  const ProfileHeaderCard({
    super.key,
    required this.name,
    required this.email,
    required this.initials,
    required this.memberSince,
    this.avatarUrl,
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
            clipBehavior: Clip.antiAlias,
            child: _avatar(colors),
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
          IconButton(
            key: const Key('profile_edit_button'),
            tooltip: 'Editar perfil',
            onPressed: onEditTap,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              backgroundColor: colors.card.withValues(alpha: 0.15),
              foregroundColor: colors.card,
              disabledBackgroundColor: colors.card.withValues(alpha: 0.08),
              disabledForegroundColor: colors.card.withValues(alpha: 0.5),
            ),
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _avatar(AppColors colors) {
    final url = avatarUrl;
    if (url == null || url.isEmpty) return _initials(colors);

    return Image.network(
      url,
      width: 56,
      height: 56,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _initials(colors);
      },
      errorBuilder: (context, error, stackTrace) => _initials(colors),
    );
  }

  Widget _initials(AppColors colors) {
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          color: colors.card,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }
}
