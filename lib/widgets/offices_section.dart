import 'package:flutter/material.dart';
import '../data/mock/mock_law_firms.dart';
import 'office_card.dart';

class OfficesSection extends StatelessWidget {
  const OfficesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Escritórios Recomendados',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: mockLawFirms.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final office = mockLawFirms[index];
            return OfficeCard(
              initials: office.initials,
              officeName: office.name,
              rating: office.rating,
              distance: office.distance,
              specialty: office.specialty,
              reviews: office.reviews,
              avatarType: office.avatarType,
              onTap: () => debugPrint('Abrir perfil: ${office.id}'),
            );
          },
        ),
      ],
    );
  }
}
