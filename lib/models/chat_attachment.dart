enum ChatAttachmentKind {
  image('image'),
  video('video'),
  document('document');

  const ChatAttachmentKind(this.value);

  final String value;

  /// Valor desconhecido cai em [document] de propósito: um tipo novo criado no
  /// servidor vira um cartão de arquivo (que sempre abre externamente) em vez
  /// de tentar renderizar mídia que este app ainda não sabe desenhar.
  static ChatAttachmentKind fromValue(String? value) {
    return switch (value) {
      'image' => ChatAttachmentKind.image,
      'video' => ChatAttachmentKind.video,
      _ => ChatAttachmentKind.document,
    };
  }
}

class ChatAttachment {
  final String id;
  final String messageId;
  final String conversationId;
  final String fileName;
  final String mimeType;
  final int fileSizeBytes;
  final String storagePath;
  final ChatAttachmentKind kind;

  const ChatAttachment({
    required this.id,
    required this.messageId,
    required this.conversationId,
    required this.fileName,
    required this.mimeType,
    required this.fileSizeBytes,
    required this.storagePath,
    required this.kind,
  });

  bool get isImage => kind == ChatAttachmentKind.image;

  bool get isVideo => kind == ChatAttachmentKind.video;

  /// Mídia é o que aparece DENTRO do balão (foto e vídeo); documento continua
  /// como cartão com nome e tamanho, porque não há o que pré-visualizar.
  bool get isMedia => isImage || isVideo;

  String get sizeLabel {
    if (fileSizeBytes >= 1024 * 1024) {
      final value = fileSizeBytes / (1024 * 1024);
      return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} MB';
    }

    final value = fileSizeBytes / 1024;
    return '${value.clamp(1, double.infinity).toStringAsFixed(0)} KB';
  }

  factory ChatAttachment.fromRow(Map<String, dynamic> row) {
    return ChatAttachment(
      id: row['id'] as String,
      messageId: row['message_id'] as String,
      conversationId: row['conversation_id'] as String,
      fileName: row['file_name'] as String? ?? 'arquivo',
      mimeType: row['mime_type'] as String? ?? 'application/octet-stream',
      fileSizeBytes: (row['file_size_bytes'] as num?)?.toInt() ?? 0,
      storagePath: row['storage_path'] as String,
      kind: ChatAttachmentKind.fromValue(row['kind'] as String?),
    );
  }
}
