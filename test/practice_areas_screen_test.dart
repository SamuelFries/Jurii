import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/repositories/practice_areas_repository.dart';
import 'package:jurii/screens/practice_areas_screen.dart';
import 'package:jurii/theme/app_theme.dart';

class _FakeRepo implements PracticeAreasRepository {
  _FakeRepo({
    this.atuais = const LawyerPracticeAreas(
      primaryArea: 'Direito Cível',
      areas: ['Direito Cível'],
    ),
    this.erro,
    this.falhaAoCarregar = false,
  });

  final LawyerPracticeAreas atuais;
  final Object? erro;
  final bool falhaAoCarregar;

  Map<String, Object?>? recebido;

  @override
  Future<LawyerPracticeAreas> fetchMine() async {
    if (falhaAoCarregar) throw Exception('sem rede');
    return atuais;
  }

  @override
  Future<List<String>> save({
    required String primaryArea,
    required List<String> areas,
  }) async {
    recebido = {'primaryArea': primaryArea, 'areas': areas};
    if (erro != null) throw erro!;
    return areas;
  }
}

void main() {
  Widget app(_FakeRepo repo) => MaterialApp(
    theme: AppTheme.lightTheme,
    home: PracticeAreasScreen(repository: repo),
  );

  Future<void> abrir(WidgetTester tester, _FakeRepo repo) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
  }

  testWidgets('abre com as áreas atuais marcadas', (tester) async {
    final repo = _FakeRepo(
      atuais: const LawyerPracticeAreas(
        primaryArea: 'Direito Trabalhista',
        areas: ['Direito Trabalhista', 'Direito Previdenciário'],
      ),
    );
    await abrir(tester, repo);

    expect(find.text('2 áreas marcadas'), findsOneWidget);
    expect(find.text('Área principal'), findsOneWidget);
  });

  testWidgets('salvar fica desligado enquanto nada mudou', (tester) async {
    await abrir(tester, _FakeRepo());

    // Um "Salvar" sempre ativo convida a gravar sem querer — e cada gravação
    // aqui reescreve por onde o cliente encontra o advogado.
    final botao = tester.widget<ElevatedButton>(
      find.byKey(const Key('save_practice_areas')),
    );
    expect(botao.onPressed, isNull);

    await tester.tap(find.text('Direito Trabalhista'));
    await tester.pumpAndSettle();

    final depois = tester.widget<ElevatedButton>(
      find.byKey(const Key('save_practice_areas')),
    );
    expect(depois.onPressed, isNotNull);
  });

  testWidgets('desmarcar a principal troca a principal', (tester) async {
    final repo = _FakeRepo(
      atuais: const LawyerPracticeAreas(
        primaryArea: 'Direito Cível',
        areas: ['Direito Cível', 'Direito Trabalhista'],
      ),
    );
    await abrir(tester, repo);

    // Sem isto o perfil ficaria com uma área principal que ele já não atende,
    // e o servidor recusaria — o erro apareceria só no salvamento.
    // `.first` é o chip: o dropdown de área principal exibe o mesmo texto.
    await tester.tap(find.text('Direito Cível').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_practice_areas')));
    await tester.pumpAndSettle();

    expect(repo.recebido?['primaryArea'], 'Direito Trabalhista');
    expect(repo.recebido?['areas'], isNot(contains('Direito Cível')));
  });

  testWidgets('a recusa do servidor nomeia a área', (tester) async {
    final repo = _FakeRepo(
      erro: Exception(
        'PostgrestException(message: Invalid practice area: Direito Bancário)',
      ),
    );
    await abrir(tester, repo);

    await tester.tap(find.text('Direito Trabalhista'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_practice_areas')));
    await tester.pumpAndSettle();

    // "Área inválida" sem o nome deixa a pessoa sem saber qual chip tirar.
    expect(
      find.text('A área "Direito Bancário" não está mais disponível. '
          'Escolha outra.'),
      findsOneWidget,
    );
    expect(find.text('Áreas de atuação'), findsWidgets, reason: 'não fecha');
  });

  testWidgets('falha ao carregar mostra retry, não tela vazia', (tester) async {
    await abrir(tester, _FakeRepo(falhaAoCarregar: true));

    expect(find.text('Não foi possível carregar suas áreas.'), findsOneWidget);
  });

  testWidgets('área herdada do cadastro antigo aparece na tela', (
    tester,
  ) async {
    final repo = _FakeRepo(
      atuais: const LawyerPracticeAreas(
        primaryArea: 'Especialidade Antiga',
        areas: ['Especialidade Antiga', 'Direito Cível'],
      ),
    );
    await abrir(tester, repo);

    // Se ela viajasse invisível, voltaria recusada do servidor sem a pessoa
    // poder sequer ver qual era a culpada.
    expect(find.text('Especialidade Antiga'), findsWidgets);
  });
}
