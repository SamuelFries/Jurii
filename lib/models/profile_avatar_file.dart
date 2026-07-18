import 'dart:typed_data';

/// Imagem de perfil já validada e pronta para envio ao Storage.
class ProfileAvatarFile {
  const ProfileAvatarFile({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String fileName;
  final String mimeType;
  final Uint8List bytes;
}
