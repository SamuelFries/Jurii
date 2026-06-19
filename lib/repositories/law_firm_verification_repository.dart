import '../models/law_firm_verification.dart';
import '../models/law_firm_verification_document.dart';
import '../models/law_firm_verification_status.dart';
import '../services/supabase_config.dart';
import 'profile_repository.dart';

class LawFirmVerificationRepository {
  const LawFirmVerificationRepository({
    this.profileRepository = const ProfileRepository(),
  });

  final ProfileRepository profileRepository;

  Future<LawFirmVerification?> fetchLatestForCurrentUser() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return null;

    final rows = await SupabaseConfig.client
        .from('law_firm_verifications')
        .select()
        .eq('owner_profile_id', user.id)
        .order('submitted_at', ascending: false)
        .limit(1);

    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<LawFirmVerification> submitVerification({
    required String firmName,
    required String cnpj,
    required String phone,
    required String email,
    required String address,
    required List<String> practiceAreas,
    required List<LawFirmVerificationDocument> documents,
  }) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) {
      throw StateError(
        'User must be authenticated to submit law firm verification.',
      );
    }

    await profileRepository.upsertProfile(
      id: user.id,
      fullName: _nameForUser(user.email, user.userMetadata),
      email: user.email ?? email,
      cpf: user.userMetadata?['cpf'] as String?,
    );

    await SupabaseConfig.client.from('law_firm_verifications').insert({
      'owner_profile_id': user.id,
      'firm_name': firmName,
      'cnpj': cnpj,
      'phone': phone,
      'email': email,
      'address': address,
      'practice_areas': practiceAreas,
      'status': 'pending',
    });

    return LawFirmVerification(
      ownerProfileId: user.id,
      firmName: firmName,
      cnpj: cnpj,
      phone: phone,
      email: email,
      address: address,
      practiceAreas: practiceAreas,
      documents: documents,
      status: LawFirmVerificationStatus.pending,
    );
  }

  LawFirmVerification _fromRow(Map<String, dynamic> row) {
    return LawFirmVerification(
      id: row['id'] as String?,
      ownerProfileId: row['owner_profile_id'] as String,
      lawFirmId: row['law_firm_id'] as String?,
      firmName: row['firm_name'] as String? ?? 'Escritório',
      cnpj: row['cnpj'] as String? ?? '',
      phone: row['phone'] as String? ?? '',
      email: row['email'] as String? ?? '',
      address: row['address'] as String? ?? '',
      practiceAreas: _practiceAreasFromRow(row['practice_areas']),
      documents: const [],
      status: _statusFromRow(row['status'] as String?),
      reviewedAt: _dateTimeFromRow(row['reviewed_at']),
      reviewerId: row['reviewer_id'] as String?,
      rejectionReason: row['rejection_reason'] as String?,
    );
  }

  LawFirmVerificationStatus _statusFromRow(String? value) {
    return switch (value) {
      'approved' => LawFirmVerificationStatus.approved,
      'rejected' => LawFirmVerificationStatus.rejected,
      _ => LawFirmVerificationStatus.pending,
    };
  }

  DateTime? _dateTimeFromRow(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  List<String> _practiceAreasFromRow(Object? value) {
    final areas = value is List
        ? value.whereType<String>().toList()
        : const <String>[];
    return areas
        .map((area) => area.trim())
        .where((area) => area.isNotEmpty)
        .toList();
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
