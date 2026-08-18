
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/case_document.dart';
import '../services/supabase_config.dart';

/// Documentos anexados a um caso, no bucket privado `case-documents`.
///
/// AS REGRAS MORAM NO BANCO, e a tela só as traduz: anexa quem acessa o caso
/// (policy de INSERT), todo mundo do caso lê (SELECT + policy de leitura do
/// bucket, que segue a linha da tabela), e REMOVE só quem subiu, enquanto
/// ainda for do caso (migration 20260910120000).
///
/// A ORDEM das operações não é estética:
///
///  - Subir: primeiro o OBJETO, depois a LINHA. Se a linha falhar, o objeto
///    recém-subido é removido (rollback); se até o rollback falhar, o órfão é
///    INALCANÇÁVEL, porque a leitura do bucket exige uma linha apontando para
///    o caminho.
///  - Remover: primeiro a LINHA, depois o objeto. Invertido, uma falha no
///    meio deixaria uma linha viva apontando para objeto morto: um documento
///    listado que nunca abre.
class CaseDocumentRepository {
  const CaseDocumentRepository();

  static const String bucket = 'case-documents';

  /// Sem Supabase (demo, testes) a seção nem aparece. O seam vive AQUI e não
  /// no widget para um fake de teste poder se declarar disponível.
  bool get isAvailable => SupabaseConfig.isReady;

  bool get _demo => !SupabaseConfig.isReady;

  Future<List<CaseDocument>> fetchForCase(String caseId) async {
    if (_demo || SupabaseConfig.client.auth.currentUser == null) {
      return const [];
    }

    final rows = await SupabaseConfig.client
        .from('case_documents')
        .select(
          'id, case_id, uploaded_by, title, storage_path, mime_type, file_size_bytes, created_at',
        )
        .eq('case_id', caseId)
        .order('created_at', ascending: false);

    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    return rows
        .map<CaseDocument>(
          (row) => CaseDocument.fromRow(row, currentUserId: currentUserId),
        )
        .toList();
  }

  /// Sobe o arquivo e registra o documento no caso.
  ///
  /// O caminho é sempre `{uid}/{caseId}/...`: o primeiro segmento é o que a
  /// policy de escrita do bucket exige, e o segundo mantém a pasta da pessoa
  /// organizada por caso (útil no dashboard, irrelevante para as policies).
  Future<CaseDocument> upload({
    required String caseId,
    required String title,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) throw StateError('User must be authenticated.');

    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final path = '${user.id}/$caseId/$timestamp-${_safeFileName(fileName)}';

    await SupabaseConfig.client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );

    try {
      final row = await SupabaseConfig.client
          .from('case_documents')
          .insert({
            'case_id': caseId,
            'uploaded_by': user.id,
            'title': title,
            'storage_path': path,
            'mime_type': mimeType,
            'file_size_bytes': bytes.length,
          })
          .select(
            'id, case_id, uploaded_by, title, storage_path, mime_type, file_size_bytes, created_at',
          )
          .single();

      return CaseDocument.fromRow(row, currentUserId: user.id);
    } catch (error) {
      // A linha falhou (caso alheio, CHECK, rede): o objeto recém-subido não
      // pode ficar ocupando a pasta da pessoa. Se ESTA remoção também
      // falhar, o órfão é inalcançável por desenho.
      try {
        await SupabaseConfig.client.storage.from(bucket).remove([path]);
      } catch (cleanupError) {
        debugPrint('Rollback do upload falhou: $cleanupError');
      }
      rethrow;
    }
  }

  /// Remove um documento que EU subi. Linha primeiro; objeto depois,
  /// best-effort (órfão sem linha é inalcançável e não aparece para ninguém).
  Future<void> remove(CaseDocument document) async {
    await SupabaseConfig.client
        .from('case_documents')
        .delete()
        .eq('id', document.id);

    try {
      await SupabaseConfig.client.storage.from(bucket).remove([
        document.storagePath,
      ]);
    } catch (error) {
      debugPrint('Remoção do objeto no bucket falhou: $error');
    }
  }

  /// URL assinada de curta duração para abrir o documento fora do app.
  /// Mesmo padrão dos anexos de chat: 5 minutos cobre o toque, e o link que
  /// vazar de um print morre sozinho.
  Future<String> signedUrl(CaseDocument document) {
    return SupabaseConfig.client.storage
        .from(bucket)
        .createSignedUrl(document.storagePath, 300);
  }

  /// Nome de arquivo sem separador de caminho nem espaço: vira segmento de
  /// path no bucket.
  String _safeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }
}
