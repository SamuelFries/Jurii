import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/repositories/professional_bio_repository.dart';
import 'package:jurii/screens/professional_bio_screen.dart';
import 'package:jurii/theme/app_theme.dart';

class _FakeBioRepository extends ProfessionalBioRepository {
  _FakeBioRepository({this.bio, this.failLoad = false, this.failSave = false});

  String? bio;
  bool failLoad;
  final bool failSave;
  String? savedBio;
  ({String id, String? text})? savedFirm;
  int loadCalls = 0;

  @override
  Future<String?> fetchMyBio() async {
    loadCalls++;
    if (failLoad) throw StateError('offline');
    return bio;
  }

  @override
  Future<String?> saveMyBio(String? value) async {
    if (failSave) throw StateError('offline');
    savedBio = value;
    bio = value;
    return value;
  }

  @override
  Future<String?> saveLawFirmDescription({
    required String lawFirmId,
    required String? description,
  }) async {
    if (failSave) throw StateError('offline');
    savedFirm = (id: lawFirmId, text: description);
    return description;
  }
}

Widget _host(Widget screen) =>
    MaterialApp(theme: AppTheme.lightTheme, home: screen);

void main() {
  testWidgets('advogado: abre com a bio atual e salva o texto novo', (
    tester,
  ) async {
    final repo = _FakeBioRepository(bio: 'Atuo em família há 12 anos.');

    await tester.pumpWidget(
      _host(ProfessionalBioScreen.lawyer(repository: repo)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Atuo em família há 12 anos.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  Novo texto.  ');
    await tester.tap(find.text('Salvar apresentação'));
    await tester.pumpAndSettle();

    // Apara espaço antes de mandar (o servidor também apara, mas o app não
    // deve enviar lixo).
    expect(repo.savedBio, 'Novo texto.');
  });

  testWidgets('limpar o campo envia null (texto padrão volta)', (tester) async {
    final repo = _FakeBioRepository(bio: 'Tinha texto.');

    await tester.pumpWidget(
      _host(ProfessionalBioScreen.lawyer(repository: repo)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Salvar apresentação'));
    await tester.pumpAndSettle();

    expect(repo.savedBio, isNull);
  });

  testWidgets('bio nunca escrita abre vazia, não com a frase padrão', (
    tester,
  ) async {
    // O perfil público troca nulo pelo texto genérico; o editor não pode
    // abrir pré-preenchido com uma frase que o advogado não escreveu.
    final repo = _FakeBioRepository();

    await tester.pumpWidget(
      _host(ProfessionalBioScreen.lawyer(repository: repo)),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(find.text('Perfil profissional verificado pela Jurii.'), findsNothing);
  });

  testWidgets('falha ao carregar tem retry', (tester) async {
    final repo = _FakeBioRepository(failLoad: true);

    await tester.pumpWidget(
      _host(ProfessionalBioScreen.lawyer(repository: repo)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível carregar sua apresentação.'),
      findsOneWidget,
    );

    repo
      ..failLoad = false
      ..bio = 'Depois do retry.';
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(find.text('Depois do retry.'), findsOneWidget);
    expect(repo.loadCalls, 2);
  });

  testWidgets('falha ao salvar avisa e mantém a tela aberta', (tester) async {
    final repo = _FakeBioRepository(bio: 'texto', failSave: true);

    await tester.pumpWidget(
      _host(ProfessionalBioScreen.lawyer(repository: repo)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Salvar apresentação'));
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível salvar. Tente novamente.'), findsOneWidget);
    expect(find.text('Salvar apresentação'), findsOneWidget);
  });

  testWidgets('escritório abre com o texto do workspace, sem fetch', (
    tester,
  ) async {
    final repo = _FakeBioRepository();

    await tester.pumpWidget(
      _host(ProfessionalBioScreen.lawFirm(
        lawFirmId: 'firma-1',
        initialText: 'Banca de família.',
        repository: repo,
      )),
    );
    await tester.pumpAndSettle();

    expect(repo.loadCalls, 0);
    expect(find.text('Banca de família.'), findsOneWidget);
    expect(find.text('Como o escritório se apresenta'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Texto novo da firma.');
    await tester.tap(find.text('Salvar apresentação'));
    await tester.pumpAndSettle();

    expect(repo.savedFirm?.id, 'firma-1');
    expect(repo.savedFirm?.text, 'Texto novo da firma.');
  });
}
