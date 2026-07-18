import 'package:flutter/foundation.dart';

import '../data/legal_practice_areas.dart';
import '../models/lawyer_status.dart';
import '../models/lawyer_verification.dart';
import '../models/pending_verification_upload.dart';
import '../models/verification_document.dart';
import '../services/supabase_config.dart';
import 'verification_document_storage.dart';

class LawyerVerificationRepository {
  const LawyerVerificationRepository({
    this.documentStorage = const VerificationDocumentStorage(),
  });

  final VerificationDocumentStorage documentStorage;

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
    List<PendingVerificationUpload> uploads = const [],
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
    final verificationId = row['id'] as String?;

    final userId = row['user_id'] as String? ?? user.id;

    if (verificationId != null && uploads.isNotEmpty) {
      await _persistDocuments(
        userId: userId,
        verificationId: verificationId,
        uploads: uploads,
      );
    }

    // A foto profissional também vira o avatar público do perfil.
    await _applyProfilePhotoAsAvatar(userId: userId, uploads: uploads);

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

  /// Sobe cada documento ao Storage e grava a linha em `verification_documents`.
  /// Em caso de falha, remove os blobs já enviados (rollback best-effort) — a
  /// verificação em si continua criada e o usuário reenvia os documentos.
  Future<void> _persistDocuments({
    required String userId,
    required String verificationId,
    required List<PendingVerificationUpload> uploads,
  }) async {
    final uploadedPaths = <String>[];
    try {
      for (final upload in uploads) {
        final path = await documentStorage.upload(userId: userId, file: upload);
        uploadedPaths.add(path);

        await SupabaseConfig.client.from('verification_documents').insert({
          'verification_id': verificationId,
          'user_id': userId,
          'document_type': upload.documentType,
          'title': upload.title,
          'storage_path': path,
          'mime_type': upload.mimeType,
          'file_size_bytes': upload.fileSizeBytes,
        });
      }
    } catch (error) {
      await documentStorage.remove(uploadedPaths);
      rethrow;
    }
  }

  /// Sobe a foto profissional ao bucket público e a define como avatar do
  /// perfil. Não-fatal: a verificação é a ação principal; se o avatar falhar,
  /// apenas registra e segue (a foto continua no pacote de documentos).
  Future<void> _applyProfilePhotoAsAvatar({
    required String userId,
    required List<PendingVerificationUpload> uploads,
  }) async {
    final photo = uploads
        .where((upload) => upload.documentType == 'professional_photo')
        .firstOrNull;
    if (photo == null) return;

    String? uploadedAvatarPath;
    try {
      uploadedAvatarPath = await documentStorage.uploadAvatar(
        userId: userId,
        file: photo,
      );
      await SupabaseConfig.client.rpc(
        'set_current_profile_avatar',
        params: {'storage_path_value': uploadedAvatarPath},
      );
    } catch (error) {
      if (uploadedAvatarPath != null) {
        await documentStorage.removeAvatar(uploadedAvatarPath);
      }
      debugPrint('Falha ao definir avatar da foto profissional: $error');
    }
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
      reviewedAt: _dateTimeFromRow(row['reviewed_at']),
      rejectionReason: row['rejection_reason'] as String?,
    );
  }

  DateTime? _dateTimeFromRow(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
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
      'rejected' => LawyerStatus.rejected,
      'pending' || 'draft' => LawyerStatus.pending,
      _ => LawyerStatus.client,
    };
  }
}
