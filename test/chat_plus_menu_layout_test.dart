import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/conversation.dart';
import 'package:jurii/screens/chat_screen.dart';
import 'package:jurii/theme/app_theme.dart';

/// O menu "+" passou de 4 para 6 opções (vídeo ganhou entradas próprias), o
/// que o levou de 2 para 3 linhas. Em aparelho pequeno com o teclado aberto
/// isso estourava a coluna do corpo em 70px: o composer — campo de texto e
/// botão de enviar — saía da tela, e a última linha do menu ficava fora de
/// alcance. Estes testes prendem as duas defesas: o teclado fecha ao abrir o
/// menu, e o menu se limita ao espaço real em vez de empurrar o resto.
const _conversation = Conversation(
  initials: 'ES',
  officeName: 'Escritorio Teste',
  specialty: 'Trabalhista',
  lastMessage: 'oi',
  time: 'Agora',
  unreadCount: 0,
  type: 'client_firm',
);

void main() {
  for (final (nome, tamanho, teclado) in [
    ('320x568 com teclado', Size(320, 568), 260.0),
    ('360x640 com teclado', Size(360, 640), 280.0),
    ('375x667 com teclado', Size(375, 667), 300.0),
  ]) {
    testWidgets('menu "+" cabe em $nome', (tester) async {
      tester.view.physicalSize = tamanho;
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = FakeViewPadding(bottom: teclado);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ChatScreen(conversation: _conversation, isLawyer: true),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Overflow em Flutter é exceção: se a coluna estourar, ela aparece aqui.
      expect(tester.takeException(), isNull);

      // E o composer continua na árvore e dentro da tela.
      final composer = find.byType(TextField);
      expect(composer, findsOneWidget);
      final caixa = tester.getRect(composer);
      expect(
        caixa.bottom,
        lessThanOrEqualTo(tamanho.height),
        reason: 'o campo de mensagem foi empurrado para fora da tela',
      );
    });
  }

  testWidgets('abrir o menu "+" tira o foco do campo de texto', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const ChatScreen(conversation: _conversation, isLawyer: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus ??
          FocusScope.of(tester.element(find.byType(TextField))).hasFocus,
      isTrue,
      reason: 'o campo deveria estar com foco depois do toque',
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // Sem isto o teclado e o menu disputam o mesmo espaço — foi o que gerava
    // o estouro de layout no aparelho pequeno.
    expect(
      FocusScope.of(tester.element(find.byType(TextField))).hasFocus,
      isFalse,
    );
  });
}
