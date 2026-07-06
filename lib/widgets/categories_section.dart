import 'package:flutter/material.dart';
import '../data/legal_practice_areas.dart';
import '../data/mock/mock_categories.dart';
import '../models/legal_category.dart';
import '../repositories/category_repository.dart';
import 'category_card.dart';

class CategoriesSection extends StatefulWidget {
  const CategoriesSection({
    super.key,
    this.searchQuery = '',
    this.onCategorySelected,
    this.repository = const CategoryRepository(),
  });

  final String searchQuery;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Categorias populares',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<LegalCategory>>(
          future: _categoriesFuture,
          initialData: mockCategories,
          builder: (context, snapshot) {
            final categories = snapshot.data ?? mockCategories;
            return GridView.builder(
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
                final practiceArea = practiceAreaForCategory(
                  id: category.id,
                  title: category.title,
                );
                final selected = isPracticeAreaSelectedForQuery(
                  area: practiceArea,
                  query: widget.searchQuery,
                );
                return CategoryCard(
                  title: category.title,
                  isGold: category.isGold,
                  selected: selected,
                  iconName: category.iconName,
                  onTap: () => widget.onCategorySelected?.call(practiceArea),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
