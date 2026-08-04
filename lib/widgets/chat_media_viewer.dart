import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/chat_attachment.dart';
import '../utils/chat_attachment_rules.dart';

/// Tela cheia de uma mídia do chat: foto com zoom, vídeo com controles.
///
/// Fundo preto e barra sobreposta, como todo visualizador de mídia — o que
/// importa é o conteúdo, não o cromo do app.
class ChatMediaViewerPage extends StatelessWidget {
  const ChatMediaViewerPage({
    super.key,
    required this.attachment,
    required this.signedUrl,
  });

  final ChatAttachment attachment;
  final String signedUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          attachment.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
          tooltip: 'Fechar',
        ),
      ),
      body: SafeArea(
        child: attachment.isVideo
            ? _VideoViewer(signedUrl: signedUrl)
            : _ImageViewer(signedUrl: signedUrl),
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.signedUrl});

  final String signedUrl;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Image.network(
          signedUrl,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const _ViewerSpinner();
          },
          errorBuilder: (context, error, stackTrace) {
            return const _ViewerFailure(
              message: 'Não foi possível carregar esta foto.',
            );
          },
        ),
      ),
    );
  }
}

/// Player enxuto em vez de um pacote de controles: o chat precisa de play,
/// pause, barra e tempo — nada além disso justificaria outra dependência.
class _VideoViewer extends StatefulWidget {
  const _VideoViewer({required this.signedUrl});

  final String signedUrl;

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.signedUrl),
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onTick);
      await controller.play();
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    final antigo = _controller;
    _controller = null;
    setState(() => _failed = false);
    antigo?.removeListener(_onTick);
    await antigo?.dispose();
    await _load();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      // Terminado, o play recomeça do zero — senão o botão não faz nada
      // visível no fim do vídeo.
      if (controller.value.position >= controller.value.duration) {
        controller.seekTo(Duration.zero);
      }
      controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (_failed) {
      // Vídeo de 25 MB em rede ruim morre no meio com frequência; sem uma nova
      // tentativa aqui, a única saída era fechar a tela cheia e tocar de novo
      // no balão.
      return _ViewerFailure(
        message: 'Não foi possível reproduzir este vídeo.',
        onRetry: _reload,
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const _ViewerSpinner();
    }

    final value = controller.value;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: GestureDetector(
              onTap: _togglePlay,
              child: AspectRatio(
                aspectRatio: value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(controller),
                    if (!value.isPlaying)
                      const _PlayGlyph(size: 68, iconSize: 34),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 16),
          child: Row(
            children: [
              IconButton(
                onPressed: _togglePlay,
                icon: Icon(
                  value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                tooltip: value.isPlaying ? 'Pausar' : 'Reproduzir',
              ),
              Expanded(
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  colors: VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white.withValues(alpha: 0.35),
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${formatMediaDuration(value.position)} / '
                '${formatMediaDuration(value.duration)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Triângulo de play sobre disco escuro — o mesmo desenho no balão e na tela
/// cheia, para o toque parecer continuidade e não outra coisa.
class _PlayGlyph extends StatelessWidget {
  const _PlayGlyph({this.size = 52, this.iconSize = 28});

  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.46),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
        ),
        child: Icon(Icons.play_arrow, color: Colors.white, size: iconSize),
      ),
    );
  }
}

class _ViewerSpinner extends StatelessWidget {
  const _ViewerSpinner();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 30,
        height: 30,
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
      ),
    );
  }
}

class _ViewerFailure extends StatelessWidget {
  const _ViewerFailure({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.broken_image_outlined,
              color: Colors.white70,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Tentar de novo'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
