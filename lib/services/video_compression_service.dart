import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_compress/video_compress.dart';

/// Vídeo já reduzido, pronto para subir.
class CompressedVideo {
  const CompressedVideo({required this.path, required this.sizeBytes});

  final String path;
  final int sizeBytes;
}

/// Compressor de vídeo do chat.
///
/// Existe como interface, e não como chamada direta ao plugin, por dois
/// motivos concretos: a decisão de comprimir é testável sem aparelho, e o dia
/// em que o `video_compress` parar de dar conta (é um pacote de manutenção
/// lenta) a troca acontece aqui dentro, sem encostar na tela.
abstract class VideoCompressionService {
  /// Falso onde não há compressor — a web é o caso real. Quem chama usa isto
  /// para cair no comportamento antigo em vez de impedir o envio.
  bool get isSupported;

  /// Reduz o vídeo de [sourcePath]. Devolve `null` quando o compressor não deu
  /// conta; quem chama decide o que fazer (mandar o original, se couber).
  ///
  /// [onProgress] recebe de 0 a 1.
  Future<CompressedVideo?> compress(
    String sourcePath, {
    required ValueChanged<double> onProgress,
  });

  /// Cancela a compressão em curso. Seguro de chamar quando não há nenhuma.
  Future<void> cancel();

  /// Limpa os arquivos temporários que a compressão deixou.
  Future<void> clearCache();
}

class PluginVideoCompressionService implements VideoCompressionService {
  const PluginVideoCompressionService();

  @override
  bool get isSupported => !kIsWeb;

  @override
  Future<CompressedVideo?> compress(
    String sourcePath, {
    required ValueChanged<double> onProgress,
  }) async {
    if (!isSupported) return null;

    final assinatura = VideoCompress.compressProgress$.subscribe(
      (progresso) => onProgress((progresso / 100).clamp(0, 1).toDouble()),
    );

    try {
      final info = await VideoCompress.compressVideo(
        sourcePath,
        // 720p explícito em vez de "média": "média" é resolvida pelo aparelho
        // e varia de fabricante para fabricante, o que faria o mesmo vídeo
        // chegar com peso diferente dependendo do celular de quem envia.
        quality: VideoQuality.Res1280x720Quality,
        // O original é arquivo temporário do seletor, mas apagá-lo aqui
        // tiraria a saída de emergência de mandar o original quando a
        // compressão falha.
        deleteOrigin: false,
        includeAudio: true,
      );

      final caminho = info?.path;
      final tamanho = info?.filesize;
      if (caminho == null || tamanho == null || tamanho <= 0) return null;

      return CompressedVideo(path: caminho, sizeBytes: tamanho);
    } catch (error) {
      debugPrint('Video compression failed: $error');
      return null;
    } finally {
      assinatura.unsubscribe();
    }
  }

  @override
  Future<void> cancel() async {
    if (!isSupported) return;
    try {
      await VideoCompress.cancelCompression();
    } catch (error) {
      debugPrint('Video compression cancel failed: $error');
    }
  }

  @override
  Future<void> clearCache() async {
    if (!isSupported) return;
    try {
      await VideoCompress.deleteAllCache();
    } catch (error) {
      debugPrint('Video compression cache cleanup failed: $error');
    }
  }
}
