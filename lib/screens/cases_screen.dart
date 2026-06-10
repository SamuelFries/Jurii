import 'package:flutter/material.dart';

import '../data/mock/mock_cases.dart';
import '../theme/app_theme.dart';

class CasesScreen extends StatelessWidget {
  final VoidCallback? onFindLawFirms;

  const CasesScreen({super.key, this.onFindLawFirms});

  @override
  Widget build(BuildContext context) {
    const cases = mockClientCases;

    return SafeArea(
      child: cases.isEmpty
          ? _EmptyCasesState(onFindLawFirms: onFindLawFirms)
          : ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: cases.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final legalCase = cases[index];
                return ListTile(
                  tileColor: AppTheme.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: AppTheme.lightBlueBorder),
                  ),
                  title: Text(legalCase.title),
                  subtitle: Text(legalCase.status),
                  leading: const Icon(Icons.folder_outlined),
                );
              },
            ),
    );
  }
}

class _EmptyCasesState extends StatelessWidget {
  final VoidCallback? onFindLawFirms;

  const _EmptyCasesState({this.onFindLawFirms});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Meus Casos',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Acompanhe aqui seus atendimentos jurídicos.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
          ),

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
                  'Nenhum caso iniciado',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  'Quando você solicitar atendimento a um escritório, seus casos aparecerão aqui.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
                ),

                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: onFindLawFirms,
                  child: const Text('Encontrar Escritórios'),
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
