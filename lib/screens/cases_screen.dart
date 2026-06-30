import 'package:flutter/material.dart';

import '../data/mock/mock_cases.dart';
import '../models/case_request.dart';
import '../models/cases.dart';
import '../repositories/case_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_theme.dart';
import 'case_details_screen.dart';

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
  late Future<_ClientCasesData> _casesFuture;

  @override
  void initState() {
    super.initState();
    _casesFuture = _loadCases();
  }

  Future<_ClientCasesData> _loadCases() async {
    if (!SupabaseConfig.isReady) {
      return const _ClientCasesData(
        cases: mockClientCases,
        requests: mockClientCaseRequests,
      );
    }

    try {
      final results = await Future.wait([
        widget.repository.fetchClientCases(),
        widget.repository.fetchClientCaseRequests(),
      ]);

      return _ClientCasesData(
        cases: results[0] as List<LegalCase>,
        requests: results[1] as List<CaseRequest>,
      );
    } catch (_) {
      return const _ClientCasesData(cases: [], requests: []);
    }
  }

  Future<void> _respondToRequest(
    CaseRequest request, {
    required bool accepted,
  }) async {
    try {
      await widget.repository.respondToCaseRequest(
        requestId: request.id,
        accepted: accepted,
      );
      if (!mounted) return;
      setState(() {
        _casesFuture = _loadCases();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accepted ? 'Caso aceito com sucesso.' : 'Solicitação recusada.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível responder à solicitação.'),
        ),
      );
    }
  }

  Future<void> _openCaseDetails(LegalCase legalCase) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CaseDetailsScreen(
          caseId: legalCase.id,
          title: legalCase.title,
          subtitle: '${legalCase.area} · ${legalCase.status}',
          canAddUpdates: false,
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
      child: FutureBuilder<_ClientCasesData>(
        future: _casesFuture,
        builder: (context, snapshot) {
          final data = snapshot.data;
          final cases = data?.cases;
          final requests = data?.requests ?? const <CaseRequest>[];

          if (snapshot.connectionState == ConnectionState.waiting &&
              data == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            );
          }

          if ((cases == null || cases.isEmpty) && requests.isEmpty) {
            return _EmptyCasesState(onFindLawFirms: widget.onFindLawFirms);
          }

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const _CasesHeader(),
              if (requests.isNotEmpty) ...[
                const SizedBox(height: 12),
                const _SectionTitle('Solicitações pendentes'),
                const SizedBox(height: 12),
                for (var index = 0; index < requests.length; index++) ...[
                  _CaseRequestCard(
                    request: requests[index],
                    onAccept: () =>
                        _respondToRequest(requests[index], accepted: true),
                    onDecline: () =>
                        _respondToRequest(requests[index], accepted: false),
                  ),
                  if (index < requests.length - 1) const SizedBox(height: 12),
                ],
                const SizedBox(height: 24),
              ],
              if (cases != null && cases.isNotEmpty) ...[
                const _SectionTitle('Casos em andamento'),
                const SizedBox(height: 12),
                for (var index = 0; index < cases.length; index++) ...[
                  _ClientCaseCard(
                    legalCase: cases[index],
                    onTap: () => _openCaseDetails(cases[index]),
                  ),
                  if (index < cases.length - 1) const SizedBox(height: 12),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ClientCasesData {
  final List<LegalCase> cases;
  final List<CaseRequest> requests;

  const _ClientCasesData({required this.cases, required this.requests});
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _CaseRequestCard extends StatelessWidget {
  const _CaseRequestCard({
    required this.request,
    required this.onAccept,
    required this.onDecline,
  });

  final CaseRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightGoldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.lightGold,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    request.requesterInitials,
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
                    Text(
                      request.title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${request.requestedBy} · ${request.area}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (request.summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              request.summary,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  child: const Text('Recusar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onAccept,
                  child: const Text('Aceitar caso'),
                ),
              ),
            ],
          ),
        ],
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
  const _ClientCaseCard({required this.legalCase, required this.onTap});

  final LegalCase legalCase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
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
