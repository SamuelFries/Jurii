import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/utils/profile_avatar_validation.dart';

void main() {
  test('aceita imagem quando extensão e assinatura são coerentes', () {
    final result = validateProfileAvatar(
      fileName: 'perfil.png',
      bytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x00]),
      sizeBytes: 5,
    );

    expect(result.isValid, isTrue);
    expect(result.mimeType, 'image/png');
  });

  test('rejeita formato que não é imagem permitida', () {
    final result = validateProfileAvatar(
      fileName: 'perfil.pdf',
      bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
      sizeBytes: 4,
    );

    expect(result.isValid, isFalse);
    expect(result.error, contains('JPG, PNG ou WEBP'));
  });

  test('rejeita arquivo renomeado sem assinatura real da imagem', () {
    final result = validateProfileAvatar(
      fileName: 'perfil.jpg',
      bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
      sizeBytes: 4,
    );

    expect(result.isValid, isFalse);
    expect(result.error, contains('inválida'));
  });

  test('rejeita imagem acima de cinco megabytes', () {
    final result = validateProfileAvatar(
      fileName: 'perfil.webp',
      bytes: Uint8List.fromList([
        0x52,
        0x49,
        0x46,
        0x46,
        0x00,
        0x00,
        0x00,
        0x00,
        0x57,
        0x45,
        0x42,
        0x50,
      ]),
      sizeBytes: maxProfileAvatarBytes + 1,
    );

    expect(result.isValid, isFalse);
    expect(result.error, contains('5 MB'));
  });

  test('usa também o tamanho real dos bytes contra metadado inconsistente', () {
    final bytes = Uint8List(maxProfileAvatarBytes + 1);
    bytes.setRange(0, 4, [0x89, 0x50, 0x4E, 0x47]);

    final result = validateProfileAvatar(
      fileName: 'perfil.png',
      bytes: bytes,
      sizeBytes: 4,
    );

    expect(result.isValid, isFalse);
    expect(result.error, contains('5 MB'));
  });
}
