import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/professional_reach.dart';
import 'package:jurii/repositories/discovery_metrics_repository.dart';
import 'package:jurii/repositories/professional_reach_repository.dart';
import 'package:jurii/screens/professional_reach_screen.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

ReachDay _dia(
  int diaDoMes, {
  int reach = 0,
  int sponsored = 0,
  int views = 0,
  int conversations = 0,
}) {
  return ReachDay(
    day: DateTime(2026, 8, diaDoMes),
    reach: reach,
    sponsoredReach: sponsored,
    profileViews: views,
    conversations: conversations,
  );
}

/// Devolve uma série pronta em vez de ir ao Supabase.
class _FakeReachRepository implements ProfessionalReachRepository {
  _FakeReachRepository(this.summary);

  final ReachSummary summary;
  int chamadas = 0;
  int? ultimaJanela;

  @override
  Future<ReachSummary> fetchReach({
    required DiscoveryTarget target,
    required String targetId,
    int windowDays = 30,
  }) async {
    chamadas++;
    ultimaJanela = windowDays;
    return summary;
  }
}

/// Banco sem a migration de alcance: o mesmo PGRST202 que o app viu em
/// produção quando a tela subiu antes do push.
class _RepositorioSemFuncao implements ProfessionalReachRepository {
  @override
  Future<ReachSummary> fetchReach({
    required DiscoveryTarget target,
    required String targetId,
    int windowDays = 30,
  }) async {
    throw const PostgrestException(
      message: 'Could not find the function public.fetch_professional_reach',
      code: 'PGRST202',
    );
  }
}

class _RepositorioQueFalha implements ProfessionalReachRepository {
  @override
  Future<ReachSummary> fetchReach({
    required DiscoveryTarget target,
    required String targetId,
    int windowDays = 30,
  }) async {
    throw StateError('offline');
  }
}

