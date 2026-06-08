import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class LawyerModeHeader extends StatelessWidget {
  const LawyerModeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Row(
            children: [
              Text('⚖️', style: TextStyle(fontSize: 14)),
              SizedBox(width: 6),
              Text(
                'Modo Advogado',
                style: TextStyle(
                  color: AppTheme.card,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () {
            // TODO: trocar para modo cliente
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.lightBlueBorder),
            ),
            child: const Text(
              'Trocar para Cliente',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }
}