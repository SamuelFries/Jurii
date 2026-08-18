/// Um documento anexado a um caso.
///
/// A tabela `case_documents` existe desde a baseline e ficou um mês sem uma
/// linha sequer, porque o app nunca ganhou a tela. Caso jurídico sem
/// procuração, contrato e comprovante é meio caso: este model é a primeira
/// peça da feature de verdade.
class CaseDocument {
  const CaseDocument({
    required this.id,
    required this.caseId,
    required this.uploadedBy,
    required this.title,
    required this.storagePath,
    required this.isMine,
    this.mimeType,
    this.fileSizeBytes,
    this.createdAt,
  });

  final String id;
  final String caseId;
  final String uploadedBy;
  final String title;
  final String storagePath;

  /// Se quem olha foi quem subiu. Decide se o botão de remover aparece: a
  /// regra do banco é "cada um remove o que ele mesmo subiu", e a tela não
  /// oferece o que o servidor vai negar.
  final bool isMine;

  final String? mimeType;
  final int? fileSizeBytes;
  final DateTime? createdAt;

  bool get isPdf => mimeType == 'application/pdf';
  bool get isImage => mimeType?.startsWith('image/') ?? false;

  /// "1,2 MB" / "340 KB": tamanho como gente lê, ou vazio sem o dado.
  String get readableSize {
    final bytes = fileSizeBytes;
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024 * 1024) {
      final kb = (bytes / 1024).round();
      return '$kb KB';
    }
    final mb = bytes / (1024 * 1024);
    final texto = mb >= 10 ? mb.round().toString() : mb.toStringAsFixed(1);
    return '${texto.replaceAll('.', ',')} MB';
  }

  static CaseDocument fromRow(
    Map<String, dynamic> row, {
    required String? currentUserId,
  }) {
    final uploadedBy = row['uploaded_by']?.toString() ?? '';
    return CaseDocument(
      id: row['id']?.toString() ?? '',
      caseId: row['case_id']?.toString() ?? '',
      uploadedBy: uploadedBy,
      title: row['title']?.toString() ?? '',
      storagePath: row['storage_path']?.toString() ?? '',
      isMine: currentUserId != null && uploadedBy == currentUserId,
      mimeType: row['mime_type']?.toString(),
      fileSizeBytes: row['file_size_bytes'] is int
          ? row['file_size_bytes'] as int
          : int.tryParse(row['file_size_bytes']?.toString() ?? ''),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
    );
  }
}
