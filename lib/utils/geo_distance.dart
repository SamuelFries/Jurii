import 'dart:math';

/// Distância em linha reta entre duas coordenadas, em km (Haversine).
///
/// É o que alimenta o "2,3 km" da descoberta. O cálculo acontece SEMPRE no
/// aparelho: o servidor conhece apenas as coordenadas do escritório (dado
/// público de estabelecimento); a posição do usuário nunca sai do device.
double haversineKm({
  required double lat1,
  required double lon1,
  required double lat2,
  required double lon2,
}) {
  const earthRadiusKm = 6371.0;
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a =
      pow(sin(dLat / 2), 2) +
      cos(_rad(lat1)) * cos(_rad(lat2)) * pow(sin(dLon / 2), 2);
  return 2 * earthRadiusKm * asin(sqrt(a.toDouble()));
}

double _rad(double deg) => deg * pi / 180;

/// Formata em padrão brasileiro: "850 m", "3,2 km", "12 km".
String formatDistanceBr(double km) {
  if (km < 1) {
    final meters = (km * 1000 / 10).round() * 10; // arredonda de 10 em 10 m
    return '$meters m';
  }
  if (km < 10) {
    return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  }
  return '${km.round()} km';
}
