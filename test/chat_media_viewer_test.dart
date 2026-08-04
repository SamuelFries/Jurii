import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/chat_attachment.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/chat_media_viewer.dart';

ChatAttachment _attachment({
  ChatAttachmentKind kind = ChatAttachmentKind.image,
  String fileName = 'contrato.jpg',
}) {
  return ChatAttachment(
    id: 'attachment_01',
    messageId: 'message_01',
    conversationId: 'conversation_01',
    fileName: fileName,
    mimeType: kind == ChatAttachmentKind.video ? 'video/mp4' : 'image/jpeg',
    fileSizeBytes: 120000,
    storagePath: 'user/conversation/arquivo',
    kind: kind,
  );
}

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(theme: AppTheme.lightTheme, home: child);

  testWidgets('foto abre com zoom e com o nome do arquivo', (tester) async {
    await tester.pumpWidget(
      wrap(
        ChatMediaViewerPage(
          attachment: _attachment(),
          signedUrl: 'https://cdn.example/contrato.jpg',
        ),
      ),
    );

    expect(find.text('contrato.jpg'), findsOneWidget);
    // O zoom é o ponto da tela cheia num app onde a mídia mais comum é foto
    // de documento: sem ele, ler letra miúda de contrato fica impossível.
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('foto que não carrega explica, em vez de ficar em branco', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ChatMediaViewerPage(
          attachment: _attachment(),
          signedUrl: 'https://cdn.example/contrato.jpg',
        ),
      ),
    );
    // Em teste toda requisição de rede falha: é o caminho de erro real.
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível carregar esta foto.'), findsOneWidget);
  });

  testWidgets('vídeo sem player disponível mostra erro com nova tentativa', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ChatMediaViewerPage(
          attachment: _attachment(
            kind: ChatAttachmentKind.video,
            fileName: 'obra.mp4',
          ),
          signedUrl: 'https://cdn.example/obra.mp4',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Sem o plugin, initialize() estoura. O que não pode acontecer é a tela
    // ficar preta girando para sempre, sem explicação e sem saída.
    expect(
      find.text('Não foi possível reproduzir este vídeo.'),
      findsOneWidget,
    );
    expect(find.text('Tentar de novo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fechar volta para a conversa', (tester) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChatMediaViewerPage(
                    attachment: _attachment(),
                    signedUrl: 'https://cdn.example/contrato.jpg',
                  ),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('contrato.jpg'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('abrir'), findsOneWidget);
    expect(find.text('contrato.jpg'), findsNothing);
  });
}
