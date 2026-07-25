import '../models/legal_category.dart';
import '../services/supabase_config.dart';

class CategoryRepository {
  const CategoryRepository();

  Future<List<LegalCategory>> fetchCategories() async {
    final rows = await SupabaseConfig.client
        .from('legal_categories')
        .select()
        .order('sort_order');

    return rows.map<LegalCategory>(_fromRow).toList();
  }

  LegalCategory _fromRow(Map<String, dynamic> row) {
    return LegalCategory(
      id: row['id'] as String,
      title: row['title'] as String,
      iconName: row['icon_name'] as String?,
      practiceArea: row['practice_area'] as String?,
    );
  }
}
