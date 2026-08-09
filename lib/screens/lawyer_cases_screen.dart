import 'dart:async';

import 'package:flutter/material.dart';
import '../data/mock/mock_cases.dart';
import '../models/lawyer_case.dart';
import '../repositories/case_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../utils/inbox_filters.dart';
import '../widgets/jurii_empty_state.dart';
import '../widgets/jurii_error_state.dart';
import '../widgets/jurii_filter_chip_row.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/jurii_no_results_state.dart';
import '../widgets/jurii_search_field.dart';
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _onlyOpen = false;
  bool _onlyNewMessage = false;

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
      _onlyNewMessage = false;
    });
  }

  Future<List<LawyerCase>> _loadCases() async {
    try {
      final cases = await widget.repository.fetchLawyerCases();
      // Mock só no demo, e só depois de perguntar ao repositório: ver a nota
      // em cases_screen.dart. Em produção o resultado é o mesmo.
      if (cases.isEmpty && !SupabaseConfig.isReady) return mockLawyerCases;
      return cases;
    } catch (error) {
      // Sobe para o FutureBuilder: falha de rede não pode virar
      // "Nenhum caso ativo".
      debugPrint('Supabase lawyer cases fetch failed: $error');
      rethrow;
    }
  }

  void _retry() {
    setState(() => _casesFuture = _loadCases()..ignore());
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
      _casesFuture = _loadCases()..ignore();
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
            return JuriiErrorState(
              title: 'Não foi possível carregar seus casos.',
              onRetry: _retry,
            );
          }

          if (cases == null || cases.isEmpty) {
            return const _EmptyCasesState();
          }

          return _CasesListState(
            cases: cases,
            visiveis: filterLawyerCases(
              cases,
              query: _searchQuery,
              onlyOpen: _onlyOpen,
              onlyNewMessage: _onlyNewMessage,
            ),
            searchController: _searchController,
            onSearchChanged: _onSearchChanged,
            onClearFilters: _clearFilters,
            onlyOpen: _onlyOpen,
            onlyNewMessage: _onlyNewMessage,
            onToggleOpen: () => setState(() => _onlyOpen = !_onlyOpen),
            onToggleNewMessage: () =>
                setState(() => _onlyNewMessage = !_onlyNewMessage),
            onOpenCase: _openCaseDetails,
          );
        },
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
                  'O caso nasce na conversa: abra o chat com o cliente e '
                  'toque em "Enviar solicitação de caso".',
            ),
          ),

          const Spacer(),
        ],
      ),
    );
  }
}

class _CasesListState extends StatelessWidget {
  /// A lista COMPLETA: é ela que decide se um chip merece existir e quantos
  /// casos a mensagem de "nenhum resultado" promete que continuam ali.
  final List<LawyerCase> cases;

  /// O que sobrou depois da busca e dos chips.
  final List<LawyerCase> visiveis;

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearFilters;
  final bool onlyOpen;
  final bool onlyNewMessage;
  final VoidCallback onToggleOpen;
  final VoidCallback onToggleNewMessage;
  final ValueChanged<LawyerCase> onOpenCase;

  const _CasesListState({
    required this.cases,
    required this.visiveis,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearFilters,
    required this.onlyOpen,
    required this.onlyNewMessage,
    required this.onToggleOpen,
    required this.onToggleNewMessage,
    required this.onOpenCase,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    // Sem FAB de "criar caso": o caso nasce dentro da conversa (o advogado
    // propõe pelo chat e o cliente aceita) — um botão aqui seria promessa
    // falsa, e era exatamente o placeholder que a revisão de loja reprova.
    return Scaffold(
      backgroundColor: colors.background,
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

            const SizedBox(height: 20),

            JuriiSearchField(
              controller: searchController,
              hintText: 'Buscar por cliente, título ou processo',
              semanticLabel: 'Buscar nos seus casos',
              onChanged: onSearchChanged,
            ),

            const SizedBox(height: 12),

            JuriiFilterChipRow(
              total: cases.length,
              filters: [
                JuriiListFilter(
                  label: 'Nova mensagem',
                  matches: cases
                      .where((c) => c.status == LawyerCaseStatus.newMessage)
                      .length,
                  selected: onlyNewMessage,
                  onToggle: onToggleNewMessage,
                ),
                JuriiListFilter(
                  label: 'Em andamento',
                  matches: cases
                      .where((c) => c.status != LawyerCaseStatus.closed)
                      .length,
                  selected: onlyOpen,
                  onToggle: onToggleOpen,
                ),
              ],
            ),

            const SizedBox(height: 20),

            Expanded(
              child: visiveis.isEmpty
                  ? SingleChildScrollView(
                      child: JuriiNoResultsState(
                        icon: Icons.folder_off_outlined,
                        message:
                            'Nenhum caso combina com esse filtro. '
                            'Seus ${cases.length} '
                            '${cases.length == 1 ? 'caso continua' : 'casos continuam'} aqui.',
                        onClear: onClearFilters,
                      ),
                    )
                  : ListView.separated(
                      itemCount: visiveis.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return JuriiStaggeredItem(
                          key: ValueKey('lawyer_case_${visiveis[index].id}'),
                          index: index,
                          child: LawyerCaseCard(
                            lawyerCase: visiveis[index],
                            onTap: () => onOpenCase(visiveis[index]),
                            onEdit: () => onOpenCase(visiveis[index]),
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
