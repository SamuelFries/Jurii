import 'package:flutter/material.dart';
import '../data/mock/mock_law_firms.dart';
import '../models/law_firm.dart';
import '../repositories/law_firm_repository.dart';
import 'office_card.dart';

class OfficesSection extends StatefulWidget {
  const OfficesSection({
    super.key,
    this.repository = const LawFirmRepository(),
  });

  final LawFirmRepository repository;

  @override
  State<OfficesSection> createState() => _OfficesSectionState();
}

class _OfficesSectionState extends State<OfficesSection> {
  late final Future<List<LawFirm>> _lawFirmsFuture;

  @override
  void initState() {
    super.initState();
    _lawFirmsFuture = _loadLawFirms();
  }

  Future<List<LawFirm>> _loadLawFirms() async {
    try {
      final lawFirms = await widget.repository.fetchRecommendedLawFirms();
      if (lawFirms.isNotEmpty) return lawFirms;
    } catch (error) {
      debugPrint('Supabase law firms fetch failed: $error');
    }
    return mockLawFirms;
  }

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
        FutureBuilder<List<LawFirm>>(
          future: _lawFirmsFuture,
          initialData: mockLawFirms,
          builder: (context, snapshot) {
            final lawFirms = snapshot.data ?? mockLawFirms;
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: lawFirms.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final office = lawFirms[index];
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
            );
          },
        ),
      ],
    );
  }
}
