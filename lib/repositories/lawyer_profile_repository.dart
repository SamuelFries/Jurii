import '../data/mock/mock_lawyers.dart';
import '../models/lawyer_profile_summary.dart';
import '../services/supabase_config.dart';

class LawyerProfileRepository {
  const LawyerProfileRepository();

  Future<List<LawyerProfileSummary>> fetchRecommendedLawyers() async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return mockRecommendedLawyers;
    }

    try {
      final rows = await SupabaseConfig.client
          .from('lawyer_profiles')
          .select(
            'id, oab_number, oab_state, primary_area, bio, profiles(full_name, initials)',
          )
          .eq('is_available', true)
          .order('approved_at', ascending: false)
          .limit(6);

      final lawyers = rows.map<LawyerProfileSummary>(_fromRow).toList();
      return lawyers.isEmpty ? mockRecommendedLawyers : lawyers;
    } catch (_) {
      return mockRecommendedLawyers;
    }
  }

  LawyerProfileSummary _fromRow(Map<String, dynamic> row) {
    final profile = row['profiles'];
    final profileMap = profile is Map<String, dynamic> ? profile : const {};
    final name = profileMap['full_name'] as String? ?? 'Advogado Jurii';
    final initials = profileMap['initials'] as String? ?? _initialsFor(name);

    return LawyerProfileSummary(
      id: row['id'] as String,
      name: name,
      initials: initials,
      oabNumber: row['oab_number'] as String? ?? '',
      oabState: row['oab_state'] as String? ?? '',
      primaryArea: row['primary_area'] as String? ?? 'Atendimento jurídico',
      bio:
          row['bio'] as String? ?? 'Perfil profissional verificado pela Jurii.',
      rating: 4.8,
      reviews: 0,
      avatarType: 'navy',
    );
  }

  String _initialsFor(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'J';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
