import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/repositories/messaging_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const pedidos = ['u/c/a.jpg', 'u/c/b.jpg', 'u/c/d.mp4'];

  test('caso normal: cada caminho recebe a sua URL', () {
    final urls = signedUrlsByRequestedPath(pedidos, [
      const SignedUrlSuccess(path: 'u/c/a.jpg', signedUrl: 'https://cdn/a'),
      const SignedUrlSuccess(path: 'u/c/b.jpg', signedUrl: 'https://cdn/b'),
      const SignedUrlSuccess(path: 'u/c/d.mp4', signedUrl: 'https://cdn/d'),
    ]);

    expect(urls, {
      'u/c/a.jpg': 'https://cdn/a',
      'u/c/b.jpg': 'https://cdn/b',
      'u/c/d.mp4': 'https://cdn/d',
    });
  });

  test('resposta fora de ordem não troca a foto de uma mensagem por outra', () {
    // Casar só por posição faria b receber a URL de a. Numa conversa isso é
    // a foto de uma mensagem aparecendo dentro de outra — vazamento visual
    // entre mensagens, não um "carregou errado" qualquer.
    final urls = signedUrlsByRequestedPath(pedidos, [
      const SignedUrlSuccess(path: 'u/c/b.jpg', signedUrl: 'https://cdn/b'),
      const SignedUrlSuccess(path: 'u/c/d.mp4', signedUrl: 'https://cdn/d'),
      const SignedUrlSuccess(path: 'u/c/a.jpg', signedUrl: 'https://cdn/a'),
    ]);

    expect(urls['u/c/a.jpg'], 'https://cdn/a');
    expect(urls['u/c/b.jpg'], 'https://cdn/b');
    expect(urls['u/c/d.mp4'], 'https://cdn/d');
  });

  test('caminho que o servidor não assinou some do mapa, e só ele', () {
    final urls = signedUrlsByRequestedPath(pedidos, [
      const SignedUrlSuccess(path: 'u/c/a.jpg', signedUrl: 'https://cdn/a'),
      const SignedUrlFailure(path: 'u/c/b.jpg', error: 'not found'),
      const SignedUrlSuccess(path: 'u/c/d.mp4', signedUrl: 'https://cdn/d'),
    ]);

    expect(urls.containsKey('u/c/b.jpg'), isFalse);
    expect(urls, hasLength(2));
  });

  test('resposta mais curta (sem eco de posição) ainda casa pelo caminho', () {
    // Se um dia o SDK devolver só o que conseguiu assinar, a posição deixa de
    // significar nada — e usá-la mapearia URL para o caminho errado.
    final urls = signedUrlsByRequestedPath(pedidos, [
      const SignedUrlSuccess(path: 'u/c/d.mp4', signedUrl: 'https://cdn/d'),
    ]);

    expect(urls, {'u/c/d.mp4': 'https://cdn/d'});
  });

  test('caminho que ninguém pediu não entra no mapa', () {
    // Chave que o balão nunca procura é lixo; pior, mascararia um bug de
    // normalização fazendo o mapa parecer completo.
    final urls = signedUrlsByRequestedPath(pedidos, [
      const SignedUrlSuccess(path: 'outro/x.jpg', signedUrl: 'https://cdn/x'),
    ]);

    expect(urls, isEmpty);
  });

  test('lista vazia não explode', () {
    expect(signedUrlsByRequestedPath(const [], const []), isEmpty);
  });
}
