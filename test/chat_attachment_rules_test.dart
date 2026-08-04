import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/chat_attachment.dart';
import 'package:jurii/utils/chat_attachment_rules.dart';
import 'package:jurii/utils/document_file_validation.dart';

Uint8List _isoBmff({List<int> brand = const [0x69, 0x73, 0x6F, 0x6D]}) {
  // [4 bytes de tamanho]['ftyp'][marca][resto]
  return Uint8List.fromList([
    0x00, 0x00, 0x00, 0x20,
    0x66, 0x74, 0x79, 0x70, // ftyp
    ...brand,
    ...List.filled(16, 0),
  ]);
}

void main() {
  group('MIME e categoria', () {
    test(
      'reconhece os dois containers de vídeo, com extensão em maiúscula',
      () {
        expect(chatAttachmentMimeType('obra.mp4'), 'video/mp4');
        // O iPhone entrega IMG_0001.MOV: extensão em maiúscula é o caso comum,
        // não a exceção.
        expect(chatAttachmentMimeType('IMG_0001.MOV'), 'video/quicktime');
      },
    );

    test('não inventa tipo para vídeo que o app não aceita', () {
      expect(chatAttachmentMimeType('clipe.webm'), isNull);
      expect(chatAttachmentMimeType('antigo.3gp'), isNull);
      expect(chatAttachmentMimeType('avi.avi'), isNull);
    });

    test('continua reconhecendo os tipos antigos', () {
      expect(chatAttachmentMimeType('doc.pdf'), 'application/pdf');
      expect(chatAttachmentMimeType('foto.JPG'), 'image/jpeg');
    });

    test('categoria separa vídeo de foto e de documento', () {
      expect(chatAttachmentKindForMime('video/mp4'), ChatAttachmentKind.video);
      expect(
        chatAttachmentKindForMime('video/quicktime'),
        ChatAttachmentKind.video,
      );
      expect(chatAttachmentKindForMime('image/png'), ChatAttachmentKind.image);
      expect(
        chatAttachmentKindForMime('application/pdf'),
        ChatAttachmentKind.document,
      );
      expect(chatAttachmentKindForMime('audio/mpeg'), isNull);
      expect(chatAttachmentKindForMime(null), isNull);
    });

    test('cada categoria tem seu próprio teto', () {
      expect(maxChatAttachmentBytes(ChatAttachmentKind.image), 5 * 1024 * 1024);
      expect(
        maxChatAttachmentBytes(ChatAttachmentKind.document),
        10 * 1024 * 1024,
      );
      expect(
        maxChatAttachmentBytes(ChatAttachmentKind.video),
        25 * 1024 * 1024,
      );
    });

    test('a recusa do vídeo diz o que fazer, não só o número', () {
      final message = chatAttachmentSizeLimitMessage(ChatAttachmentKind.video);
      expect(message, contains('25 MB'));
      expect(message, contains('trecho menor'));
    });
  });

  test('tudo que o seletor de arquivos oferece o app sabe enviar', () {
    // A lista alimenta o seletor: uma extensão aqui que o resto não reconheça
    // vira arquivo escolhível que morre em "tipo não suportado" no toque —
    // sem nada quebrando antes disso.
    for (final extensao in chatAttachmentAllowedExtensions) {
      final mime = chatAttachmentMimeType('arquivo.$extensao');
      expect(mime, isNotNull, reason: '.$extensao não tem MIME');
      expect(
        chatAttachmentKindForMime(mime),
        isNotNull,
        reason: '.$extensao ($mime) não cai em nenhuma categoria',
      );
    }
  });

  group('categoria do anexo vinda do banco', () {
    ChatAttachment attachmentWithKind(String? kind) {
      return ChatAttachment.fromRow({
        'id': 'a1',
        'message_id': 'm1',
        'conversation_id': 'c1',
        'file_name': 'arquivo',
        'mime_type': 'video/mp4',
        'file_size_bytes': 10,
        'storage_path': 'u/c/arquivo',
        'kind': kind,
      });
    }

    test('kind=video vira mídia (é o que decide o balão)', () {
      final video = attachmentWithKind('video');
      expect(video.kind, ChatAttachmentKind.video);
      expect(video.isVideo, isTrue);
      expect(video.isImage, isFalse);
      // isMedia é o predicado que escolhe entre prévia no balão e cartão de
      // arquivo: se ele deixar o vídeo de fora, o vídeo volta a ser anexo.
      expect(video.isMedia, isTrue);
    });

    test('foto continua mídia e documento continua fora', () {
      expect(attachmentWithKind('image').isMedia, isTrue);
      expect(attachmentWithKind('document').isMedia, isFalse);
    });

    test('kind desconhecido cai em documento, não em mídia quebrada', () {
      final unknown = attachmentWithKind('audio');
      expect(unknown.kind, ChatAttachmentKind.document);
      expect(unknown.isMedia, isFalse);
    });
  });

  group('assinatura de vídeo', () {
    test('aceita ISO-BMFF (ftyp no byte 4), que é mp4 e mov', () {
      expect(bytesMatchMimeType(_isoBmff(), 'video/mp4'), isTrue);
      expect(
        bytesMatchMimeType(
          _isoBmff(brand: const [0x71, 0x74, 0x20, 0x20]), // 'qt  '
          'video/quicktime',
        ),
        isTrue,
      );
    });

    test('recusa binário arbitrário renomeado para .mp4', () {
      final fake = Uint8List.fromList(List.filled(32, 0x41)); // 'AAAA...'
      expect(bytesMatchMimeType(fake, 'video/mp4'), isFalse);
    });

    test('recusa arquivo curto demais para ter cabeçalho', () {
      expect(
        bytesMatchMimeType(Uint8List.fromList([0x00, 0x00]), 'video/mp4'),
        isFalse,
      );
    });
  });

  group('corpo automático de anexo', () {
    test('reconhece os três rótulos que o servidor grava', () {
      expect(isChatAttachmentAutoBody('Foto enviada'), isTrue);
      expect(isChatAttachmentAutoBody('Vídeo enviado'), isTrue);
      expect(isChatAttachmentAutoBody('Documento enviado'), isTrue);
    });

    test('texto de gente continua sendo texto de gente', () {
      expect(isChatAttachmentAutoBody('Foto enviada ontem'), isFalse);
      expect(isChatAttachmentAutoBody('olha essa foto'), isFalse);
      expect(isChatAttachmentAutoBody(''), isFalse);
    });
  });

  group('duração', () {
    test('formata em m:ss e cresce para h:mm:ss', () {
      expect(formatMediaDuration(const Duration(seconds: 7)), '0:07');
      expect(formatMediaDuration(const Duration(seconds: 75)), '1:15');
      expect(
        formatMediaDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('duração negativa não vira texto quebrado', () {
      expect(formatMediaDuration(const Duration(seconds: -5)), '0:00');
    });
  });

  test('o teto de vídeo do app é o mesmo do servidor', () {
    // O app recusa antes de subir; o RPC recusa de verdade. Se os dois números
    // divergirem, o usuário sobe 25 MB de rede para ouvir um erro do servidor —
    // ou, pior, o app recusa algo que o servidor aceitaria.
    //
    // Lê a migration MAIS RECENTE que mexe no teto, não um arquivo fixo: preso
    // a um nome, este teste continuaria verde para sempre enquanto uma
    // migration nova mudasse o número no banco.
    final migrations =
        Directory('supabase/migrations')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final ultima = migrations.lastWhere(
      (file) => file.readAsStringSync().contains('Video attachment exceeds'),
      orElse: () => throw StateError('nenhuma migration define o teto'),
    );
    final migration = ultima.readAsStringSync();

    expect(
      migration,
      contains('file_size_bytes_value > $maxChatVideoBytes'),
      reason: 'teto de vídeo do app não bate com o do RPC',
    );
    expect(
      migration,
      contains('file_size_limit = $maxChatVideoBytes'),
      reason: 'teto do bucket não bate com o do app',
    );
    for (final mime in const ['video/mp4', 'video/quicktime']) {
      expect(
        chatAttachmentKindForMime(mime),
        ChatAttachmentKind.video,
        reason: '$mime está na migration mas o app não o reconhece',
      );
      expect(
        migration,
        contains("'$mime'"),
        reason: '$mime é aceito pelo app mas não pelo servidor',
      );
    }
  });
}
