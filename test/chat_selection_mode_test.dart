import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/conversation.dart';
import 'package:jurii/screens/chat_screen.dart';
import 'package:jurii/theme/app_theme.dart';

/// Conversa de demonstração: 'Fries Advogados' é a chave que casa com as
/// mensagens de mock_chat_messages, então a tela abre com histórico sem
/// precisar de Supabase.
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
  testWidgets('toque longo abre o modo de seleção com a contagem', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // Barra normal da conversa antes de qualquer seleção.
    expect(find.text('1 selecionada'), findsNothing);

    await tester.longPress(find.text('Perfeito. Quais documentos preciso enviar primeiro?'));
    await tester.pumpAndSettle();

    expect(find.text('1 selecionada'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('com a seleção aberta, o toque simples marca e desmarca', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final primeira = find.text(
      'Perfeito. Quais documentos preciso enviar primeiro?',
    );
    final segunda = find.textContaining('Recebemos sua solicitação');

    await tester.longPress(primeira);
    await tester.pumpAndSettle();
    expect(find.text('1 selecionada'), findsOneWidget);

    // Fora do modo de seleção este toque não faria nada; dentro dele, marca.
    await tester.tap(segunda);
    await tester.pumpAndSettle();
    expect(find.text('2 selecionadas'), findsOneWidget);

    // E desmarca de novo, até esvaziar — aí o modo se fecha sozinho.
    await tester.tap(segunda);
    await tester.pumpAndSettle();
    expect(find.text('1 selecionada'), findsOneWidget);

    await tester.tap(primeira);
    await tester.pumpAndSettle();
    expect(find.text('1 selecionada'), findsNothing);
    expect(find.text('2 selecionadas'), findsNothing);
  });

  testWidgets('o X cancela a seleção sem apagar nada', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final alvo = find.text('Perfeito. Quais documentos preciso enviar primeiro?');

    await tester.longPress(alvo);
    await tester.pumpAndSettle();
    expect(find.text('1 selecionada'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('1 selecionada'), findsNothing);
    expect(alvo, findsOneWidget, reason: 'cancelar não pode apagar a mensagem');
  });

  testWidgets('o botão de apagar abre a folha com as duas opções', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // Mensagem própria de demonstração: sem createdAt, "para todos" não é
    // oferecida — é exatamente a regra de não mostrar botão que falharia.
    await tester.longPress(
      find.text('Perfeito. Quais documentos preciso enviar primeiro?'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Apagar mensagem?'), findsOneWidget);
    expect(find.text('Apagar para mim'), findsOneWidget);
    expect(find.text('Apagar para todos'), findsNothing);
    expect(
      find.text('Some só da sua conversa. A outra pessoa continua vendo.'),
      findsOneWidget,
    );
  });

  testWidgets('"apagar para mim" tira a mensagem da conversa', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final alvo = find.text('Perfeito. Quais documentos preciso enviar primeiro?');

    await tester.longPress(alvo);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar para mim'));
    await tester.pumpAndSettle();

    expect(alvo, findsNothing);
    expect(find.text('1 selecionada'), findsNothing);
  });

  testWidgets('a barra da conversa dá lugar à barra de seleção', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Fries Advogados'), findsWidgets);

    await tester.longPress(
      find.text('Perfeito. Quais documentos preciso enviar primeiro?'),
    );
    await tester.pumpAndSettle();

    // O nome do interlocutor sai da barra: com a seleção aberta, tocar nele
    // abriria o perfil no meio de uma ação destrutiva.
    expect(find.text('Fries Advogados'), findsNothing);
    expect(find.text('1 selecionada'), findsOneWidget);
  });

  testWidgets('voltar com a seleção aberta fecha a seleção, não a conversa', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.longPress(
      find.text('Perfeito. Quais documentos preciso enviar primeiro?'),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 selecionada'), findsOneWidget);

    // Gesto de voltar do sistema (Android).
    final widgetsBinding = tester.binding;
    await widgetsBinding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('1 selecionada'), findsNothing);
    expect(
      find.text('Perfeito. Quais documentos preciso enviar primeiro?'),
      findsOneWidget,
      reason: 'a conversa não pode ter sido fechada junto',
    );
  });

  testWidgets('durante a seleção o composer sai de cena', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);

    await tester.longPress(
      find.text('Perfeito. Quais documentos preciso enviar primeiro?'),
    );
    await tester.pumpAndSettle();

    // Escrever e apagar ao mesmo tempo não é fluxo nenhum, e o campo ainda
    // roubaria o espaço da lista bem na hora de marcar várias.
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });
}
