import 'package:flutter/material.dart';

import '../data/mock/mock_firm_workspace.dart';
import '../data/mock/mock_users.dart';
import '../models/firm_case_overview.dart';
import '../models/firm_team_member.dart';
import '../models/firm_workspace.dart';
import '../repositories/case_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_theme.dart';
import 'case_details_screen.dart';

class FirmCasesScreen extends StatefulWidget {
  const FirmCasesScreen({
    super.key,
    this.workspace,
    this.repository = const CaseRepository(),
  });

  final FirmWorkspace? workspace;
  final CaseRepository repository;

  @override
  State<FirmCasesScreen> createState() => _FirmCasesScreenState();
}

class _FirmCasesScreenState extends State<FirmCasesScreen> {
  late Future<List<FirmCaseOverview>> _casesFuture;

  @override
  void initState() {
    super.initState();
    _casesFuture = _loadCases();
  }

  @override
  void didUpdateWidget(covariant FirmCasesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace?.firm.id != widget.workspace?.firm.id) {
      _casesFuture = _loadCases();
    }
  }

  Future<List<FirmCaseOverview>> _loadCases() async {
    final lawFirmId = widget.workspace?.firm.id;
    if (!SupabaseConfig.isReady || lawFirmId == null) return mockFirmCases;

    try {
      return await widget.repository.fetchLawFirmCases(lawFirmId);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _openCaseDetails(FirmCaseOverview overview) async {
    final currentUserId = SupabaseConfig.isReady
        ? SupabaseConfig.client.auth.currentUser?.id
        : mockCurrentUser.id;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CaseDetailsScreen(
          caseId: overview.id,
          title: overview.title,
          subtitle: '${overview.clientName} · ${overview.assignedLawyer}',
          canAddUpdates:
              widget.workspace?.canAttendAssignedCases == true &&
              overview.assignedLawyerId == currentUserId,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      _casesFuture = _loadCases();
    });
  }

  Future<void> _openAssignCaseSheet(FirmCaseOverview overview) async {
    final workspace = widget.workspace;
    final lawyers =
        workspace?.teamMembers
            .where((member) => member.canReceiveCaseAssignment)
            .toList() ??
        const <FirmTeamMember>[];

    if (workspace?.fromSupabase != true || workspace?.canAssignCases != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Apenas dono, admin e secretaria podem atribuir casos.',
          ),
        ),
      );
      return;
    }

    if (lawyers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum advogado ativo disponível para atribuição.'),
        ),
      );
      return;
    }

    final selectedLawyer = await showModalBottomSheet<FirmTeamMember>(
      context: context,
      useSafeArea: true,
      builder: (_) => _AssignLawyerSheet(
        lawyers: lawyers,
        selectedLawyerId: overview.assignedLawyerId,
      ),
    );

    if (selectedLawyer == null) return;

    try {
      await widget.repository.assignLawFirmCase(
        lawFirmId: workspace!.firm.id,
        caseId: overview.id,
        lawyerProfileId: selectedLawyer.id,
      );
      if (!mounted) return;
      setState(() {
        _casesFuture = _loadCases();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Caso atribuído a ${selectedLawyer.name}.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyAssignError(error))));
    }
  }

  String _friendlyAssignError(Object error) {
    final message = error.toString();
    if (message.contains('Only office case managers')) {
      return 'Apenas dono, admin e secretaria podem atribuir casos.';
    }
    if (message.contains('Target member must be an active lawyer')) {
      return 'Escolha um advogado ativo do escritório.';
    }
    if (message.contains('assign_law_firm_case') ||
        message.contains('function') ||
        message.contains('patch')) {
      return 'Rode o patch de cargos no Supabase antes de atribuir casos.';
    }
    return 'Não foi possível atribuir o caso.';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<List<FirmCaseOverview>>(
        future: _casesFuture,
        builder: (context, snapshot) {
          final cases = snapshot.data;

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Casos',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Visão geral dos casos por cliente e advogado responsável.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
              ),
              const SizedBox(height: 20),
              if (snapshot.connectionState == ConnectionState.waiting &&
                  cases == null)
                const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.officePurple,
                    ),
                  ),
                )
              else if (cases == null || cases.isEmpty)
                const _EmptyFirmCasesState()
              else
                for (var index = 0; index < cases.length; index++) ...[
                  _FirmCaseCard(
                    overview: cases[index],
                    onTap: () => _openCaseDetails(cases[index]),
                    onAssign: widget.workspace?.canAssignCases == true
                        ? () => _openAssignCaseSheet(cases[index])
                        : null,
                  ),
                  if (index < cases.length - 1) const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _EmptyFirmCasesState extends StatelessWidget {
  const _EmptyFirmCasesState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.officePurpleBorder),
      ),
      child: const Text(
        'Nenhum caso encontrado para este escritório.',
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FirmCaseCard extends StatelessWidget {
  const _FirmCaseCard({
    required this.overview,
    required this.onTap,
    this.onAssign,
  });

  final FirmCaseOverview overview;
  final VoidCallback onTap;
  final VoidCallback? onAssign;

  @override
  Widget build(BuildContext context) {
    final statusColor = overview.urgent ? AppTheme.danger : AppTheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.card,
          border: Border.all(
            color: overview.urgent
                ? AppTheme.danger.withValues(alpha: 0.35)
                : AppTheme.officePurpleBorder,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: overview.urgent
                    ? AppTheme.danger.withValues(alpha: 0.10)
                    : AppTheme.officePurpleSurface,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Center(
                child: Text(
                  overview.clientInitials,
                  style: TextStyle(
                    color: overview.urgent
                        ? AppTheme.danger
                        : AppTheme.officePurple,
                    fontWeight: FontWeight.w900,
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
                          overview.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          overview.area,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${overview.clientName} · ${overview.assignedLawyer}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        overview.urgent
                            ? Icons.warning_amber_outlined
                            : Icons.task_alt_outlined,
                        color: statusColor,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${overview.statusLabel}: ${overview.nextStep}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: statusColor, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (onAssign != null)
              IconButton(
                onPressed: onAssign,
                icon: const Icon(Icons.assignment_ind_outlined),
                color: AppTheme.officePurple,
                tooltip: 'Atribuir caso',
              ),
            const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _AssignLawyerSheet extends StatelessWidget {
  const _AssignLawyerSheet({
    required this.lawyers,
    required this.selectedLawyerId,
  });

  final List<FirmTeamMember> lawyers;
  final String? selectedLawyerId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Atribuir caso',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: lawyers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final lawyer = lawyers[index];
                final selected = lawyer.id == selectedLawyerId;

                return ListTile(
                  onTap: () => Navigator.of(context).pop(lawyer),
                  tileColor: AppTheme.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: selected
                          ? AppTheme.officePurple
                          : AppTheme.officePurpleBorder,
                    ),
                  ),
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.officePurpleSurface,
                    child: Text(
                      lawyer.initials,
                      style: const TextStyle(
                        color: AppTheme.officePurple,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  title: Text(
                    lawyer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    lawyer.specialty,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_circle, color: AppTheme.primary)
                      : const Icon(Icons.chevron_right),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
