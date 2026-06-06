import 'package:flutter/material.dart';
import '../data/categories_data.dart';
import 'category_card.dart';

class CategoriesSection extends StatelessWidget {
  const CategoriesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Categorias Populares',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        GridView.builder(
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
            return CategoryCard(
              emoji: category.emoji,
              title: category.title,
              isGold: category.isGold,
              onTap: () => debugPrint('Categoria clicada: ${category.id}'),
            );
          },
        ),
      ],
    );
  }
}