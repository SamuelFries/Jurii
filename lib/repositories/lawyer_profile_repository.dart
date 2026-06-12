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
      final rows = await SupabaseConfig.client
          .from('lawyer_profiles')
          .select('id, oab_number, oab_state, primary_area, bio, approved_at')
          .eq('is_available', true)
          .order('approved_at', ascending: false)
          .limit(6);

      final profileIds = rows
          .map((row) => row['id'] as String?)
          .whereType<String>()
          .toList();
      final profilesById = await _fetchProfilesById(profileIds);

      return rows
          .map<LawyerProfileSummary>(
            (row) => _fromRow(row, profilesById[row['id'] as String?]),
          )
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

  Future<Map<String, _ProfileData>> _fetchProfilesById(
    List<String> profileIds,
  ) async {
    if (profileIds.isEmpty) return const {};

    try {
      final rows = await SupabaseConfig.client
          .from('profiles')
          .select('id, full_name, initials')
          .inFilter('id', profileIds);

      return {
        for (final row in rows)
          row['id'] as String: _ProfileData(
            name: row['full_name'] as String? ?? 'Advogado Jurii',
            initials: row['initials'] as String? ?? '',
          ),
      };
    } catch (_) {
      return const {};
    }
  }

  LawyerProfileSummary _fromRow(
    Map<String, dynamic> row,
    _ProfileData? profile,
  ) {
    final name = profile?.name ?? 'Advogado Jurii';
    final initials = profile?.initials.isNotEmpty == true
        ? profile!.initials
        : _initialsFor(name);

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

class _ProfileData {
  final String name;
  final String initials;

  const _ProfileData({required this.name, required this.initials});
}
