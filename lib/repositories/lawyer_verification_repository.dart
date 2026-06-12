import '../models/lawyer_status.dart';
import '../models/lawyer_verification.dart';
import '../models/verification_document.dart';
import '../services/supabase_config.dart';
import 'profile_repository.dart';

class LawyerVerificationRepository {
  const LawyerVerificationRepository({
    this.profileRepository = const ProfileRepository(),
  });

  final ProfileRepository profileRepository;

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
    required List<VerificationDocument> documents,
  }) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) {
      throw StateError('User must be authenticated to submit verification.');
    }

    await profileRepository.upsertProfile(
      id: user.id,
      fullName: _nameForUser(user.email, user.userMetadata),
      email: user.email ?? '',
      cpf: user.userMetadata?['cpf'] as String?,
    );

    await SupabaseConfig.client.from('lawyer_verifications').insert({
      'user_id': user.id,
      'oab_number': oabNumber,
      'oab_state': oabState,
      'practice_area': practiceArea,
      'status': 'pending',
    });

    return LawyerVerification(
      userId: user.id,
      oabNumber: oabNumber,
      oabState: oabState,
      practiceArea: practiceArea,
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
      documents: const [],
      status: _statusFromRow(row['status'] as String?),
    );
  }

  LawyerStatus _statusFromRow(String? value) {
    return switch (value) {
      'approved' => LawyerStatus.approved,
      'pending' || 'draft' => LawyerStatus.pending,
      _ => LawyerStatus.client,
    };
  }

  String _nameForUser(String? email, Map<String, dynamic>? metadata) {
    final metadataName =
        metadata?['full_name'] as String? ?? metadata?['name'] as String?;
    if (metadataName != null && metadataName.trim().isNotEmpty) {
      return metadataName.trim();
    }

    final localPart = email?.split('@').first.trim() ?? '';
    if (localPart.isEmpty) return 'Usuário Jurii';
    return localPart
        .split(RegExp(r'[._-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}
