import 'package:flutter/material.dart';

import '../data/legal_practice_areas.dart';
import '../models/law_firm.dart';
import '../models/lawyer_profile_summary.dart';
import '../repositories/favorites_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/jurii_empty_state.dart';
import '../widgets/jurii_error_state.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/lawyer_profile_card.dart';
import '../widgets/office_card.dart';
import 'law_firm_profile_screen.dart';
import 'lawyer_profile_screen.dart';

/// Favoritos do cliente: advogados e escritórios salvos pelo coração dos
/// perfis. Lista própria, fora do ranking da descoberta — favorito não
/// reordena busca nem conflita com o destaque pago.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({
    super.key,
    this.repository = const FavoritesRepository(),
  });

  final FavoritesRepository repository;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<LawyerProfileSummary>? _lawyers;
  List<LawFirm>? _firms;
  bool _loadFailed = false;
  bool _showFirms = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _lawyers = null;
      _firms = null;
      _loadFailed = false;
    });
    await _reloadSilently(showErrorState: true);
  }

  /// Recarrega mantendo o que está na tela (usado ao voltar de um perfil,
  /// onde o usuário pode ter desfavoritado pelo coração).
  Future<void> _reloadSilently({bool showErrorState = false}) async {
    try {
      final results = await Future.wait([
        widget.repository.fetchFavoriteLawyers(),
        widget.repository.fetchFavoriteLawFirms(),
      ], eagerError: true);
      if (!mounted) return;
      setState(() {
        _lawyers = results[0] as List<LawyerProfileSummary>;
        _firms = results[1] as List<LawFirm>;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (showErrorState) setState(() => _loadFailed = true);
    }
  }

  void _openLawyer(LawyerProfileSummary lawyer) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => LawyerProfileScreen(lawyer: lawyer),
          ),
        )
        .then((_) => _reloadSilently());
  }

  void _openFirm(LawFirm firm) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => LawFirmProfileScreen(lawFirm: firm),
          ),
        )
        .then((_) => _reloadSilently());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Favoritos'),
        backgroundColor: colors.background,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            _TypeToggle(
              showFirms: _showFirms,
              lawyersCount: _lawyers?.length,
              firmsCount: _firms?.length,
              onChanged: (value) => setState(() => _showFirms = value),
            ),
            const SizedBox(height: 16),
            ..._buildList(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildList() {
    if (_loadFailed) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: JuriiErrorState(
            title: 'Não foi possível carregar seus favoritos.',
            onRetry: _load,
          ),
        ),
      ];
    }

    final lawyers = _lawyers;
    final firms = _firms;
    if (lawyers == null || firms == null) {
      return const [JuriiSkeletonList(itemCount: 3, itemHeight: 88)];
    }

    if (_showFirms) {
      if (firms.isEmpty) {
        return const [
          JuriiEmptyState(
            icon: Icons.favorite_border,
            title: 'Nenhum escritório favorito',
            message:
                'Toque no coração no perfil de um escritório para salvá-lo aqui.',
          ),
        ];
      }
      return [
        for (final (index, firm) in firms.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: JuriiStaggeredItem(
              key: ValueKey('favorite_firm_${firm.id}'),
              index: index,
              child: OfficeCard(
                initials: firm.initials,
                officeName: firm.name,
                rating: firm.rating,
                distance: '',
                specialty: practiceAreaSummary(firm.practiceAreas),
                reviews: firm.reviews,
                avatarType: firm.avatarType,
                avatarUrl: firm.avatarUrl,
                isFeatured: firm.isFeatured,
                onTap: () => _openFirm(firm),
              ),
            ),
          ),
      ];
    }

    if (lawyers.isEmpty) {
      return const [
        JuriiEmptyState(
          icon: Icons.favorite_border,
          title: 'Nenhum advogado favorito',
          message:
              'Toque no coração no perfil de um advogado para salvá-lo aqui.',
        ),
      ];
    }
    return [
      for (final (index, lawyer) in lawyers.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: JuriiStaggeredItem(
            key: ValueKey('favorite_lawyer_${lawyer.id}'),
            index: index,
            child: LawyerProfileCard(
              lawyer: lawyer,
              onTap: () => _openLawyer(lawyer),
            ),
          ),
        ),
    ];
  }
}

/// Alterna entre as listas. Mesmo par de pílulas da agenda: selecionada em
/// dourado, 48dp de alvo, a já selecionada não é acionável.
class _TypeToggle extends StatelessWidget {
  const _TypeToggle({
    required this.showFirms,
    required this.lawyersCount,
    required this.firmsCount,
    required this.onChanged,
  });

  final bool showFirms;
  final int? lawyersCount;
  final int? firmsCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    Widget pill({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: InkWell(
            onTap: selected ? null : onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? colors.lightGold : colors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? colors.lightGoldBorder
                      : colors.lightBlueBorder,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? colors.accent : colors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      );
    }

    String withCount(String label, int? count) =>
        count == null ? label : '$label ($count)';

    return Row(
      children: [
        pill(
          label: withCount('Advogados', lawyersCount),
          selected: !showFirms,
          onTap: () => onChanged(false),
        ),
        const SizedBox(width: 8),
        pill(
          label: withCount('Escritórios', firmsCount),
          selected: showFirms,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }
}
