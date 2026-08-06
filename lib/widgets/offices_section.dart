import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../data/legal_practice_areas.dart';
import '../data/mock/mock_law_firms.dart';
import '../models/law_firm.dart';
import '../repositories/law_firm_repository.dart';
import '../screens/law_firm_profile_screen.dart';
import '../services/location_service.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../utils/discovery_pagination.dart';
import '../utils/geo_distance.dart';
import '../utils/office_sorting.dart';
import 'discovery_load_more_button.dart';
import 'jurii_empty_state.dart';
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
  // Estado explícito (não FutureBuilder): paginação ACUMULA páginas, e um
  // FutureBuilder só sabe recomeçar do zero.
  List<LawFirm>? _lawFirms;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  bool _loadFailed = false;

  /// Offset em coordenadas do SERVIDOR: avança pelo que ele entregou, não
  /// pelo tamanho da lista na tela (o dedupe visual pode descartar item).
  int _nextOffset = 0;

  /// Geração do fetch: trocar a busca com uma página em voo descarta a
  /// resposta atrasada (mesma race da agenda, mesmo antídoto).
  int _generation = 0;

  Position? _userPosition;
  bool _locationChipDismissed = false;
  bool _isLocating = false;

  /// Padrão: relevância (a ordem do servidor, onde vive o destaque pago).
  OfficeSort _sort = OfficeSort.relevance;

  /// Incrementado a cada gesto de ordenação. Um await de GPS que terminar
  /// depois de o usuário já ter escolhido OUTRO método não pode sobrescrever
  /// a escolha mais recente.
  int _sortGesture = 0;

  bool get _shouldUseMock {
    if (!SupabaseConfig.isReady) return true;
    return SupabaseConfig.client.auth.currentUser == null;
  }

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
    // Se a permissão JÁ foi concedida antes, mostra as distâncias direto —
    // sem nunca abrir diálogo por conta própria (isso é do chip).
    if (!_shouldUseMock) {
      LocationService.instance.refreshIfPermitted().then((position) {
        if (mounted && position != null) {
          setState(() => _userPosition = position);
        }
      });
    }
  }

  Future<void> _enableDistances() async {
    setState(() => _isLocating = true);
    final position = await LocationService.instance.requestAndRefresh();
    if (!mounted) return;
    setState(() {
      _isLocating = false;
      _userPosition = position;
      // Negou (ou serviço desligado): o chip some nesta sessão — pedir de
      // novo a cada rebuild seria insistência.
      if (position == null) _locationChipDismissed = true;
    });
  }

  /// Distância calculada NO APARELHO. Em produção, só distância real: o
  /// distance_label legado do banco (fake, herdado do seed) não é exibido —
  /// ele sobrevive apenas no modo demo (mocks).
  String _distanceLabelFor(LawFirm office) {
    if (_shouldUseMock) return office.distance;
    final position = _userPosition;
    if (position == null || !office.hasCoordinates) return '';
    final km = haversineKm(
      lat1: position.latitude,
      lon1: position.longitude,
      lat2: office.latitude!,
      lon2: office.longitude!,
    );
    return formatDistanceBr(km);
  }

  bool get _showLocationChip =>
      !_shouldUseMock && _userPosition == null && !_locationChipDismissed;

  /// Troca de ordenação: RECARREGA do servidor, da primeira página.
  ///
  /// Reordenar só o que já está na tela responderia "qual o mais perto DOS DEZ
  /// PRIMEIROS" — a lista chega paginada por relevância, e o mais próximo pode
  /// estar na página 4. Quem enxerga o conjunto inteiro é o servidor, então é
  /// ele que ordena (20260817120000) e a paginação passa a andar já na ordem
  /// certa. No modo demo não há servidor: lá o sort local sobre os mocks é a
  /// resposta completa.
  Future<void> _changeSort(OfficeSort sort) async {
    if (sort == _sort) return;
    final gesture = ++_sortGesture;

    // "Distância" precisa da posição; escolher a opção É o gesto do usuário
    // que autoriza pedir a permissão. No modo demo (mocks sem coordenadas)
    // não há o que pedir: seleciona e segue — nada de diálogo de permissão
    // real por um sort que não muda nada.
    if (sort == OfficeSort.distance &&
        _userPosition == null &&
        !_shouldUseMock) {
      setState(() => _isLocating = true);
      final position = await LocationService.instance.requestAndRefresh();
      if (!mounted) return;
      // O usuário escolheu outro método enquanto o GPS respondia: a posição
      // ainda vale (guarda), mas a escolha mais recente vence.
      if (gesture != _sortGesture) {
        setState(() {
          _isLocating = false;
          if (position != null) _userPosition = position;
        });
        return;
      }
      if (position == null) {
        setState(() {
          _isLocating = false;
          _locationChipDismissed = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ative a localização para ordenar por distância.'),
          ),
        );
        return; // mantém a ordenação atual
      }
      setState(() {
        _isLocating = false;
        _userPosition = position;
        _sort = sort;
      });
      await _loadFirstPage();
      return;
    }

    setState(() => _sort = sort);
    await _loadFirstPage();
  }

  @override
  void didUpdateWidget(covariant OfficesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _loadFirstPage();
    }
  }

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    setState(() {
      _lawFirms = null;
      _loadFailed = false;
      _hasMore = false;
      // Sem zerar aqui, uma página 2 em voo da BUSCA ANTERIOR deixaria o
      // spinner preso para sempre: a resposta atrasada é descartada pela
      // guarda de geração ANTES de limpar a flag.
      _isLoadingMore = false;
      _nextOffset = 0;
    });

    if (_shouldUseMock) {
      // Demo: uma página só, direto dos mocks.
      setState(() => _lawFirms = _filterMockLawFirms());
      return;
    }

    try {
      final page = await widget.repository.fetchRecommendedLawFirms(
        searchQuery: widget.searchQuery,
        offset: 0,
        limit: LawFirmRepository.firstPageSize,
        sort: _sort,
        userLatitude: _userPosition?.latitude,
        userLongitude: _userPosition?.longitude,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _lawFirms = page.items;
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
      final page = await widget.repository.fetchRecommendedLawFirms(
        searchQuery: widget.searchQuery,
        offset: _nextOffset,
        limit: LawFirmRepository.nextPageSize,
        // MESMA ordenação da primeira página: pedir a página 2 sob outra
        // ordem devolveria um recorte de outra lista — com repetido e com
        // faltando.
        sort: _sort,
        userLatitude: _userPosition?.latitude,
        userLongitude: _userPosition?.longitude,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _isLoadingMore = false;
        _nextOffset += page.items.length;
        _lawFirms = appendUniqueBy(
          _lawFirms ?? const [],
          page.items,
          (office) => office.id,
        );
        _hasMore = page.hasMore;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      // A lista que já está na tela fica; só o bloco novo falhou.
      setState(() => _isLoadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível carregar mais escritórios.'),
        ),
      );
    }
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
        Row(
          children: [
            Expanded(
              child: Text(
                'Escritórios recomendados',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (_showLocationChip)
              _DistanceChip(isLocating: _isLocating, onTap: _enableDistances),
          ],
        ),
        const SizedBox(height: 10),
        // Ordenação: relevância (padrão, com o destaque pago), avaliação ou
        // distância. Troca em tempo real — sort local, sem novo fetch.
        Row(
          children: [
            for (final sort in OfficeSort.values) ...[
              _SortChip(
                label: sort.label,
                selected: _sort == sort,
                busy: _isLocating && sort == OfficeSort.distance,
                onTap: () => _changeSort(sort),
              ),
              if (sort != OfficeSort.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _buildBody(),
      ],
    );
  }

  Widget _buildBody() {
    if (_loadFailed && !_shouldUseMock) {
      return JuriiFadeThroughSwitcher(
        child: KeyedSubtree(
          key: const ValueKey('offices_error'),
          child: _OfficesErrorState(onRetry: _loadFirstPage),
        ),
      );
    }

    final loaded = _lawFirms;
    if (loaded == null) {
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

    // A ordem CERTA já veio do servidor, que enxerga o conjunto inteiro.
    // Reordenar aqui serve ao modo demo (mocks, sem servidor) e é inofensivo
    // no resto: aplicar o mesmo critério sobre uma lista já ordenada por ele
    // não muda nada — e cobre a janela de deploy contra um banco que ainda
    // devolva a ordem antiga.
    final lawFirms = sortLawFirms(
      loaded,
      _sort,
      userLatitude: _userPosition?.latitude,
      userLongitude: _userPosition?.longitude,
    );

    if (lawFirms.isEmpty) {
      return const JuriiFadeThroughSwitcher(
        child: KeyedSubtree(
          key: ValueKey('offices_empty'),
          child: _EmptyOfficesState(),
        ),
      );
    }

    return JuriiFadeThroughSwitcher(
      // Keyada por busca+ordenação, não pelos ids: anexar página cresce a
      // lista no lugar (sem re-disparar fade/stagger do que já estava);
      // trocar a ordenação continua animando a transição, como antes.
      child: Column(
        key: ValueKey('offices_${widget.searchQuery}_${_sort.name}'),
        children: [
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: lawFirms.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final office = lawFirms[index];
              return JuriiStaggeredItem(
                key: ValueKey('office_${office.id}'),
                index: index,
                child: OfficeCard(
                  initials: office.initials,
                  officeName: office.name,
                  rating: office.rating,
                  distance: _distanceLabelFor(office),
                  specialty: practiceAreaSummary(office.practiceAreas),
                  reviews: office.reviews,
                  avatarType: office.avatarType,
                  avatarUrl: office.avatarUrl,
                  isFeatured: office.isFeatured,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LawFirmProfileScreen(lawFirm: office),
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
              label: 'Ver mais escritórios',
              isLoading: _isLoadingMore,
              onPressed: _loadMore,
            ),
          ],
        ],
      ),
    );
  }
}

/// Chip de método de ordenação (relevância/avaliação/distância). Selecionado
/// usa o par lightGold + accent, o mesmo do FilterChip da home — seguro nos
/// dois temas.
class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return JuriiPressable(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(999),
      semanticSelected: selected,
      semanticLabel: 'Ordenar por $label',
      child: AnimatedContainer(
        duration: JuriiMotion.fast,
        curve: JuriiMotion.ease,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colors.lightGold : colors.card,
          border: Border.all(
            color: selected ? colors.lightGoldBorder : colors.lightBlueBorder,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy) ...[
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.accent,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? colors.textPrimary : colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip discreto que pede a localização só por gesto do usuário — nunca há
/// popup de permissão não solicitado. Some após a resposta (concedida vira
/// distâncias; negada não insiste).
class _DistanceChip extends StatelessWidget {
  const _DistanceChip({required this.isLocating, required this.onTap});

  final bool isLocating;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return JuriiPressable(
      onTap: isLocating ? null : onTap,
      borderRadius: BorderRadius.circular(999),
      semanticLabel: 'Ver distâncias até os escritórios',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.lightBlue,
          border: Border.all(color: colors.lightBlueBorder),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLocating)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                ),
              )
            else
              Icon(Icons.near_me_outlined, size: 14, color: colors.primary),
            const SizedBox(width: 6),
            Text(
              'Ver distâncias',
              style: TextStyle(
                color: colors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyOfficesState extends StatelessWidget {
  const _EmptyOfficesState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: JuriiEmptyState(
        icon: Icons.apartment_outlined,
        title: 'Nenhum escritório encontrado',
        message: 'Ajuste a busca ou tente novamente em alguns instantes.',
      ),
    );
  }
}

class _OfficesErrorState extends StatelessWidget {
  const _OfficesErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.lightBlueBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Não foi possível carregar os escritórios.',
            style: TextStyle(
              color: colors.textSecondary,
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
