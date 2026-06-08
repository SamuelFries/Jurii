import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'attention_today_card.dart';

class AttentionTodaySection extends StatelessWidget {
  const AttentionTodaySection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Atenção Hoje',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        const Row(
          children: [
            Expanded(
              child: AttentionTodayCard(
                emoji: '💬',
                count: 5,
                label: 'Mensagens\npendentes',
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: AttentionTodayCard(
                emoji: '📅',
                count: 2,
                label: 'Reuniões\nhoje',
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: AttentionTodayCard(
                emoji: '⏰',
                count: 1,
                label: 'Prazos\npróximos',
              ),
            ),
          ],
        ),
      ],
    );
  }
}