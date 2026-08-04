import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/chat_attachment.dart';
import 'package:jurii/models/chat_message.dart';
import 'package:jurii/theme/app_colors.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/chat_media_bubble.dart';
import 'package:jurii/widgets/jurii_motion.dart';

ChatAttachment _attachment({
  ChatAttachmentKind kind = ChatAttachmentKind.image,
}) {
  return ChatAttachment(
    id: 'attachment_01',
    messageId: 'message_01',
    conversationId: 'conversation_01',
    fileName: kind == ChatAttachmentKind.video ? 'obra.mp4' : 'foto.jpg',
    mimeType: kind == ChatAttachmentKind.video ? 'video/mp4' : 'image/jpeg',
    fileSizeBytes: 120000,
    storagePath: 'user/conversation/arquivo',
    kind: kind,
  );
}

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Center(child: SizedBox(width: 300, child: child)),
      ),
    );
  }

  testWidgets('com URL assinada a foto vira imagem, não cartão de arquivo', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ChatMediaBubble(
          attachment: _attachment(),
          signedUrl: 'https://cdn.example/foto.jpg',
          isLoadingUrl: false,
          isMine: true,
          time: '10:04',
          status: MessageDeliveryStatus.read,
          onOpen: () {},
          onRetry: () {},
          onAutoRetry: () {},
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    // O nome do arquivo era o conteúdo do balão antigo; agora não aparece.
    expect(find.text('foto.jpg'), findsNothing);
  });

  testWidgets('sem URL e ainda carregando mostra esqueleto, não erro', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ChatMediaBubble(
          attachment: _attachment(),
          signedUrl: null,
          isLoadingUrl: true,
          isMine: false,
          time: '10:04',
          status: MessageDeliveryStatus.sent,
          onOpen: () {},
          onRetry: () {},
          onAutoRetry: () {},
        ),
      ),
    );

    expect(find.byType(JuriiSkeletonCard), findsOneWidget);
    expect(find.text('Tentar de novo'), findsNothing);
  });

  testWidgets('sem URL e sem lote em voo oferece nova tentativa', (
    tester,
  ) async {
    var retries = 0;

    await tester.pumpWidget(
      wrap(
        ChatMediaBubble(
          attachment: _attachment(),
          signedUrl: null,
          isLoadingUrl: false,
          isMine: false,
          time: '10:04',
          status: MessageDeliveryStatus.sent,
          onOpen: () {},
          onRetry: () => retries++,
          onAutoRetry: () {},
        ),
      ),
    );

    expect(find.text('Não foi possível carregar a foto.'), findsOneWidget);

    await tester.tap(find.text('Tentar de novo'));
    await tester.pump();

    expect(retries, 1);
  });

  testWidgets('a URL assinada é a que vai para o download', (tester) async {
    await tester.pumpWidget(
      wrap(
        ChatMediaBubble(
          attachment: _attachment(),
          signedUrl: 'https://cdn.example/foto.jpg?token=abc',
          isLoadingUrl: false,
          isMine: true,
          time: '10:04',
          status: MessageDeliveryStatus.read,
          onOpen: () {},
          onRetry: () {},
          onAutoRetry: () {},
        ),
      ),
    );

    // Sem isto, trocar a URL pelo storagePath (que não é endereço nenhum)
    // passaria despercebido: o balão continuaria "funcionando" no teste.
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image;
    expect(provider, isA<ResizeImage>());
    final resize = provider as ResizeImage;
    expect(
      (resize.imageProvider as NetworkImage).url,
      'https://cdn.example/foto.jpg?token=abc',
    );
    // A decodificação é reduzida à altura da prévia; sem isso uma conversa com
    // dez fotos de 12 MP decodifica em resolução plena e o app morre de RAM.
    expect(resize.height, isNotNull);
    expect(
      resize.width,
      isNull,
      reason: 'o corte é por altura, não por largura',
    );
  });

  testWidgets('cada URL nova que falha é reportada — quem limita é a tela', (
    tester,
  ) async {
    // Em teste toda requisição de rede falha, então Image.network cai no
    // errorBuilder — que é exatamente o caminho de URL vencida em produção.
    var retries = 0;

    Widget bubble(String url) => wrap(
      ChatMediaBubble(
        attachment: _attachment(),
        signedUrl: url,
        isLoadingUrl: false,
        isMine: false,
        time: '10:04',
        status: MessageDeliveryStatus.sent,
        onOpen: () {},
        onRetry: () {},
        onAutoRetry: () => retries++,
      ),
    );

    await tester.pumpWidget(bubble('https://cdn.example/foto.jpg?token=A'));
    await tester.pumpAndSettle();
    expect(retries, 1, reason: 'a primeira falha deve avisar a tela');

    // Mesma URL: o widget não repete o aviso dentro do mesmo estado.
    await tester.pumpWidget(bubble('https://cdn.example/foto.jpg?token=A'));
    await tester.pumpAndSettle();
    expect(retries, 1);

    // URL nova: o widget avisa de novo. Este é o ponto — o balão NÃO tem como
    // saber que já tentou, porque cada tentativa traz token novo. O teto de
    // uma tentativa por anexo mora em AttachmentUrlCache.forgetForAutoRetry,
    // e é lá que ele está testado.
    await tester.pumpWidget(bubble('https://cdn.example/foto.jpg?token=B'));
    await tester.pumpAndSettle();
    expect(retries, 2);
  });

  testWidgets('a hora fica sobre a mídia, e some quando há legenda', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ChatMediaBubble(
          attachment: _attachment(),
          signedUrl: 'https://cdn.example/foto.jpg',
          isLoadingUrl: false,
          isMine: true,
          time: '10:04',
          status: MessageDeliveryStatus.read,
          onOpen: () {},
          onRetry: () {},
          onAutoRetry: () {},
        ),
      ),
    );
    expect(find.text('10:04'), findsOneWidget);
    expect(find.byIcon(Icons.done_all), findsOneWidget);

    await tester.pumpWidget(
      wrap(
        ChatMediaBubble(
          attachment: _attachment(),
          signedUrl: 'https://cdn.example/foto.jpg',
          isLoadingUrl: false,
          isMine: true,
          time: '10:04',
          status: MessageDeliveryStatus.read,
          showTimestamp: false,
          onOpen: () {},
          onRetry: () {},
          onAutoRetry: () {},
        ),
      ),
    );
    expect(find.text('10:04'), findsNothing);
  });

  testWidgets(
    'o tique sobre a mídia usa o azul de fundo escuro nos dois temas',
    (tester) async {
      for (final tema in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: tema,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  child: ChatMediaBubble(
                    attachment: _attachment(),
                    signedUrl: 'https://cdn.example/foto.jpg',
                    isLoadingUrl: false,
                    isMine: true,
                    time: '10:04',
                    status: MessageDeliveryStatus.read,
                    onOpen: () {},
                    onRetry: () {},
                    onAutoRetry: () {},
                  ),
                ),
              ),
            ),
          ),
        );

        // O véu sobre a foto é escuro nos DOIS temas. Se este tique seguisse o
        // token do tema, no modo escuro ele viraria azul-marinho sobre preto.
        final tique = tester.widget<Icon>(find.byIcon(Icons.done_all));
        expect(tique.color, AppColors.readReceiptOnDark);
      }
    },
  );

  testWidgets('toque abre a mídia quando há URL, e nada quando não há', (
    tester,
  ) async {
    var opens = 0;

    await tester.pumpWidget(
      wrap(
        ChatMediaBubble(
          attachment: _attachment(),
          signedUrl: 'https://cdn.example/foto.jpg',
          isLoadingUrl: false,
          isMine: true,
          time: '10:04',
          status: MessageDeliveryStatus.read,
          onOpen: () => opens++,
          onRetry: () {},
          onAutoRetry: () {},
        ),
      ),
    );

    await tester.tap(find.byType(ChatMediaBubble));
    await tester.pump();
    expect(opens, 1);

    await tester.pumpWidget(
      wrap(
        ChatMediaBubble(
          attachment: _attachment(),
          signedUrl: null,
          isLoadingUrl: true,
          isMine: true,
          time: '10:04',
          status: MessageDeliveryStatus.read,
          onOpen: () => opens++,
          onRetry: () {},
          onAutoRetry: () {},
        ),
      ),
    );

    await tester.tap(find.byType(ChatMediaBubble));
    await tester.pump();
    expect(opens, 1, reason: 'sem URL não há o que abrir');
  });

  testWidgets('vídeo mostra play e o peso do arquivo, sem baixar nada', (
    tester,
  ) async {
    // O balão de vídeo NÃO pode carregar o arquivo: o ExoPlayer bufferiza ao
    // preparar, então uma capa "de verdade" baixaria o vídeo inteiro de cada
    // um que passasse pela tela. A prova aqui é indireta e suficiente: nenhum
    // Image nem player na árvore, e o peso à mostra para quem está no 4G
    // decidir antes de tocar.
    await tester.pumpWidget(
      wrap(
        ChatMediaBubble(
          attachment: _attachment(kind: ChatAttachmentKind.video),
          signedUrl: 'https://cdn.example/obra.mp4',
          isLoadingUrl: false,
          isMine: false,
          time: '10:04',
          status: MessageDeliveryStatus.sent,
          onOpen: () {},
          onRetry: () {},
          onAutoRetry: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text('117 KB'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
