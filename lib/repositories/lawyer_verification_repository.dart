import '../models/lawyer_status.dart';
import '../models/lawyer_verification.dart';
import '../models/verification_document.dart';
import '../services/supabase_config.dart';

class LawyerVerificationRepository {
  const LawyerVerificationRepository();

  Future<LawyerVerification> submitVerification({
    required String oabNumber,
    required String oabState,
    required String practiceArea,
    required List<VerificationDocument> documents,
  }) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) {
      throw StateError('User must be authenticated to submit verification.');
    }

    final row = await SupabaseConfig.client
        .from('lawyer_verifications')
        .insert({
          'user_id': user.id,
          'oab_number': oabNumber,
          'oab_state': oabState,
          'practice_area': practiceArea,
          'status': 'pending',
        })
        .select()
        .single();

    return LawyerVerification(
      userId: row['user_id'] as String,
      oabNumber: row['oab_number'] as String,
      oabState: row['oab_state'] as String,
      practiceArea: row['practice_area'] as String,
      documents: documents,
      status: LawyerStatus.pending,
    );
  }
}
