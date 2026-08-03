import 'package:flutter/material.dart';

import '../data/legal_practice_areas.dart';
import '../data/mock/mock_lawyers.dart';
import '../models/lawyer_profile_summary.dart';
import '../repositories/lawyer_profile_repository.dart';
import '../screens/lawyer_profile_screen.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../utils/discovery_pagination.dart';
import 'discovery_load_more_button.dart';
import 'jurii_empty_state.dart';
import 'jurii_error_state.dart';
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
  // Estado explícito (não FutureBuilder): paginação ACUMULA páginas, e um
  // FutureBuilder só sabe recomeçar do zero.
  List<LawyerProfileSummary>? _lawyers;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  bool _loadFailed = false;

  /// Offset em coordenadas do SERVIDOR: avança pelo que ele entregou, não
  /// pelo tamanho da lista na tela (o dedupe visual pode descartar item).
  int _nextOffset = 0;

  /// Geração do fetch: trocar a busca com uma página em voo descarta a
  /// resposta atrasada (mesma race da agenda, mesmo antídoto).
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  @override
  void didUpdateWidget(covariant RecommendedLawyersSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _loadFirstPage();
    }
  }

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    setState(() {
      _lawyers = null;
      _loadFailed = false;
      _hasMore = false;
      _nextOffset = 0;
    });
    try {
      final page = await widget.repository.fetchRecommendedLawyers(
        searchQuery: widget.searchQuery,
        offset: 0,
        limit: LawyerProfileRepository.firstPageSize,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _lawyers = page.items;
        _hasMore = page.hasMore;
        _nextOffset = page.items.length;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _loadFailed = true);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    final generation = _generation;
    setState(() => _isLoadingMore = true);
    try {
      final page = await widget.repository.fetchRecommendedLawyers(
        searchQuery: widget.searchQuery,
        offset: _nextOffset,
        limit: LawyerProfileRepository.nextPageSize,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _isLoadingMore = false;
        _nextOffset += page.items.length;
        _lawyers = appendUniqueBy(
          _lawyers ?? const [],
          page.items,
          (lawyer) => lawyer.id,
        );
        _hasMore = page.hasMore;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      // A lista que já está na tela fica; só o bloco novo falhou.
      setState(() => _isLoadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível carregar mais advogados.'),
        ),
      );
    }
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
        Text(
          'Perfis verificados para atendimento direto.',
          style: TextStyle(color: context.jColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 16),
        _buildBody(),
      ],
    );
  }

  Widget _buildBody() {
    final shouldUseMock = !SupabaseConfig.isReady;
    // Demo renderiza os mocks já no primeiro frame (o load é um microtask,
    // mas o skeleton piscaria à toa).
    final lawyers = _lawyers ?? (shouldUseMock ? _filterMockLawyers() : null);

    if (_loadFailed && !shouldUseMock) {
      return JuriiFadeThroughSwitcher(
        child: KeyedSubtree(
          key: const ValueKey('recommended_lawyers_error'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: JuriiErrorState(
              title: 'Não foi possível carregar os advogados.',
              onRetry: _loadFirstPage,
            ),
          ),
        ),
      );
    }

    if (lawyers == null) {
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
      // Keyada pela BUSCA, não pelos ids: anexar página cresce a lista no
      // lugar, sem re-disparar o fade e o stagger de tudo que já estava lá.
      child: Column(
        key: ValueKey('recommended_lawyers_${widget.searchQuery}'),
        children: [
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: lawyers.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
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
          if (_hasMore) ...[
            const SizedBox(height: 12),
            DiscoveryLoadMoreButton(
              label: 'Ver mais advogados',
              isLoading: _isLoadingMore,
              onPressed: _loadMore,
            ),
          ],
        ],
      ),
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
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: JuriiEmptyState(
        icon: Icons.person_search_outlined,
        title: 'Nenhum advogado recomendado',
        message: 'Ajuste a busca ou tente novamente em alguns instantes.',
      ),
    );
  }
}
