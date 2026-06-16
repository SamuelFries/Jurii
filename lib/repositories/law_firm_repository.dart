import '../data/legal_practice_areas.dart';
import '../models/law_firm.dart';
import '../services/supabase_config.dart';

class LawFirmRepository {
  const LawFirmRepository();

  Future<List<LawFirm>> fetchRecommendedLawFirms({
    String searchQuery = '',
  }) async {
    try {
      final rows = await SupabaseConfig.client.rpc(
        'fetch_recommended_law_firms',
        params: {'limit_value': 10, 'search_value': searchQuery},
      );

      return (rows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map<LawFirm>(_fromRow)
          .toList();
    } catch (_) {
      final rows = await SupabaseConfig.client
          .from('law_firms')
          .select()
          .eq('is_active', true)
          .order('rating', ascending: false);

      return _filterLawFirms(rows.map<LawFirm>(_fromRow).toList(), searchQuery);
    }
  }

  Future<LawFirm?> fetchLawFirmById(String lawFirmId) async {
    final row = await SupabaseConfig.client
        .from('law_firms')
        .select()
        .eq('id', lawFirmId)
        .maybeSingle();

    if (row == null) return null;
    return _fromRow(row);
  }

  LawFirm _fromRow(Map<String, dynamic> row) {
    final specialty = row['specialty'] as String? ?? 'Escritório jurídico';

    return LawFirm(
      id: row['id'] as String,
      name: row['name'] as String,
      initials: row['initials'] as String,
      rating: (row['rating'] as num).toDouble(),
      distance: row['distance_label'] as String? ?? '',
      specialty: specialty,
      practiceAreas: _practiceAreasFromRow(
        row['practice_areas'],
        fallback: [specialty],
      ),
      reviews: row['reviews_count'] as int? ?? 0,
      avatarType: row['avatar_type'] as String? ?? 'blue',
      description: row['description'] as String?,
      phone: row['phone'] as String?,
      email: row['email'] as String?,
      websiteUrl: row['website_url'] as String?,
      address: row['address'] as String?,
    );
  }

  List<LawFirm> _filterLawFirms(List<LawFirm> lawFirms, String query) {
    return lawFirms
        .where(
          (lawFirm) => matchesPracticeAreaSearch(
            practiceAreas: lawFirm.practiceAreas,
            query: query,
            extraFields: [lawFirm.name, lawFirm.specialty],
          ),
        )
        .toList();
  }

  List<String> _practiceAreasFromRow(Object? value, {List<String>? fallback}) {
    final areas = value is List
        ? value.whereType<String>().toList()
        : const <String>[];
    final cleanAreas = areas
        .map((area) => area.trim())
        .where((area) => area.isNotEmpty)
        .toList();
    if (cleanAreas.isNotEmpty) return cleanAreas;

    return (fallback ?? const <String>[])
        .map((area) => area.trim())
        .where((area) => area.isNotEmpty)
        .toList();
  }
}
