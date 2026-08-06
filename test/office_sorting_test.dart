import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/law_firm.dart';
import 'package:jurii/utils/office_sorting.dart';

LawFirm _firm(
  String id, {
  double rating = 0,
  int reviews = 0,
  double? lat,
  double? lng,
  bool isFeatured = false,
}) {
  return LawFirm(
    id: id,
    name: id,
    initials: id.substring(0, 1).toUpperCase(),
    rating: rating,
    distance: '',
    specialty: 'Direito Civil',
    practiceAreas: const ['Direito Civil'],
    reviews: reviews,
    avatarType: 'blue',
    isFeatured: isFeatured,
    latitude: lat,
    longitude: lng,
  );
}

void main() {
  // Ordem "do servidor": destacado primeiro, como o RPC devolve.
  final serverOrder = [
    _firm(
      'patrocinado',
      rating: 3.0,
      reviews: 2,
      lat: -30.10,
      lng: -51.20,
      isFeatured: true,
    ),
    _firm('cinco-estrelas', rating: 5.0, reviews: 40, lat: -30.20, lng: -51.20),
    _firm('perto', rating: 4.0, reviews: 10, lat: -30.051, lng: -51.221),
    _firm('sem-cep', rating: 4.8, reviews: 5),
    _firm('novo'), // rating 0, 0 reviews
  ];

  test('relevância preserva a ordem do servidor (onde vive o destaque)', () {
    final sorted = sortLawFirms(serverOrder, OfficeSort.relevance);
    expect(sorted.map((f) => f.id).toList(), [
      'patrocinado',
      'cinco-estrelas',
      'perto',
      'sem-cep',
      'novo',
    ]);
  });

  test('relevância devolve cópia (não muta a lista original)', () {
    final sorted = sortLawFirms(serverOrder, OfficeSort.relevance);
    expect(identical(sorted, serverOrder), isFalse);
  });

  test('avaliação: nota desc, patrocinado NÃO fura, "novo" vai pro fim', () {
    final sorted = sortLawFirms(serverOrder, OfficeSort.rating);
    expect(sorted.map((f) => f.id).toList(), [
      'cinco-estrelas', // 5.0
      'sem-cep', // 4.8
      'perto', // 4.0
      'patrocinado', // 3.0 — pagou, mas o usuário pediu POR AVALIAÇÃO
      'novo', // 0
    ]);
  });

  test('avaliação desempata por volume de reviews', () {
    final firms = [
      _firm('a', rating: 5.0, reviews: 1),
      _firm('b', rating: 5.0, reviews: 40),
    ];
    final sorted = sortLawFirms(firms, OfficeSort.rating);
    expect(sorted.first.id, 'b');
  });

  test('distância: mais perto primeiro, sem-CEP vai pro fim', () {
    final sorted = sortLawFirms(
      serverOrder,
      OfficeSort.distance,
      userLatitude: -30.05,
      userLongitude: -51.22,
    );
    expect(sorted.first.id, 'perto');
    // Sem coordenadas (sem-cep e novo) ficam no fim, em ordem estável.
    expect(sorted.map((f) => f.id).skip(3).toList(), ['sem-cep', 'novo']);
  });

  test('distância sem posição do usuário mantém a ordem do servidor', () {
    final sorted = sortLawFirms(serverOrder, OfficeSort.distance);
    expect(
      sorted.map((f) => f.id).toList(),
      serverOrder.map((f) => f.id).toList(),
    );
  });

  test('padrão declarado é relevância', () {
    expect(OfficeSort.relevance.label, 'Relevância');
    expect(OfficeSort.values.first, OfficeSort.relevance);
  });

  test(
    'empates são ESTÁVEIS mesmo em lista grande (List.sort não garante)',
    () {
      // 40 firmas com a MESMA nota: acima do limiar em que o sort do Dart
      // deixa de ser estável por acidente. A ordem original deve sobreviver.
      final firms = [
        for (var i = 0; i < 40; i++) _firm('f$i', rating: 4.0, reviews: 3),
      ];
      final sorted = sortLawFirms(firms, OfficeSort.rating);
      expect(sorted.map((f) => f.id).toList(), [
        for (var i = 0; i < 40; i++) 'f$i',
      ]);
    },
  );

  group('o que vai para o servidor', () {
    // Desde a 20260817120000 quem ordena e o SERVIDOR: so ele ve o conjunto
    // inteiro. Ordenar client-side uma lista paginada respondia "qual o mais
    // perto DOS DEZ PRIMEIROS" — o mais proximo podia estar na pagina 4.
    test('cada criterio tem um valor estavel de contrato', () {
      expect(OfficeSort.relevance.serverValue, 'relevance');
      expect(OfficeSort.rating.serverValue, 'rating');
      expect(OfficeSort.distance.serverValue, 'distance');
    });

    test('o rotulo da tela e o valor do contrato sao coisas diferentes', () {
      // O texto e PT-BR e pode mudar por decisao de copy; o contrato com o
      // banco nao pode mudar junto.
      for (final sort in OfficeSort.values) {
        expect(
          sort.serverValue,
          isNot(sort.label),
          reason: 'nao derive o valor do banco a partir do rotulo da tela',
        );
        expect(sort.serverValue, matches(RegExp(r'^[a-z]+$')));
      }
    });

    test('a posicao do usuario SO viaja na ordenacao por distancia', () {
      // Mandar coordenada junto de "Avaliacao" seria enviar localizacao para
      // uma pergunta que nao e sobre localizacao.
      for (final sort in [OfficeSort.relevance, OfficeSort.rating]) {
        final params = discoverySortParams(
          sort,
          userLatitude: -30.02,
          userLongitude: -51.22,
        );
        expect(params.keys, ['sort_value'], reason: '${sort.name} nao precisa');
      }

      final comDistancia = discoverySortParams(
        OfficeSort.distance,
        userLatitude: -30.02,
        userLongitude: -51.22,
      );
      expect(comDistancia['sort_value'], 'distance');
      expect(comDistancia['user_latitude'], -30.02);
      expect(comDistancia['user_longitude'], -51.22);
    });

    test('sem posicao, distancia vai sem coordenada (o servidor decide)', () {
      expect(
        discoverySortParams(OfficeSort.distance).keys,
        ['sort_value'],
        reason: 'GPS negado nao pode virar coordenada nula no fio',
      );
      // Meia coordenada nao ordena nada e o servidor a descartaria; nao
      // enviar da o mesmo resultado com um dado a menos no fio.
      expect(
        discoverySortParams(OfficeSort.distance, userLatitude: -30.02).keys,
        ['sort_value'],
      );
      expect(
        discoverySortParams(OfficeSort.distance, userLongitude: -51.22).keys,
        ['sort_value'],
      );
    });

    test('o mais perto pode estar fora da primeira pagina', () {
      // Por que a ordenacao TEM que ser do servidor: o recorte muda a
      // RESPOSTA, nao so a ordem. Aqui o mais proximo e o ultimo da ordem de
      // relevancia — client-side ele so apareceria depois do "Ver mais".
      final pagina1 = [
        _firm('a', lat: -30.10, lng: -51.20),
        _firm('b', lat: -30.20, lng: -51.20),
      ];
      final pagina2 = [_firm('c', lat: -30.01, lng: -51.20)];

      const lat = -30.0;
      const lon = -51.2;

      final soPagina1 = sortLawFirms(
        pagina1,
        OfficeSort.distance,
        userLatitude: lat,
        userLongitude: lon,
      );
      expect(soPagina1.first.id, 'a', reason: 'o melhor do recorte');

      final completa = sortLawFirms(
        [...pagina1, ...pagina2],
        OfficeSort.distance,
        userLatitude: lat,
        userLongitude: lon,
      );
      expect(completa.first.id, 'c', reason: 'o melhor de verdade');
    });
  });
}
