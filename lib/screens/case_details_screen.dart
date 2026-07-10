import 'package:flutter/material.dart';

import '../models/case_update.dart';
import '../repositories/case_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/jurii_empty_state.dart';
import '../widgets/jurii_motion.dart';

class CaseDetailsScreen extends StatefulWidget {
  const CaseDetailsScreen({
    super.key,
    required this.caseId,
    required this.title,
    required this.subtitle,
    required this.canAddUpdates,
    this.repository = const CaseRepository(),
  });

  final String caseId;
  final String title;
  final String subtitle;
  final bool canAddUpdates;
  final CaseRepository repository;

  @override
  State<CaseDetailsScreen> createState() => _CaseDetailsScreenState();
}

class _CaseDetailsScreenState extends State<CaseDetailsScreen> {
  late Future<List<CaseUpdate>> _updatesFuture;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _updatesFuture = widget.repository.fetchCaseUpdates(widget.caseId);
  }

  Future<void> _openAddUpdateSheet() async {
    final result = await showModalBottomSheet<_CaseUpdateDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Detalhes do caso')),
      floatingActionButton: widget.canAddUpdates
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.card,
              onPressed: _isSubmitting ? null : _openAddUpdateSheet,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: AppTheme.card,
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
                const SizedBox(height: 24),
                const Text(
                  'Atualizações',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.lightBlueBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.lightBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.folder_outlined, color: AppTheme.primary),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
                  color: AppTheme.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.lightGoldBorder, width: 2),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.lightBlueBorder,
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightBlueBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.lightGold,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                update.authorInitials,
                style: const TextStyle(
                  color: AppTheme.accent,
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
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      update.createdAtLabel,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  update.authorName,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (update.body.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    update.body,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      height: 1.35,
                    ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.lightBlueBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Não foi possível carregar as atualizações.',
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
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Adicionar atualização',
            style: TextStyle(
              color: AppTheme.textPrimary,
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submit,
              child: const Text('Salvar atualização'),
            ),
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
