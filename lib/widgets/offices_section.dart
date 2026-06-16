import 'package:flutter/material.dart';
import '../data/legal_practice_areas.dart';
import '../data/mock/mock_law_firms.dart';
import '../models/law_firm.dart';
import '../repositories/law_firm_repository.dart';
import '../screens/law_firm_profile_screen.dart';
import 'office_card.dart';

class OfficesSection extends StatefulWidget {
  const OfficesSection({
    super.key,
    this.searchQuery = '',
    this.repository = const LawFirmRepository(),
  });

  final String searchQuery;
  final LawFirmRepository repository;

  @override
  State<OfficesSection> createState() => _OfficesSectionState();
}

class _OfficesSectionState extends State<OfficesSection> {
  late Future<List<LawFirm>> _lawFirmsFuture;

  @override
  void initState() {
    super.initState();
    _lawFirmsFuture = _loadLawFirms();
  }

  @override
  void didUpdateWidget(covariant OfficesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _lawFirmsFuture = _loadLawFirms();
    }
  }

  Future<List<LawFirm>> _loadLawFirms() async {
    try {
      final lawFirms = await widget.repository.fetchRecommendedLawFirms(
        searchQuery: widget.searchQuery,
      );
      if (lawFirms.isNotEmpty || widget.searchQuery.trim().isNotEmpty) {
        return lawFirms;
      }
    } catch (error) {
      debugPrint('Supabase law firms fetch failed: $error');
    }
    return _filterMockLawFirms();
  }

  List<LawFirm> _filterMockLawFirms() {
    return mockLawFirms
        .where(
          (lawFirm) => matchesPracticeAreaSearch(
            practiceAreas: lawFirm.practiceAreas,
            query: widget.searchQuery,
            extraFields: [lawFirm.name, lawFirm.specialty],
          ),
        )
        .toList();
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
          initialData: _filterMockLawFirms(),
          builder: (context, snapshot) {
            final lawFirms = snapshot.data ?? _filterMockLawFirms();
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
                  specialty: practiceAreaSummary(office.practiceAreas),
                  reviews: office.reviews,
                  avatarType: office.avatarType,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LawFirmProfileScreen(lawFirm: office),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }
}
