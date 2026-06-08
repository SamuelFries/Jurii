import 'package:flutter/material.dart';
import '../data/lawyer_cases_data.dart';
import '../theme/app_theme.dart';
import 'lawyer_case_card.dart';

class LawyerCasesSection extends StatelessWidget {
  const LawyerCasesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Casos Ativos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            GestureDetector(
              onTap: () {
                // TODO: navegar para lista completa de casos
              },
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
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: lawyerCases.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return LawyerCaseCard(
              lawyerCase: lawyerCases[index],
              onTap: () {
                // TODO: navegar para detalhe do caso
              },
            );
          },
        ),
      ],
    );
  }
}