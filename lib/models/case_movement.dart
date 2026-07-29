/// Movimento do processo vindo do DataJud (CNJ), já traduzido para a
/// linguagem do cliente pela tabela `case_movement_translations` do banco.
/// A timeline só recebe movimentos com tradução curada; o ruído processual
/// (juntadas, certidões etc.) fica fora por decisão de produto.
class CaseMovement {
  final String id;
  final String title;
  final String body;
  final String dateLabel;

  const CaseMovement({
    required this.id,
    required this.title,
    required this.body,
    required this.dateLabel,
  });
}
