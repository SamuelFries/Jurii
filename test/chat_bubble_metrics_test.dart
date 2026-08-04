import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/chat_attachment.dart';
import 'package:jurii/models/chat_message.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/chat_bubble_metrics.dart';
import 'package:jurii/widgets/chat_media_bubble.dart';

void main() {
  group('largura do balão', () {
    test('no celular quem manda é a porcentagem', () {
      // 400dp de tela: 78% dá 312, bem abaixo do teto — o balão continua
      // acompanhando a tela, que é o comportamento certo no aparelho.
      expect(chatBubbleWidthFor(400), 312);
      expect(chatCardWidthFor(400), 352);
    });

    test('em tela larga quem manda é o teto absoluto', () {
      // Sem teto, 78% de 2000px davam um balão de 1560px — e a mídia, que
      // ocupa tudo que lhe derem, virava uma faixa com a foto numa tira.
      expect(chatBubbleWidthFor(2000), kChatBubbleMaxWidth);
      expect(chatCardWidthFor(2000), kChatCardMaxWidth);
    });

    test('a virada acontece onde os dois se cruzam', () {
      expect(chatBubbleWidthFor(kChatBubbleMaxWidth / 0.78), kChatBubbleMaxWidth);
      expect(
        chatBubbleWidthFor(kChatBubbleMaxWidth / 0.78 - 1),
        lessThan(kChatBubbleMaxWidth),
      );
    });
  });

  testWidgets('a prévia de mídia é quadrada e não estica em tela larga', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: ChatMediaBubble(
              attachment: const ChatAttachment(
                id: 'a1',
                messageId: 'm1',
                conversationId: 'c1',
                fileName: 'bandeira.jpg',
                mimeType: 'image/jpeg',
                fileSizeBytes: 120000,
                storagePath: 'u/c/bandeira.jpg',
                kind: ChatAttachmentKind.image,
              ),
              signedUrl: 'https://cdn.example/bandeira.jpg',
              isLoadingUrl: false,
              isMine: true,
              time: '14:57',
              status: MessageDeliveryStatus.read,
              onOpen: () {},
              onRetry: () {},
              onAutoRetry: () {},
            ),
          ),
        ),
      ),
    );

    final caixa = tester.getSize(find.byType(ChatMediaBubble));
    expect(caixa.width, kChatMediaSide);
    expect(caixa.height, kChatMediaSide);
    // Quadrada: foto retrato (formato de documento, o caso mais comum aqui)
    // perde ~25% da altura em vez de mais da metade.
    expect(caixa.width, caixa.height);
  });
}
