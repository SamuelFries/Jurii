import 'package:flutter/material.dart';
import '../data/lawyer_contacts_data.dart';
import '../theme/app_theme.dart';
import 'lawyer_contact_card.dart';

class LawyerContactsSection extends StatelessWidget {
  const LawyerContactsSection({super.key});

  @override
  Widget build(BuildContext context) {
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
          itemCount: lawyerContacts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return LawyerContactCard(
              contact: lawyerContacts[index],
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