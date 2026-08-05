/// Um dia de alcance na descoberta.
class ReachDay {
  const ReachDay({
    required this.day,
    required this.reach,
    required this.sponsoredReach,
    required this.profileViews,
    required this.conversations,
  });

  final DateTime day;

  /// Pessoas DIFERENTES que viram o profissional numa lista naquele dia.
  final int reach;

  /// Quantas dessas vieram de uma vaga patrocinada.
  final int sponsoredReach;

  final int profileViews;
  final int conversations;

  factory ReachDay.fromRow(Map<String, dynamic> row) {
    return ReachDay(
      day: DateTime.parse(row['day'] as String),
      reach: (row['reach'] as num?)?.toInt() ?? 0,
      sponsoredReach: (row['sponsored_reach'] as num?)?.toInt() ?? 0,
      profileViews: (row['profile_views'] as num?)?.toInt() ?? 0,
      conversations: (row['conversations'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Um degrau do funil: quantas pessoas chegaram até aqui.
class ReachStep {
  const ReachStep({
    required this.label,
    required this.value,
    required this.rateFromPrevious,
  });

  final String label;
  final int value;

  /// Fração de quem chegou no degrau ANTERIOR e avançou até este. `null` no
  /// primeiro degrau (não há de onde converter) e quando o anterior é zero.
  final double? rateFromPrevious;
}

/// O que o painel mostra: o período pedido, o período anterior de mesmo
/// tamanho para comparar, e o funil já montado.
class ReachSummary {
  const ReachSummary({
    required this.days,
    required this.reach,
    required this.sponsoredReach,
    required this.profileViews,
    required this.conversations,
    required this.previousReach,
    required this.steps,
  });

  final List<ReachDay> days;
  final int reach;
  final int sponsoredReach;
  final int profileViews;
  final int conversations;

  /// Alcance do período anterior de mesmo tamanho, para a variação.
  final int previousReach;

  final List<ReachStep> steps;

  /// Variação do alcance contra o período anterior, de -1 a +infinito.
  /// `null` quando não havia base de comparação — crescer "infinito%" a partir
  /// de zero não é informação, é ruído.
  double? get reachChange {
    if (previousReach == 0) return null;
    return (reach - previousReach) / previousReach;
  }

  bool get hasSponsoredReach => sponsoredReach > 0;

  bool get isEmpty => reach == 0 && profileViews == 0 && conversations == 0;
}

/// Monta o resumo a partir da série que o servidor devolveu.
///
/// [rows] vem com o DOBRO da janela pedida: a metade recente é o período em
/// exibição, a antiga existe só para a comparação. Uma chamada só em vez de
/// duas — a série é barata e o servidor já preenche dia sem evento com zero.
ReachSummary summarizeReach(List<ReachDay> rows, int windowDays) {
  final ordenados = [...rows]..sort((a, b) => a.day.compareTo(b.day));

  final janela = ordenados.length >= windowDays
      ? ordenados.sublist(ordenados.length - windowDays)
      : ordenados;
  final anterior = ordenados.length > windowDays
      ? ordenados.sublist(0, ordenados.length - windowDays)
      : const <ReachDay>[];

  int soma(List<ReachDay> dias, int Function(ReachDay) campo) =>
      dias.fold(0, (total, dia) => total + campo(dia));

  final alcance = soma(janela, (d) => d.reach);
  final visitas = soma(janela, (d) => d.profileViews);
  final conversas = soma(janela, (d) => d.conversations);

  double? taxa(int de, int para) => de == 0 ? null : para / de;

  return ReachSummary(
    days: janela,
    reach: alcance,
    sponsoredReach: soma(janela, (d) => d.sponsoredReach),
    profileViews: visitas,
    conversations: conversas,
    previousReach: soma(anterior, (d) => d.reach),
    steps: [
      ReachStep(
        label: 'viram você na busca',
        value: alcance,
        rateFromPrevious: null,
      ),
      ReachStep(
        label: 'abriram seu perfil',
        value: visitas,
        rateFromPrevious: taxa(alcance, visitas),
      ),
      ReachStep(
        label: 'iniciaram conversa',
        value: conversas,
        rateFromPrevious: taxa(visitas, conversas),
      ),
    ],
  );
}
