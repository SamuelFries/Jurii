import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/services/attachment_url_cache.dart';

/// Assinador falso: registra cada lote pedido e devolve URL derivada do
/// caminho, para o teste conseguir afirmar QUANTAS idas ao servidor houve —
/// que é a razão de o cache existir.
class _FakeSigner {
  final List<List<String>> batches = [];
  final List<Completer<Map<String, String>>> pending = [];

  /// Quando `manual` é true, cada chamada fica pendurada até o teste resolver.
  bool manual = false;
  bool shouldFail = false;

  Future<Map<String, String>> call(List<String> paths, Duration ttl) {
    batches.add(List<String>.from(paths));
    if (shouldFail) return Future.error(StateError('sem rede'));
    if (manual) {
      final completer = Completer<Map<String, String>>();
      pending.add(completer);
      return completer.future;
    }
    return Future.value({for (final path in paths) path: 'https://cdn/$path'});
  }

  void resolveLast() {
    final completer = pending.removeLast();
    final paths = batches.last;
    completer.complete({for (final path in paths) path: 'https://cdn/$path'});
  }
}

void main() {
  late _FakeSigner signer;
  late DateTime now;

  setUp(() {
    signer = _FakeSigner();
    now = DateTime.utc(2026, 8, 6, 12);
  });

  AttachmentUrlCache buildCache() {
    return AttachmentUrlCache(
      signer: signer.call,
      clock: () => now,
      ttl: const Duration(hours: 1),
      refreshMargin: const Duration(minutes: 5),
    );
  }

  test('assina tudo num lote só e guarda o resultado', () async {
    final cache = buildCache();

    await cache.ensureUrls(['a/1.jpg', 'a/2.jpg', 'a/3.mp4']);

    expect(signer.batches, hasLength(1));
    expect(signer.batches.single, hasLength(3));
    expect(cache.cachedUrlFor('a/2.jpg'), 'https://cdn/a/2.jpg');
  });

  test(
    'caminho já assinado e longe do vencimento não gera nova chamada',
    () async {
      final cache = buildCache();
      await cache.ensureUrls(['a/1.jpg']);

      now = now.add(const Duration(minutes: 30));
      await cache.ensureUrls(['a/1.jpg']);

      expect(signer.batches, hasLength(1));
    },
  );

  test('reassina quando entra na margem de vencimento', () async {
    final cache = buildCache();
    await cache.ensureUrls(['a/1.jpg']);

    // Falta menos que a margem (5 min) para vencer: a URL ainda serve, mas um
    // download que comece agora pode não terminar antes de ela morrer.
    now = now.add(const Duration(minutes: 56));
    await cache.ensureUrls(['a/1.jpg']);

    expect(signer.batches, hasLength(2));
  });

  test('URL vencida some do cache mesmo sem nova assinatura', () async {
    final cache = buildCache();
    await cache.ensureUrls(['a/1.jpg']);

    now = now.add(const Duration(hours: 2));

    expect(cache.cachedUrlFor('a/1.jpg'), isNull);
  });

  test(
    'falha do assinador NÃO vira cache: a próxima tentativa vai de novo',
    () async {
      final cache = buildCache();
      signer.shouldFail = true;

      await cache.ensureUrls(['a/1.jpg']);
      expect(cache.cachedUrlFor('a/1.jpg'), isNull);
      expect(cache.isPending('a/1.jpg'), isFalse);

      signer.shouldFail = false;
      await cache.ensureUrls(['a/1.jpg']);

      expect(signer.batches, hasLength(2));
      expect(cache.cachedUrlFor('a/1.jpg'), 'https://cdn/a/1.jpg');
    },
  );

  test('chamadas concorrentes para o mesmo caminho geram UM lote', () async {
    final cache = buildCache();
    signer.manual = true;

    final first = cache.ensureUrls(['a/1.jpg']);
    final second = cache.ensureUrls(['a/1.jpg']);

    expect(signer.batches, hasLength(1));
    expect(cache.isPending('a/1.jpg'), isTrue);

    signer.resolveLast();
    await Future.wait([first, second]);

    expect(cache.isPending('a/1.jpg'), isFalse);
    expect(cache.cachedUrlFor('a/1.jpg'), 'https://cdn/a/1.jpg');
  });

  test(
    'forget força nova assinatura (a URL guardada acabou de falhar)',
    () async {
      final cache = buildCache();
      await cache.ensureUrls(['a/1.jpg']);

      cache.forget('a/1.jpg');
      expect(cache.cachedUrlFor('a/1.jpg'), isNull);

      await cache.ensureUrls(['a/1.jpg']);
      expect(signer.batches, hasLength(2));
    },
  );

  test('lote em voo não ressuscita o que o forget apagou', () async {
    final cache = buildCache();
    signer.manual = true;

    final inFlight = cache.ensureUrls(['a/1.jpg']);
    cache.forget('a/1.jpg');
    signer.resolveLast();
    await inFlight;

    // Sem a checagem de identidade do lote, a URL velha voltaria ao cache e a
    // nova tentativa reusaria exatamente a que tinha falhado.
    expect(cache.cachedUrlFor('a/1.jpg'), isNull);
  });

  test('caminho vazio não vira chamada', () async {
    final cache = buildCache();
    await cache.ensureUrls(['', '   ']);
    expect(signer.batches, isEmpty);
  });

  group('teto da nova tentativa automática', () {
    test('o primeiro descarte automático passa, o segundo não', () async {
      final cache = buildCache();
      await cache.ensureUrls(['a/1.jpg']);

      expect(cache.forgetForAutoRetry('a/1.jpg'), isTrue);
      expect(cache.cachedUrlFor('a/1.jpg'), isNull);

      await cache.ensureUrls(['a/1.jpg']);
      expect(signer.batches, hasLength(2));

      // Segunda falha da MESMA foto: o descarte é recusado, e sem descarte não
      // há nova assinatura. Sem este teto a recuperação vira laço — cada
      // tentativa gera URL nova, que reconstrói o balão, que baixa e falha.
      expect(cache.forgetForAutoRetry('a/1.jpg'), isFalse);
      expect(
        cache.cachedUrlFor('a/1.jpg'),
        'https://cdn/a/1.jpg',
        reason: 'a recusa não pode apagar a URL boa',
      );

      await cache.ensureUrls(['a/1.jpg']);
      expect(signer.batches, hasLength(2), reason: 'nenhuma assinatura nova');
    });

    test(
      'o teto é por caminho: uma foto quebrada não trava as outras',
      () async {
        final cache = buildCache();
        await cache.ensureUrls(['a/1.jpg', 'a/2.jpg']);

        expect(cache.forgetForAutoRetry('a/1.jpg'), isTrue);
        expect(cache.forgetForAutoRetry('a/1.jpg'), isFalse);
        expect(cache.forgetForAutoRetry('a/2.jpg'), isTrue);
      },
    );

    test('o toque manual (forget) não tem teto', () async {
      final cache = buildCache();
      await cache.ensureUrls(['a/1.jpg']);

      cache.forgetForAutoRetry('a/1.jpg');
      await cache.ensureUrls(['a/1.jpg']);

      // A pessoa tocando em "Tentar de novo" decide quantas vezes quiser.
      cache.forget('a/1.jpg');
      await cache.ensureUrls(['a/1.jpg']);
      cache.forget('a/1.jpg');
      await cache.ensureUrls(['a/1.jpg']);

      expect(signer.batches, hasLength(4));
    });
  });

  test('assinatura pendurada não prende o caminho para sempre', () async {
    // Socket num buraco negro (troca de Wi-Fi para 4G, app suspenso no meio da
    // chamada): sem o teto de espera, os caminhos daquele lote ficam "em voo"
    // eternamente e a foto vira esqueleto cinza que nada desfaz.
    late AttachmentUrlCache cache;
    fakeAsync((async) {
      cache = AttachmentUrlCache(
        signer: (paths, ttl) => Completer<Map<String, String>>().future,
        clock: () => now,
        requestTimeout: const Duration(seconds: 5),
      );

      unawaited(cache.ensureUrls(['a/1.jpg']));
      async.flushMicrotasks();
      expect(cache.isPending('a/1.jpg'), isTrue);

      async.elapse(const Duration(seconds: 6));
      async.flushMicrotasks();
    });

    expect(cache.isPending('a/1.jpg'), isFalse);
  });

  test('clear esvazia o cache', () async {
    final cache = buildCache();
    await cache.ensureUrls(['a/1.jpg']);
    cache.clear();
    expect(cache.cachedUrlFor('a/1.jpg'), isNull);
  });
}
