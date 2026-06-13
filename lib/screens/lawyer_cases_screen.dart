import 'package:flutter/material.dart';
import '../data/mock/mock_cases.dart';
import '../models/lawyer_case.dart';
import '../repositories/case_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_theme.dart';
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
    } catch (_) {
      return const [];
    }
  }

  Future<void> _openCaseDetails(LawyerCase lawyerCase) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CaseDetailsScreen(
          caseId: lawyerCase.id,
          title: lawyerCase.title,
          subtitle: '${lawyerCase.clientName} · ${lawyerCase.area}',
          canAddUpdates: true,
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
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            );
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

class _EmptyCasesState extends StatelessWidget {
  const _EmptyCasesState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Casos',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
              decoration: TextDecoration.none,
            ),
          ),

          const SizedBox(height: 8 + 24),

          const Text(''),

          const Spacer(),

          Center(
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppTheme.lightBlue,
                    borderRadius: BorderRadius.circular(48),
                  ),
                  child: const Icon(
                    Icons.folder_open_outlined,
                    size: 42,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Nenhum caso ativo',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Quando você aceitar um cliente, os casos aparecerão aqui.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 15,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
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
    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primary,
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'A criação de casos será habilitada na integração.',
              ),
            ),
          );
        },
        child: const Icon(Icons.add, color: AppTheme.card),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Casos',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
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
                  return LawyerCaseCard(
                    lawyerCase: cases[index],
                    onTap: () => onOpenCase(cases[index]),
                    onEdit: () => onOpenCase(cases[index]),
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
