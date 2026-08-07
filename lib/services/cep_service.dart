import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Coordenadas aproximadas de um CEP (precisão de rua/bairro — suficiente
/// para exibir distância em km até o escritório).
class CepCoordinates {
  const CepCoordinates({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

/// O que se sabe sobre um CEP: onde fica, e o endereço por escrito.
class CepLookup {
  const CepLookup({
    this.coordinates,
    this.street,
    this.neighborhood,
    this.city,
    this.state,
  });

  final CepCoordinates? coordinates;
  final String? street;
  final String? neighborhood;
  final String? city;
  final String? state;

  /// Endereço numa linha, do jeito que vai para o cadastro. Vazio quando o
  /// CEP não trouxe nada aproveitável — CEP de cidade inteira, por exemplo,
  /// não tem rua.
  String get formattedAddress {
    final partes = [
      street,
      neighborhood,
      [city, state].where((p) => p != null && p.isNotEmpty).join(' - '),
    ].where((p) => p != null && p.trim().isNotEmpty).cast<String>();
    return partes.join(', ');
  }

  CepLookup withCoordinates(CepCoordinates? value) => CepLookup(
    coordinates: value,
    street: street,
    neighborhood: neighborhood,
    city: city,
    state: state,
  );

  /// `true` quando dá para montar uma busca por endereço (e não só por CEP).
  bool get hasAddress =>
      (street ?? '').trim().isNotEmpty && (city ?? '').trim().isNotEmpty;
}

/// Geocodificação de CEP, em cascata.
///
/// POR QUE CASCATA: a BrasilAPI v2 era a fonte única, e o campo
/// `location.coordinates` dela vem VAZIO. Medido em 06/08/2026: 10 de 10 CEPs
/// testados voltaram `{"type":"Point","coordinates":{}}` (provider
/// "open-cep"). Ou seja, a geocodificação do app nunca resolvia — e é por isso
/// que 39 dos 40 escritórios em produção têm CEP e não têm coordenada, e que o
/// cartão deles aparece sem distância na descoberta.
///
/// A BrasilAPI continua sendo a primeira porta porque é ela que devolve o
/// ENDEREÇO (rua, bairro, cidade, UF), que o formulário usa. O que mudou é que
/// a coordenada, quando ela não traz, é buscada em outra fonte:
///
///   1. BrasilAPI v2 — endereço (+ coordenada, nas raras vezes em que vem)
///   2. AwesomeAPI    — coordenada por CEP; acertou 10 de 12 no teste
///   3. Nominatim/OSM — coordenada por ENDEREÇO estruturado; pega os casos em
///      que a AwesomeAPI não tem o CEP, e foi quem resolveu justamente o
///      90540140 que motivou a investigação (por CEP sozinho ela falha nele;
///      com rua + cidade + UF, acerta)
///
/// As duas últimas se completam: no teste, a união cobriu 12 de 12.
class CepService {
  const CepService({this.client});

  final http.Client? client;

  /// Nominatim exige identificação de quem chama (política de uso da OSM) e
  /// pede no máximo 1 requisição por segundo. O app faz UMA por cadastro ou
  /// edição de escritório, então cabe folgado — mas o cabeçalho é obrigatório
  /// e sem ele a chamada é bloqueada.
  static const _userAgent = 'JuriiApp/1.0 (https://jurii.com.br)';

  static const _timeout = Duration(seconds: 6);

  /// Consulta completa: endereço E coordenadas.
  ///
  /// Preencher o endereço sozinho é o que evita a pessoa digitar rua, bairro e
  /// cidade que o CEP já determina — e digitar errado, deixando o cadastro
  /// dizendo uma coisa e a coordenada apontando outra.
  /// [addressNumber] afina a coordenada quando existe.
  ///
  /// Medido em 07/08/2026 para o CEP 90540140: o centroide da rua e o número
  /// 70 ficam a 305 m um do outro. Não muda a decisão de ninguém num rótulo de
  /// "2,3 km", mas é de graça — e a busca com número não é menos confiável:
  /// em 5 endereços testados, todo caso que resolveu pela rua também resolveu
  /// com o número, e o único que falhou falhou dos dois jeitos. Por isso a
  /// tentativa com número vem antes, com queda para a rua.
  Future<CepLookup?> lookupFull(String cep, {String? addressNumber}) async {
    final digits = _digits(cep);
    if (digits.length != 8) return null;

    final httpClient = client ?? http.Client();
    final base = await _brasilApi(httpClient, digits);

    // Coordenada já veio junto (raro, mas quando vem é a melhor: mesma fonte
    // do endereço, sem risco de discordar dele). Com número na mão, ainda
    // vale tentar afinar — o CEP sozinho é centroide.
    if (base?.coordinates != null && !_temNumero(addressNumber)) return base;

    final coordenadas =
        (_temNumero(addressNumber)
            ? await _nominatim(httpClient, digits, base, addressNumber)
            : null) ??
        base?.coordinates ??
        await _awesomeApi(httpClient, digits) ??
        await _nominatim(httpClient, digits, base);

    if (base != null) return base.withCoordinates(coordenadas);
    if (coordenadas == null) return null;
    // Endereço não veio, coordenada sim: melhor que nada — a distância na
    // descoberta funciona, só o preenchimento automático do endereço não.
    return CepLookup(coordinates: coordenadas);
  }

  /// Só as coordenadas. Mesma cascata, para quem não precisa do endereço.
  Future<CepCoordinates?> lookup(String cep, {String? addressNumber}) async =>
      (await lookupFull(cep, addressNumber: addressNumber))?.coordinates;

  /// "s/n", "sn" e afins não são número de porta: mandá-los ao Nominatim só
  /// faz a busca falhar e cair na rua, gastando uma requisição para nada.
  static bool _temNumero(String? value) {
    final texto = (value ?? '').trim();
    if (texto.isEmpty) return false;
    return RegExp(r'\d').hasMatch(texto);
  }

  // ---------------------------------------------------------------------
  // Fontes
  // ---------------------------------------------------------------------

  Future<CepLookup?> _brasilApi(http.Client httpClient, String digits) async {
    try {
      final response = await httpClient
          .get(Uri.parse('https://brasilapi.com.br/api/cep/v2/$digits'))
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      return parseLookup(response.body);
    } catch (error) {
      debugPrint('BrasilAPI cep lookup failed: $error');
      return null;
    }
  }

  Future<CepCoordinates?> _awesomeApi(
    http.Client httpClient,
    String digits,
  ) async {
    try {
      final response = await httpClient
          .get(Uri.parse('https://cep.awesomeapi.com.br/json/$digits'))
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      return parseAwesomeCoordinates(response.body);
    } catch (error) {
      debugPrint('AwesomeAPI cep lookup failed: $error');
      return null;
    }
  }

  Future<CepCoordinates?> _nominatim(
    http.Client httpClient,
    String digits,
    CepLookup? endereco, [
    String? addressNumber,
  ]) async {
    try {
      // Com rua + cidade + UF a busca acerta CEPs que a consulta por código
      // sozinha erra — foi o caso do 90540140. Sem endereço, sobra o CEP.
      final query = <String, String>{
        'format': 'json',
        'limit': '1',
        'country': 'Brazil',
        if (endereco?.hasAddress == true) ...{
          // O Nominatim espera o número ANTES do logradouro no campo `street`
          // ("70 Rua X"); em outra ordem ele ignora o número em silêncio.
          'street': _temNumero(addressNumber)
              ? '${addressNumber!.trim()} ${endereco!.street!}'
              : endereco!.street!,
          'city': endereco.city!,
          if ((endereco.state ?? '').isNotEmpty) 'state': endereco.state!,
        } else
          'postalcode': digits,
      };

      final response = await httpClient
          .get(
            Uri.https('nominatim.openstreetmap.org', '/search', query),
            headers: const {'User-Agent': _userAgent},
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      return parseNominatimCoordinates(response.body);
    } catch (error) {
      debugPrint('Nominatim lookup failed: $error');
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // Parsers — separados do fetch para serem testáveis sem rede.
  // ---------------------------------------------------------------------

  @visibleForTesting
  static CepLookup? parseLookup(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return CepLookup(
        coordinates: parseCoordinates(body),
        street: (json['street'] as String?)?.trim(),
        neighborhood: (json['neighborhood'] as String?)?.trim(),
        city: (json['city'] as String?)?.trim(),
        state: (json['state'] as String?)?.trim(),
      );
    } catch (_) {
      return null;
    }
  }

  /// BrasilAPI v2: coordenadas como STRINGS em `location.coordinates`.
  ///
  /// Na prática o objeto vem VAZIO (provider "open-cep"), e é justamente por
  /// isso que existe o resto da cascata. O parser fica porque quando a
  /// BrasilAPI responde por outro provider a coordenada vem — e sendo da mesma
  /// resposta do endereço, é a que menos risco tem de discordar dele.
  @visibleForTesting
  static CepCoordinates? parseCoordinates(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final location = json['location'] as Map<String, dynamic>?;
      final coordinates = location?['coordinates'] as Map<String, dynamic>?;
      return _coordenadasDe(coordinates?['latitude'], coordinates?['longitude']);
    } catch (_) {
      return null;
    }
  }

  /// AwesomeAPI: `lat` e `lng`, também como strings.
  @visibleForTesting
  static CepCoordinates? parseAwesomeCoordinates(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return _coordenadasDe(json['lat'], json['lng']);
    } catch (_) {
      return null;
    }
  }

  /// Nominatim: lista de resultados; o primeiro é o mais relevante.
  @visibleForTesting
  static CepCoordinates? parseNominatimCoordinates(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! List || json.isEmpty) return null;
      final primeiro = json.first as Map<String, dynamic>;
      return _coordenadasDe(primeiro['lat'], primeiro['lon']);
    } catch (_) {
      return null;
    }
  }

  /// Aceita número ou string e recusa o que estiver fora do planeta.
  ///
  /// A checagem de faixa não é preciosismo: coordenada inválida gravada vira
  /// "12.482 km" no cartão do escritório, e ordena a descoberta errado.
  static CepCoordinates? _coordenadasDe(Object? rawLat, Object? rawLng) {
    final lat = rawLat is num ? rawLat.toDouble() : double.tryParse('$rawLat');
    final lng = rawLng is num ? rawLng.toDouble() : double.tryParse('$rawLng');
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return CepCoordinates(latitude: lat, longitude: lng);
  }

  static String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');
}
