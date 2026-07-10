import 'package:flutter/material.dart';
import '../data/legal_practice_areas.dart';
import '../data/mock/mock_law_firms.dart';
import '../models/law_firm.dart';
import '../repositories/law_firm_repository.dart';
import '../screens/law_firm_profile_screen.dart';
import '../services/supabase_config.dart';
import '../theme/app_theme.dart';
import 'jurii_motion.dart';
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

  bool get _shouldUseMock {
    if (!SupabaseConfig.isReady) return true;
    return SupabaseConfig.client.auth.currentUser == null;
  }

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

  Future<List<LawFirm>> _loadLawFirms() {
    if (_shouldUseMock) {
      return Future.value(_filterMockLawFirms());
    }
    return widget.repository.fetchRecommendedLawFirms(
      searchQuery: widget.searchQuery,
    );
  }

  void _retry() {
    setState(() {
      _lawFirmsFuture = _loadLawFirms();
    });
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
          'Escritórios recomendados',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<LawFirm>>(
          future: _lawFirmsFuture,
          builder: (context, snapshot) {
            final shouldUseMock = _shouldUseMock;

            if (snapshot.connectionState == ConnectionState.waiting &&
                !shouldUseMock) {
              return const JuriiFadeThroughSwitcher(
                child: KeyedSubtree(
                  key: ValueKey('offices_loading'),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: JuriiSkeletonList(itemCount: 2, itemHeight: 88),
                  ),
                ),
              );
            }

            if (snapshot.hasError && !shouldUseMock) {
              return JuriiFadeThroughSwitcher(
                child: KeyedSubtree(
                  key: const ValueKey('offices_error'),
                  child: _OfficesErrorState(onRetry: _retry),
                ),
              );
            }

            final lawFirms =
                snapshot.data ??
                (shouldUseMock ? _filterMockLawFirms() : const <LawFirm>[]);

            if (lawFirms.isEmpty) {
              return const JuriiFadeThroughSwitcher(
                child: KeyedSubtree(
                  key: ValueKey('offices_empty'),
                  child: _EmptyOfficesState(),
                ),
              );
            }

            return JuriiFadeThroughSwitcher(
              child: ListView.separated(
                key: ValueKey(
                  'offices_${widget.searchQuery}_${lawFirms.map((lawFirm) => lawFirm.id).join('|')}',
                ),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: lawFirms.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final office = lawFirms[index];
                  return JuriiStaggeredItem(
                    key: ValueKey('office_${office.id}'),
                    index: index,
                    child: OfficeCard(
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
                            builder: (_) =>
                                LawFirmProfileScreen(lawFirm: office),
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
}

class _EmptyOfficesState extends StatelessWidget {
  const _EmptyOfficesState();

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
        'Nenhum escritório encontrado',
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _OfficesErrorState extends StatelessWidget {
  const _OfficesErrorState({required this.onRetry});

  final VoidCallback onRetry;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Não foi possível carregar os escritórios.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}
