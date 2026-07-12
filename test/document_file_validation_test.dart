import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/utils/document_file_validation.dart';

Uint8List _bytes(List<int> prefix, {int pad = 0}) {
  return Uint8List.fromList([...prefix, ...List.filled(pad, 0)]);
}

final _pdf = _bytes([0x25, 0x50, 0x44, 0x46], pad: 20); // %PDF
final _png = _bytes([0x89, 0x50, 0x4E, 0x47], pad: 20);
final _jpeg = _bytes([0xFF, 0xD8, 0xFF], pad: 20);

void main() {
  group('mimeTypeForFileName', () {
    test('mapeia extensões suportadas', () {
      expect(mimeTypeForFileName('doc.pdf'), 'application/pdf');
      expect(mimeTypeForFileName('FOTO.JPG'), 'image/jpeg');
      expect(mimeTypeForFileName('scan.jpeg'), 'image/jpeg');
      expect(mimeTypeForFileName('img.png'), 'image/png');
      expect(mimeTypeForFileName('img.webp'), 'image/webp');
    });

    test('retorna null para extensão desconhecida', () {
      expect(mimeTypeForFileName('arquivo.txt'), isNull);
      expect(mimeTypeForFileName('semextensao'), isNull);
    });
  });

  group('bytesMatchMimeType', () {
    test('aceita assinatura correta', () {
      expect(bytesMatchMimeType(_pdf, 'application/pdf'), isTrue);
      expect(bytesMatchMimeType(_png, 'image/png'), isTrue);
      expect(bytesMatchMimeType(_jpeg, 'image/jpeg'), isTrue);
    });

    test('recusa bytes que não batem com o MIME', () {
      expect(bytesMatchMimeType(_png, 'application/pdf'), isFalse);
      expect(bytesMatchMimeType(_pdf, 'image/png'), isFalse);
    });
  });

  group('validateVerificationDocument', () {
    test('aceita PDF válido', () {
      final result = validateVerificationDocument(
        fileName: 'oab.pdf',
        bytes: _pdf,
        sizeBytes: _pdf.length,
      );
      expect(result.isValid, isTrue);
      expect(result.mimeType, 'application/pdf');
    });

    test('aceita imagem válida', () {
      final result = validateVerificationDocument(
        fileName: 'foto.png',
        bytes: _png,
        sizeBytes: _png.length,
      );
      expect(result.isValid, isTrue);
      expect(result.mimeType, 'image/png');
    });

    test('recusa extensão não permitida (docx)', () {
      final result = validateVerificationDocument(
        fileName: 'contrato.docx',
        bytes: _bytes([0x50, 0x4B], pad: 10),
        sizeBytes: 12,
      );
      expect(result.isValid, isFalse);
      expect(result.error, contains('PDF ou imagem'));
    });

    test('recusa arquivo renomeado (magic bytes divergentes)', () {
      // .png por extensão, mas bytes de PDF.
      final result = validateVerificationDocument(
        fileName: 'fake.png',
        bytes: _pdf,
        sizeBytes: _pdf.length,
      );
      expect(result.isValid, isFalse);
      expect(result.error, contains('inválido ou corrompido'));
    });

    test('recusa bytes vazios', () {
      final result = validateVerificationDocument(
        fileName: 'x.pdf',
        bytes: Uint8List(0),
        sizeBytes: 0,
      );
      expect(result.isValid, isFalse);
      expect(result.error, contains('ler o arquivo'));
    });

    test('recusa acima de 10 MB', () {
      final result = validateVerificationDocument(
        fileName: 'grande.pdf',
        bytes: _pdf,
        sizeBytes: maxVerificationFileBytes + 1,
      );
      expect(result.isValid, isFalse);
      expect(result.error, contains('10 MB'));
    });
  });
}
