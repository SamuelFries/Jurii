import 'dart:developer' as developer;

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
      final rows = await SupabaseConfig.client.rpc(
        'fetch_recommended_lawyers',
        params: {'limit_value': 6},
      );

      return (rows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map<LawyerProfileSummary>(_fromRow)
          .toList();
    } catch (error, stackTrace) {
      developer.log(
        'Supabase recommended lawyers fetch failed',
        name: 'LawyerProfileRepository',
        error: error,
        stackTrace: stackTrace,
      );
      return const [];
    }
  }

  Future<LawyerProfileSummary?> fetchLawyerById(String lawyerId) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return null;
    }

    final row = await SupabaseConfig.client
        .rpc(
          'fetch_lawyer_public_profile',
          params: {'lawyer_profile_id_value': lawyerId},
        )
        .maybeSingle();

    if (row == null) return null;
    return _fromRow(row);
  }

  LawyerProfileSummary _fromRow(Map<String, dynamic> row) {
    final name = row['full_name'] as String? ?? 'Advogado Jurii';
    final initials = row['initials'] as String? ?? _initialsFor(name);

    return LawyerProfileSummary(
      id: row['id'].toString(),
      name: name,
      initials: initials,
      oabNumber: row['oab_number'] as String? ?? '',
      oabState: row['oab_state'] as String? ?? '',
      primaryArea: row['primary_area'] as String? ?? 'Atendimento jurídico',
      bio:
          row['bio'] as String? ?? 'Perfil profissional verificado pela Jurii.',
      rating: (row['rating'] as num?)?.toDouble() ?? 4.8,
      reviews: row['reviews_count'] as int? ?? 0,
      avatarType: row['avatar_type'] as String? ?? 'navy',
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
