import 'package:flutter/material.dart';
import '../data/mock/mock_cases.dart';
import '../models/lawyer_case.dart';
import '../theme/app_theme.dart';
import '../widgets/lawyer_case_card.dart';

class LawyerCasesScreen extends StatelessWidget {
  const LawyerCasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const cases = mockLawyerCases;

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
  final List<LawyerCase> cases;

  const _CasesListState({required this.cases});

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
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Detalhes do caso em preparação.'),
                        ),
                      );
                    },
                    onEdit: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Edição de caso em preparação.'),
                        ),
                      );
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
