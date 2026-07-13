import 'dart:typed_data';

/// Documento de verificação já escolhido pelo usuário e pronto para upload.
///
/// O usuário seleciona o arquivo (bytes na memória) ao tocar em cada item; o
/// envio real ao Storage acontece no submit, quando a verificação já tem id.
/// [documentType] é a string do enum do banco (`verification_document_type`
/// ou `law_firm_document_type`) — igual ao `id` do catálogo em ambos os
/// fluxos.
class PendingVerificationUpload {
  const PendingVerificationUpload({
    required this.documentId,
    required this.documentType,
    required this.title,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String documentId;
  final String documentType;
  final String title;
  final String fileName;
  final String mimeType;
  final Uint8List bytes;

  int get fileSizeBytes => bytes.length;
}
