import '../models/chat_attachment.dart';
import 'document_file_validation.dart';

/// Regras de anexo do CHAT (o que pode ser enviado e com que teto).
///
/// Ficam separadas de [document_file_validation] porque são políticas
/// diferentes: lá é documento de verificação profissional, aqui é conversa —
/// vídeo entra, e cada tipo tem seu próprio teto. A checagem de magic bytes é
/// compartilhada ([bytesMatchMimeType]): assinatura de arquivo é a mesma
/// pergunta nos dois fluxos.
///
/// Estes tetos são ESPELHO do que o RPC `send_chat_attachment` valida
/// (migration 20260806120000). O servidor continua sendo a autoridade; o que
/// está aqui existe para recusar antes do upload, e não em vez dele.

const int maxChatImageBytes = 5 * 1024 * 1024;
const int maxChatDocumentBytes = 10 * 1024 * 1024;

/// 25 MB, cerca de 30 segundos em 1080p. Nem o image_picker do Android nem o
/// do iOS comprimem vídeo, então o arquivo que sai da galeria é o que sobe.
const int maxChatVideoBytes = 25 * 1024 * 1024;

/// Extensões aceitas em "Anexar arquivo". Foto e vídeo têm entradas próprias
/// no menu, mas continuam aqui: quem chega pelo seletor de arquivos espera
/// encontrá-las.
const List<String> chatAttachmentAllowedExtensions = [
  'jpg',
  'jpeg',
  'png',
  'webp',
  'mp4',
  'mov',
  'pdf',
  'doc',
  'docx',
];

/// MIME a partir da extensão, incluindo os dois containers de vídeo aceitos.
/// Os tipos compartilhados vêm de [mimeTypeForFileName] — uma tabela só.
String? chatAttachmentMimeType(String fileName) {
  final extension = fileName.split('.').last.toLowerCase();
  return switch (extension) {
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    _ => mimeTypeForFileName(fileName),
  };
}

/// Categoria do anexo, ou `null` quando o MIME não é aceito no chat.
ChatAttachmentKind? chatAttachmentKindForMime(String? mimeType) {
  if (mimeType == null) return null;
  if (mimeType.startsWith('image/')) return ChatAttachmentKind.image;
  if (mimeType == 'video/mp4' || mimeType == 'video/quicktime') {
    return ChatAttachmentKind.video;
  }
  if (mimeType == 'application/pdf' ||
      mimeType == 'application/msword' ||
      mimeType ==
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
    return ChatAttachmentKind.document;
  }
  return null;
}

int maxChatAttachmentBytes(ChatAttachmentKind kind) {
  return switch (kind) {
    ChatAttachmentKind.image => maxChatImageBytes,
    ChatAttachmentKind.video => maxChatVideoBytes,
    ChatAttachmentKind.document => maxChatDocumentBytes,
  };
}

/// Mensagem de recusa por tamanho. A do vídeo diz o que fazer a seguir: o teto
/// sozinho ("25 MB") não ajuda quem não faz ideia de quanto pesa um vídeo.
String chatAttachmentSizeLimitMessage(ChatAttachmentKind kind) {
  return switch (kind) {
    ChatAttachmentKind.image => 'Fotos podem ter no máximo 5 MB.',
    ChatAttachmentKind.document => 'Documentos podem ter no máximo 10 MB.',
    ChatAttachmentKind.video =>
      'Vídeos podem ter no máximo 25 MB, cerca de 30 segundos em alta '
          'qualidade. Envie um trecho menor.',
  };
}

/// Corpos que o servidor grava sozinho quando a mensagem é um anexo
/// (`send_chat_attachment`). Não é texto de ninguém: é rótulo para a prévia da
/// lista de conversas. Dentro do balão a mídia já se explica, então esse texto
/// é escondido — ver [isChatAttachmentAutoBody].
const Set<String> chatAttachmentAutoBodies = {
  'Foto enviada',
  'Vídeo enviado',
  'Documento enviado',
};

/// `true` quando o corpo da mensagem foi gerado pelo servidor para um anexo.
///
/// A comparação é EXATA de propósito: no dia em que o app enviar legenda junto
/// com a foto, a legenda aparece — só o rótulo automático some.
bool isChatAttachmentAutoBody(String body) {
  return chatAttachmentAutoBodies.contains(body.trim());
}

/// Duração no formato do player (`m:ss`, ou `h:mm:ss` quando passa da hora).
String formatMediaDuration(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final hours = safe.inHours;
  final minutes = safe.inMinutes.remainder(60);
  final seconds = safe.inSeconds.remainder(60);
  final secondsLabel = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$secondsLabel';
  }
  return '$minutes:$secondsLabel';
}
