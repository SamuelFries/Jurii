import '../models/chat_attachment.dart';
import 'chat_attachment_rules.dart';

/// Acima disto vale gastar CPU e bateria comprimindo. Abaixo, não: um vídeo de
/// 5 MB já cabe e já sobe rápido, e transcodificar só trocaria qualidade por
/// nada — o usuário esperaria vinte segundos para economizar dois megabytes.
const int kChatVideoCompressThresholdBytes = 8 * 1024 * 1024;

/// Teto do arquivo de ENTRADA. Um vídeo de 4K com dois minutos passa de meio
/// giga; comprimir isso num celular é minutos de espera com o app travado na
/// tela. Recusar antes é mais honesto que começar um trabalho que ninguém vai
/// querer esperar terminar.
const int kChatVideoSourceMaxBytes = 400 * 1024 * 1024;

enum VideoUploadAction {
  /// Já cabe e não compensa comprimir: sobe como está.
  sendAsIs,

  /// Passa pelo compressor antes de subir.
  compress,

  /// Nem tenta: o arquivo é grande demais para o caminho existir.
  reject,
}

class VideoUploadDecision {
  const VideoUploadDecision._(this.action, this.message);

  final VideoUploadAction action;

  /// Texto para o usuário quando [action] é [VideoUploadAction.reject].
  final String? message;

  static const VideoUploadDecision sendAsIs = VideoUploadDecision._(
    VideoUploadAction.sendAsIs,
    null,
  );
  static const VideoUploadDecision compress = VideoUploadDecision._(
    VideoUploadAction.compress,
    null,
  );

  factory VideoUploadDecision.reject(String message) =>
      VideoUploadDecision._(VideoUploadAction.reject, message);
}

/// Decide o que fazer com o vídeo que a pessoa escolheu.
///
/// [canCompress] é falso onde não existe compressor (navegador). Lá o
/// comportamento continua o de antes: cabe, sobe; não cabe, recusa. É o que
/// garante que um compressor quebrado ou ausente degrade para o que já
/// funcionava, em vez de impedir o envio.
VideoUploadDecision decideVideoUpload({
  required int sourceBytes,
  required bool canCompress,
}) {
  if (sourceBytes <= 0) {
    return VideoUploadDecision.reject('Não foi possível ler o vídeo.');
  }

  final cabeSemComprimir = sourceBytes <= maxChatVideoBytes;

  if (!canCompress) {
    return cabeSemComprimir
        ? VideoUploadDecision.sendAsIs
        : VideoUploadDecision.reject(
            chatAttachmentSizeLimitMessage(ChatAttachmentKind.video),
          );
  }

  if (sourceBytes > kChatVideoSourceMaxBytes) {
    return VideoUploadDecision.reject(
      'Este vídeo é grande demais para ser preparado no celular. '
      'Envie um trecho menor.',
    );
  }

  if (cabeSemComprimir && sourceBytes < kChatVideoCompressThresholdBytes) {
    return VideoUploadDecision.sendAsIs;
  }

  return VideoUploadDecision.compress;
}

/// Depois de comprimir, o resultado ainda precisa caber. Devolve `null` quando
/// está tudo certo, ou o texto da recusa.
///
/// A mensagem fala de DURAÇÃO, não de megabytes: quem chegou até aqui já
/// escolheu o vídeo e esperou a compressão, e "reduza o tamanho" não diz o que
/// fazer. O que a pessoa controla é quanto tempo ela grava.
String? videoRejectionAfterCompression(int compressedBytes) {
  if (compressedBytes <= 0) return 'Não foi possível preparar o vídeo.';
  if (compressedBytes <= maxChatVideoBytes) return null;
  return 'Mesmo reduzido, o vídeo passa de 25 MB. '
      'Envie um trecho de até cerca de um minuto e meio.';
}

/// Nome do arquivo depois da compressão: o compressor devolve mp4 nos dois
/// sistemas, então o `.MOV` do iPhone tem que virar `.mp4` — senão a extensão
/// mente sobre o conteúdo e o servidor recusa por MIME incoerente.
String mp4FileNameFor(String originalName) {
  final ponto = originalName.lastIndexOf('.');
  // Nome que começa com ponto (arquivo oculto) não tem extensão para trocar.
  final base = ponto > 0 ? originalName.substring(0, ponto) : originalName;
  return '$base.mp4';
}
