import 'package:flutter/material.dart';
import '../data/mock/mock_messages.dart';
import '../theme/app_theme.dart';
import 'lawyer_contact_card.dart';

class LawyerContactsSection extends StatelessWidget {
  final VoidCallback? onOpenMessages;

  const LawyerContactsSection({super.key, this.onOpenMessages});

  @override
  Widget build(BuildContext context) {
    final contacts = mockLawyerContacts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Novos Contatos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (contacts.isNotEmpty)
              GestureDetector(
                onTap: onOpenMessages,
                child: const Row(
                  children: [
                    Text(
                      'Ver todas',
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
        if (contacts.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    '📭',
                    style: TextStyle(
                      fontSize: 32,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Nenhum novo contato por enquanto',
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
            itemCount: contacts.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return LawyerContactCard(
                contact: contacts[index],
                onTap: onOpenMessages,
              );
            },
          ),
      ],
    );
  }
}
