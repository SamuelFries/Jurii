import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/business_hours.dart';
import 'package:jurii/repositories/business_hours_repository.dart';
import 'package:jurii/screens/business_hours_screen.dart';
import 'package:jurii/theme/app_theme.dart';

class _FakeRepo implements BusinessHoursRepository {
  _FakeRepo({this.inicial = BusinessHours.empty, this.erro, this.falhaAoLer = false});

  final BusinessHours inicial;
  final Object? erro;
  final bool falhaAoLer;

  List<BusinessHourInterval>? recebido;

  @override
  Future<BusinessHours> fetch(String lawFirmId) async {
    if (falhaAoLer) throw Exception('offline');
    return inicial;
  }

  @override
  Future<BusinessHours> save({
    required String lawFirmId,
    required List<BusinessHourInterval> intervals,
  }) async {
    recebido = intervals;
    if (erro != null) throw erro!;
    return BusinessHours(intervals);
  }
}

BusinessHourInterval _intervalo(int weekday, int abre, int fecha) =>
    BusinessHourInterval(
      weekday: weekday,
      opensAt: abre * 60,
      closesAt: fecha * 60,
    );

void main() {
  Future<void> abrir(WidgetTester tester, _FakeRepo repo) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: BusinessHoursScreen(lawFirmId: 'f1', repository: repo),
      ),
    );
    await tester.pumpAndSettle();
  }

  ElevatedButton salvar(WidgetTester tester) =>
      tester.widget<ElevatedButton>(find.byKey(const Key('salvar_horarios')));

  testWidgets('escritório sem horário abre sugerindo seg a sex', (
    tester,
  ) async {
    final repo = _FakeRepo();
    await abrir(tester, repo);

    // Sugerir o comum é diferente de gravar por ele: nada vai ao banco sem a
    // pessoa tocar em "Salvar", e por isso o botão começa desligado.
    expect(find.text('Fechado'), findsNWidgets(2), reason: 'sáb e dom');
    expect(salvar(tester).onPressed, isNull);
  });

  testWidgets('abre com o horário que já existe', (tester) async {
    final repo = _FakeRepo(
      inicial: BusinessHours([_intervalo(1, 8, 17), _intervalo(2, 8, 17)]),
    );
    await abrir(tester, repo);

    expect(find.text('8h'), findsNWidgets(2));
    expect(find.text('17h'), findsNWidgets(2));
    // Cinco dias fechados: quarta a domingo.
    expect(find.text('Fechado'), findsNWidgets(5));
  });

  testWidgets('salva só os dias abertos', (tester) async {
    final repo = _FakeRepo();
    await abrir(tester, repo);

    // Fecha a segunda; sobram terça a sexta.
    await tester.tap(find.byKey(const Key('dia_1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('salvar_horarios')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('salvar_horarios')));
    await tester.pumpAndSettle();

    expect(repo.recebido?.map((i) => i.weekday).toList(), [2, 3, 4, 5]);
    expect(repo.recebido?.first.opensAt, 9 * 60);
    expect(repo.recebido?.first.closesAt, 18 * 60);
  });

  testWidgets('nenhum dia aberto é gravável, e avisa o que significa', (
    tester,
  ) async {
    final repo = _FakeRepo(inicial: BusinessHours([_intervalo(1, 9, 18)]));
    await abrir(tester, repo);

    await tester.tap(find.byKey(const Key('dia_1')));
    await tester.pumpAndSettle();

    // Escritório que só atende sob agendamento existe — mas ele precisa saber
    // que o cliente vai ficar sem a informação.
    expect(find.textContaining('o perfil não mostra horário'), findsOneWidget);
    expect(salvar(tester).onPressed, isNotNull);

    await tester.ensureVisible(find.byKey(const Key('salvar_horarios')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('salvar_horarios')));
    await tester.pumpAndSettle();

    expect(repo.recebido, isEmpty);
  });

  testWidgets('repetir copia o horário para os outros dias abertos', (
    tester,
  ) async {
    final repo = _FakeRepo(
      inicial: BusinessHours([
        _intervalo(1, 8, 17),
        _intervalo(2, 9, 18),
        _intervalo(3, 10, 19),
      ]),
    );
    await abrir(tester, repo);

    await tester.ensureVisible(find.byKey(const Key('replicar_horario')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('replicar_horario')));
    await tester.pumpAndSettle();

    // Sem isto, um horário igual em cinco dias custa dez toques em relógio.
    expect(find.text('8h'), findsNWidgets(3));
    expect(find.text('17h'), findsNWidgets(3));
  });

  testWidgets('salvar fica desligado enquanto nada mudou', (tester) async {
    final repo = _FakeRepo(inicial: BusinessHours([_intervalo(1, 9, 18)]));
    await abrir(tester, repo);

    expect(salvar(tester).onPressed, isNull);

    await tester.tap(find.byKey(const Key('dia_2')));
    await tester.pumpAndSettle();
    expect(salvar(tester).onPressed, isNotNull);
  });

  testWidgets('recusa do servidor vira texto, e a tela não fecha', (
    tester,
  ) async {
    final repo = _FakeRepo(
      inicial: BusinessHours([_intervalo(1, 9, 18)]),
      erro: Exception('PostgrestException(message: Not allowed)'),
    );
    await abrir(tester, repo);

    await tester.tap(find.byKey(const Key('dia_2')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('salvar_horarios')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('salvar_horarios')));
    await tester.pumpAndSettle();

    expect(
      find.text('Você não tem permissão para editar este escritório.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('salvar_horarios')), findsOneWidget);
  });

  testWidgets('falha ao carregar mostra retry, não grade vazia', (
    tester,
  ) async {
    await abrir(tester, _FakeRepo(falhaAoLer: true));

    // Grade vazia diria "fechado a semana toda" — que é uma afirmação, não um
    // erro de rede.
    expect(
      find.text('Não foi possível carregar os horários.'),
      findsOneWidget,
    );
  });
}
