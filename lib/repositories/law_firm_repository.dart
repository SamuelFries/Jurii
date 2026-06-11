import '../models/law_firm.dart';
import '../services/supabase_config.dart';

class LawFirmRepository {
  const LawFirmRepository();

  Future<List<LawFirm>> fetchRecommendedLawFirms() async {
    final rows = await SupabaseConfig.client
        .from('law_firms')
        .select()
        .eq('is_active', true)
        .order('rating', ascending: false);

    return rows.map<LawFirm>(_fromRow).toList();
  }

  LawFirm _fromRow(Map<String, dynamic> row) {
    return LawFirm(
      id: row['id'] as String,
      name: row['name'] as String,
      initials: row['initials'] as String,
      rating: (row['rating'] as num).toDouble(),
      distance: row['distance_label'] as String? ?? '',
      specialty: row['specialty'] as String,
      reviews: row['reviews_count'] as int? ?? 0,
      avatarType: row['avatar_type'] as String? ?? 'blue',
    );
  }
}
