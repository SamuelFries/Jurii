import 'package:flutter/material.dart';

import '../models/lawyer_profile_summary.dart';
import '../repositories/lawyer_profile_repository.dart';
import '../theme/app_colors.dart';
import 'jurii_empty_state.dart';
import 'jurii_form_motion.dart';
import 'jurii_motion.dart';

/// Folha em que o escritório escolhe qual advogado da organização vai sugerir
/// ao cliente. Devolve o id do advogado escolhido, ou `null` se desistiu.
Future<String?> showRecommendLawyerSheet(
  BuildContext context, {
  required String lawFirmId,
  LawyerProfileRepository repository = const LawyerProfileRepository(),
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        RecommendLawyerSheet(lawFirmId: lawFirmId, repository: repository),
  );
}

class RecommendLawyerSheet extends StatefulWidget {
  const RecommendLawyerSheet({
    super.key,
    required this.lawFirmId,
    this.repository = const LawyerProfileRepository(),
  });

  final String lawFirmId;
  final LawyerProfileRepository repository;

  @override
  State<RecommendLawyerSheet> createState() => _RecommendLawyerSheetState();
}

class _RecommendLawyerSheetState extends State<RecommendLawyerSheet> {
  List<LawyerProfileSummary> _lawyers = const [];
  bool _isLoading = true;
  bool _loadFailed = false;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });

    try {
      final lawyers = await widget.repository.fetchLawFirmLawyers(
        widget.lawFirmId,
      );
      if (!mounted) return;
      setState(() {
        _lawyers = lawyers;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Supabase law firm lawyers fetch failed: $error');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return JuriiModalSheetScaffold(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sugerir advogado',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'O cliente recebe o perfil no chat e fala direto com o advogado. '
              'É ele quem envia a solicitação de caso depois.',
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            Flexible(child: _content(colors)),
            if (!_isLoading && !_loadFailed && _lawyers.isNotEmpty) ...[
              const SizedBox(height: 16),
              JuriiLoadingButton(
                label: 'Enviar sugestão',
                shadow: false,
                onPressed: _selectedId == null
                    ? null
                    : () => Navigator.of(context).pop(_selectedId),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _content(AppColors colors) {
    if (_isLoading) {
      return const JuriiSkeletonList(itemCount: 3, itemHeight: 76, gap: 10);
    }

    if (_loadFailed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Não foi possível carregar os advogados do escritório.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _load,
            child: const Text('Tentar novamente'),
          ),
        ],
      );
    }

    if (_lawyers.isEmpty) {
      return JuriiEmptyState(
        icon: Icons.person_search_outlined,
        title: 'Nenhum advogado para sugerir',
        message:
            'Só entram na lista advogados com cadastro aprovado e vínculo ativo. '
            'Convide na aba Equipe.',
        accentColor: colors.officePurple,
        surfaceColor: colors.officePurpleSurface,
        borderColor: colors.officePurpleBorder,
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: _lawyers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final lawyer = _lawyers[index];
        return _LawyerOption(
          lawyer: lawyer,
          selected: lawyer.id == _selectedId,
          onTap: () => setState(() => _selectedId = lawyer.id),
        );
      },
    );
  }
}

class _LawyerOption extends StatelessWidget {
  const _LawyerOption({
    required this.lawyer,
    required this.selected,
    required this.onTap,
  });

  final LawyerProfileSummary lawyer;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return JuriiPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      semanticLabel: 'Sugerir ${lawyer.name}',
      child: AnimatedContainer(
        duration: JuriiMotion.fast,
        curve: JuriiMotion.ease,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? colors.officePurpleSurface : colors.card,
          border: Border.all(
            color: selected ? colors.officePurple : colors.lightBlueBorder,
            width: selected ? 1.6 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.officePurpleSurface,
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: _photo(colors),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lawyer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${lawyer.oabLabel} · ${lawyer.primaryArea}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked_outlined,
              color: selected ? colors.officePurple : colors.divider,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _photo(AppColors colors) {
    final url = lawyer.photoUrl;
    if (url == null || url.isEmpty) return _initials(colors);

    return Image.network(
      url,
      width: 48,
      height: 48,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _initials(colors);
      },
      errorBuilder: (context, error, stackTrace) => _initials(colors),
    );
  }

  Widget _initials(AppColors colors) {
    return Center(
      child: Text(
        lawyer.initials,
        style: TextStyle(
          color: colors.officePurple,
          fontWeight: FontWeight.w900,
          fontSize: 15,
        ),
      ),
    );
  }
}
