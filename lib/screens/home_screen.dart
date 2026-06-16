import 'package:flutter/material.dart';

import 'package:jurii/data/legal_practice_areas.dart';
import 'package:jurii/models/jurii_notification.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/categories_section.dart';
import 'package:jurii/widgets/notification_bell.dart';
import 'package:jurii/widgets/offices_section.dart';
import 'package:jurii/widgets/recommended_lawyers_section.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setSearchQuery(String value) {
    setState(() => _searchQuery = value.trim());
  }

  void _toggleArea(String area) {
    final selected =
        normalizePracticeAreaQuery(_searchQuery) ==
        normalizePracticeAreaQuery(area);
    final nextQuery = selected ? '' : area;
    _searchController.text = nextQuery;
    _setSearchQuery(nextQuery);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Como podemos ajudar hoje?',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  NotificationBell(
                    scope: NotificationScope.client,
                    iconColor: AppTheme.accent,
                    backgroundColor: AppTheme.card,
                    borderColor: AppTheme.lightGoldBorder,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: _setSearchQuery,
                decoration: InputDecoration(
                  hintText: 'Busque por área do direito',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            _setSearchQuery('');
                          },
                          icon: const Icon(Icons.close),
                          tooltip: 'Limpar busca',
                        ),
                ),
              ),

              const SizedBox(height: 12),

              const Text('Ex.: "Direito de Família"'),

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
                    final selected =
                        normalizePracticeAreaQuery(_searchQuery) ==
                        normalizePracticeAreaQuery(area);
                    return FilterChip(
                      label: Text(area),
                      selected: selected,
                      showCheckmark: false,
                      selectedColor: AppTheme.lightGold,
                      backgroundColor: AppTheme.card,
                      side: BorderSide(
                        color: selected
                            ? AppTheme.accent
                            : AppTheme.lightBlueBorder,
                      ),
                      labelStyle: TextStyle(
                        color: selected
                            ? AppTheme.accent
                            : AppTheme.textSecondary,
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
                searchQuery: _searchQuery,
                onCategorySelected: _toggleArea,
              ),

              const SizedBox(height: 40),

              RecommendedLawyersSection(searchQuery: _searchQuery),

              const SizedBox(height: 40),

              OfficesSection(searchQuery: _searchQuery),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
