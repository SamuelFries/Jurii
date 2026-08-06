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
  _FakeFirmProfileRepository({this.erro, this.cnpj = '12345678000190'});

  final Object? erro;
  final String? cnpj;
  Map<String, Object?>? recebido;
  int chamadas = 0;

  @override
  LawFirmLogoStorage get logoStorage => const LawFirmLogoStorage();

  @override
  Future<String?> fetchCnpj(String lawFirmId) async => cnpj;

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
      'websiteUrl': websiteUrl,
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
  static const endereco = 'Av. Ipiranga, Praia de Belas, Porto Alegre';
  int chamadas = 0;
  int buscasCompletas = 0;

  @override
  get client => null;

  @override
  Future<CepCoordinates?> lookup(String cep) async {
    chamadas++;
    return const CepCoordinates(latitude: -30.03, longitude: -51.22);
  }

  @override
  Future<CepLookup?> lookupFull(String cep) async {
    buscasCompletas++;
    chamadas++;
    final partes = endereco.split(', ');
    return CepLookup(
      coordinates: const CepCoordinates(latitude: -30.03, longitude: -51.22),
      street: partes.isNotEmpty ? partes[0] : null,
      neighborhood: partes.length > 1 ? partes[1] : null,
      city: partes.length > 2 ? partes[2].split(' - ').first : null,
      state: partes.length > 2 && partes[2].contains(' - ')
          ? partes[2].split(' - ').last
          : null,
    );
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
    await tester.ensureVisible(find.text('Salvar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(repo.recebido?['name'], 'Firma Nova');
  });

  testWidgets('nome vazio nem chega ao servidor', (tester) async {
    final repo = _FakeFirmProfileRepository();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '   ');
    await tester.ensureVisible(find.text('Salvar'));
    await tester.pumpAndSettle();
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

    // Mexe só no telefone: o CEP fica como estava.
    await tester.enterText(find.byType(TextFormField).at(2), '51988887777');
    await tester.ensureVisible(find.text('Salvar'));
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

    await tester.enterText(find.byType(TextFormField).at(6), '90160091');
    await tester.ensureVisible(find.text('Salvar'));
    await tester.pumpAndSettle();
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

    await tester.enterText(find.byType(TextFormField).at(6), '');
    await tester.ensureVisible(find.text('Salvar'));
    await tester.pumpAndSettle();
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

    await tester.enterText(find.byType(TextFormField).at(6), '123');
    await tester.ensureVisible(find.text('Salvar'));
    await tester.pumpAndSettle();
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

    await tester.enterText(find.byType(TextFormField).first, 'Firma Nova');
    await tester.ensureVisible(find.text('Salvar'));
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
    await tester.ensureVisible(find.text('Salvar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    final areas = repo.recebido?['practiceAreas'] as List<String>;
    expect(areas, isNot(contains('Direito Cível')));
    expect(repo.recebido?['primaryArea'], isIn(areas));
  });

  testWidgets('o CEP preenche o endereço quando ele está vazio', (
    tester,
  ) async {
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
          practiceAreas: ['Direito Cível'],
          reviews: 0,
          avatarType: 'blue',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Digitar rua, bairro e cidade que o CEP já determina é trabalho repetido
    // — e digitado errado deixa o cadastro dizendo uma coisa e a coordenada
    // apontando outra.
    await tester.enterText(find.byType(TextFormField).at(6), '90160091');
    await tester.tap(find.byType(TextFormField).at(0));
    await tester.pumpAndSettle();

    expect(
      find.text('Av. Ipiranga, Praia de Belas, Porto Alegre'),
      findsOneWidget,
    );
  });

  testWidgets('endereço já preenchido NÃO é sobrescrito pelo CEP', (
    tester,
  ) async {
    // Sobrescrever apagaria número e complemento, que o CEP não sabe.
    final repo = _FakeFirmProfileRepository();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(6), '90160091');
    await tester.tap(find.byType(TextFormField).at(0));
    await tester.pumpAndSettle();

    expect(find.text('Rua Velha, 10'), findsOneWidget);
  });

  testWidgets('sem alterações o botão de salvar fica desligado', (
    tester,
  ) async {
    await tester.pumpWidget(app(_FakeFirmProfileRepository()));
    await tester.pumpAndSettle();

    // Um "Salvar" sempre ativo convida a gravar sem querer, e cada gravação
    // reescreve o cartão que o cliente vê na descoberta.
    final antes = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(antes.onPressed, isNull);

    await tester.enterText(find.byType(TextFormField).first, 'Firma Nova');
    await tester.pumpAndSettle();

    final depois = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(depois.onPressed, isNotNull);
  });

  testWidgets('sair com alteração pendente pede confirmação', (tester) async {
    await tester.pumpWidget(app(_FakeFirmProfileRepository()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Firma Nova');
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Seis campos de formulário perdidos em silêncio seriam bastante coisa.
    expect(find.text('Descartar alterações?'), findsOneWidget);
  });

  testWidgets('o site ganha esquema antes de ser gravado', (tester) async {
    final repo = _FakeFirmProfileRepository();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(4), 'weber.com.br');
    await tester.ensureVisible(find.text('Salvar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    // Sem esquema a URL não abre: vira busca no navegador, ou nada.
    expect(repo.recebido?['websiteUrl'], 'https://weber.com.br');
  });

  testWidgets('o CNPJ aparece formatado e travado', (tester) async {
    await tester.pumpWidget(app(_FakeFirmProfileRepository()));
    await tester.pumpAndSettle();

    // Mostrar travado explica melhor do que simplesmente não ter o campo, que
    // pareceria esquecimento.
    expect(find.text('12.345.678/0001-90'), findsOneWidget);

    final campo = tester.widget<TextFormField>(
      find.byKey(const Key('firm_cnpj_field')),
    );
    expect(campo.enabled, isFalse);
  });

  testWidgets('sem verificação aprovada o campo fica vazio, não quebra', (
    tester,
  ) async {
    await tester.pumpWidget(app(_FakeFirmProfileRepository(cnpj: null)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('firm_cnpj_field')), findsOneWidget);
    expect(find.text('12.345.678/0001-90'), findsNothing);
  });

  testWidgets('o CNPJ não conta como alteração', (tester) async {
    final repo = _FakeFirmProfileRepository();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    // Ele chega depois do primeiro build, por uma consulta própria: se
    // entrasse no cálculo, o botão de salvar ligaria sozinho ao carregar.
    final botao = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(botao.onPressed, isNull);
  });

  group('áreas herdadas do cadastro antigo', () {
    const firmaLegada = LawFirm(
      id: 'f1',
      name: 'Firma Antiga',
      initials: 'FA',
      rating: 5,
      distance: '',
      specialty: 'Direito do Trabalho',
      // Valores reais de produção: o cadastro é anterior à lista canônica.
      practiceAreas: ['Direito do Trabalho', 'Direito Bancário'],
      reviews: 0,
      avatarType: 'blue',
    );

    testWidgets('aparecem na tela em vez de irem escondidas', (tester) async {
      await tester.pumpWidget(
        app(_FakeFirmProfileRepository(), firm: firmaLegada),
      );
      await tester.pumpAndSettle();

      // Invisíveis, elas iam junto no salvamento e voltavam recusadas — sem a
      // pessoa poder sequer ver qual era a culpada.
      expect(find.text('Direito do Trabalho'), findsWidgets);
      expect(find.text('Direito Bancário'), findsWidgets);
    });

    testWidgets('salvar o telefone não esbarra nelas', (tester) async {
      final repo = _FakeFirmProfileRepository();
      await tester.pumpWidget(app(repo, firm: firmaLegada));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(2), '51999990000');
      await tester.ensureVisible(find.text('Salvar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      // O campo é mascarado; o servidor recebe o texto e normaliza.
      expect(repo.recebido?['phone'], '(51) 99999-0000');
      expect(
        repo.recebido?['practiceAreas'],
        containsAll(['Direito do Trabalho', 'Direito Bancário']),
        reason: 'a área herdada segue no cadastro, não some em silêncio',
      );
    });

    testWidgets('a recusa do servidor nomeia a área', (tester) async {
      final repo = _FakeFirmProfileRepository(
        erro: Exception(
          'PostgrestException(message: Invalid practice area: Direito Bancário)',
        ),
      );
      await tester.pumpWidget(app(repo, firm: firmaLegada));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Outro Nome');
      await tester.ensureVisible(find.text('Salvar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      // "Uma das áreas não é válida" deixava a pessoa procurando qual — foi
      // exatamente o que aconteceu em uso.
      expect(find.textContaining('Direito Bancário'), findsWidgets);
    });
  });
}
