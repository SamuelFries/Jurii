import 'dart:typed_data';

/// Validação de arquivos enviados (verificação profissional/escritório).
///
/// Mesma abordagem defensiva dos anexos de chat: além da extensão, confere os
/// magic bytes para não aceitar um arquivo renomeado. Extraído para util porque
/// agora dois fluxos precisam da mesma regra (anexos e documentos de
/// verificação).

/// Teto de tamanho por documento de verificação (10 MB), alinhado ao limite
/// dos anexos de documento no chat e ao CHECK da tabela no banco.
const int maxVerificationFileBytes = 10 * 1024 * 1024;

/// Extensões aceitas em documentos de verificação (PDF ou imagem).
const List<String> verificationAllowedExtensions = [
  'pdf',
  'jpg',
  'jpeg',
  'png',
  'webp',
];

/// MIME a partir da extensão do nome do arquivo, ou `null` se não suportado.
String? mimeTypeForFileName(String fileName) {
  final extension = fileName.split('.').last.toLowerCase();
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    _ => null,
  };
}

/// Confere se os primeiros bytes do arquivo batem com o MIME declarado.
bool bytesMatchMimeType(List<int> bytes, String mimeType) {
  bool startsWith(List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }

  switch (mimeType) {
    case 'application/pdf':
      return startsWith(const [0x25, 0x50, 0x44, 0x46]); // %PDF
    case 'image/jpeg':
      return startsWith(const [0xFF, 0xD8, 0xFF]);
    case 'image/png':
      return startsWith(const [0x89, 0x50, 0x4E, 0x47]);
    case 'image/webp':
      return bytes.length >= 12 &&
          startsWith(const [0x52, 0x49, 0x46, 0x46]) && // RIFF
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50; // WEBP
    case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
      return startsWith(const [0x50, 0x4B]); // ZIP (PK)
    case 'application/msword':
      return startsWith(const [0xD0, 0xCF, 0x11, 0xE0]) ||
          startsWith(const [0x50, 0x4B]);
    default:
      return false;
  }
}

/// Resultado de validação: `null` em `error` quando o arquivo é aceito.
class DocumentValidation {
  const DocumentValidation._({this.mimeType, this.error});

  final String? mimeType;
  final String? error;

  bool get isValid => error == null;
}

/// Valida um documento de verificação escolhido pelo usuário: extensão
/// suportada, bytes legíveis, assinatura coerente e tamanho dentro do teto.
DocumentValidation validateVerificationDocument({
  required String fileName,
  required Uint8List? bytes,
  required int sizeBytes,
}) {
  final mimeType = mimeTypeForFileName(fileName);
  if (mimeType == null ||
      !verificationAllowedExtensions.contains(
        fileName.split('.').last.toLowerCase(),
      )) {
    return const DocumentValidation._(
      error: 'Envie um PDF ou imagem (JPG, PNG ou WEBP).',
    );
  }
  if (bytes == null || bytes.isEmpty) {
    return const DocumentValidation._(
      error: 'Não foi possível ler o arquivo selecionado.',
    );
  }
  if (!bytesMatchMimeType(bytes, mimeType)) {
    return const DocumentValidation._(error: 'Arquivo inválido ou corrompido.');
  }
  if (sizeBytes > maxVerificationFileBytes) {
    return const DocumentValidation._(
      error: 'Cada documento pode ter no máximo 10 MB.',
    );
  }
  return DocumentValidation._(mimeType: mimeType);
}
