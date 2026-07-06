import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class JuriiBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const JuriiBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_outlined, Icons.home, 'Início'),
      (Icons.chat_bubble_outline, Icons.chat_bubble, 'Mensagens'),
      (Icons.folder_outlined, Icons.folder, 'Meus Casos'),
      (Icons.person_outline, Icons.person, 'Perfil'),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.card,
        border: Border(top: BorderSide(color: AppTheme.lightBlueBorder)),
      ),
      // Scaffold não aplica safe area ao bottomNavigationBar: sem isto o
      // home indicator do iPhone sobrepõe os labels.
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 84,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (index) {
              final selected = currentIndex == index;

              return GestureDetector(
                onTap: () => onTap(index),
                child: SizedBox(
                  width: 80,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 6,
                        child: selected
                            ? Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: AppTheme.accent,
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
                                ? AppTheme.primary
                                : AppTheme.textSecondary,
                            size: 28,
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
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
