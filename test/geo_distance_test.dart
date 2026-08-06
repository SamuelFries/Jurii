import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/services/cep_service.dart';
import 'package:jurii/utils/geo_distance.dart';

void main() {
  group('haversineKm', () {
    test('mesmo ponto é zero', () {
      expect(
        haversineKm(lat1: -30.05, lon1: -51.22, lat2: -30.05, lon2: -51.22),
        closeTo(0, 0.0001),
      );
    });

    test('1 grau de latitude ≈ 111,2 km', () {
      expect(
        haversineKm(lat1: 0, lon1: 0, lat2: 1, lon2: 0),
        closeTo(111.19, 0.2),
      );
    });

    test('POA centro -> aeroporto Salgado Filho ≈ 6 km', () {
      // Mercado Público (-30.0277, -51.2287) -> POA Airport (-29.9939, -51.1711)
      final km = haversineKm(
        lat1: -30.0277,
        lon1: -51.2287,
        lat2: -29.9939,
        lon2: -51.1711,
      );
      expect(km, inInclusiveRange(5.5, 7.5));
    });
  });

  group('formatDistanceBr', () {
    test('abaixo de 1 km vira metros (de 10 em 10)', () {
      expect(formatDistanceBr(0.4), '400 m');
      expect(formatDistanceBr(0.847), '850 m');
    });

    test('entre 1 e 10 km usa 1 casa com vírgula', () {
      expect(formatDistanceBr(3.24), '3,2 km');
      expect(formatDistanceBr(9.96), '10,0 km');
    });

    test('10 km ou mais arredonda inteiro', () {
      expect(formatDistanceBr(12.4), '12 km');
      expect(formatDistanceBr(15.7), '16 km');
    });
  });

  group('CepService.parseCoordinates', () {
    test('parseia o formato da BrasilAPI (strings)', () {
      const body =
          '{"cep":"90160093","location":{"type":"Point",'
          '"coordinates":{"longitude":"-51.2224949","latitude":"-30.0546449"}}}';
      final coords = CepService.parseCoordinates(body);
      expect(coords, isNotNull);
      expect(coords!.latitude, closeTo(-30.0546, 0.001));
      expect(coords.longitude, closeTo(-51.2225, 0.001));
    });

    test('CEP sem coordenadas vira null (não inventa posição)', () {
      const body =
          '{"cep":"01001000","location":{"type":"Point",'
          '"coordinates":{}}}';
      expect(CepService.parseCoordinates(body), isNull);
    });

    test('lixo/faixa inválida vira null', () {
      expect(CepService.parseCoordinates('nao é json'), isNull);
      const foraDeFaixa =
          '{"location":{"coordinates":'
          '{"longitude":"-200","latitude":"-30"}}}';
      expect(CepService.parseCoordinates(foraDeFaixa), isNull);
    });

    test('a resposta REAL da BrasilAPI hoje não traz coordenada', () {
      // Corpo copiado da resposta de 06/08/2026 para o CEP do escritório que
      // motivou a investigação. O `coordinates` vem VAZIO — foi assim em 10 de
      // 10 CEPs testados, e é por isso que existe a cascata: sem ela, o app
      // gravava CEP e endereço e nunca gravava coordenada, e o cartão do
      // escritório aparecia sem distância.
      const real =
          '{"cep":"90540140","state":"RS","city":"Porto Alegre",'
          '"neighborhood":"Auxiliadora","street":"Rua Germano Petersen '
          'Júnior","service":"open-cep","location":{"type":"Point",'
          '"coordinates":{}}}';

      expect(CepService.parseCoordinates(real), isNull);

      // O ENDEREÇO, esse vem — e é por isso que a BrasilAPI segue sendo a
      // primeira porta da cascata.
      final lookup = CepService.parseLookup(real);
      expect(lookup!.street, 'Rua Germano Petersen Júnior');
      expect(lookup.city, 'Porto Alegre');
      expect(lookup.state, 'RS');
      expect(lookup.hasAddress, isTrue, reason: 'dá para consultar por endereço');
      expect(lookup.coordinates, isNull);
    });
  });

  group('CepService — as outras fontes da cascata', () {
    test('AwesomeAPI: lat/lng como strings', () {
      // Resposta real de 06/08/2026 para o mesmo CEP que a BrasilAPI não
      // geocodifica.
      const body =
          '{"cep":"90540140","city":"Porto Alegre","lat":"-30.0193337",'
          '"lng":"-51.1902671"}';
      final coords = CepService.parseAwesomeCoordinates(body);
      expect(coords, isNotNull);
      expect(coords!.latitude, closeTo(-30.0193, 0.001));
      expect(coords.longitude, closeTo(-51.1903, 0.001));
    });

    test('AwesomeAPI sem coordenada vira null', () {
      expect(
        CepService.parseAwesomeCoordinates('{"cep":"69900000"}'),
        isNull,
      );
      expect(CepService.parseAwesomeCoordinates('nao é json'), isNull);
    });

    test('Nominatim: primeiro resultado da lista', () {
      const body =
          '[{"lat":"-30.0170250","lon":"-51.1904777",'
          '"display_name":"Rua Germano Petersen Júnior, Porto Alegre"},'
          '{"lat":"-1","lon":"-1"}]';
      final coords = CepService.parseNominatimCoordinates(body);
      expect(coords, isNotNull);
      expect(coords!.latitude, closeTo(-30.0170, 0.001));
      expect(coords.longitude, closeTo(-51.1905, 0.001));
    });

    test('Nominatim sem resultado vira null (não inventa posição)', () {
      expect(CepService.parseNominatimCoordinates('[]'), isNull);
      expect(CepService.parseNominatimCoordinates('nao é json'), isNull);
      expect(CepService.parseNominatimCoordinates('{}'), isNull);
    });

    test('toda fonte recusa coordenada fora do planeta', () {
      // Coordenada inválida gravada vira "12.482 km" no cartão e ordena a
      // descoberta errado — pior que não ter distância.
      expect(
        CepService.parseAwesomeCoordinates('{"lat":"91","lng":"0"}'),
        isNull,
      );
      expect(
        CepService.parseNominatimCoordinates('[{"lat":"0","lon":"181"}]'),
        isNull,
      );
    });

    test('as duas fontes concordam dentro da tolerância de um rótulo em km', () {
      // Medido: AwesomeAPI -30.0193/-51.1903, Nominatim -30.0170/-51.1905.
      // ~250 m de diferença, que some no arredondamento de "2,3 km".
      final awesome = CepService.parseAwesomeCoordinates(
        '{"lat":"-30.0193337","lng":"-51.1902671"}',
      )!;
      final osm = CepService.parseNominatimCoordinates(
        '[{"lat":"-30.0170250","lon":"-51.1904777"}]',
      )!;

      final km = haversineKm(
        lat1: awesome.latitude,
        lon1: awesome.longitude,
        lat2: osm.latitude,
        lon2: osm.longitude,
      );
      expect(km, lessThan(0.5));
    });
  });
}
