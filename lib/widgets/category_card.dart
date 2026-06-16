import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CategoryCard extends StatelessWidget {
  final String title;
  final bool isGold;
  final bool selected;
  final VoidCallback? onTap;

  const CategoryCard({
    super.key,
    required this.title,
    required this.isGold,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = isGold ? AppTheme.accent : AppTheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isGold ? AppTheme.lightGold : AppTheme.lightBlue,
          border: Border.all(
            color: selected
                ? accentColor
                : isGold
                ? AppTheme.lightGoldBorder
                : AppTheme.lightBlueBorder,
            width: selected ? 2 : 1.5,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_categoryIcon, size: 28, color: accentColor),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData get _categoryIcon {
    final normalizedTitle = title.replaceAll('\n', ' ').toLowerCase();

    if (normalizedTitle.contains('divórcio')) {
      return Icons.family_restroom;
    }
    if (normalizedTitle.contains('pensão')) {
      return Icons.child_care_outlined;
    }
    if (normalizedTitle.contains('trabalhista')) {
      return Icons.work_outline;
    }
    if (normalizedTitle.contains('imobiliário')) {
      return Icons.home_outlined;
    }
    if (normalizedTitle.contains('acidente')) {
      return Icons.directions_car_outlined;
    }
    if (normalizedTitle.contains('consumidor')) {
      return Icons.shopping_bag_outlined;
    }

    return Icons.balance_outlined;
  }
}
