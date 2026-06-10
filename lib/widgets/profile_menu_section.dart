import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'profile_menu_item.dart';

class ProfileMenuSection extends StatelessWidget {
  final String title;
  final List<ProfileMenuItem> items;

  const ProfileMenuSection({
    super.key,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            children: items.asMap().entries.map((entry) {
              return ProfileMenuItemTile(
                item: entry.value,
                showDivider: entry.key < items.length - 1,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
