import 'package:flutter/material.dart';

import '../data/mock/mock_cases.dart';
import '../models/cases.dart';
import '../repositories/case_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_theme.dart';

class CasesScreen extends StatefulWidget {
  final VoidCallback? onFindLawFirms;

  const CasesScreen({
    super.key,
    this.onFindLawFirms,
    this.repository = const CaseRepository(),
  });

  final CaseRepository repository;

  @override
  State<CasesScreen> createState() => _CasesScreenState();
}

class _CasesScreenState extends State<CasesScreen> {
  late Future<List<LegalCase>> _casesFuture;

  @override
  void initState() {
    super.initState();
    _casesFuture = _loadCases();
  }

  Future<List<LegalCase>> _loadCases() async {
    if (!SupabaseConfig.isReady) return mockClientCases;

    try {
      return await widget.repository.fetchClientCases();
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<List<LegalCase>>(
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
            return _EmptyCasesState(onFindLawFirms: widget.onFindLawFirms);
          }

          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: cases.length + 1,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return const _CasesHeader();
              }

              final legalCase = cases[index - 1];
              return _ClientCaseCard(legalCase: legalCase);
            },
          );
        },
      ),
    );
  }
}

class _CasesHeader extends StatelessWidget {
  const _CasesHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Meus Casos',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Acompanhe aqui seus atendimentos jurídicos.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
        ),
        SizedBox(height: 8),
      ],
    );
  }
}

class _ClientCaseCard extends StatelessWidget {
  const _ClientCaseCard({required this.legalCase});

  final LegalCase legalCase;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      tileColor: AppTheme.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.lightBlueBorder),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      title: Text(
        legalCase.title,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('${legalCase.area} · ${legalCase.lastUpdate}'),
      ),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.lightBlue,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.folder_outlined, color: AppTheme.primary),
      ),
      trailing: Text(
        legalCase.status,
        style: const TextStyle(
          color: AppTheme.primary,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
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
