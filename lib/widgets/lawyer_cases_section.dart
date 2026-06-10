import 'package:flutter/material.dart';
import '../data/mock/mock_cases.dart';
import '../theme/app_theme.dart';
import 'lawyer_case_card.dart';

class LawyerCasesSection extends StatelessWidget {
  final VoidCallback? onOpenCases;

  const LawyerCasesSection({super.key, this.onOpenCases});

  @override
  Widget build(BuildContext context) {
    final cases = mockLawyerCases;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Casos Ativos', style: Theme.of(context).textTheme.titleLarge),
            if (cases.isNotEmpty)
              GestureDetector(
                onTap: onOpenCases,
                child: const Row(
                  children: [
                    Text(
                      'Ver todos',
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Icon(Icons.chevron_right, color: AppTheme.accent, size: 18),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (cases.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    '📂',
                    style: TextStyle(
                      fontSize: 32,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Nenhum caso ativo no momento',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                      decoration: TextDecoration.none,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cases.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return LawyerCaseCard(
                lawyerCase: cases[index],
                onTap: onOpenCases,
              );
            },
          ),
      ],
    );
  }
}
