import 'package:flutter/material.dart';

import '../data/mock/mock_lawyers.dart';
import '../models/lawyer_profile_summary.dart';
import '../repositories/lawyer_profile_repository.dart';
import '../screens/lawyer_profile_screen.dart';
import '../theme/app_theme.dart';
import 'lawyer_profile_card.dart';

class RecommendedLawyersSection extends StatefulWidget {
  const RecommendedLawyersSection({
    super.key,
    this.repository = const LawyerProfileRepository(),
  });

  final LawyerProfileRepository repository;

  @override
  State<RecommendedLawyersSection> createState() =>
      _RecommendedLawyersSectionState();
}

class _RecommendedLawyersSectionState extends State<RecommendedLawyersSection> {
  late final Future<List<LawyerProfileSummary>> _lawyersFuture;

  @override
  void initState() {
    super.initState();
    _lawyersFuture = widget.repository.fetchRecommendedLawyers();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Advogados recomendados',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        const Text(
          'Perfis verificados para atendimento direto.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<LawyerProfileSummary>>(
          future: _lawyersFuture,
          initialData: mockRecommendedLawyers,
          builder: (context, snapshot) {
            final lawyers = snapshot.data ?? mockRecommendedLawyers;
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: lawyers.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final lawyer = lawyers[index];
                return LawyerProfileCard(
                  lawyer: lawyer,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LawyerProfileScreen(lawyer: lawyer),
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
