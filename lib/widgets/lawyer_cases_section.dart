import 'package:flutter/material.dart';
import '../data/lawyer_cases_data.dart';
import '../theme/app_theme.dart';
import 'lawyer_case_card.dart';

class LawyerCasesSection extends StatelessWidget {
  const LawyerCasesSection({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: substituir por dados reais da API
    final cases = lawyerCases;

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
            if (cases.isNotEmpty)
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
                    Icon(
                      Icons.chevron_right,
                      color: AppTheme.accent,
                      size: 18,
                    ),
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
                  Text( '📂', style: TextStyle(fontSize: 32, decoration: TextDecoration.none,),),
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
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return LawyerCaseCard(
                lawyerCase: cases[index],
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