import '../models/law_firm_verification.dart';
import '../models/law_firm_verification_document.dart';
import '../models/law_firm_verification_status.dart';
import '../models/pending_verification_upload.dart';
import '../services/supabase_config.dart';
import 'profile_repository.dart';
import 'verification_document_storage.dart';

class LawFirmVerificationRepository {
  const LawFirmVerificationRepository({
    this.profileRepository = const ProfileRepository(),
    this.documentStorage = const VerificationDocumentStorage(),
  });

  final ProfileRepository profileRepository;
  final VerificationDocumentStorage documentStorage;

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
    String? addressNumber,
    String? addressComplement,
    required List<String> practiceAreas,
    required List<LawFirmVerificationDocument> documents,
    List<PendingVerificationUpload> uploads = const [],
    PendingVerificationUpload? profilePhoto,
    String? cep,
    double? latitude,
    double? longitude,
  }) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) {
      throw StateError(
        'User must be authenticated to submit law firm verification.',
      );
    }

    // Evita duplicar verificações: só permite reenvio após decisão.
    final latest = await fetchLatestForCurrentUser();
    if (latest?.status == LawFirmVerificationStatus.pending) {
      throw StateError(
        'Já existe uma verificação em andamento para este escritório.',
      );
    }

    // Cria o profile apenas se ainda não existir — o upsert cego sobrescrevia
    // o nome curado do usuário e anulava cpf/phone já preenchidos.
    final existingProfile = await profileRepository.fetchCurrentProfile();
    if (existingProfile == null) {
      await profileRepository.upsertProfile(
        fullName: _nameForUser(user.email, user.userMetadata),
        cpf: user.userMetadata?['cpf'] as String?,
      );
    }

    final inserted = await SupabaseConfig.client
        .from('law_firm_verifications')
        .insert({
          'owner_profile_id': user.id,
          'firm_name': firmName,
          'cnpj': cnpj,
          'phone': phone,
          'email': email,
          'address': address,
          if (addressNumber != null && addressNumber.isNotEmpty)
            'address_number': addressNumber,
          if (addressComplement != null && addressComplement.isNotEmpty)
            'address_complement': addressComplement,
          // CEP + coordenadas (BrasilAPI no submit). Best-effort: sem eles o
          // cadastro segue; o escritório só fica sem distância na descoberta.
          // O check do banco exige lat/lng aos pares.
          if (cep != null && cep.isNotEmpty) 'cep': cep,
          if (latitude != null && longitude != null) ...{
            'latitude': latitude,
            'longitude': longitude,
          },
          'practice_areas': practiceAreas,
          'status': 'pending',
        })
        .select('id')
        .single();

    final verificationId = inserted['id'] as String?;
    if (verificationId != null && uploads.isNotEmpty) {
      await _persistDocuments(
        ownerProfileId: user.id,
        verificationId: verificationId,
        uploads: uploads,
      );
    }

    final avatarStoragePath = verificationId == null || profilePhoto == null
        ? null
        : await _persistProfilePhoto(
            ownerProfileId: user.id,
            verificationId: verificationId,
            profilePhoto: profilePhoto,
          );

    return LawFirmVerification(
      id: verificationId,
      ownerProfileId: user.id,
      avatarStoragePath: avatarStoragePath,
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

  Future<String> _persistProfilePhoto({
    required String ownerProfileId,
    required String verificationId,
    required PendingVerificationUpload profilePhoto,
  }) async {
    String? uploadedPath;
    try {
      uploadedPath = await documentStorage.uploadLawFirmAvatar(
        userId: ownerProfileId,
        verificationId: verificationId,
        file: profilePhoto,
      );
      await SupabaseConfig.client.rpc(
        'set_current_law_firm_verification_avatar',
        params: {
          'verification_id_value': verificationId,
          'storage_path_value': uploadedPath,
        },
      );
      return uploadedPath;
    } catch (_) {
      if (uploadedPath != null) {
        await documentStorage.removeLawFirmAvatar(uploadedPath);
      }
      rethrow;
    }
  }

  /// Sobe cada documento ao Storage e grava a linha em
  /// `law_firm_verification_documents`; rollback best-effort dos blobs em caso
  /// de falha (a verificação continua criada, o usuário reenvia os documentos).
  Future<void> _persistDocuments({
    required String ownerProfileId,
    required String verificationId,
    required List<PendingVerificationUpload> uploads,
  }) async {
    final uploadedPaths = <String>[];
    try {
      for (final upload in uploads) {
        final path = await documentStorage.upload(
          userId: ownerProfileId,
          file: upload,
        );
        uploadedPaths.add(path);

        await SupabaseConfig.client
            .from('law_firm_verification_documents')
            .insert({
              'verification_id': verificationId,
              'owner_profile_id': ownerProfileId,
              'document_type': upload.documentType,
              'title': upload.title,
              'storage_path': path,
              'mime_type': upload.mimeType,
            });
      }
    } catch (error) {
      await documentStorage.remove(uploadedPaths);
      rethrow;
    }
  }

  LawFirmVerification _fromRow(Map<String, dynamic> row) {
    return LawFirmVerification(
      id: row['id'] as String?,
      ownerProfileId: row['owner_profile_id'] as String,
      lawFirmId: row['law_firm_id'] as String?,
      avatarStoragePath: row['avatar_storage_path'] as String?,
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
