import 'package:flutter/material.dart';
import '../data/mock/mock_cases.dart';
import '../models/lawyer_case.dart';
import '../repositories/case_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../widgets/jurii_empty_state.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/lawyer_case_card.dart';
import 'case_details_screen.dart';

class LawyerCasesScreen extends StatefulWidget {
  const LawyerCasesScreen({
    super.key,
    this.repository = const CaseRepository(),
  });

  final CaseRepository repository;

  @override
  State<LawyerCasesScreen> createState() => _LawyerCasesScreenState();
}

class _LawyerCasesScreenState extends State<LawyerCasesScreen> {
  late Future<List<LawyerCase>> _casesFuture;

  @override
  void initState() {
    super.initState();
    _casesFuture = _loadCases();
  }

  Future<List<LawyerCase>> _loadCases() async {
    if (!SupabaseConfig.isReady) return mockLawyerCases;

    try {
      return await widget.repository.fetchLawyerCases();
    } catch (error) {
      // Sobe para o FutureBuilder: falha de rede não pode virar
      // "Nenhum caso ativo".
      debugPrint('Supabase lawyer cases fetch failed: $error');
      rethrow;
    }
  }

  void _retry() {
    setState(() => _casesFuture = _loadCases());
  }

  Future<void> _openCaseDetails(LawyerCase lawyerCase) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CaseDetailsScreen(
          caseId: lawyerCase.id,
          title: lawyerCase.title,
          subtitle: '${lawyerCase.clientName} · ${lawyerCase.area}',
          canAddUpdates: true,
          cnjNumber: lawyerCase.cnjNumber,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      _casesFuture = _loadCases();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<List<LawyerCase>>(
        future: _casesFuture,
        builder: (context, snapshot) {
          final cases = snapshot.data;

          if (snapshot.connectionState == ConnectionState.waiting &&
              cases == null) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: JuriiSkeletonList(itemCount: 4, itemHeight: 84),
            );
          }

          if (snapshot.hasError && cases == null) {
            return _CasesLoadErrorState(onRetry: _retry);
          }

          if (cases == null || cases.isEmpty) {
            return const _EmptyCasesState();
          }

          return _CasesListState(cases: cases, onOpenCase: _openCaseDetails);
        },
      ),
    );
  }
}

class _CasesLoadErrorState extends StatelessWidget {
  const _CasesLoadErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 40, color: colors.textSecondary),
            const SizedBox(height: 16),
            Text(
              'Não foi possível carregar seus casos.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCasesState extends StatelessWidget {
  const _EmptyCasesState();

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Casos',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
              decoration: TextDecoration.none,
            ),
          ),

          const SizedBox(height: 8 + 24),

          const Text(''),

          const Spacer(),

          const Center(
            child: JuriiEmptyState(
              icon: Icons.folder_open_outlined,
              title: 'Nenhum caso ativo',
              message:
                  'Quando você aceitar um cliente, os casos aparecerão aqui.',
            ),
          ),

          const Spacer(),
        ],
      ),
    );
  }
}

class _CasesListState extends StatelessWidget {
  final List<LawyerCase> cases;
  final ValueChanged<LawyerCase> onOpenCase;

  const _CasesListState({required this.cases, required this.onOpenCase});

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Scaffold(
      backgroundColor: colors.background,
      floatingActionButton: FloatingActionButton(
        backgroundColor: colors.primary,
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'A criação de casos será habilitada na integração.',
              ),
            ),
          );
        },
        child: Icon(Icons.add, color: colors.card),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Casos',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
                decoration: TextDecoration.none,
              ),
            ),

            const SizedBox(height: 24),

            Expanded(
              child: ListView.separated(
                itemCount: cases.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  return JuriiStaggeredItem(
                    key: ValueKey('lawyer_case_${cases[index].id}'),
                    index: index,
                    child: LawyerCaseCard(
                      lawyerCase: cases[index],
                      onTap: () => onOpenCase(cases[index]),
                      onEdit: () => onOpenCase(cases[index]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
