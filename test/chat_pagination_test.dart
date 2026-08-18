import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/conversation.dart';
import 'package:jurii/screens/chat_screen.dart';
import 'package:jurii/theme/app_theme.dart';

/// A lista do chat virou `reverse: true` por causa da paginação: numa lista
/// invertida, prepender página antiga só cresce o teto e os itens visíveis
/// não se movem. O preço de inverter é ter que REMAPEAR os índices, e é
/// exatamente o que este arquivo trava: se alguém remover o remapeamento, a
/// conversa renderiza de cabeça para baixo e nenhum outro teste percebe.
const _conversation = Conversation(
  initials: 'FA',
  officeName: 'Fries Advogados',
  specialty: 'Trabalhista',
  lastMessage: 'oi',
  time: 'Agora',
  unreadCount: 0,
  type: 'client_firm',
);

Widget _app() => MaterialApp(
  theme: AppTheme.lightTheme,
  home: const ChatScreen(conversation: _conversation, isLawyer: false),
);

void main() {
  testWidgets('a conversa continua em ordem cronológica, de cima para baixo', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final primeira = find.textContaining('Recebemos sua solicitação');
    final ultima = find.textContaining('Contrato, últimos contracheques');
    expect(primeira, findsOneWidget);
    expect(ultima, findsOneWidget);

    // Na lista INVERTIDA com o remapeamento certo, a mensagem mais antiga
    // continua ACIMA da mais nova, como toda conversa se lê.
    expect(
      tester.getTopLeft(primeira).dy,
      lessThan(tester.getTopLeft(ultima).dy),
    );
  });

  testWidgets('mensagem enviada entra no rodapé, abaixo das anteriores', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'Mensagem nova');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    final anterior = find.textContaining('Contrato, últimos contracheques');
    final nova = find.text('Mensagem nova');
    expect(nova, findsOneWidget);
    expect(
      tester.getTopLeft(anterior).dy,
      lessThan(tester.getTopLeft(nova).dy),
    );
  });
}
