import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/utils/chat_attachment_rules.dart';
import 'package:jurii/utils/video_upload_policy.dart';

const int _mb = 1024 * 1024;

void main() {
  group('sem compressor (navegador)', () {
    test('o que cabe sobe como está', () {
      final d = decideVideoUpload(sourceBytes: 20 * _mb, canCompress: false);
      expect(d.action, VideoUploadAction.sendAsIs);
    });

    test('o que não cabe é recusado, como antes', () {
      // Esta é a rede de segurança inteira: onde não há compressor, o
      // comportamento é exatamente o que já funcionava.
      final d = decideVideoUpload(sourceBytes: 40 * _mb, canCompress: false);
      expect(d.action, VideoUploadAction.reject);
      expect(d.message, contains('25 MB'));
    });
  });

  group('com compressor', () {
    test('vídeo pequeno não paga o custo de comprimir', () {
      // Transcodificar 5 MB é o usuário esperando vinte segundos para
      // economizar dois — e perdendo qualidade de graça.
      final d = decideVideoUpload(sourceBytes: 5 * _mb, canCompress: true);
      expect(d.action, VideoUploadAction.sendAsIs);
    });

    test('vídeo médio que já cabe ainda assim é comprimido', () {
      // Cabe, mas 20 MB por vídeo enche a conta de Storage rápido.
      final d = decideVideoUpload(sourceBytes: 20 * _mb, canCompress: true);
      expect(d.action, VideoUploadAction.compress);
    });

    test('vídeo grande passa a ser enviável', () {
      // O ponto da frente inteira: 80 MB era recusa seca antes.
      final d = decideVideoUpload(sourceBytes: 80 * _mb, canCompress: true);
      expect(d.action, VideoUploadAction.compress);
    });

    test('vídeo gigante é recusado antes de gastar bateria', () {
      final d = decideVideoUpload(sourceBytes: 700 * _mb, canCompress: true);
      expect(d.action, VideoUploadAction.reject);
      expect(d.message, contains('grande demais'));
    });
  });

  test('arquivo vazio é recusado nos dois casos', () {
    for (final pode in [true, false]) {
      expect(
        decideVideoUpload(sourceBytes: 0, canCompress: pode).action,
        VideoUploadAction.reject,
      );
    }
  });

  group('depois de comprimir', () {
    test('dentro do teto passa', () {
      expect(videoRejectionAfterCompression(10 * _mb), isNull);
      expect(videoRejectionAfterCompression(maxChatVideoBytes), isNull);
    });

    test('acima do teto fala de DURAÇÃO, não de megabytes', () {
      // Quem chegou aqui já escolheu o vídeo e esperou a compressão: "reduza o
      // tamanho" não diz o que fazer. O que a pessoa controla é o tempo.
      final recusa = videoRejectionAfterCompression(maxChatVideoBytes + 1);
      expect(recusa, isNotNull);
      expect(recusa, contains('trecho'));
    });
  });

  group('nome do arquivo comprimido', () {
    test('a extensão vira mp4, preservando o nome', () {
      expect(mp4FileNameFor('IMG_0042.MOV'), 'IMG_0042.mp4');
      expect(mp4FileNameFor('VID_20260808.mp4'), 'VID_20260808.mp4');
    });

    test('nome com pontos no meio só perde a última extensão', () {
      expect(mp4FileNameFor('caso.2026.audiencia.mov'), 'caso.2026.audiencia.mp4');
    });

    test('nome sem extensão ganha uma', () {
      expect(mp4FileNameFor('video'), 'video.mp4');
    });
  });

  test('o gatilho de compressão fica abaixo do teto de envio', () {
    // Se o gatilho passasse do teto, existiria uma faixa de vídeos grandes
    // demais para subir e pequenos demais para serem comprimidos — recusados
    // sem nenhum caminho de saída.
    expect(kChatVideoCompressThresholdBytes, lessThan(maxChatVideoBytes));
  });
}
