import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Posição do usuário para o cálculo local de distâncias.
///
/// Regras:
/// - NUNCA abre o diálogo de permissão sozinho: `refreshIfPermitted` só usa
///   permissão já concedida; o pedido explícito é `requestAndRefresh`,
///   disparado por um gesto do usuário (chip "ver distâncias").
/// - Nunca lança: qualquer falha (serviço desligado, negado, timeout) vira
///   posição nula e o app segue sem distâncias, como sempre funcionou.
/// - A posição fica só em memória (cache da sessão) e nunca é enviada a
///   lugar nenhum.
class LocationService {
  LocationService._();

  static final LocationService instance = LocationService._();

  Position? _cached;

  Position? get cachedPosition => _cached;

  /// Atualiza a posição APENAS se a permissão já foi concedida antes.
  Future<Position?> refreshIfPermitted() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }
      return await _fetch();
    } catch (error) {
      debugPrint('Location refresh failed: $error');
      return null;
    }
  }

  /// Pede a permissão (chamar só a partir de um gesto do usuário) e, se
  /// concedida, atualiza a posição.
  Future<Position?> requestAndRefresh() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }
      return await _fetch();
    } catch (error) {
      debugPrint('Location request failed: $error');
      return null;
    }
  }

  Future<Position?> _fetch() async {
    try {
      // Precisão baixa basta para km — mais rápida e gasta menos bateria.
      _cached = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return _cached;
    } catch (error) {
      debugPrint('Location fetch failed: $error');
      // Melhor uma posição de minutos atrás do que nenhuma distância.
      _cached ??= await Geolocator.getLastKnownPosition();
      return _cached;
    }
  }
}
