import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class FirmBottomNav extends StatelessWidget {
  const FirmBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_outlined, Icons.home, 'Início'),
      (Icons.chat_bubble_outline, Icons.chat_bubble, 'Mensagens'),
      (Icons.group_outlined, Icons.group, 'Equipe'),
      (Icons.folder_outlined, Icons.folder, 'Casos'),
      (Icons.apartment_outlined, Icons.apartment, 'Perfil'),
    ];

    return Container(
      height: 90,
      decoration: const BoxDecoration(
        color: AppTheme.card,
        border: Border(top: BorderSide(color: AppTheme.officePurpleBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final selected = currentIndex == index;

          return GestureDetector(
            onTap: () => onTap(index),
            child: SizedBox(
              width: 70,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 6,
                    child: selected
                        ? Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppTheme.officePurple,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 6),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        selected ? items[index].$2 : items[index].$1,
                        color: selected
                            ? AppTheme.officePurple
                            : AppTheme.textSecondary,
                        size: 26,
                      ),
                      if (selected)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: CircleAvatar(
                            radius: 4,
                            backgroundColor: AppTheme.accent,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    items[index].$3,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? AppTheme.officePurple
                          : AppTheme.textSecondary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
