import 'package:flutter/material.dart';
import '../data/lawyer_cases_data.dart';
import '../theme/app_theme.dart';
import '../widgets/lawyer_case_card.dart';

class LawyerCasesScreen extends StatelessWidget {
  const LawyerCasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: substituir por dados reais da API
    final cases = lawyerCases;

    return SafeArea(
      child: cases.isEmpty
          ? const _EmptyCasesState()
          : _CasesListState(cases: cases),
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
  final List cases;

  const _CasesListState({required this.cases});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primary,
        onPressed: () {
          // TODO: navegar para criar novo caso
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
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  return LawyerCaseCard(
                    lawyerCase: cases[index],
                    onTap: () {
                      // TODO: navegar para detalhe do caso
                    },
                    onEdit: () {
                      // TODO: navegar para editar caso
                    },
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