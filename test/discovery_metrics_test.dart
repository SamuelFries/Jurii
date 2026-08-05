import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/discovery_page.dart';
import 'package:jurii/models/lawyer_profile_summary.dart';
import 'package:jurii/utils/discovery_pagination.dart';

LawyerProfileSummary _lawyer(String id, {bool featured = false}) {
  return LawyerProfileSummary(
    id: id,
    name: 'Advogada $id',
    initials: 'AJ',
    oabNumber: '000000',
    oabState: 'RS',
    primaryArea: 'Direito Cível',
    practiceAreas: const ['Direito Cível'],
    bio: 'bio',
    rating: 5,
    reviews: 1,
    avatarType: 'navy',
    isFeatured: featured,
  );
}

void main() {
  group('o que conta como impressão', () {
    test('a linha-sentinela da paginação NÃO vira alcance', () {
      // A descoberta pede limit+1 para saber se há próxima página. Essa linha
      // extra nunca é desenhada — contá-la inflaria o número que vira fatura
      // em um por página, silenciosamente.
      final vindos = [
        _lawyer('a'),
        _lawyer('b'),
        _lawyer('c'),
        _lawyer('sentinela'),
      ];

      final page = pageFromSentinel(vindos, 3);

      expect(page.hasMore, isTrue);
      expect(page.items.map((l) => l.id), ['a', 'b', 'c']);
      expect(
        page.items.any((l) => l.id == 'sentinela'),
        isFalse,
        reason: 'a sentinela não aparece na tela, logo não é impressão',
      );
    });

    test('sem próxima página, tudo que veio foi visto', () {
      final page = pageFromSentinel([_lawyer('a'), _lawyer('b')], 3);
      expect(page.hasMore, isFalse);
      expect(page.items, hasLength(2));
    });

    test('patrocinados saem da MESMA lista que foi para a tela', () {
      // Se a lista de patrocinados fosse tirada de `parsed` em vez de
      // `page.items`, um patrocinado na posição da sentinela contaria como
      // alcance pago sem nunca ter aparecido.
      final vindos = [
        _lawyer('a', featured: true),
        _lawyer('b'),
        _lawyer('pago_na_sentinela', featured: true),
      ];

      final page = pageFromSentinel(vindos, 2);
      final patrocinados = page.items
          .where((l) => l.isFeatured)
          .map((l) => l.id)
          .toList();

      expect(patrocinados, ['a']);
      expect(patrocinados, isNot(contains('pago_na_sentinela')));
    });
  });

  test('página vazia não gera evento nenhum', () {
    final page = pageFromSentinel(<LawyerProfileSummary>[], 6);
    expect(page.items, isEmpty);
    // O repositório sai cedo com lista vazia; a chamada nem chega ao servidor.
    expect(page.hasMore, isFalse);
  });

  test('DiscoveryPage.last não inventa próxima página', () {
    const page = DiscoveryPage<LawyerProfileSummary>.last([]);
    expect(page.hasMore, isFalse);
  });
}
