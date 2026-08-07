import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/data/mock/mock_users.dart';
import 'package:jurii/screens/law_firm_verification_form_screen.dart';
import 'package:jurii/services/cep_service.dart';
import 'package:jurii/theme/app_theme.dart';

/// CEP que resolve, com o endereço completo — a resposta que a BrasilAPI já
/// devolvia e o formulário jogava fora.
class _FakeCepService implements CepService {
  _FakeCepService({this.resultado = _resolvido});

  static const _resolvido = CepLookup(
    coordinates: CepCoordinates(latitude: -30.0193, longitude: -51.1903),
    street: 'Rua Germano Petersen Júnior',
    neighborhood: 'Auxiliadora',
    city: 'Porto Alegre',
    state: 'RS',
  );

  final CepLookup? resultado;
  final List<String> consultas = [];
  final List<String> numeros = [];

  @override
  get client => null;

  @override
  Future<CepLookup?> lookupFull(String cep, {String? addressNumber}) async {
    consultas.add(cep);
    numeros.add(addressNumber ?? '');
    return resultado;
  }

  @override
  Future<CepCoordinates?> lookup(String cep, {String? addressNumber}) async =>
      (await lookupFull(cep, addressNumber: addressNumber))?.coordinates;
}

void main() {
  final endereco = find.byKey(const Key('firm_verification_address_field'));
  final cep = find.byKey(const Key('firm_verification_cep_field'));

  Future<void> abrir(WidgetTester tester, _FakeCepService servico) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: LawFirmVerificationFormScreen(
          user: mockCurrentUser,
          cepService: servico,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Digita o CEP e tira o foco — é o blur que dispara a consulta.
  Future<void> digitarCep(WidgetTester tester, String valor) async {
    await tester.enterText(cep, valor);
    await tester.pump();
    await tester.tap(endereco);
    await tester.pumpAndSettle();
  }

  testWidgets('o CEP preenche o endereço, que era digitado à mão', (
    tester,
  ) async {
    final servico = _FakeCepService();
    await abrir(tester, servico);

    await digitarCep(tester, '90540140');

    // O endereço JÁ vinha nesta resposta e era descartado: o envio chamava
    // CepService.lookup, que por dentro é lookupFull(...)?.coordinates. O
    // escritório digitava os ~70 caracteres inteiros.
    expect(servico.consultas, ['90540140']);
    expect(
      find.text(
        'Rua Germano Petersen Júnior, Auxiliadora, Porto Alegre - RS',
      ),
      findsOneWidget,
    );
  });

  testWidgets('endereço já digitado NÃO é sobrescrito', (tester) async {
    final servico = _FakeCepService();
    await abrir(tester, servico);

    await tester.enterText(endereco, 'Rua que eu mesmo escrevi, 70 - sala 1102');
    await tester.pump();
    await digitarCep(tester, '90540140');

    // Sobrescrever apagaria o número e o complemento, que o CEP não sabe — e
    // são justamente eles que distinguem dois escritórios no mesmo CEP.
    expect(
      find.text('Rua que eu mesmo escrevi, 70 - sala 1102'),
      findsOneWidget,
    );
  });

  testWidgets('o mesmo CEP não é consultado duas vezes', (tester) async {
    final servico = _FakeCepService();
    await abrir(tester, servico);

    await digitarCep(tester, '90540140');
    // Volta ao campo e sai de novo, como acontece num preenchimento normal.
    await tester.tap(cep);
    await tester.pumpAndSettle();
    await tester.tap(endereco);
    await tester.pumpAndSettle();

    expect(servico.consultas, ['90540140'], reason: 'uma consulta por CEP');
  });

  testWidgets('CEP que não resolve avisa, em vez de falhar em silêncio', (
    tester,
  ) async {
    final servico = _FakeCepService(resultado: null);
    await abrir(tester, servico);

    await digitarCep(tester, '99999999');

    // Antes a falha morria num debugPrint, que não existe em release: a
    // pessoa ficava olhando um campo que não preenche sem saber se esperou
    // pouco ou digitou errado.
    expect(
      find.textContaining('Não encontramos esse CEP'),
      findsOneWidget,
    );
  });

  testWidgets('CEP incompleto não vai à rede', (tester) async {
    final servico = _FakeCepService();
    await abrir(tester, servico);

    await digitarCep(tester, '905401');

    expect(servico.consultas, isEmpty);
  });

  testWidgets('digitar o número DEPOIS do CEP refina a coordenada', (
    tester,
  ) async {
    final servico = _FakeCepService();
    await abrir(tester, servico);

    await digitarCep(tester, '90540140');
    expect(servico.consultas, ['90540140']);

    // O guarda de deduplicação olha CEP E número: sem isso, quem digita o
    // CEP e só depois o número ficaria com a coordenada no centroide da rua
    // para sempre — o CEP não mudou. Medido: 305 m de diferença.
    await tester.enterText(
      find.byKey(const Key('firm_verification_number_field')),
      '70',
    );
    await tester.pump();
    await tester.tap(endereco);
    await tester.pumpAndSettle();

    expect(servico.numeros, ['', '70']);
  });

  testWidgets('"s/n" não vira busca por número', (tester) async {
    final servico = _FakeCepService();
    await abrir(tester, servico);

    await tester.enterText(
      find.byKey(const Key('firm_verification_number_field')),
      's/n',
    );
    await tester.pump();
    await digitarCep(tester, '90540140');

    // Mandar "s/n" ao Nominatim só faz a busca falhar e cair na rua,
    // gastando uma requisição para nada — quem decide isso é o CepService,
    // então aqui basta garantir que o valor chega até ele.
    expect(servico.numeros, ['s/n']);
  });
}
