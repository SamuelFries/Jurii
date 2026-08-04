import '../models/discovery_page.dart';

/// Converte o resultado bruto de uma consulta feita com `limit + 1` numa
/// página: a linha extra é só o sinal de que existe próxima — vira
/// `hasMore` e é descartada. Vive aqui (e não inline nos repositórios)
/// para a lógica da sentinela ter teste de unidade: os repositórios reais
/// não rodam sem Supabase.
DiscoveryPage<T> pageFromSentinel<T>(List<T> rows, int limit) {
  final hasMore = rows.length > limit;
  return DiscoveryPage(
    items: hasMore ? rows.sublist(0, limit) : rows,
    hasMore: hasMore,
  );
}

/// Anexa uma página nova à lista acumulada descartando itens cuja chave já
/// apareceu, preservando a ordem (os antigos ficam onde estão; os novos
/// entram no fim, na ordem do servidor).
///
/// O dedupe existe porque a ordem do servidor pode mudar ENTRE páginas: os
/// slots patrocinados da descoberta giram por hora (md5 do id + hora), então
/// paginar cruzando a virada da hora pode reapresentar um perfil já exibido.
/// Duplicata visual seria bug na tela — e, com ListView keyada por id,
/// exceção de key duplicada.
List<T> appendUniqueBy<T>(
  List<T> current,
  List<T> incoming,
  Object Function(T item) keyOf,
) {
  final seen = current.map(keyOf).toSet();
  return [
    ...current,
    ...incoming.where((item) => seen.add(keyOf(item))),
  ];
}
