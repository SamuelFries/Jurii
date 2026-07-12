import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ProfileMenuItem {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;

  const ProfileMenuItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.subtitle,
    this.onTap,
  });
}

class ProfileMenuItemTile extends StatelessWidget {
  final ProfileMenuItem item;
  final bool showDivider;

  const ProfileMenuItemTile({
    super.key,
    required this.item,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Column(
      children: [
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: item.iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(item.icon, color: item.iconColor, size: 20),
          ),
          title: Text(
            item.label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
          subtitle: item.subtitle != null
              ? Text(
                  item.subtitle!,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                )
              : null,
          trailing: Icon(Icons.chevron_right, color: colors.textSecondary),
          onTap: item.onTap,
        ),
        if (showDivider) Divider(height: 1, indent: 56, color: colors.divider),
      ],
    );
  }
}
