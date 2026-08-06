import '../models/law_firm.dart';
import 'geo_distance.dart';

/// Métodos de ordenação da descoberta de escritórios.
enum OfficeSort {
  /// A ordem do servidor: posições patrocinadas no topo + relevância da busca
  /// + nota. É o padrão.
  relevance('Relevância', 'relevance'),

  /// Melhor avaliação primeiro (nota, depois volume de avaliações).
  rating('Avaliação', 'rating'),

  /// Mais perto primeiro. Exige a posição do usuário.
  distance('Distância', 'distance');

  const OfficeSort(this.label, this.serverValue);

  final String label;

  /// O que vai em `sort_value` na RPC. Separado do rótulo de propósito: o
  /// texto da tela é PT-BR e pode mudar por decisão de copy; o contrato com o
  /// banco não pode mudar junto.
  final String serverValue;
}

/// Os parâmetros de ordenação que vão para a RPC da descoberta.
///
/// Existe separado da chamada para ser exercitável sem servidor — o que
/// importa aqui é uma regra de PRIVACIDADE, e regra de privacidade não pode
/// depender de alguém lembrar dela ao escrever o `params:`.
///
/// A posição do usuário só viaja quando a ordenação PEDIDA precisa dela.
/// Mandar coordenada junto de "Avaliação" seria enviar localização para uma
/// pergunta que não é sobre localização.
Map<String, Object> discoverySortParams(
  OfficeSort sort, {
  double? userLatitude,
  double? userLongitude,
}) {
  final params = <String, Object>{'sort_value': sort.serverValue};
  if (sort != OfficeSort.distance) return params;
  // Meia coordenada não ordena nada, e o servidor a descartaria de qualquer
  // forma; não enviar é o mesmo resultado com um dado a menos no fio.
  if (userLatitude == null || userLongitude == null) return params;
  params['user_latitude'] = userLatitude;
  params['user_longitude'] = userLongitude;
  return params;
}

/// Ordena a lista já carregada.
///
/// Desde a 20260817120000 quem ordena de verdade é o SERVIDOR: só ele vê o
/// conjunto inteiro, e ordenar client-side uma lista paginada respondia "qual
/// o mais perto DOS DEZ PRIMEIROS". Esta função continua existindo para o modo
/// demo (mocks, sem servidor) e como rede de segurança contra um servidor que
/// devolva a ordem antiga durante a janela de deploy — sobre a página já
/// carregada, ordenar de novo não piora nada.
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
