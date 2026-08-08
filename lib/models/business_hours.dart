/// Um intervalo de atendimento num dia da semana.
///
/// [weekday] segue `DateTime.weekday` do Dart: 1 = segunda … 7 = domingo. O
/// banco guarda a mesma convenção de propósito — quem lê e escreve é o app.
class BusinessHourInterval {
  const BusinessHourInterval({
    required this.weekday,
    required this.opensAt,
    required this.closesAt,
  });

  final int weekday;

  /// Minutos desde a meia-noite. Guardado assim, e não como `TimeOfDay`, para
  /// o modelo não depender do Flutter — o cálculo de "aberto agora" precisa
  /// rodar em teste puro.
  final int opensAt;
  final int closesAt;

  factory BusinessHourInterval.fromRow(Map<String, dynamic> row) {
    return BusinessHourInterval(
      weekday: (row['weekday'] as num).toInt(),
      opensAt: parseMinutes(row['opens_at'] as String? ?? '00:00'),
      closesAt: parseMinutes(row['closes_at'] as String? ?? '00:00'),
    );
  }

  Map<String, Object?> toJson() => {
    'weekday': weekday,
    'opens_at': formatMinutes(opensAt),
    'closes_at': formatMinutes(closesAt),
  };

  /// "09:00:00" e "09:00" viram 540. O Postgres devolve com segundos; o app
  /// escreve sem.
  static int parseMinutes(String value) {
    final partes = value.split(':');
    if (partes.length < 2) return 0;
    final hora = int.tryParse(partes[0]) ?? 0;
    final minuto = int.tryParse(partes[1]) ?? 0;
    return hora * 60 + minuto;
  }

  static String formatMinutes(int minutes) {
    final hora = (minutes ~/ 60).toString().padLeft(2, '0');
    final minuto = (minutes % 60).toString().padLeft(2, '0');
    return '$hora:$minuto';
  }

  /// "9h" ou "9h30" — como brasileiro escreve horário, não "09:00".
  static String label(int minutes) {
    final hora = minutes ~/ 60;
    final minuto = minutes % 60;
    return minuto == 0 ? '${hora}h' : '${hora}h${minuto.toString().padLeft(2, '0')}';
  }

  String get rangeLabel => '${label(opensAt)} às ${label(closesAt)}';
}

const _nomesDosDias = [
  'Segunda',
  'Terça',
  'Quarta',
  'Quinta',
  'Sexta',
  'Sábado',
  'Domingo',
];

String weekdayName(int weekday) => _nomesDosDias[(weekday - 1) % 7];

/// Os horários de um escritório, prontos para exibir e para responder "está
/// aberto agora?".
class BusinessHours {
  const BusinessHours(this.intervals);

  final List<BusinessHourInterval> intervals;

  static const BusinessHours empty = BusinessHours([]);

  bool get isEmpty => intervals.isEmpty;

  List<BusinessHourInterval> forWeekday(int weekday) =>
      intervals.where((i) => i.weekday == weekday).toList()
        ..sort((a, b) => a.opensAt.compareTo(b.opensAt));

  /// `true` quando [instante] cai dentro de algum intervalo do dia.
  ///
  /// O horário é gravado como hora de PAREDE do escritório, sem fuso. Este
  /// cálculo usa o horário de Brasília (UTC-3, sem horário de verão desde
  /// 2019) e não a hora do aparelho: um cliente viajando ou num estado a
  /// oeste veria "aberto" com o escritório fechado, o que é pior que não
  /// mostrar nada. É a mesma referência que as métricas de alcance usam.
  bool isOpenAt(DateTime instante) {
    final local = instante.toUtc().subtract(const Duration(hours: 3));
    final minutos = local.hour * 60 + local.minute;
    return forWeekday(local.weekday).any(
      (i) => minutos >= i.opensAt && minutos < i.closesAt,
    );
  }

  /// Dias agrupados por horário igual: "Seg a Sex · 9h às 18h".
  ///
  /// Sete linhas repetindo o mesmo horário é ruído — o cliente lê a exceção,
  /// não a repetição. Só agrupa dias CONSECUTIVOS: "Seg, Qua e Sex" não vira
  /// faixa, porque faixa implica os dias do meio.
  List<String> get summaryLines {
    final linhas = <String>[];
    var dia = 1;

    while (dia <= 7) {
      final doDia = forWeekday(dia);
      if (doDia.isEmpty) {
        dia++;
        continue;
      }

      final assinatura = doDia.map((i) => i.rangeLabel).join(' e ');
      var ultimo = dia;
      while (ultimo < 7) {
        final proximo = forWeekday(ultimo + 1);
        if (proximo.isEmpty) break;
        if (proximo.map((i) => i.rangeLabel).join(' e ') != assinatura) break;
        ultimo++;
      }

      final nomes = dia == ultimo
          ? weekdayName(dia)
          : ultimo == dia + 1
          // Dois dias seguidos não são uma faixa: "Sáb a Dom" soa longo para
          // dizer "Sáb e Dom".
          ? '${weekdayName(dia)} e ${weekdayName(ultimo)}'
          : '${weekdayName(dia)} a ${weekdayName(ultimo)}';

      linhas.add('$nomes · $assinatura');
      dia = ultimo + 1;
    }

    return linhas;
  }
}
