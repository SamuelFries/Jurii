import '../models/law_firm.dart';
import 'geo_distance.dart';

/// Métodos de ordenação da descoberta de escritórios.
enum OfficeSort {
  /// A ordem do servidor: posições patrocinadas no topo + relevância da busca
  /// + nota. É o padrão.
  relevance('Relevância'),

  /// Melhor avaliação primeiro (nota, depois volume de avaliações).
  rating('Avaliação'),

  /// Mais perto primeiro. Exige a posição do usuário.
  distance('Distância');

  const OfficeSort(this.label);
  final String label;
}

/// Ordena a lista da descoberta SEM tocar no servidor — a troca de método é
/// instantânea (client-side) e reaproveita os dados já carregados.
///
/// Decisão de produto: o boost do destaque pago vive APENAS na ordenação por
/// relevância (a ordem do servidor). Quando o usuário escolhe explicitamente
/// um critério objetivo (avaliação/distância), a lista obedece o critério —
/// o selo "Destaque" continua visível no card, mas patrocinado não fura uma
/// ordenação que o usuário pediu. Transparência primeiro.
List<LawFirm> sortLawFirms(
  List<LawFirm> firms,
  OfficeSort sort, {
  double? userLatitude,
  double? userLongitude,
}) {
  switch (sort) {
    case OfficeSort.relevance:
      // A ordem que veio do RPC já É a relevância (slots + busca + nota).
      return List.of(firms);

    case OfficeSort.rating:
      return _sortedStable(firms, (a, b) {
        final byRating = b.rating.compareTo(a.rating);
        if (byRating != 0) return byRating;
        // 5.0 com 40 avaliações vale mais que 5.0 com 1.
        return b.reviews.compareTo(a.reviews);
      });

    case OfficeSort.distance:
      final hasUser = userLatitude != null && userLongitude != null;
      if (!hasUser) return List.of(firms);
      double kmOf(LawFirm firm) {
        if (!firm.hasCoordinates) return double.infinity; // sem CEP → fim
        return haversineKm(
          lat1: userLatitude,
          lon1: userLongitude,
          lat2: firm.latitude!,
          lon2: firm.longitude!,
        );
      }

      return _sortedStable(firms, (a, b) => kmOf(a).compareTo(kmOf(b)));
  }
}

/// Sort ESTÁVEL garantido: List.sort do Dart não promete estabilidade (só é
/// estável por acidente de implementação em listas pequenas), então empates
/// são desfeitos pela posição original — quem empata mantém a ordem de
/// relevância que veio do servidor.
List<LawFirm> _sortedStable(
  List<LawFirm> firms,
  int Function(LawFirm a, LawFirm b) compare,
) {
  final indexed = firms.asMap().entries.toList();
  indexed.sort((a, b) {
    final result = compare(a.value, b.value);
    return result != 0 ? result : a.key.compareTo(b.key);
  });
  return [for (final entry in indexed) entry.value];
}
