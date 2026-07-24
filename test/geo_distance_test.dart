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
      const body = '{"cep":"90160093","location":{"type":"Point",'
          '"coordinates":{"longitude":"-51.2224949","latitude":"-30.0546449"}}}';
      final coords = CepService.parseCoordinates(body);
      expect(coords, isNotNull);
      expect(coords!.latitude, closeTo(-30.0546, 0.001));
      expect(coords.longitude, closeTo(-51.2225, 0.001));
    });

    test('CEP sem coordenadas vira null (não inventa posição)', () {
      const body = '{"cep":"01001000","location":{"type":"Point",'
          '"coordinates":{}}}';
      expect(CepService.parseCoordinates(body), isNull);
    });

    test('lixo/faixa inválida vira null', () {
      expect(CepService.parseCoordinates('nao é json'), isNull);
      const foraDeFaixa = '{"location":{"coordinates":'
          '{"longitude":"-200","latitude":"-30"}}}';
      expect(CepService.parseCoordinates(foraDeFaixa), isNull);
    });
  });
}
