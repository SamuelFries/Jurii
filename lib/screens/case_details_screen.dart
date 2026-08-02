import 'dart:async';

import 'package:flutter/material.dart';

import '../models/case_details.dart';
import '../models/case_movement.dart';
import '../models/case_update.dart';
import '../repositories/case_repository.dart';
import '../repositories/law_firm_repository.dart';
import '../repositories/lawyer_profile_repository.dart';
import '../theme/app_colors.dart';
import '../utils/cnj_input_formatter.dart';
import '../utils/validators.dart';
import '../widgets/jurii_empty_state.dart';
import '../widgets/jurii_form_motion.dart';
import '../widgets/jurii_motion.dart';
import 'law_firm_profile_screen.dart';
import 'lawyer_profile_screen.dart';

class CaseDetailsScreen extends StatefulWidget {
  const CaseDetailsScreen({
    super.key,
    required this.caseId,
    required this.title,
    required this.subtitle,
    required this.canAddUpdates,
    this.cnjNumber,
    this.repository = const CaseRepository(),
  });

  final String caseId;
  final String title;
  final String subtitle;
  final bool canAddUpdates;

  /// Número do processo (padrão CNJ, 20 dígitos) quando já informado.
  final String? cnjNumber;

  final CaseRepository repository;

  @override
  State<CaseDetailsScreen> createState() => _CaseDetailsScreenState();
}

class _CaseDetailsScreenState extends State<CaseDetailsScreen> {
  late Future<List<CaseUpdate>> _updatesFuture;
  Future<List<CaseMovement>>? _movementsFuture;
  String? _cnjNumber;
  bool _isSubmitting = false;

  /// Detalhe completo (relato, prazo, status, quem pode gerenciar). Chega em
  /// paralelo e refina a tela; nulo mantém o comportamento das props.
  CaseDetails? _details;
  bool _isOpeningReview = false;

  bool get _canManage => _details?.canManage ?? widget.canAddUpdates;

  /// Encerrar/reabrir/prazo: espelho do gate de escrita no servidor (inclui
  /// gestor do escritório, que não tem o can_manage estreito das
  /// atualizações). Só existe depois que o detalhe chega.
  bool get _canManageLifecycle => _details?.canManageLifecycle ?? false;
  bool get _isClosed => _details?.isClosed ?? false;

  @override
  void initState() {
    super.initState();
    _updatesFuture = widget.repository.fetchCaseUpdates(widget.caseId);
    _cnjNumber = widget.cnjNumber;
    if (_cnjNumber != null) {
      _movementsFuture = widget.repository.fetchCaseMovements(widget.caseId);
    }
    unawaited(_loadDetails());
  }

  /// Fail-open: se esta leitura falhar, a tela continua com o que as listas
  /// passaram por parâmetro (título, subtítulo, permissão, número).
  Future<void> _loadDetails() async {
    try {
      final details = await widget.repository.fetchCaseDetails(widget.caseId);
      if (!mounted || details == null) return;
      setState(() {
        _details = details;
        _cnjNumber = details.cnjNumber ?? _cnjNumber;
      });
    } catch (error) {
      debugPrint('Case details fetch failed: $error');
    }
  }

