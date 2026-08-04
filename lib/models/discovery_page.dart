/// Uma página da descoberta (advogados ou escritórios) com o sinal de que
/// existe próxima. O `hasMore` vem do truque da sentinela: o repositório pede
/// `limit + 1` linhas ao servidor; veio a mais = há outra página, e a linha
/// extra é descartada — nenhuma segunda ida ao servidor só para saber isso.
class DiscoveryPage<T> {
  final List<T> items;
  final bool hasMore;

  const DiscoveryPage({required this.items, required this.hasMore});

  const DiscoveryPage.last(this.items) : hasMore = false;
}
