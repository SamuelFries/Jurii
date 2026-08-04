import 'package:flutter/material.dart';

import '../models/chat_attachment.dart';
import '../models/chat_message.dart';
import '../theme/app_colors.dart';
import 'chat_bubble_metrics.dart';
import 'jurii_motion.dart';
import 'message_status_check.dart';

/// Altura da prévia dentro do balão. Ver [kChatMediaSide] para o porquê de ser
/// quadrada; fixa, porque a mensagem não carrega as dimensões da mídia e
/// descobrir a proporção só depois do download faria cada balão pular de
/// altura no meio da rolagem.
const double kChatMediaHeight = kChatMediaSide;

/// Opacidade do véu escuro atrás da hora e da etiqueta de duração/peso.
///
/// 0.72 não é gosto: o pior caso desta interface é foto de documento em papel
/// BRANCO, e é sobre ela que o conteúdo do véu tem que continuar legível.
/// Quem manda no número é o TIQUE AZUL de visualizado, não o texto branco — o
/// azul é bem mais claro que o branco em luminância, e precisa de véu mais
/// fundo para alcançar os 4.5:1 que o resto do app segue
/// (test/contrast_guard_test.dart). Com 0.72 o tique fica em 4.8:1 e a hora,
/// em branco, sobra com 9.2:1.
const double kChatMediaScrimAlpha = 0.72;

/// Foto ou vídeo renderizado DENTRO do balão, com a hora sobreposta no canto —
/// o mesmo formato de aplicativo de mensagens. Documento continua como cartão
/// (não há prévia possível de um PDF sem renderizá-lo).
class ChatMediaBubble extends StatelessWidget {
  const ChatMediaBubble({
    super.key,
    required this.attachment,
    required this.signedUrl,
    required this.isLoadingUrl,
    required this.isMine,
    required this.time,
    required this.status,
    required this.onOpen,
    required this.onRetry,
    required this.onAutoRetry,
    this.showTimestamp = true,
  });

  final ChatAttachment attachment;

  /// URL assinada do bucket privado, ou `null` enquanto não há uma válida.
  final String? signedUrl;
  final bool isLoadingUrl;
  final bool isMine;
  final String time;
  final MessageDeliveryStatus status;

  /// Falso quando a mensagem tem legenda: aí a hora vai na linha de texto,
  /// embaixo, e sobrepô-la à mídia também seria repetição.
  final bool showTimestamp;

  final VoidCallback onOpen;

  /// Toque em "Tentar de novo": descarta a URL guardada e assina outra.
  /// Sempre permitido — é uma ação da pessoa.
  final VoidCallback onRetry;

  /// Recuperação AUTOMÁTICA de URL vencida, disparada pelo próprio download
  /// que falhou. Precisa ser um callback separado porque quem segura o limite
  /// é a tela, não este widget: cada nova tentativa gera URL nova e reconstrói
  /// a árvore, então um trinco local seria zerado a cada volta e a foto
  /// quebrada entraria em laço de assinar-baixar-falhar.
  final VoidCallback onAutoRetry;