  Future<void> _confirmCloseCase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Encerrar caso?'),
        content: const Text(
          'O cliente será avisado e convidado a avaliar o atendimento. '
          'Você pode reabrir o caso depois, se precisar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Encerrar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runLifecycleAction(
      () => widget.repository.closeCase(widget.caseId),
      'Caso encerrado. O cliente foi convidado a avaliar.',
    );
  }

  Future<void> _reopenCase() async {
    await _runLifecycleAction(
      () => widget.repository.reopenCase(widget.caseId),
      'Caso reaberto.',
    );
  }

  Future<void> _runLifecycleAction(
    Future<void> Function() action,
    String successMessage,
  ) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await action();
      if (!mounted) return;
      await _loadDetails();
      if (!mounted) return;
      setState(() {
        _updatesFuture = widget.repository.fetchCaseUpdates(widget.caseId);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      debugPrint('Case lifecycle action failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível concluir. Tente novamente.')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _editDeadline() async {
    final current = _details?.deadlineAt;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now.add(const Duration(days: 7)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
      helpText: 'Prazo do caso',
      cancelText: 'Cancelar',
      confirmText: 'Salvar',
    );
    if (picked == null || !mounted) return;
    await _saveDeadline(picked);
  }

  Future<void> _saveDeadline(DateTime? deadline) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.repository.setCaseDeadline(
        caseId: widget.caseId,
        deadline: deadline,
      );
      if (!mounted) return;
      await _loadDetails();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(deadline == null ? 'Prazo removido.' : 'Prazo salvo.'),
        ),
      );
    } catch (error) {
      debugPrint('Case deadline save failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível salvar o prazo.')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// O convite de avaliação leva ao perfil público onde vive o painel de
  /// avaliações (o gate de elegibilidade é do servidor). Advogado primeiro;
  /// caso de escritório sem advogado (ou advogado indisponível/excluído)
  /// cai para o perfil do escritório — o cliente é elegível a avaliá-lo.
  Future<void> _openReview() async {
    if (_isOpeningReview) return;
    final lawyerId = _details?.assignedLawyerId;
    final lawFirmId = _details?.lawFirmId;
    if (lawyerId == null && lawFirmId == null) return;

    setState(() => _isOpeningReview = true);
    try {
      if (lawyerId != null) {
        final lawyer = await const LawyerProfileRepository().fetchLawyerById(
          lawyerId,
        );
        if (!mounted) return;
        if (lawyer != null) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LawyerProfileScreen(lawyer: lawyer),
            ),
          );
          return;
        }
      }

      if (lawFirmId != null) {
        final firm = await const LawFirmRepository().fetchLawFirmById(
          lawFirmId,
        );
        if (!mounted) return;
        if (firm != null) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LawFirmProfileScreen(lawFirm: firm),
            ),
          );
          return;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o perfil para avaliar.'),
        ),
      );
    } catch (error) {
      debugPrint('Review profile open failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o perfil para avaliar.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isOpeningReview = false);
    }
  }

  Future<void> _openCnjSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CnjNumberSheet(initialCnjNumber: _cnjNumber),
    );

    if (result == null || _isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      await widget.repository.setCaseCnjNumber(
        caseId: widget.caseId,
        cnjNumber: result,
      );
      if (!mounted) return;
      setState(() {
        _cnjNumber = result;
        _movementsFuture = widget.repository.fetchCaseMovements(widget.caseId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Número do processo salvo. O andamento passa a ser acompanhado '
            'automaticamente.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível salvar o número do processo.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _openAddUpdateSheet() async {
    final result = await showModalBottomSheet<_CaseUpdateDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AddUpdateSheet(),
    );

    if (result == null || _isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      await widget.repository.addCaseUpdate(
        caseId: widget.caseId,
        title: result.title,
        body: result.body,
      );
      if (!mounted) return;
      setState(() {
        _updatesFuture = widget.repository.fetchCaseUpdates(widget.caseId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Atualização adicionada ao caso.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível adicionar a atualização.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Detalhes do caso'),
        actions: [
          if (_canManageLifecycle)
            PopupMenuButton<String>(
              tooltip: 'Opções do caso',
              onSelected: (value) {
                switch (value) {
                  case 'close':
                    _confirmCloseCase();
                  case 'reopen':
                    _reopenCase();
                }
              },
              itemBuilder: (context) => [
                if (!_isClosed)
                  const PopupMenuItem(
                    value: 'close',
                    child: Text('Encerrar caso'),
                  )
                else
                  const PopupMenuItem(
                    value: 'reopen',
                    child: Text('Reabrir caso'),
                  ),
              ],
            ),
        ],
      ),
      floatingActionButton: _canManage && !_isClosed
          ? FloatingActionButton.extended(
              backgroundColor: colors.primary,
              foregroundColor: colors.card,
              onPressed: _isSubmitting ? null : _openAddUpdateSheet,
              icon: _isSubmitting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: colors.card,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.add_comment_outlined),
              label: const Text('Atualizar'),
            )
          : null,
      body: SafeArea(
        child: FutureBuilder<List<CaseUpdate>>(
          future: _updatesFuture,
          builder: (context, snapshot) {
            final updates = snapshot.data;

            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
              children: [
                _CaseHeader(title: widget.title, subtitle: widget.subtitle),
                if (_isClosed) ...[
                  const SizedBox(height: 12),
                  _ClosedCaseBanner(
                    showReviewButton:
                        _details?.viewerIsClient == true &&
                        (_details?.assignedLawyerId != null ||
                            _details?.lawFirmId != null),
                    isOpeningReview: _isOpeningReview,
                    onReview: _openReview,
                  ),
                ],
                if (_details?.description != null) ...[
                  const SizedBox(height: 12),
                  _ClientSummaryCard(description: _details!.description!),
                ],
                // Prazo: quem gerencia sempre vê (para poder definir); os
                // demais só quando existe.
                if (!_isClosed &&
                    (_canManageLifecycle || _details?.deadlineAt != null)) ...[
                  const SizedBox(height: 12),
                  _DeadlineCard(
                    deadlineAt: _details?.deadlineAt,
                    canEdit: _canManageLifecycle,
                    onEdit: _isSubmitting ? null : _editDeadline,
                    onClear: _isSubmitting || _details?.deadlineAt == null
                        ? null
                        : () => _saveDeadline(null),
                  ),
                ],
                // Cliente em caso sem processo não tem nada aqui: nem o
                // espaçamento (senão vira vão morto no fluxo mais comum).
                if (_cnjNumber != null ||
                    widget.canAddUpdates ||
                    _canManageLifecycle) ...[
                  const SizedBox(height: 12),
                  _ProcessNumberCard(
                    cnjNumber: _cnjNumber,
                    // set_case_cnj_number aceita advogado do caso OU gestor
                    // do escritório — mesmo público do ciclo de vida.
                    canEdit: widget.canAddUpdates || _canManageLifecycle,
                    onEdit: _isSubmitting ? null : _openCnjSheet,
                  ),
                ],
                if (_cnjNumber != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Andamento do processo',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Fonte oficial: DataJud (CNJ). Atualiza sozinho e pode '
                    'levar alguns dias.',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Key pelo número: trocar o número descarta o snapshot da
                  // future anterior (senão a timeline do processo antigo
                  // ficaria visível durante o carregamento do novo).
                  KeyedSubtree(
                    key: ValueKey('movements_$_cnjNumber'),
                    child: _CaseMovementsSection(
                      movementsFuture: _movementsFuture,
                      onRetry: () => setState(() {
                        _movementsFuture = widget.repository
                            .fetchCaseMovements(widget.caseId);
                      }),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Atualizações',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    updates == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: JuriiSkeletonList(itemCount: 3, itemHeight: 96),
                  )
                else if (snapshot.hasError)
                  _UpdatesErrorState(
                    onRetry: () => setState(() {
                      _updatesFuture = widget.repository.fetchCaseUpdates(
                        widget.caseId,
                      );
                    }),
                  )
                else if (updates == null || updates.isEmpty)
                  const _EmptyUpdatesState()
                else
                  for (var index = 0; index < updates.length; index++) ...[
                    JuriiStaggeredItem(
                      key: ValueKey('case_update_${updates[index].id}'),
                      index: index,
                      child: _CaseUpdateTimelineItem(
                        update: updates[index],
                        isLast: index == updates.length - 1,
                      ),
                    ),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CaseHeader extends StatelessWidget {
  const _CaseHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.lightBlueBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.lightBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.folder_outlined, color: colors.primary),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Número do processo no detalhe do caso. Sem número: profissional vê o
/// convite para adicionar (tom neutro; caso sem processo é o estado normal),
/// cliente não vê nada. Com número: todos veem, profissional pode editar.
class _ClosedCaseBanner extends StatelessWidget {
  const _ClosedCaseBanner({
    required this.showReviewButton,
    required this.isOpeningReview,
    required this.onReview,
  });

  final bool showReviewButton;
  final bool isOpeningReview;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.successSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.success.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline, size: 20, color: colors.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Caso encerrado',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (showReviewButton) ...[
            const SizedBox(height: 6),
            Text(
              'Como foi sua experiência? Sua avaliação ajuda outras pessoas '
              'a escolher.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: isOpeningReview ? null : onReview,
              icon: isOpeningReview
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.star_outline, size: 18),
              label: const Text('Avaliar atendimento'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ClientSummaryCard extends StatelessWidget {
  const _ClientSummaryCard({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.lightBlueBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Relato do cliente',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(color: colors.textPrimary, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _DeadlineCard extends StatelessWidget {
  const _DeadlineCard({
    required this.deadlineAt,
    required this.canEdit,
    required this.onEdit,
    required this.onClear,
  });

  final DateTime? deadlineAt;
  final bool canEdit;
  final VoidCallback? onEdit;
  final VoidCallback? onClear;

  String get _dateLabel {
    final date = deadlineAt!;
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    if (deadlineAt == null) {
      if (!canEdit) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.event_outlined, size: 18),
          label: const Text('Definir prazo'),
        ),
      );
    }

    // Mesma comparação do painel do escritório e da lista do advogado.
    final isNear = !deadlineAt!.isAfter(
      DateTime.now().add(const Duration(days: 7)),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isNear ? colors.dangerBorder : colors.lightBlueBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.event_outlined,
            size: 18,
            color: isNear ? colors.danger : colors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Prazo',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  _dateLabel,
                  style: TextStyle(
                    color: isNear ? colors.danger : colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (canEdit) ...[
            if (onClear != null)
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close, size: 18),
                color: colors.textSecondary,
                tooltip: 'Remover prazo',
              ),
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: colors.textSecondary,
              tooltip: 'Editar prazo',
            ),
          ],
        ],
      ),
    );
  }
}

class _ProcessNumberCard extends StatelessWidget {
  const _ProcessNumberCard({
    required this.cnjNumber,
    required this.canEdit,
    required this.onEdit,
  });

  final String? cnjNumber;
  final bool canEdit;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    if (cnjNumber == null && !canEdit) return const SizedBox.shrink();

    if (cnjNumber == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.tag, size: 18),
          label: const Text('Adicionar número do processo'),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.lightBlueBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.tag, size: 18, color: colors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Processo',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  formatCnj(cnjNumber!),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (canEdit)
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: colors.textSecondary,
              tooltip: 'Editar número do processo',
            ),
        ],
      ),
    );
  }
}

class _CaseMovementsSection extends StatelessWidget {
  const _CaseMovementsSection({
    required this.movementsFuture,
    required this.onRetry,
  });

  final Future<List<CaseMovement>>? movementsFuture;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CaseMovement>>(
      future: movementsFuture,
      builder: (context, snapshot) {
        final movements = snapshot.data;

        if (snapshot.connectionState == ConnectionState.waiting &&
            movements == null) {
          return const Padding(
            padding: EdgeInsets.only(top: 8),
            child: JuriiSkeletonList(itemCount: 2, itemHeight: 76),
          );
        }
        if (snapshot.hasError) {
          return _MovementsErrorState(onRetry: onRetry);
        }
        if (movements == null || movements.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: JuriiEmptyState(
              icon: Icons.gavel_outlined,
              title: 'Nenhuma movimentação pública ainda',
              message:
                  'Assim que houver andamento público, ele aparece aqui. '
                  'Processos em segredo de justiça não aparecem em '
                  'consultas públicas.',
            ),
          );
        }

        return Column(
          children: [
            for (var index = 0; index < movements.length; index++)
              JuriiStaggeredItem(
                key: ValueKey('case_movement_${movements[index].id}'),
                index: index,
                child: _MovementTimelineItem(
                  movement: movements[index],
                  isLast: index == movements.length - 1,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MovementTimelineItem extends StatelessWidget {
  const _MovementTimelineItem({required this.movement, required this.isLast});

  final CaseMovement movement;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 18),
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.lightBlueBorder, width: 2),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.lightBlueBorder,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.lightBlueBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            movement.title,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          movement.dateLabel,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    if (movement.body.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        movement.body,
                        style: TextStyle(
                          color: colors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementsErrorState extends StatelessWidget {
  const _MovementsErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.lightBlueBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Não foi possível carregar o andamento do processo.',
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

class _CnjNumberSheet extends StatefulWidget {
  const _CnjNumberSheet({required this.initialCnjNumber});

  final String? initialCnjNumber;

  @override
  State<_CnjNumberSheet> createState() => _CnjNumberSheetState();
}

class _CnjNumberSheetState extends State<_CnjNumberSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _cnjController;

  @override
  void initState() {
    super.initState();
    _cnjController = TextEditingController(
      text: formatCnj(widget.initialCnjNumber ?? ''),
    );
  }

  @override
  void dispose() {
    _cnjController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(digitsOnly(_cnjController.text));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return JuriiModalSheetScaffold(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Número do processo',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'O padrão CNJ está na capa do processo e nas intimações. Com '
              'ele, o Jurii acompanha o andamento público automaticamente e '
              'avisa o cliente quando o processo andar.',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cnjController,
              keyboardType: TextInputType.number,
              inputFormatters: const [CnjInputFormatter()],
              validator: validateCnjField,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(
                labelText: 'Número (padrão CNJ)',
                hintText: '0000000-00.0000.0.00.0000',
              ),
            ),
            const SizedBox(height: 16),
            JuriiLoadingButton(
              label: 'Salvar número',
              onPressed: _submit,
              shadow: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _CaseUpdateTimelineItem extends StatelessWidget {
  const _CaseUpdateTimelineItem({required this.update, required this.isLast});

  final CaseUpdate update;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 18),
                decoration: BoxDecoration(
                  color: colors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.lightGoldBorder, width: 2),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.lightBlueBorder,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: _CaseUpdateCard(update: update),
            ),
          ),
        ],
      ),
    );
  }
}

class _CaseUpdateCard extends StatelessWidget {
  const _CaseUpdateCard({required this.update});

  final CaseUpdate update;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.lightBlueBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.lightGold,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                update.authorInitials,
                style: TextStyle(
                  color: colors.accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        update.title,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      update.createdAtLabel,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  update.authorName,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (update.body.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    update.body,
                    style: TextStyle(color: colors.textSecondary, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdatesErrorState extends StatelessWidget {
  const _UpdatesErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.lightBlueBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Não foi possível carregar as atualizações.',
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

class _EmptyUpdatesState extends StatelessWidget {
  const _EmptyUpdatesState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: JuriiEmptyState(
        icon: Icons.timeline_outlined,
        title: 'Nenhuma atualização registrada',
        message: 'As movimentações importantes deste caso aparecerão aqui.',
      ),
    );
  }
}

class _AddUpdateSheet extends StatefulWidget {
  const _AddUpdateSheet();

  @override
  State<_AddUpdateSheet> createState() => _AddUpdateSheetState();
}

class _AddUpdateSheetState extends State<_AddUpdateSheet> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    Navigator.of(
      context,
    ).pop(_CaseUpdateDraft(title: title, body: _bodyController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return JuriiModalSheetScaffold(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Adicionar atualização',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Título',
              hintText: 'Ex.: Petição protocolada',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Descrição',
              hintText: 'Descreva o andamento do caso',
            ),
          ),
          const SizedBox(height: 16),
          JuriiLoadingButton(
            label: 'Salvar atualização',
            onPressed: _submit,
            shadow: false,
          ),
        ],
      ),
    );
  }
}

class _CaseUpdateDraft {
  final String title;
  final String body;

  const _CaseUpdateDraft({required this.title, required this.body});
}
