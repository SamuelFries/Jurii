import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/law_firm.dart';
import 'package:jurii/models/profile_avatar_file.dart';
import 'package:jurii/repositories/law_firm_profile_repository.dart';
import 'package:jurii/screens/edit_firm_profile_screen.dart';
import 'package:jurii/services/cep_service.dart';
import 'package:jurii/theme/app_theme.dart';

const _firma = LawFirm(
  id: 'f1',
  name: 'Firma Antiga',
  initials: 'FA',
  rating: 4.8,
  distance: '',
  specialty: 'Direito Cível',
  practiceAreas: ['Direito Cível'],
  reviews: 12,
  avatarType: 'blue',
  phone: '5133334444',
  email: 'contato@antiga.com',
  address: 'Rua Velha, 10',
  cep: '90000000',
  latitude: -30.0,
  longitude: -51.0,
);

class _FakeFirmProfileRepository implements LawFirmProfileRepository {
  _FakeFirmProfileRepository({this.erro});

  final Object? erro;
  Map<String, Object?>? recebido;
  int chamadas = 0;

  @override
  LawFirmLogoStorage get logoStorage => const LawFirmLogoStorage();

  @override
  Future<LawFirm> updateProfile({
    required String lawFirmId,
    required String name,
    String? phone,
    String? email,
    String? websiteUrl,
    String? address,
    String? cep,
    double? latitude,
    double? longitude,
    String? primaryArea,
    List<String> practiceAreas = const [],
    ProfileAvatarFile? logo,
    bool removeLogo = false,
  }) async {
    chamadas++;
    recebido = {
      'name': name,
      'phone': phone,
      'cep': cep,
      'latitude': latitude,
      'longitude': longitude,
      'primaryArea': primaryArea,
      'practiceAreas': practiceAreas,
      'removeLogo': removeLogo,
    };
    if (erro != null) throw erro!;
    return _firma;
  }
}

/// Geocodificação previsível: devolve sempre a mesma coordenada, e conta
/// quantas vezes foi chamada.
class _FakeCepService implements CepService {
  int chamadas = 0;

  @override
  get client => null;

  @override
  Future<CepCoordinates?> lookup(String cep) async {
    chamadas++;
    return const CepCoordinates(latitude: -30.03, longitude: -51.22);
  }
}

void main() {
  setUp(() {
    // O formulário tem logo, seis campos e o seletor de áreas: no viewport
    // padrão (800x600) o botão Salvar nem chega a ser montado.
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1000, 2600);
    view.devicePixelRatio = 1.0;
    addTearDown(view.reset);
  });

  Widget app(
    LawFirmProfileRepository repo, {
    CepService? cep,
    LawFirm firm = _firma,
  }) => MaterialApp(
    theme: AppTheme.lightTheme,
    home: EditFirmProfileScreen(
      firm: firm,
      repository: repo,
      cepService: cep ?? _FakeCepService(),
    ),
  );

  testWidgets('abre preenchido com o cadastro atual', (tester) async {
    await tester.pumpWidget(app(_FakeFirmProfileRepository()));
    await tester.pumpAndSettle();

    // Formulário de edição que abre vazio faz a pessoa redigitar tudo — e
    // apagar sem querer o que não pretendia mexer.
    expect(find.text('Firma Antiga'), findsOneWidget);
    expect(find.text('5133334444'), findsOneWidget);
    expect(find.text('contato@antiga.com'), findsOneWidget);
    expect(find.text('Rua Velha, 10'), findsOneWidget);
    expect(find.text('90000000'), findsOneWidget);
  });

  testWidgets('salva o que foi editado', (tester) async {
    final repo = _FakeFirmProfileRepository();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Firma Nova');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(repo.recebido?['name'], 'Firma Nova');
  });

  testWidgets('nome vazio nem chega ao servidor', (tester) async {
    final repo = _FakeFirmProfileRepository();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '   ');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(repo.chamadas, 0);
    expect(find.text('Informe o nome do escritório'), findsOneWidget);
  });

  testWidgets('CEP inalterado NÃO gasta uma geocodificação', (tester) async {
    // Salvar só o telefone não deve custar uma ida à BrasilAPI.
    final cep = _FakeCepService();
    final repo = _FakeFirmProfileRepository();
    await tester.pumpWidget(app(repo, cep: cep));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(cep.chamadas, 0);
    expect(repo.recebido?['latitude'], -30.0, reason: 'mantém a coordenada');
  });

  testWidgets('CEP novo busca a coordenada', (tester) async {
    final cep = _FakeCepService();
    final repo = _FakeFirmProfileRepository();
    await tester.pumpWidget(app(repo, cep: cep));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(5), '90160091');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(cep.chamadas, 1);
    expect(repo.recebido?['latitude'], -30.03);
    expect(repo.recebido?['cep'], '90160091');
  });

  testWidgets('apagar o CEP limpa a coordenada junto', (tester) async {
    // Coordenada órfã de um endereço que já não existe colocaria o escritório
    // na distância errada da descoberta.
    final repo = _FakeFirmProfileRepository();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(5), '');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(repo.recebido?['cep'], isNull);
    expect(repo.recebido?['latitude'], isNull);
    expect(repo.recebido?['longitude'], isNull);
  });

  testWidgets('CEP incompleto é barrado antes de salvar', (tester) async {
    final repo = _FakeFirmProfileRepository();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(5), '123');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(repo.chamadas, 0);
    expect(find.text('CEP tem 8 dígitos'), findsOneWidget);
  });

  testWidgets('recusa do servidor vira texto, e a tela não fecha', (
    tester,
  ) async {
    final repo = _FakeFirmProfileRepository(
      erro: Exception('PostgrestException: Not allowed'),
    );
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(
      find.text('Você não tem permissão para editar este escritório.'),
      findsOneWidget,
    );
    expect(find.text('Salvar'), findsOneWidget, reason: 'a tela continua');
  });

  testWidgets('a área principal segue as áreas escolhidas', (tester) async {
    final repo = _FakeFirmProfileRepository();
    await tester.pumpWidget(
      app(
        repo,
        firm: const LawFirm(
          id: 'f1',
          name: 'Firma',
          initials: 'F',
          rating: 5,
          distance: '',
          specialty: 'Direito Cível',
          practiceAreas: ['Direito Cível', 'Direito Trabalhista'],
          reviews: 0,
          avatarType: 'blue',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Desmarcar a área principal não pode deixar o escritório com uma
    // especialidade que ele já não atende.
    await tester.tap(find.text('Direito Cível').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    final areas = repo.recebido?['practiceAreas'] as List<String>;
    expect(areas, isNot(contains('Direito Cível')));
    expect(repo.recebido?['primaryArea'], isIn(areas));
  });
}
