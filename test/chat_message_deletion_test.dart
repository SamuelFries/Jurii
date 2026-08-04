import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/chat_message.dart';
import 'package:jurii/utils/chat_message_deletion.dart';

ChatMessage _message({
  MessageAuthor author = MessageAuthor.me,
  DateTime? createdAt,
  bool deletedForAll = false,
  Map<String, dynamic> metadata = const {},
}) {
  return ChatMessage(
    id: 'm1',
    conversationKey: 'c1',
    author: author,
    text: 'oi',
    time: '10:04',
    createdAt: createdAt,
    deletedForAll: deletedForAll,
    metadata: metadata,
  );
}

void main() {
  final agora = DateTime(2026, 8, 8, 12);

  group('o que pode entrar na seleção', () {
    test('mensagem comum pode', () {
      expect(canSelectMessage(_message()), isTrue);
    });

    test('cartão de solicitação de caso NÃO pode', () {
      // Ele tem botões de aceitar e recusar: misturar "tocar para marcar" com
      // "tocar para aceitar o caso" é como alguém recusa um caso sem querer.
      final card = _message(
        metadata: const {
          'type': 'case_request',
          'case_request_id': 'r1',
          'request_status': 'pending',
        },
      );
      expect(canSelectMessage(card), isFalse);
    });
  });

  group('apagar para todos', () {
    test('mensagem própria e recente pode', () {
      expect(
        canDeleteForEveryone(
          _message(createdAt: agora.subtract(const Duration(minutes: 5))),
          now: agora,
        ),
        isTrue,
      );
    });

    test('mensagem do OUTRO nunca pode', () {
      expect(
        canDeleteForEveryone(
          _message(
            author: MessageAuthor.other,
            createdAt: agora.subtract(const Duration(minutes: 5)),
          ),
          now: agora,
        ),
        isFalse,
      );
    });

    test('exatamente na janela ainda pode; um segundo depois não', () {
      expect(
        canDeleteForEveryone(
          _message(createdAt: agora.subtract(kDeleteForEveryoneWindow)),
          now: agora,
        ),
        isTrue,
      );
      expect(
        canDeleteForEveryone(
          _message(
            createdAt: agora.subtract(
              kDeleteForEveryoneWindow + const Duration(seconds: 1),
            ),
          ),
          now: agora,
        ),
        isFalse,
      );
    });

    test('já apagada não se apaga de novo', () {
      expect(
        canDeleteForEveryone(
          _message(createdAt: agora, deletedForAll: true),
          now: agora,
        ),
        isFalse,
      );
    });

    test('sem instante conhecido não oferece o botão', () {
      // Mensagem otimista, que ainda não voltou do servidor: sem createdAt não
      // dá para afirmar que está na janela, e oferecer um botão que o servidor
      // vai recusar é pior que não oferecer.
      expect(canDeleteForEveryone(_message(), now: agora), isFalse);
    });
  });

  group('seleção inteira', () {
    test('basta UMA fora da janela para a opção sumir', () {
      final selecao = [
        _message(createdAt: agora.subtract(const Duration(minutes: 1))),
        _message(createdAt: agora.subtract(const Duration(days: 10))),
      ];
      expect(canDeleteSelectionForEveryone(selecao, now: agora), isFalse);
    });

    test('todas próprias e recentes liberam', () {
      final selecao = [
        _message(createdAt: agora.subtract(const Duration(minutes: 1))),
        _message(createdAt: agora.subtract(const Duration(hours: 2))),
      ];
      expect(canDeleteSelectionForEveryone(selecao, now: agora), isTrue);
    });

    test('seleção vazia não libera nada', () {
      expect(canDeleteSelectionForEveryone(const [], now: agora), isFalse);
    });
  });

  test('a janela do app é a mesma do servidor', () {
    // O app usa a janela só para decidir se MOSTRA o botão; quem recusa de
    // verdade é o RPC. Divergir nos dois sentidos é ruim: um botão que falha,
    // ou uma opção legítima escondida.
    final migrations =
        Directory('supabase/migrations')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final ultima = migrations.lastWhere(
      (file) =>
          file.readAsStringSync().contains('delete_messages_for_everyone'),
      orElse: () => throw StateError('nenhuma migration define a janela'),
    );

    expect(
      ultima.readAsStringSync(),
      contains("interval '${kDeleteForEveryoneWindow.inHours} hours'"),
      reason: 'a janela do app não bate com a do servidor',
    );
  });
}
