import 'package:flutter/material.dart';

import '../data/legal_practice_areas.dart';
import '../data/mock/mock_lawyers.dart';
import '../models/lawyer_profile_summary.dart';
import '../repositories/lawyer_profile_repository.dart';
import '../screens/lawyer_profile_screen.dart';
import '../services/supabase_config.dart';
import '../theme/app_theme.dart';
import 'jurii_motion.dart';
import 'lawyer_profile_card.dart';

class RecommendedLawyersSection extends StatefulWidget {
  const RecommendedLawyersSection({
    super.key,
    this.searchQuery = '',
    this.repository = const LawyerProfileRepository(),
  });

  final String searchQuery;
  final LawyerProfileRepository repository;

  @override
  State<RecommendedLawyersSection> createState() =>
      _RecommendedLawyersSectionState();
}

class _RecommendedLawyersSectionState extends State<RecommendedLawyersSection> {
  late Future<List<LawyerProfileSummary>> _lawyersFuture;

  @override
  void initState() {
    super.initState();
    _lawyersFuture = _loadLawyers();
  }

  @override
  void didUpdateWidget(covariant RecommendedLawyersSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _lawyersFuture = _loadLawyers();
    }
  }

  Future<List<LawyerProfileSummary>> _loadLawyers() {
    return widget.repository.fetchRecommendedLawyers(
      searchQuery: widget.searchQuery,
    );
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
          builder: (context, snapshot) {
            final shouldUseMock = !SupabaseConfig.isReady;
            final lawyers =
                snapshot.data ??
                (shouldUseMock ? _filterMockLawyers() : const []);

            if (snapshot.connectionState == ConnectionState.waiting &&
                !shouldUseMock) {
              return const JuriiFadeThroughSwitcher(
                child: KeyedSubtree(
                  key: ValueKey('recommended_lawyers_loading'),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: JuriiSkeletonList(itemCount: 2, itemHeight: 88),
                  ),
                ),
              );
            }

            if (lawyers.isEmpty) {
              return const JuriiFadeThroughSwitcher(
                child: KeyedSubtree(
                  key: ValueKey('recommended_lawyers_empty'),
                  child: _EmptyRecommendedLawyersState(),
                ),
              );
            }

            return JuriiFadeThroughSwitcher(
              child: ListView.separated(
                key: ValueKey(
                  'recommended_lawyers_${widget.searchQuery}_${lawyers.map((lawyer) => lawyer.id).join('|')}',
                ),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: lawyers.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final lawyer = lawyers[index];
                  return JuriiStaggeredItem(
                    key: ValueKey('recommended_lawyer_${lawyer.id}'),
                    index: index,
                    child: LawyerProfileCard(
                      lawyer: lawyer,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LawyerProfileScreen(lawyer: lawyer),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  List<LawyerProfileSummary> _filterMockLawyers() {
    return mockRecommendedLawyers
        .where(
          (lawyer) => matchesPracticeAreaSearch(
            practiceAreas: lawyer.practiceAreas,
            query: widget.searchQuery,
            extraFields: [lawyer.name, lawyer.primaryArea],
          ),
        )
        .toList();
  }
}

class _EmptyRecommendedLawyersState extends StatelessWidget {
  const _EmptyRecommendedLawyersState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightBlueBorder),
      ),
      child: const Text(
        'Nenhum advogado recomendado disponível no momento.',
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
