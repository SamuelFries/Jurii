import 'package:flutter/material.dart';

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
    const primary = Color(0xFF0D234B);
    const accent = Color(0xFFC9A227);

    final items = [
      (Icons.home_outlined, Icons.home, 'Início'),
      (Icons.chat_bubble_outline, Icons.chat_bubble, 'Mensagens'),
      (Icons.folder_outlined, Icons.folder, 'Meus Casos'),
      (Icons.person_outline, Icons.person, 'Perfil'),
    ];

    return Container(
      height: 90,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: Color(0xFFEAEAEA),
          ),
        ),
      ),
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
                              color: accent,
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
                        color: selected ? primary : Colors.grey,
                        size: 28,
                      ),

                      if (selected)
                        const Positioned(
                          top: -2,
                          right: -2,
                          child: CircleAvatar(
                            radius: 4,
                            backgroundColor: accent,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  Text(
                    items[index].$3,
                    style: TextStyle(
                      color: selected ? primary : Colors.grey,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 12,
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