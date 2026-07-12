import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'jurii_motion.dart';

class CategoryCard extends StatelessWidget {
  final String title;
  final bool isGold;
  final bool selected;
  final String? iconName;
  final VoidCallback? onTap;

  const CategoryCard({
    super.key,
    required this.title,
    required this.isGold,
    this.selected = false,
    this.iconName,
    this.onTap,
  });

  /// Ícones suportados por legal_categories.icon_name. Categorias novas
  /// cadastradas no banco caem aqui sem precisar de release do app.
  static const Map<String, IconData> _iconsByName = {
    'family_restroom': Icons.family_restroom,
    'child_care_outlined': Icons.child_care_outlined,
    'work_outline': Icons.work_outline,
    'home_outlined': Icons.home_outlined,
    'directions_car_outlined': Icons.directions_car_outlined,
    'shopping_bag_outlined': Icons.shopping_bag_outlined,
    'gavel': Icons.gavel,
    'balance_outlined': Icons.balance_outlined,
    'account_balance_outlined': Icons.account_balance_outlined,
    'shield_outlined': Icons.shield_outlined,
    'computer_outlined': Icons.computer_outlined,
    'receipt_long_outlined': Icons.receipt_long_outlined,
    'business_center_outlined': Icons.business_center_outlined,
    'elderly_outlined': Icons.elderly_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final accentColor = isGold ? colors.accent : colors.primary;

    return JuriiPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      semanticLabel: title,
      child: AnimatedContainer(
        duration: JuriiMotion.fast,
        curve: JuriiMotion.ease,
        decoration: BoxDecoration(
          color: isGold ? colors.lightGold : colors.lightBlue,
          border: Border.all(
            color: selected
                ? accentColor
                : isGold
                ? colors.lightGoldBorder
                : colors.lightBlueBorder,
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
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData get _categoryIcon {
    final fromName = iconName == null ? null : _iconsByName[iconName];
    if (fromName != null) return fromName;

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
