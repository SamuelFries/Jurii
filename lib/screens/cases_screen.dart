import 'dart:async';

import 'package:flutter/material.dart';

import '../data/mock/mock_cases.dart';
import '../models/case_request.dart';
import '../models/cases.dart';
import '../repositories/case_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../utils/inbox_filters.dart';
import '../widgets/jurii_empty_state.dart';
import '../widgets/jurii_error_state.dart';
import '../widgets/jurii_filter_chip_row.dart';
import '../widgets/jurii_list_card.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/jurii_no_results_state.dart';
import '../widgets/jurii_search_field.dart';
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _onlyOpen = false;

  @override
  void initState() {
    super.initState();
    _casesFuture = _loadCases();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value.trim());
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _onlyOpen = false;
    });
  }

  String _mensagemSemResultado(int total) {
    final casos = total == 1 ? 'caso' : 'casos';
    return 'Nenhum caso combina com esse filtro. '
        'Seus $total $casos continuam aqui.';
  }

  Future<_ClientCasesData> _loadCases() async {
    try {
      final results = await Future.wait([
        widget.repository.fetchClientCases(),
        widget.repository.fetchClientCaseRequests(),
      ]);

      final cases = results[0] as List<LegalCase>;
      final requests = results[1] as List<CaseRequest>;

      // Mock só no modo demo, e só DEPOIS de perguntar ao repositório. O
      // atalho antigo decidia pelo estado global antes de falar com o
      // colaborador: em produção dava no mesmo (o repositório também devolve
      // vazio sem Supabase), mas nenhum teste conseguia alimentar a tela, e
      // filtro sem teste de fiação é filtro que ninguém garante que está
      // ligado.
      if (cases.isEmpty && requests.isEmpty && !SupabaseConfig.isReady) {
        return const _ClientCasesData(cases: mockClientCases, requests: []);
      }

      return _ClientCasesData(cases: cases, requests: requests);
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
        _casesFuture = _loadCases()..ignore();
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
      _casesFuture = _loadCases()..ignore();
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
            return JuriiErrorState(
              title: 'Não foi possível carregar seus casos.',
              onRetry: _refresh,
            );
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

          // As duas seções obedecem à MESMA busca: filtrar só os casos e
          // deixar as solicitações intactas faria a seção de cima parecer
          // ignorar o que foi digitado.
          final casosVisiveis = filterClientCases(
            cases ?? const [],
            query: _searchQuery,
            onlyOpen: _onlyOpen,
          );
          final pedidosVisiveis = filterCaseRequests(
            requests,
            query: _searchQuery,
          );
          final totalCarregado = (cases?.length ?? 0) + requests.length;
          final nadaVisivel =
              casosVisiveis.isEmpty && pedidosVisiveis.isEmpty;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const _CasesHeader(),
                JuriiSearchField(
                  controller: _searchController,
                  hintText: 'Buscar por título, área ou processo',
                  semanticLabel: 'Buscar nos seus casos',
                  onChanged: _onSearchChanged,
                ),
                const SizedBox(height: 12),
                JuriiFilterChipRow(
                  total: totalCarregado,
                  filters: [
                    JuriiListFilter(
                      label: 'Em andamento',
                      matches:
                          (cases ?? const <LegalCase>[])
                              .where((c) => !c.isClosed)
                              .length +
                          requests.length,
                      selected: _onlyOpen,
                      onToggle: () => setState(() => _onlyOpen = !_onlyOpen),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (nadaVisivel)
                  JuriiNoResultsState(
                    icon: Icons.folder_off_outlined,
                    message: _mensagemSemResultado(totalCarregado),
                    onClear: _clearFilters,
                  ),
                if (pedidosVisiveis.isNotEmpty) ...[
                  const _SectionTitle('Solicitações pendentes'),
                  const SizedBox(height: 12),
                  for (
                    var index = 0;
                    index < pedidosVisiveis.length;
                    index++
                  ) ...[
                    JuriiStaggeredItem(
                      key: ValueKey('case_request_${pedidosVisiveis[index].id}'),
                      index: index,
                      child: _CaseRequestCard(
                        request: pedidosVisiveis[index],
                        onAccept: () => _respondToRequest(
                          pedidosVisiveis[index],
                          accepted: true,
                        ),
                        onDecline: () => _respondToRequest(
                          pedidosVisiveis[index],
                          accepted: false,
                        ),
                      ),
                    ),
                    if (index < pedidosVisiveis.length - 1)
                      const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 24),
                ],
                if (casosVisiveis.isNotEmpty) ...[
                  const _SectionTitle('Casos em andamento'),
                  const SizedBox(height: 12),
                  for (var index = 0; index < casosVisiveis.length; index++) ...[
                    JuriiStaggeredItem(
                      key: ValueKey('client_case_${casosVisiveis[index].id}'),
                      index: index + pedidosVisiveis.length,
                      child: _ClientCaseCard(
                        legalCase: casosVisiveis[index],
                        onTap: () => _openCaseDetails(casosVisiveis[index]),
                      ),
                    ),
                    if (index < casosVisiveis.length - 1)
                      const SizedBox(height: 12),
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
