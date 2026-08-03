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
