import '../data/legal_practice_areas.dart';
import '../models/lawyer_status.dart';
import '../models/lawyer_verification.dart';
import '../models/verification_document.dart';
import '../services/supabase_config.dart';

class LawyerVerificationRepository {
  const LawyerVerificationRepository();

  Future<LawyerVerification?> fetchLatestForCurrentUser() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return null;

    final rows = await SupabaseConfig.client
        .from('lawyer_verifications')
        .select()
        .eq('user_id', user.id)
        .order('submitted_at', ascending: false)
        .limit(1);

    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<LawyerVerification> submitVerification({
    required String oabNumber,
    required String oabState,
    required String practiceArea,
    required List<String> practiceAreas,
    required List<VerificationDocument> documents,
  }) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) {
      throw StateError('User must be authenticated to submit verification.');
    }

    final rows = await SupabaseConfig.client.rpc(
      'submit_lawyer_verification',
      params: {
        'oab_number_value': oabNumber,
        'oab_state_value': oabState,
        'practice_area_value': practiceArea,
        'practice_areas_value': practiceAreas,
      },
    );

    final row = (rows as List<dynamic>).cast<Map<String, dynamic>>().first;

    final returnedPracticeArea =
        row['practice_area'] as String? ?? primaryPracticeArea(practiceAreas);

    return LawyerVerification(
      userId: row['user_id'] as String? ?? user.id,
      oabNumber: row['oab_number'] as String? ?? oabNumber,
      oabState: row['oab_state'] as String? ?? oabState,
      practiceArea: returnedPracticeArea,
      practiceAreas: _practiceAreasFromRow(
        row['practice_areas'],
        fallback: [returnedPracticeArea],
      ),
      documents: documents,
      status: LawyerStatus.pending,
    );
  }

  LawyerVerification _fromRow(Map<String, dynamic> row) {
    return LawyerVerification(
      userId: row['user_id'] as String,
      oabNumber: row['oab_number'] as String? ?? '',
      oabState: row['oab_state'] as String? ?? '',
      practiceArea: row['practice_area'] as String? ?? '',
      practiceAreas: _practiceAreasFromRow(
        row['practice_areas'],
        fallback: [row['practice_area'] as String? ?? ''],
      ),
      documents: const [],
      status: _statusFromRow(row['status'] as String?),
    );
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

  LawyerStatus _statusFromRow(String? value) {
    return switch (value) {
      'approved' => LawyerStatus.approved,
      'pending' || 'draft' => LawyerStatus.pending,
      _ => LawyerStatus.client,
    };
  }
}
