/// Plano de licenciamento do escritório.
///
/// O preço acompanha o TAMANHO DA EQUIPE: todos os planos incluem tudo, o que
/// muda é o teto de advogados. Os valores vivem no banco (linhas, não código):
/// mudar preço é um UPDATE, não um release.
class LicensePlan {
  const LicensePlan({
    required this.code,
    required this.name,
    required this.maxLawyers,
    required this.monthlyPriceCents,
    this.annualPriceCents,
    this.sortOrder = 0,
  });

  final String code;
  final String name;

  /// Nulo = sem teto (reservado para negociação direta).
  final int? maxLawyers;
  final int monthlyPriceCents;

  /// Preço do ano inteiro, pago de uma vez. Nulo = plano sem opção anual.
  final int? annualPriceCents;
  final int sortOrder;

  factory LicensePlan.fromRow(Map<String, dynamic> row) => LicensePlan(
    code: row['code'] as String,
    name: row['name'] as String? ?? '',
    maxLawyers: (row['max_lawyers'] as num?)?.toInt(),
    monthlyPriceCents: (row['monthly_price_cents'] as num?)?.toInt() ?? 0,
    annualPriceCents: (row['annual_price_cents'] as num?)?.toInt(),
    sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
  );

  /// "R$ 349", sem centavos quando o preço é redondo, que é como preço de
  /// plano se escreve no Brasil.
  String get priceLabel => formatPrice(monthlyPriceCents);

  /// O equivalente MENSAL do plano anual ("R\$ 290"), e a ÚNICA forma de
  /// preço que a tela mostra no ciclo anual.
  ///
  /// O total do ano não aparece de propósito: dois números competindo no
  /// mesmo cartão fazem a pessoa parar para comparar em vez de escolher. Que
  /// a cobrança é anual está dito uma vez, abaixo da chave.
  ///
  /// Os preços do banco são escolhidos para esta divisão dar reais inteiros.
  String? get annualMonthlyLabel {
    final total = annualPriceCents;
    if (total == null) return null;
    return formatPrice((total / 12).round());
  }

  /// Desconto do anual sobre 12 mensalidades, em % inteiro. Calculado, não
  /// declarado: se o preço mudar na tabela, o selo acompanha sozinho.
  int? get annualDiscountPercent {
    final total = annualPriceCents;
    if (total == null || monthlyPriceCents == 0) return null;
    final cheio = monthlyPriceCents * 12;
    return (100 - (total * 100 / cheio)).round();
  }

  static String formatPrice(int cents) {
    final reais = cents ~/ 100;
    final centavos = cents % 100;
    final inteiro = _milhar(reais);
    return centavos == 0
        ? 'R\$ $inteiro'
        : 'R\$ $inteiro,${centavos.toString().padLeft(2, '0')}';
  }

  String get teamLabel => maxLawyers == null
      ? 'Sem limite de advogados'
      : maxLawyers == 1
      ? '1 advogado'
      : 'Até $maxLawyers advogados';

  /// "~R$ 35 por advogado" — o argumento de que crescer não é punido.
  String? get perLawyerLabel {
    final teto = maxLawyers;
    if (teto == null || teto == 0) return null;
    final porAdvogado = (monthlyPriceCents / teto / 100).round();
    return '~R\$ $porAdvogado por advogado';
  }

  static String _milhar(int valor) {
    final texto = valor.toString();
    if (texto.length <= 3) return texto;
    final corte = texto.length - 3;
    return '${texto.substring(0, corte)}.${texto.substring(corte)}';
  }
}

enum LicenseStatus {
  trialing,
  active,
  pastDue,
  canceled;

  static LicenseStatus fromValue(String? value) => switch (value) {
    'active' => LicenseStatus.active,
    'past_due' => LicenseStatus.pastDue,
    'canceled' => LicenseStatus.canceled,
    _ => LicenseStatus.trialing,
  };
}

/// A assinatura de um contratante (e, depois da aprovação, do escritório).
class LicenseSubscription {
  const LicenseSubscription({
    required this.id,
    required this.ownerProfileId,
    required this.planCode,
    required this.status,
    this.billingCycle = 'monthly',
    this.trialEndsAt,
    this.lawFirmId,
    this.plan,
  });

  final String id;
  final String ownerProfileId;
  final String planCode;
  final LicenseStatus status;

  /// 'monthly' ou 'annual'. Registrado na escolha: na hora de cobrar (fora do
  /// app), é o que diz o que foi combinado.
  final String billingCycle;
  final DateTime? trialEndsAt;
  final String? lawFirmId;

  /// Presente quando a leitura veio com o join do plano.
  final LicensePlan? plan;

  factory LicenseSubscription.fromRow(Map<String, dynamic> row) {
    final planRow = row['law_firm_license_plans'];
    return LicenseSubscription(
      id: row['id'].toString(),
      ownerProfileId: row['owner_profile_id']?.toString() ?? '',
      planCode: row['plan_code'] as String? ?? '',
      status: LicenseStatus.fromValue(row['status'] as String?),
      billingCycle: row['billing_cycle'] as String? ?? 'monthly',
      trialEndsAt: row['trial_ends_at'] == null
          ? null
          : DateTime.tryParse(row['trial_ends_at'].toString()),
      lawFirmId: row['law_firm_id']?.toString(),
      plan: planRow is Map<String, dynamic>
          ? LicensePlan.fromRow(planRow)
          : null,
    );
  }

  /// A licença dá passagem? (mesma regra do portão no banco)
  bool get ativa =>
      status == LicenseStatus.trialing || status == LicenseStatus.active;

  bool get emTeste => status == LicenseStatus.trialing;

  /// Dias restantes do teste, nunca negativo — "faltam -3 dias" não é frase.
  int diasRestantesDeTeste(DateTime agora) {
    final fim = trialEndsAt;
    if (fim == null || status != LicenseStatus.trialing) return 0;
    final dias = fim.difference(agora).inDays;
    return dias < 0 ? 0 : dias;
  }

  /// "Escritório · anual · teste grátis, 23 dias restantes": o subtítulo do
  /// perfil. O ciclo só aparece quando é anual, porque mensal é o comum.
  String statusLabel(DateTime agora) {
    final base = plan?.name ?? planCode;
    final nome = billingCycle == 'annual' ? '$base · anual' : base;
    return switch (status) {
      LicenseStatus.trialing =>
        '$nome · teste grátis, ${_dias(diasRestantesDeTeste(agora))}',
      LicenseStatus.active => '$nome · ativo',
      LicenseStatus.pastDue => '$nome · pagamento pendente',
      LicenseStatus.canceled => '$nome · cancelado',
    };
  }

  static String _dias(int dias) =>
      dias == 1 ? '1 dia restante' : '$dias dias restantes';
}
