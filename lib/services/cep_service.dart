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

/// Geocodificação de CEP via BrasilAPI (gratuita, sem chave).
///
/// Usada UMA vez, no cadastro do escritório: o sócio informa o CEP e o app
/// resolve as coordenadas antes do submit. Best-effort — sem coordenadas o
/// cadastro segue normalmente, só não há distância na descoberta.
class CepService {
  const CepService({this.client});

  final http.Client? client;

  Future<CepCoordinates?> lookup(String cep) async {
    final digits = cep.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 8) return null;

    try {
      final httpClient = client ?? http.Client();
      final response = await httpClient
          .get(Uri.parse('https://brasilapi.com.br/api/cep/v2/$digits'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      return parseCoordinates(response.body);
    } catch (error) {
      debugPrint('BrasilAPI cep lookup failed: $error');
      return null;
    }
  }

  /// Parse separado do fetch para ser testável sem rede. A BrasilAPI devolve
  /// as coordenadas como STRINGS em location.coordinates — e nem todo CEP as
  /// tem (retorna null nesses casos).
  @visibleForTesting
  static CepCoordinates? parseCoordinates(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final location = json['location'] as Map<String, dynamic>?;
      final coordinates = location?['coordinates'] as Map<String, dynamic>?;
      final lat = double.tryParse('${coordinates?['latitude']}');
      final lng = double.tryParse('${coordinates?['longitude']}');
      if (lat == null || lng == null) return null;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
      return CepCoordinates(latitude: lat, longitude: lng);
    } catch (_) {
      return null;
    }
  }
}
