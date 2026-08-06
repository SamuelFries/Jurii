class LawyerProfileSummary {
  final String id;
  final String name;
  final String initials;
  final String oabNumber;
  final String oabState;
  final String primaryArea;
  final List<String> practiceAreas;
  final String bio;
  final double rating;
  final int reviews;
  final String avatarType;

  /// Foto profissional (bucket público), quando o advogado já enviou uma na
  /// verificação. Nula para quem se cadastrou antes disso — aí vale o avatar
  /// de iniciais.
  final String? photoUrl;

  /// Posição patrocinada ativa na descoberta (destaque pago/cortesia).
  /// Vem de `is_featured` nos RPCs de descoberta; default false para os mocks
  /// e para RPCs que não expõem o campo (ex.: fetch_law_firm_lawyers).
  final bool isFeatured;

  /// Ocupou uma das (no máximo duas) VAGAS PAGAS desta lista.
  ///
  /// Diferente de [isFeatured], que só diz que há patrocínio ativo: quem paga
  /// também aparece organicamente quando as vagas já estão tomadas. O selo na
  /// tela segue [isFeatured] — quem pagou é identificado sempre. Só a MEDIÇÃO
  /// usa este campo, porque atribuir à vaga uma impressão que ela não entregou
  /// infla o número que justifica a renovação.
  final bool isSponsoredSlot;

  const LawyerProfileSummary({
    required this.id,
    required this.name,
    required this.initials,
    required this.oabNumber,
    required this.oabState,
    required this.primaryArea,
    required this.practiceAreas,
    required this.bio,
    required this.rating,
    required this.reviews,
    required this.avatarType,
    this.photoUrl,
    this.isFeatured = false,
    this.isSponsoredSlot = false,
  });

  String get oabLabel => 'OAB/$oabState $oabNumber';
}
