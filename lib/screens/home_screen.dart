import 'dart:async';

import 'package:flutter/material.dart';

import 'package:jurii/data/legal_practice_areas.dart';
import 'package:jurii/models/jurii_notification.dart';
import 'package:jurii/widgets/categories_section.dart';
import 'package:jurii/widgets/notification_bell.dart';
import 'package:jurii/widgets/offices_section.dart';
import 'package:jurii/widgets/recommended_lawyers_section.dart';
import '../theme/app_colors.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// Âncora da primeira seção de resultados. Depois de um TOQUE (chip ou
  /// categoria) a tela rola até aqui, porque o primeiro advogado vive em
  /// y=875 numa dobra útil de 760: sem rolar, a pessoa toca, vê a borda
  /// acender e nenhum resultado muda na frente dela. Só toque rola; digitar
  /// não, que ninguém merece a tela fugindo no meio da frase.
  final GlobalKey _resultsAnchorKey = GlobalKey();
  String _searchQuery = '';
  Timer? _searchDebounce;
  int _refreshTick = 0;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _setSearchQuery(String value) {
    setState(() => _searchQuery = value.trim());
  }

  /// Debounce de 350ms: cada mudança de query dispara 2 RPCs (advogados e
  /// escritórios); sem isso, digitar "pensão alimentícia" gera ~36 round-trips.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    // Atualiza já o botão de limpar, sem refazer as buscas.
    setState(() {});
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _setSearchQuery(value),
    );
  }

  Future<void> _refresh() async {
    // Troca a key das seções para recriá-las e refazer os fetches.
    setState(() => _refreshTick++);
  }

  void _toggleArea(String area) {
    final selected = isPracticeAreaSelectedForQuery(
      area: area,
      query: _searchQuery,
    );
    final nextQuery = selected ? '' : area;
    _searchController.text = nextQuery;
    _setSearchQuery(nextQuery);
    if (!selected) _scrollToResults();
  }

  /// Toque numa categoria: quem entra na caixa é o TÍTULO, a palavra do
  /// cliente, não "Direito Médico e da Saúde". O resultado é o mesmo porque
  /// as regras de intenção traduzem o título para a área, e há teste
  /// barrando categoria cujo título não pesca a própria área
  /// (test/categorias_populares_test.dart). O toggle é por identidade de
  /// título, espelhando o aceso do cartão.
  void _selectCategory(String title) {
    final selected =
        normalizePracticeAreaQuery(_searchQuery) ==
        normalizePracticeAreaQuery(title);
    final nextQuery = selected ? '' : title;
    _searchController.text = nextQuery;
    _setSearchQuery(nextQuery);
    if (!selected) _scrollToResults();
  }

  void _scrollToResults() {
    // Pós-frame: a rolagem mede a posição DEPOIS que o filtro reconstruiu as
    // seções, senão mira no layout velho.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final anchorContext = _resultsAnchorKey.currentContext;
      if (anchorContext == null || !mounted) return;
      Scrollable.ensureVisible(
        anchorContext,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Como podemos ajudar hoje?',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    NotificationBell(
                      scope: NotificationScope.client,
                      iconColor: colors.accent,
                      backgroundColor: colors.card,
                      borderColor: colors.lightGoldBorder,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onChanged: _onSearchChanged,
                  onSubmitted: _setSearchQuery,
                  decoration: InputDecoration(
                    hintText: 'Descreva seu problema jurídico',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchDebounce?.cancel();
                              _searchController.clear();
                              _setSearchQuery('');
                            },
                            icon: const Icon(Icons.close),
                            tooltip: 'Limpar busca',
                          ),
                  ),
                ),

                const SizedBox(height: 12),

                // O exemplo ensina o GESTO de descrever o problema. "pensão"
                // sozinha era o pior professor possível: infere 4 áreas e
                // alcança 68 perfis. Esta frase pesca só Trabalhista, a maior
                // prateleira do app.
                const Text('Ex.: "meu chefe não me paga"'),

                const SizedBox(height: 14),

                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: legalPracticeAreas.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final area = legalPracticeAreas[index];
                      final selected = isPracticeAreaSelectedForQuery(
                        area: area,
                        query: _searchQuery,
                      );
                      return FilterChip(
                        label: Text(area),
                        selected: selected,
                        showCheckmark: false,
                        selectedColor: colors.lightGold,
                        backgroundColor: colors.card,
                        side: BorderSide(
                          color: selected
                              ? colors.accent
                              : colors.lightBlueBorder,
                        ),
                        labelStyle: TextStyle(
                          color: selected
                              ? colors.accent
                              : colors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                        onSelected: (_) => _toggleArea(area),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 40),

                CategoriesSection(
                  key: ValueKey('categories_$_refreshTick'),
                  searchQuery: _searchQuery,
                  onCategorySelected: _selectCategory,
                ),

                const SizedBox(height: 40),

                KeyedSubtree(
                  key: _resultsAnchorKey,
                  child: RecommendedLawyersSection(
                    key: ValueKey('lawyers_$_refreshTick'),
                    searchQuery: _searchQuery,
                  ),
                ),

                const SizedBox(height: 40),

                OfficesSection(
                  key: ValueKey('offices_$_refreshTick'),
                  searchQuery: _searchQuery,
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
