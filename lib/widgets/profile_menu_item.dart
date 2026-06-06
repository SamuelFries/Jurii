import 'package:flutter/material.dart';

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
    return Column(
      children: [
        ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: item.iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(item.icon, color: item.iconColor, size: 20),
          ),
          title: Text(
            item.label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF0A1C3B),
            ),
          ),
          subtitle: item.subtitle != null
              ? Text(
                  item.subtitle!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                )
              : null,
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          onTap: item.onTap,
        ),
        if (showDivider)
          Divider(height: 1, indent: 56, color: Colors.grey.shade100),
      ],
    );
  }
}