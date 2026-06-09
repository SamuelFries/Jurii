import 'package:flutter/material.dart';
import '../data/lawyer_contacts_data.dart';
import '../theme/app_theme.dart';
import 'lawyer_contact_card.dart';

class LawyerContactsSection extends StatelessWidget {
  const LawyerContactsSection({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: substituir por dados reais da API
    final contacts = lawyerContacts;

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
                onTap: () {
                  // TODO: navegar para lista completa de contatos
                },
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
        if (contacts.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Text( '📭', style: TextStyle( fontSize: 32, decoration: TextDecoration.none, ), ), 
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
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return LawyerContactCard(
                contact: contacts[index],
                onTap: () {
                  // TODO: navegar para conversa
                },
              );
            },
          ),
      ],
    );
  }
}