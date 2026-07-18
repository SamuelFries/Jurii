import 'dart:typed_data';

import 'document_file_validation.dart';

const int maxProfileAvatarBytes = 5 * 1024 * 1024;
const List<String> profileAvatarAllowedExtensions = [
  'jpg',
  'jpeg',
  'png',
  'webp',
];

class ProfileAvatarValidation {
  const ProfileAvatarValidation._({this.mimeType, this.error});

  final String? mimeType;
  final String? error;

  bool get isValid => error == null;
}

/// Valida extensão, assinatura real e tamanho antes de subir uma foto pública.
ProfileAvatarValidation validateProfileAvatar({
  required String fileName,
  required Uint8List? bytes,
  required int sizeBytes,
}) {
  final extension = fileName.split('.').last.toLowerCase();
  final mimeType = mimeTypeForFileName(fileName);

  if (!profileAvatarAllowedExtensions.contains(extension) ||
      mimeType == null ||
      !mimeType.startsWith('image/')) {
    return const ProfileAvatarValidation._(
      error: 'Escolha uma imagem JPG, PNG ou WEBP.',
    );
  }
  if (bytes == null || bytes.isEmpty) {
    return const ProfileAvatarValidation._(
      error: 'Não foi possível ler a imagem selecionada.',
    );
  }
  if (sizeBytes > maxProfileAvatarBytes ||
      bytes.length > maxProfileAvatarBytes) {
    return const ProfileAvatarValidation._(
      error: 'A foto pode ter no máximo 5 MB.',
    );
  }
  if (!bytesMatchMimeType(bytes, mimeType)) {
    return const ProfileAvatarValidation._(
      error: 'A imagem selecionada é inválida ou está corrompida.',
    );
  }
  return ProfileAvatarValidation._(mimeType: mimeType);
}