void main() {
  group('resumo do período', () {
    test('separa a janela em exibição do período de comparação', () {
      // O servidor devolve o DOBRO: os 2 primeiros dias são a base de
      // comparação, os 2 últimos é o que aparece na tela.
      final resumo = summarizeReach([
        _dia(1, reach: 10),
        _dia(2, reach: 10),
        _dia(3, reach: 15),
        _dia(4, reach: 15),
      ], 2);

      expect(resumo.reach, 30, reason: 'só a janela recente soma');
      expect(resumo.previousReach, 20);
      expect(resumo.reachChange, closeTo(0.5, 0.001));
      expect(resumo.days, hasLength(2));
    });

    test('série fora de ordem é ordenada antes de dividir', () {
      final resumo = summarizeReach([
        _dia(4, reach: 15),
        _dia(1, reach: 10),
        _dia(3, reach: 15),
        _dia(2, reach: 10),
      ], 2);

      expect(resumo.reach, 30);
      expect(resumo.previousReach, 20);
    });

    test('sem base de comparação a variação é nula, não infinita', () {
      // Crescer "infinito por cento" a partir de zero não é informação, e
      // mostrar isso no painel de um advogado novo seria ruído.
      final resumo = summarizeReach([
        _dia(1, reach: 0),
        _dia(2, reach: 8),
      ], 1);

      expect(resumo.previousReach, 0);
      expect(resumo.reachChange, isNull);
    });

    test('queda vira variação negativa', () {
      final resumo = summarizeReach([
        _dia(1, reach: 20),
        _dia(2, reach: 10),
      ], 1);

      expect(resumo.reachChange, closeTo(-0.5, 0.001));
    });

    test('série menor que a janela não estoura', () {
      final resumo = summarizeReach([_dia(1, reach: 5)], 30);
      expect(resumo.reach, 5);
      expect(resumo.previousReach, 0);
    });

    test('série vazia devolve painel zerado', () {
      final resumo = summarizeReach(const [], 30);
      expect(resumo.isEmpty, isTrue);
      expect(resumo.peakReach, 0);
      expect(resumo.steps, hasLength(3));
    });
  });

  group('funil', () {
    test('cada degrau converte do anterior, não do topo', () {
      // 100 viram, 20 abriram (20% de 100), 5 conversaram (25% de 20 — e NÃO
      // 5% de 100). Confundir os dois esconde onde está o gargalo.
      final resumo = summarizeReach([
        _dia(1, reach: 100, views: 20, conversations: 5),
      ], 1);

      expect(resumo.steps[0].value, 100);
      expect(resumo.steps[0].rateFromPrevious, isNull);
      expect(resumo.steps[1].value, 20);
      expect(resumo.steps[1].rateFromPrevious, closeTo(0.2, 0.001));
      expect(resumo.steps[2].value, 5);
      expect(resumo.steps[2].rateFromPrevious, closeTo(0.25, 0.001));
    });

    test('degrau anterior zerado não vira divisão por zero', () {
      final resumo = summarizeReach([
        _dia(1, reach: 0, views: 0, conversations: 0),
      ], 1);

      expect(resumo.steps[1].rateFromPrevious, isNull);
      expect(resumo.steps[2].rateFromPrevious, isNull);
    });
  });

  group('painel', () {
    setUp(() {
      // O painel tem três cartões empilhados; no viewport padrão de teste
      // (800x600) o último não chega a ser montado e some dos finders.
      final view = TestWidgetsFlutterBinding.instance.platformDispatcher
          .views
          .first;
      view.physicalSize = const Size(900, 2000);
      view.devicePixelRatio = 1.0;
      addTearDown(view.reset);
    });

    Widget app(ProfessionalReachRepository repo) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: ProfessionalReachScreen.lawyer(
        lawyerId: 'lawyer-1',
        repository: repo,
      ),
    );

    testWidgets('mostra o funil com os três degraus', (tester) async {
      final repo = _FakeReachRepository(
        summarizeReach([
          _dia(1, reach: 240, views: 36, conversations: 5),
        ], 1),
      );

      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();

      expect(find.text('viram você na busca'), findsOneWidget);
      expect(find.text('abriram seu perfil'), findsOneWidget);
      expect(find.text('iniciaram conversa'), findsOneWidget);
      // As taxas de conversão são o que a caixa de entrada nunca conta.
      expect(find.text('15%'), findsOneWidget);
      expect(find.text('14%'), findsOneWidget);
    });

    testWidgets('quem não tem patrocínio vê o convite', (tester) async {
      final repo = _FakeReachRepository(
        summarizeReach([_dia(1, reach: 38, views: 4)], 1),
      );

      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();

      // O painel é o vendedor: ele existe para todo profissional, não só
      // para quem já pagou.
      expect(find.text('Quer aparecer para mais gente?'), findsOneWidget);
      expect(find.text('Patrocínio ativo'), findsNothing);
    });

    testWidgets('quem tem patrocínio vê o que ele rendeu', (tester) async {
      final repo = _FakeReachRepository(
        summarizeReach([_dia(1, reach: 100, sponsored: 40)], 1),
      );

      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();

      expect(find.text('Patrocínio ativo'), findsOneWidget);
      expect(
        find.textContaining('40 das 100 pessoas'),
        findsOneWidget,
        reason: 'o número do patrocínio é o que justifica a renovação',
      );
      expect(find.textContaining('40% do seu alcance'), findsOneWidget);
    });

    testWidgets('trocar o período refaz a busca com a janela nova', (
      tester,
    ) async {
      final repo = _FakeReachRepository(summarizeReach(const [], 30));

      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      expect(repo.ultimaJanela, 30, reason: '30 dias é o padrão');

      await tester.tap(find.text('7 dias'));
      await tester.pumpAndSettle();

      expect(repo.ultimaJanela, 7);
      expect(repo.chamadas, 2);
    });

    testWidgets('falha mostra erro com retry, não painel vazio', (
      tester,
    ) async {
      await tester.pumpWidget(app(_RepositorioQueFalha()));
      await tester.pumpAndSettle();

      // Painel zerado por falha de rede seria pior que erro: o advogado
      // concluiria que ninguém o viu.
      expect(
        find.text('Não foi possível carregar seus números.'),
        findsOneWidget,
      );
      expect(find.text('viram você na busca'), findsNothing);
    });

    testWidgets('banco sem a migration explica em vez de pedir retry', (
      tester,
    ) async {
      await tester.pumpWidget(app(_RepositorioSemFuncao()));
      await tester.pumpAndSettle();

      // "Não foi possível carregar" com botão de tentar de novo faria o
      // profissional insistir num botão que não tem como funcionar: a função
      // não existe no banco, e nenhuma quantidade de toques cria ela.
      expect(
        find.text('Seus números estão sendo preparados'),
        findsOneWidget,
      );
      expect(
        find.text('Não foi possível carregar seus números.'),
        findsNothing,
      );
    });

    testWidgets('período sem movimento explica em vez de mostrar só zeros', (
      tester,
    ) async {
      final repo = _FakeReachRepository(summarizeReach(const [], 30));

      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();

      expect(find.textContaining('Ainda sem movimento'), findsOneWidget);
    });
  });
}
