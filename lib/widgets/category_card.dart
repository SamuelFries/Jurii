import 'package:flutter/material.dart';

class CategoryCard extends StatelessWidget {
  final String emoji;
  final String title;
  final bool isGold;
  final VoidCallback? onTap;

  const CategoryCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.isGold,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isGold
              ? const Color(0xFFFDF6E3)
              : const Color(0xFFEEF1F8),
          border: Border.all(
            color: isGold
                ? const Color(0xFFE8D5A0)
                : const Color(0xFFC5CFE8),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              emoji,
              style: const TextStyle(fontSize: 28),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0A1C3B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}