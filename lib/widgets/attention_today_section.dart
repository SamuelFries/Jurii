import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'attention_today_card.dart';

class AttentionTodaySection extends StatelessWidget {
  const AttentionTodaySection({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: substituir por dados reais da API
    const int pendingMessages = 0;
    const int meetingsToday = 0;
    const int upcomingDeadlines = 0;
    const bool hasAttention =
        pendingMessages > 0 || meetingsToday > 0 || upcomingDeadlines > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Atenção Hoje',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (!hasAttention)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Text('✅', style: TextStyle(fontSize: 32, decoration: TextDecoration.none, ),),
                  SizedBox(height: 8),
                  Text(
                    'Nenhuma atenção necessária hoje',
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
          const Row(
            children: [
              Expanded(
                child: AttentionTodayCard(
                  emoji: '💬',
                  count: pendingMessages,
                  label: 'Mensagens\npendentes',
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: AttentionTodayCard(
                  emoji: '📅',
                  count: meetingsToday,
                  label: 'Reuniões\nhoje',
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: AttentionTodayCard(
                  emoji: '⏰',
                  count: upcomingDeadlines,
                  label: 'Prazos\npróximos',
                ),
              ),
            ],
          ),
      ],
    );
  }
}