import 'package:flutter/material.dart';
import '../data/legal_practice_areas.dart';
import '../data/mock/mock_categories.dart';
import '../models/legal_category.dart';
import '../repositories/category_repository.dart';
import '../theme/app_colors.dart';
import 'category_card.dart';
import 'jurii_motion.dart';

class CategoriesSection extends StatefulWidget {
  const CategoriesSection({
    super.key,
    this.searchQuery = '',
    this.onCategorySelected,
    this.repository = const CategoryRepository(),
  });

  final String searchQuery;

  /// Chamado com o TÍTULO do cartão, a palavra do cliente.
  ///
  /// É o título que vai para a caixa de busca. Antes ia a área canônica:
  /// quem tocava "Acidente de Trânsito" via a caixa virar "Direito Cível",
  /// e o filtro abria para a segunda maior área da taxonomia.
  final ValueChanged<String>? onCategorySelected;
  final CategoryRepository repository;

  @override
  State<CategoriesSection> createState() => _CategoriesSectionState();
}

class _CategoriesSectionState extends State<CategoriesSection> {
  late final Future<List<LegalCategory>> _categoriesFuture;

  @override
  void initState() {
    super.initState();
    _categoriesFuture = _loadCategories();
  }

  Future<List<LegalCategory>> _loadCategories() async {
    try {
      final categories = await widget.repository.fetchCategories();
      if (categories.isNotEmpty) return categories;
    } catch (error) {
      debugPrint('Supabase categories fetch failed: $error');
    }
    return mockCategories;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "Comece por aqui", e não "Categorias populares": popularidade
        // afirmaria uma medição que não existe (discovery_events não grava
        // toque em categoria nem termo buscado). O conjunto é curadoria.
        Text(
          'Comece por aqui',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        // O toggle de filtro é invisível sem isto: o gesto precisa ser dito.
        Text(
          'Toque para filtrar advogados e escritórios.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<LegalCategory>>(
          future: _categoriesFuture,
          initialData: mockCategories,
          builder: (context, snapshot) {
            final categories = snapshot.data ?? mockCategories;
            return JuriiFadeThroughSwitcher(
              child: GridView.builder(
                key: ValueKey(
                  'categories_${categories.map((category) => category.id).join('|')}',
                ),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: categories.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.9,
                ),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  // Aceso por IDENTIDADE de título, não por inferência de
                  // área. Inferir reacendia cartões em par: "Inventário e
                  // Herança" infere Cível junto de Sucessões e acendia
                  // também "Acidente e Indenização". Cartão aceso significa
                  // "foi isto que você tocou", nada além.
                  final selected =
                      normalizePracticeAreaQuery(widget.searchQuery) ==
                      normalizePracticeAreaQuery(category.title);
                  return JuriiStaggeredItem(
                    key: ValueKey('category_${category.id}'),
                    index: index,
                    child: CategoryCard(
                      title: category.title,
                      selected: selected,
                      iconName: category.iconName,
                      onTap: () =>
                          widget.onCategorySelected?.call(category.title),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}
