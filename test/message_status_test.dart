import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/chat_message.dart';
import 'package:jurii/models/conversation.dart';
import 'package:jurii/screens/chat_screen.dart';
import 'package:jurii/theme/app_colors.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/conversation_card.dart';
import 'package:jurii/widgets/message_status_check.dart';

void main() {
  group('estado da mensagem a partir dos carimbos', () {
    test('sem carimbo nenhum a mensagem está apenas enviada', () {
      expect(
        MessageDeliveryStatus.resolve(delivered: false, read: false),
        MessageDeliveryStatus.sent,
      );
    });

    test('entregue sem leitura para no segundo tique', () {
      expect(
        MessageDeliveryStatus.resolve(delivered: true, read: false),
        MessageDeliveryStatus.delivered,
      );
    });

    test('lida é lida', () {
      expect(
        MessageDeliveryStatus.resolve(delivered: true, read: true),
        MessageDeliveryStatus.read,
      );
    });

    test('lida sem entrega registrada ainda conta como lida', () {
      // O banco garante que ler implica entregar, mas uma linha antiga (ou uma
      // corrida entre as duas RPCs) não pode fazer o tique regredir.
      expect(
        MessageDeliveryStatus.resolve(delivered: false, read: true),
        MessageDeliveryStatus.read,
      );
    });
  });

  group('tique de confirmação', () {
    Widget wrap(MessageDeliveryStatus status) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: MessageStatusCheck(
          status: status,
          pendingColor: Colors.grey,
          readColor: Colors.blue,
        ),
      ),
    );

    testWidgets('enviada mostra UM risco', (tester) async {
      await tester.pumpWidget(wrap(MessageDeliveryStatus.sent));
      expect(find.byIcon(Icons.done), findsOneWidget);
      expect(find.byIcon(Icons.done_all), findsNothing);
    });

    testWidgets('entregue mostra dois riscos, mas na cor de espera', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(MessageDeliveryStatus.delivered));
      expect(find.byIcon(Icons.done_all), findsOneWidget);
      expect(tester.widget<Icon>(find.byType(Icon)).color, Colors.grey);
    });

    testWidgets('visualizada mostra dois riscos na cor de leitura', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(MessageDeliveryStatus.read));
      expect(find.byIcon(Icons.done_all), findsOneWidget);
      // A diferença entre entregue e visualizada é SÓ a cor: sem esta
      // asserção, trocar a cor por engano deixaria os dois estados idênticos.
      expect(tester.widget<Icon>(find.byType(Icon)).color, Colors.blue);
    });

    testWidgets('cada estado se anuncia para o leitor de tela', (tester) async {
      final semantics = tester.ensureSemantics();

      for (final (status, rotulo) in [
        (MessageDeliveryStatus.sent, 'Enviada'),
        (MessageDeliveryStatus.delivered, 'Entregue'),
        (MessageDeliveryStatus.read, 'Visualizada'),
      ]) {
        await tester.pumpWidget(wrap(status));
        expect(
          find.bySemanticsLabel(rotulo),
          findsOneWidget,
          reason:
              'quem não enxerga a diferença entre um risco e dois perde '
              'a informação inteira do tique',
        );
      }

      semantics.dispose();
    });
  });

  group('contraste do tique de visualizado', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final lighter = la > lb ? la : lb;
      final darker = la > lb ? lb : la;
      return (lighter + 0.05) / (darker + 0.05);
    }

    test('legível no balão do tema claro (fundo navy)', () {
      expect(
        contrast(AppColors.light.readReceipt, AppColors.light.primary),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('legível no balão do tema escuro (fundo azul claro)', () {
      // No escuro o balão de quem enviou INVERTE: fica claro, com texto
      // escuro. Um azul só para os dois temas deixaria o tique sumir aqui.
      expect(
        contrast(AppColors.dark.readReceipt, AppColors.dark.primary),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('contador de não lidas na lista', () {
    testWidgets('badge aparece com a contagem e some no zero', (tester) async {
      Widget card(int unread) => MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ConversationCard(
            conversation: Conversation(
              id: 'c1',
              initials: 'AJ',
              officeName: 'Advogada Jurii',
              specialty: 'Trabalhista',
              lastMessage: 'oi',
              time: '10:04',
              unreadCount: unread,
            ),
            onTap: () {},
          ),
        ),
      );

      await tester.pumpWidget(card(3));
      expect(find.text('3'), findsOneWidget);

      await tester.pumpWidget(card(0));
      expect(find.text('0'), findsNothing);
    });
  });

  group('evento de tempo real que não muda nada', () {
    ChatMessage msg({
      required MessageAuthor author,
      MessageDeliveryStatus status = MessageDeliveryStatus.sent,
      String text = 'oi',
    }) => ChatMessage(
      id: 'm1',
      conversationKey: 'c1',
      author: author,
      text: text,
      time: '10:04',
      status: status,
    );

    test('mudar o status de mensagem do OUTRO não pede redesenho', () {
      // Abrir uma conversa com 50 por ler devolve 50 eventos de UPDATE para a
      // tela de quem acabou de ler. Como o tique só existe na própria
      // mensagem, nenhum desses eventos muda um pixel.
      final antes = msg(author: MessageAuthor.other);
      final depois = msg(
        author: MessageAuthor.other,
        status: MessageDeliveryStatus.read,
      );

      expect(antes.rendersSameAs(depois), isTrue);
    });

    test('mudar o status da PRÓPRIA mensagem pede redesenho', () {
      final antes = msg(author: MessageAuthor.me);
      final depois = msg(
        author: MessageAuthor.me,
        status: MessageDeliveryStatus.read,
      );

      expect(antes.rendersSameAs(depois), isFalse);
    });

    test('texto diferente sempre pede redesenho', () {
      expect(
        msg(
          author: MessageAuthor.other,
        ).rendersSameAs(msg(author: MessageAuthor.other, text: 'outro')),
        isFalse,
      );
    });
  });

  group('lápide de mensagem apagada', () {
    Widget chat(MessageAuthor author) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: ChatDeletedMessagePreview(
          isMine: author == MessageAuthor.me,
          time: '10:04',
        ),
      ),
    );

    testWidgets('quem apagou lê na primeira pessoa', (tester) async {
      await tester.pumpWidget(chat(MessageAuthor.me));
      expect(find.text('Você apagou esta mensagem'), findsOneWidget);
    });

    testWidgets('do outro lado a frase é impessoal', (tester) async {
      await tester.pumpWidget(chat(MessageAuthor.other));
      expect(find.text('Esta mensagem foi apagada'), findsOneWidget);
      // A hora fica: o balão continua sendo um ponto na linha do tempo.
      expect(find.text('10:04'), findsOneWidget);
    });
  });
}
