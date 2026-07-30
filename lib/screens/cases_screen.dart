import 'package:flutter/material.dart';

import '../data/mock/mock_cases.dart';
import '../models/case_request.dart';
import '../models/cases.dart';
import '../repositories/case_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../widgets/jurii_empty_state.dart';
import '../widgets/jurii_list_card.dart';
import '../widgets/jurii_motion.dart';
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
      return const _ClientCasesData(cases: mockClientCases, requests: []);
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
    } catch (error) {
      // Erro sobe para o FutureBuilder: falha de rede não pode virar
      // "Nenhum caso iniciado".
      debugPrint('Supabase client cases fetch failed: $error');
      rethrow;
    }
  }

  Future<void> _refresh() async {
    final future = _loadCases();
    setState(() => _casesFuture = future);
    try {
      await future;
    } catch (_) {
      // O FutureBuilder exibe o estado de erro.
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
          cnjNumber: legalCase.cnjNumber,
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
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CasesHeader(),
                  SizedBox(height: 20),
                  JuriiSkeletonList(itemCount: 4, itemHeight: 92),
                ],
              ),
            );
          }

          if (snapshot.hasError && data == null) {
            return _CasesErrorState(onRetry: _refresh);
          }

          if ((cases == null || cases.isEmpty) && requests.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: _EmptyCasesState(
                      onFindLawFirms: widget.onFindLawFirms,
                    ),
                  ),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const _CasesHeader(),
                if (requests.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const _SectionTitle('Solicitações pendentes'),
                  const SizedBox(height: 12),
                  for (var index = 0; index < requests.length; index++) ...[
                    JuriiStaggeredItem(
                      key: ValueKey('case_request_${requests[index].id}'),
                      index: index,
                      child: _CaseRequestCard(
                        request: requests[index],
                        onAccept: () =>
                            _respondToRequest(requests[index], accepted: true),
                        onDecline: () =>
                            _respondToRequest(requests[index], accepted: false),
                      ),
                    ),
                    if (index < requests.length - 1) const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 24),
                ],
                if (cases != null && cases.isNotEmpty) ...[
                  const _SectionTitle('Casos em andamento'),
                  const SizedBox(height: 12),
                  for (var index = 0; index < cases.length; index++) ...[
                    JuriiStaggeredItem(
                      key: ValueKey('client_case_${cases[index].id}'),
                      index: index + requests.length,
                      child: _ClientCaseCard(
                        legalCase: cases[index],
                        onTap: () => _openCaseDetails(cases[index]),
                      ),
                    ),
                    if (index < cases.length - 1) const SizedBox(height: 12),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CasesErrorState extends StatelessWidget {
  const _CasesErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

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
            const SizedBox(height: 8),
            Text(
              'Verifique sua conexão e tente novamente.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
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
    final colors = context.jColors;
    return Text(
      title,
      style: TextStyle(
        color: colors.textPrimary,
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
    final colors = context.jColors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.lightGoldBorder),
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
                  color: colors.lightGold,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    request.requesterInitials,
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
                    Text(
                      request.title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${request.requestedBy} · ${request.area}',
                      style: TextStyle(
                        color: colors.textSecondary,
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
              style: TextStyle(color: colors.textSecondary),
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
    final colors = context.jColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Meus Casos',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Acompanhe aqui seus atendimentos jurídicos.',
          style: TextStyle(color: colors.textSecondary, fontSize: 16),
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
    final colors = context.jColors;
    return JuriiListCard(
      onTap: onTap,
      semanticLabel: legalCase.title,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.lightBlue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.folder_outlined, color: colors.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  legalCase.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${legalCase.area} · ${legalCase.lastUpdate}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            legalCase.status,
            style: TextStyle(
              color: colors.primary,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCasesState extends StatelessWidget {
  final VoidCallback? onFindLawFirms;

  const _EmptyCasesState({this.onFindLawFirms});

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Meus Casos',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Acompanhe aqui seus atendimentos jurídicos.',
            style: TextStyle(color: colors.textSecondary, fontSize: 16),
          ),

          const Spacer(),

          Center(
            child: JuriiEmptyState(
              icon: Icons.folder_open_outlined,
              title: 'Nenhum caso iniciado',
              message:
                  'Quando você solicitar atendimento a um escritório, seus casos aparecerão aqui.',
              actionLabel: 'Encontrar Escritórios',
              onAction: onFindLawFirms,
            ),
          ),

          const Spacer(),
        ],
      ),
    );
  }
}
