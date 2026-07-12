import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pending_verification_upload.dart';
import '../services/supabase_config.dart';

/// Envio dos documentos de verificação ao bucket privado
/// `verification-documents`. Compartilhado pelos repositórios de advogado e
/// escritório (mesmo bucket, mesma policy de pasta própria `{uid}/...`).
///
/// A policy de escrita do bucket exige que o primeiro segmento do caminho seja
/// o `auth.uid()`, então todo caminho começa por `{userId}/`. O caminho não
/// depende do id da verificação — assim o upload roda antes de criar a linha,
/// e as linhas de documento só são inseridas depois, apontando para o caminho.
class VerificationDocumentStorage {
  const VerificationDocumentStorage();

  static const String bucket = 'verification-documents';

  /// Bucket público das fotos de perfil.
  static const String avatarBucket = 'profile-avatars';

  /// Sobe um documento e retorna o caminho salvo no Storage.
  Future<String> upload({
    required String userId,
    required PendingVerificationUpload file,
  }) async {
    final path = _pathFor(userId: userId, file: file);
    await SupabaseConfig.client.storage
        .from(bucket)
        .uploadBinary(
          path,
          file.bytes,
          fileOptions: FileOptions(contentType: file.mimeType, upsert: false),
        );
    return path;
  }

  /// Sobe a foto profissional como avatar público e retorna a URL pública.
  ///
  /// Vai para o bucket `profile-avatars` (leitura pública, escrita na pasta
  /// própria `{uid}/...`), separado dos documentos privados de verificação.
  Future<String> uploadAvatar({
    required String userId,
    required PendingVerificationUpload file,
  }) async {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final path = '$userId/avatar-$timestamp-${_safeFileName(file.fileName)}';
    await SupabaseConfig.client.storage
        .from(avatarBucket)
        .uploadBinary(
          path,
          file.bytes,
          fileOptions: FileOptions(contentType: file.mimeType, upsert: true),
        );
    return SupabaseConfig.client.storage.from(avatarBucket).getPublicUrl(path);
  }

  /// Remove caminhos já enviados (rollback quando o submit falha no meio).
  Future<void> remove(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await SupabaseConfig.client.storage.from(bucket).remove(paths);
    } catch (error) {
      // Rollback best-effort: um blob órfão no bucket privado é inócuo e não
      // deve mascarar o erro original do submit.
      debugPrint('VerificationDocumentStorage.remove falhou: $error');
    }
  }

  String _pathFor({
    required String userId,
    required PendingVerificationUpload file,
  }) {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final safeName = _safeFileName(file.fileName);
    return '$userId/${file.documentType}-$timestamp-$safeName';
  }

  String _safeFileName(String fileName) {
    final name = fileName
        .split(RegExp(r'[\\/]'))
        .where((part) => part.trim().isNotEmpty)
        .lastOrNull;
    final sanitized = (name ?? 'documento')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    return sanitized.isEmpty ? 'documento' : sanitized;
  }
}