  @override
  Widget build(BuildContext context) {
    final url = signedUrl;

    final Widget media;
    if (attachment.isVideo) {
      // A capa do vídeo não depende de URL nenhuma (não carrega nada), então
      // falha de assinatura não pode virar cartão de erro aqui: o toque ainda
      // funciona — a tela cheia assina na hora se o lote tiver falhado.
      media = _VideoPlaceholder(sizeLabel: attachment.sizeLabel);
    } else if (url == null) {
      media = isLoadingUrl
          ? const JuriiSkeletonCard(
              height: kChatMediaHeight,
              borderRadius: BorderRadius.all(Radius.circular(12)),
            )
          : _MediaFailure(onRetry: onRetry);
    } else {
      media = _ImageThumb(signedUrl: url, onExpired: onAutoRetry);
    }

    return JuriiPressable(
      // Foto sem URL não tem o que abrir; o alvo do toque vira o "Tentar de
      // novo" do cartão de falha, que tem botão próprio.
      onTap: attachment.isVideo || url != null ? onOpen : null,
      borderRadius: BorderRadius.circular(12),
      pressedScale: 0.99,
      // Sem URL o alvo fica desativado, e "Abrir foto, desativado" faria o
      // leitor de tela anunciar o anexo como indisponível — quando na verdade
      // existe o botão de nova tentativa logo ali dentro.
      semanticLabel: attachment.isVideo
          ? 'Abrir vídeo ${attachment.fileName}'
          : url != null
          ? 'Abrir foto ${attachment.fileName}'
          : isLoadingUrl
          ? 'Carregando foto ${attachment.fileName}'
          : 'Foto ${attachment.fileName} não carregada',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: kChatMediaHeight,
          // Teto próprio, além do teto do balão: sem ele a prévia estica até o
          // limite do balão e, numa tela larga, vira uma faixa deitada com a
          // foto reduzida a uma tira.
          width: kChatMediaSide,
          child: Stack(
            fit: StackFit.expand,
            children: [
              media,
              if (showTimestamp)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: _MediaTimestamp(
                    time: time,
                    status: status,
                    showStatus: isMine,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Foto com recuperação de URL vencida: avisa a tela quando o download falha,
/// e é a TELA que decide se vale outra tentativa (uma por anexo). O trinco por
/// URL aqui embaixo é só para não pedir duas vezes pela mesma URL dentro do
/// mesmo build — sozinho ele não seguraria nada, porque cada tentativa traz
/// URL nova e a troca de estado (falha, esqueleto, foto) recria este State.
class _ImageThumb extends StatefulWidget {
  const _ImageThumb({required this.signedUrl, required this.onExpired});

  final String signedUrl;
  final VoidCallback onExpired;

  @override
  State<_ImageThumb> createState() => _ImageThumbState();
}

class _ImageThumbState extends State<_ImageThumb> {
  String? _retriedUrl;

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    return Image.network(
      widget.signedUrl,
      fit: BoxFit.cover,
      // Decodifica no tamanho da prévia: uma foto de 2560px em memória cheia,
      // várias por conversa, é o caminho curto para o app ser morto por RAM.
      cacheHeight: (kChatMediaHeight * devicePixelRatio).round(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const JuriiSkeletonCard(
          height: kChatMediaHeight,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        _scheduleRetry();
        return _MediaFailure(onRetry: widget.onExpired);
      },
    );
  }

  void _scheduleRetry() {
    if (_retriedUrl == widget.signedUrl) return;
    _retriedUrl = widget.signedUrl;
    // errorBuilder roda DENTRO do build; mexer no estado do pai aqui dispara
    // "setState during build".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onExpired();
    });
  }
}

/// Capa do vídeo: superfície escura, botão de play e o peso do arquivo.
///
/// NÃO carrega o vídeo. A tentação era mostrar o primeiro quadro criando um
/// VideoPlayerController aqui, mas o ExoPlayer do Android chama `prepare()` no
/// construtor e bufferiza até 50 segundos de mídia — para um vídeo de 25 MB e
/// até 1 minuto, isso é BAIXAR O ARQUIVO INTEIRO só para desenhar um quadro,
/// em cada vídeo que passa pela tela, no plano de dados de quem está rolando a
/// conversa. Enquanto não existir miniatura gravada no envio, o certo é não
/// gastar nada até o toque — e é por isso que o peso aparece: quem está no 4G
/// decide antes de abrir.
class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder({required this.sizeLabel});

  final String sizeLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A3242), Color(0xFF11161F)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Center(child: _PlayBadge()),
          Positioned(
            left: 8,
            bottom: 8,
            child: _MediaChip(label: sizeLabel, icon: Icons.videocam),
          ),
        ],
      ),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: kChatMediaScrimAlpha),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
        ),
        child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
      ),
    );
  }
}

class _MediaChip extends StatelessWidget {
  const _MediaChip({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: kChatMediaScrimAlpha),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hora sobre a mídia, com véu escuro atrás: sem ele o texto branco some numa
/// foto clara — é o mesmo motivo de todo aplicativo de mensagens usar véu aqui.
class _MediaTimestamp extends StatelessWidget {
  const _MediaTimestamp({
    required this.time,
    required this.status,
    required this.showStatus,
  });

  final String time;
  final MessageDeliveryStatus status;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    if (time.isEmpty && !showStatus) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: kChatMediaScrimAlpha),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              time,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (showStatus) ...[
              const SizedBox(width: 4),
              MessageStatusCheck(
                status: status,
                pendingColor: Colors.white,
                // O véu é escuro nos dois temas (é preto sobre a foto), então
                // aqui o azul é sempre o de fundo escuro — usar o do tema
                // deixaria o tique invisível no modo escuro.
                readColor: AppColors.readReceiptOnDark,
                size: 13,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Só a FOTO chega aqui: o vídeo não carrega nada no balão, então não tem como
/// falhar antes do toque.
class _MediaFailure extends StatelessWidget {
  const _MediaFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return ColoredBox(
      color: colors.lightBlue,
      child: Center(
        // A prévia tem altura fixa, e este cartão é o ÚNICO caminho de volta
        // para quem a foto não carregou. Com fonte de acessibilidade grande o
        // conteúdo passava dos 240px e o botão "Tentar de novo" era cortado
        // pela borda — reduzir junto é melhor que perder a saída.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                color: colors.textSecondary,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                'Não foi possível carregar a foto.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: onRetry,
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
