import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/business_hours.dart';

BusinessHourInterval _intervalo(int weekday, String abre, String fecha) =>
    BusinessHourInterval(
      weekday: weekday,
      opensAt: BusinessHourInterval.parseMinutes(abre),
      closesAt: BusinessHourInterval.parseMinutes(fecha),
    );

/// Instante em horário de Brasília (UTC-3), que é a referência do cálculo.
DateTime _brasilia(int ano, int mes, int dia, int hora, [int minuto = 0]) =>
    DateTime.utc(ano, mes, dia, hora + 3, minuto);

void main() {
  group('leitura e escrita do horário', () {
    test('o Postgres devolve com segundos; o app escreve sem', () {
      expect(BusinessHourInterval.parseMinutes('09:00:00'), 540);
      expect(BusinessHourInterval.parseMinutes('09:00'), 540);
      expect(BusinessHourInterval.parseMinutes('18:30:00'), 1110);
      expect(BusinessHourInterval.formatMinutes(1110), '18:30');
    });

    test('lixo não vira meia-noite silenciosa em campo errado', () {
      expect(BusinessHourInterval.parseMinutes(''), 0);
      expect(BusinessHourInterval.parseMinutes('abacaxi'), 0);
    });

    test('o rótulo é como brasileiro escreve hora', () {
      expect(BusinessHourInterval.label(540), '9h');
      expect(BusinessHourInterval.label(1110), '18h30');
      expect(BusinessHourInterval.label(0), '0h');
    });

    test('a ida e volta pelo JSON preserva o intervalo', () {
      final original = _intervalo(3, '08:30', '17:45');
      final volta = BusinessHourInterval.fromRow({
        'weekday': original.toJson()['weekday'],
        'opens_at': original.toJson()['opens_at'],
        'closes_at': original.toJson()['closes_at'],
      });
      expect(volta.weekday, 3);
      expect(volta.opensAt, original.opensAt);
      expect(volta.closesAt, original.closesAt);
    });
  });

  group('aberto agora', () {
    final comercial = BusinessHours([
      for (var d = 1; d <= 5; d++) _intervalo(d, '09:00', '18:00'),
    ]);

    test('dentro do intervalo, num dia aberto', () {
      // Quarta, 14h.
      expect(comercial.isOpenAt(_brasilia(2026, 8, 5, 14)), isTrue);
    });

    test('antes de abrir e depois de fechar', () {
      expect(comercial.isOpenAt(_brasilia(2026, 8, 5, 8, 59)), isFalse);
      expect(comercial.isOpenAt(_brasilia(2026, 8, 5, 18, 1)), isFalse);
    });

    test('a hora de fechar já está fechado', () {
      // Às 18h em ponto o expediente acabou; dizer "aberto" convida a
      // mensagem que ninguém vai responder.
      expect(comercial.isOpenAt(_brasilia(2026, 8, 5, 18)), isFalse);
      // E a hora de abrir já está aberto.
      expect(comercial.isOpenAt(_brasilia(2026, 8, 5, 9)), isTrue);
    });

    test('dia sem intervalo é fechado o dia inteiro', () {
      // Sábado e domingo (2026-08-08 e 08-09).
      expect(comercial.isOpenAt(_brasilia(2026, 8, 8, 14)), isFalse);
      expect(comercial.isOpenAt(_brasilia(2026, 8, 9, 14)), isFalse);
    });

    test('o cálculo é em Brasília, não na hora do aparelho', () {
      // 14h UTC é 11h em Brasília — aberto. O MESMO instante visto de um
      // aparelho em Lisboa (15h local) não pode virar "fechado": o cliente
      // veria "fechado" com o escritório atendendo.
      final instante = DateTime.utc(2026, 8, 5, 14);
      expect(comercial.isOpenAt(instante), isTrue);
      expect(comercial.isOpenAt(instante.toLocal()), isTrue);
    });

    test('dois intervalos no mesmo dia: fecha para almoço', () {
      // A tela escreve um intervalo por dia, mas o banco guarda linhas — o
      // dia com almoço já funciona sem mudar esquema.
      final comAlmoco = BusinessHours([
        _intervalo(3, '09:00', '12:00'),
        _intervalo(3, '13:30', '18:00'),
      ]);
      expect(comAlmoco.isOpenAt(_brasilia(2026, 8, 5, 10)), isTrue);
      expect(comAlmoco.isOpenAt(_brasilia(2026, 8, 5, 12, 30)), isFalse);
      expect(comAlmoco.isOpenAt(_brasilia(2026, 8, 5, 15)), isTrue);
    });

    test('sem horário nenhum nunca está aberto', () {
      expect(BusinessHours.empty.isOpenAt(_brasilia(2026, 8, 5, 14)), isFalse);
      expect(BusinessHours.empty.isEmpty, isTrue);
    });
  });

  group('resumo para o cliente', () {
    test('dias iguais e seguidos viram uma faixa', () {
      final comercial = BusinessHours([
        for (var d = 1; d <= 5; d++) _intervalo(d, '09:00', '18:00'),
      ]);
      // Cinco linhas repetindo o mesmo horário é ruído: o cliente lê a
      // exceção, não a repetição.
      expect(comercial.summaryLines, ['Segunda a Sexta · 9h às 18h']);
    });

    test('horário diferente quebra a faixa', () {
      final horarios = BusinessHours([
        for (var d = 1; d <= 4; d++) _intervalo(d, '09:00', '18:00'),
        _intervalo(5, '09:00', '12:00'),
      ]);
      expect(horarios.summaryLines, [
        'Segunda a Quinta · 9h às 18h',
        'Sexta · 9h às 12h',
      ]);
    });

    test('dias NÃO consecutivos não viram faixa', () {
      // "Segunda a Sexta" implicaria terça, quarta e quinta — que estão
      // fechadas. Faixa que mente é pior que três linhas.
      final horarios = BusinessHours([
        _intervalo(1, '09:00', '18:00'),
        _intervalo(3, '09:00', '18:00'),
        _intervalo(5, '09:00', '18:00'),
      ]);
      expect(horarios.summaryLines, [
        'Segunda · 9h às 18h',
        'Quarta · 9h às 18h',
        'Sexta · 9h às 18h',
      ]);
    });

    test('dois dias seguidos usam "e", não "a"', () {
      final horarios = BusinessHours([
        _intervalo(6, '09:00', '13:00'),
        _intervalo(7, '09:00', '13:00'),
      ]);
      expect(horarios.summaryLines, ['Sábado e Domingo · 9h às 13h']);
    });

    test('dia com dois intervalos aparece inteiro', () {
      final horarios = BusinessHours([
        _intervalo(1, '13:30', '18:00'),
        _intervalo(1, '09:00', '12:00'),
      ]);
      expect(horarios.summaryLines, [
        'Segunda · 9h às 12h e 13h30 às 18h',
      ]);
    });

    test('sem horário, sem linha', () {
      expect(BusinessHours.empty.summaryLines, isEmpty);
    });
  });
}
