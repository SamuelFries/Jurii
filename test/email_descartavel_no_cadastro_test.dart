import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/repositories/email_policy_repository.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/types/auth_callbacks.dart';
import 'package:jurii/widgets/register_form.dart';

/// O cadastro não aceita e-mail descartável.
///
/// A barreira de verdade é o gatilho em auth.users (provado em
/// supabase/tests/email_descartavel_test.sql, e medido pela API real). O que
/// este arquivo trava é a parte da TELA: dizer o motivo antes de enviar, não
/// enviar o cadastro que o servidor vai recusar, e traduzir a recusa do
/// servidor quando ela escapar pela checagem prévia.
class _PoliticaFalsa implements EmailPolicyRepository {
  _PoliticaFalsa({this.descartavel = false, this.estoura = false});

  final bool descartavel;
  final bool estoura;
  final List<String> perguntados = <String>[];

  @override
  Future<bool> ehDescartavel(String email) async {
    perguntados.add(email);
    // Sem rede, quem decide é o banco: a tela não pode travar o cadastro.
    if (estoura) return false;
    return descartavel;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const String _recado =
    'Use um e-mail permanente. Endereços descartáveis não são aceitos';

/// Os campos não têm chave; a ordem no formulário é nome, e-mail, CPF, senha
/// e confirmação (lib/widgets/register_form.dart). Se alguém trocar a ordem,
/// a validação do formulário reprova e o teste cai, que é o aviso certo.
Future<void> _preenche(WidgetTester tester, {required String email}) async {
  final campos = find.byType(TextFormField);
  await tester.enterText(campos.at(0), 'Ana Souza');
  await tester.enterText(campos.at(1), email);
  // CPF válido pelo dígito verificador: o formulário recusa qualquer outro.
  await tester.enterText(campos.at(2), '52998224725');
  await tester.enterText(campos.at(3), 'SenhaForte!2026');
  await tester.enterText(campos.at(4), 'SenhaForte!2026');
  await tester.pump();
}

Widget _tela({
  required EmailPolicyRepository politica,
  required RegisterSubmit onRegister,
}) => MaterialApp(
  theme: AppTheme.lightTheme,
  home: Scaffold(
    body: SingleChildScrollView(
      child: RegisterForm(
        onRegister: onRegister,
        emailPolicyRepository: politica,
      ),
    ),
  ),
);

void main() {
  testWidgets('e-mail descartável: diz o motivo e NÃO envia o cadastro', (
    tester,
  ) async {
    final politica = _PoliticaFalsa(descartavel: true);
    var enviou = 0;
    await tester.pumpWidget(
      _tela(
        politica: politica,
        onRegister:
            ({
              required fullName,
              required email,
              required cpf,
              required password,
            }) async {
              enviou++;
              return RegisterResult.signedIn;
            },
      ),
    );

    await _preenche(tester, email: 'abusador@mailinator.com');
    await tester.tap(find.text('Criar conta'));
    await tester.pumpAndSettle();

    expect(find.textContaining(_recado), findsOneWidget);
    // O que importa: o cadastro nem sai. Sem isto a pessoa esperaria o
    // servidor recusar para só então ler o motivo.
    expect(enviou, 0);
    expect(politica.perguntados, ['abusador@mailinator.com']);
  });

  testWidgets('e-mail legítimo: segue o cadastro normalmente', (tester) async {
    final politica = _PoliticaFalsa();
    var enviou = 0;
    await tester.pumpWidget(
      _tela(
        politica: politica,
        onRegister:
            ({
              required fullName,
              required email,
              required cpf,
              required password,
            }) async {
              enviou++;
              return RegisterResult.needsEmailConfirmation;
            },
      ),
    );

    await _preenche(tester, email: 'ana@gmail.com');
    await tester.tap(find.text('Criar conta'));
    await tester.pumpAndSettle();

    expect(enviou, 1);
    expect(find.textContaining(_recado), findsNothing);
  });

  testWidgets('sem rede para checar: o cadastro segue e o banco decide', (
    tester,
  ) async {
    final politica = _PoliticaFalsa(estoura: true);
    var enviou = 0;
    await tester.pumpWidget(
      _tela(
        politica: politica,
        onRegister:
            ({
              required fullName,
              required email,
              required cpf,
              required password,
            }) async {
              enviou++;
              return RegisterResult.needsEmailConfirmation;
            },
      ),
    );

    await _preenche(tester, email: 'ana@gmail.com');
    await tester.tap(find.text('Criar conta'));
    await tester.pumpAndSettle();

    // Errar para o lado de deixar seguir só adianta a recusa para quem tem a
    // palavra final; travar aqui derrubaria cadastro legítimo por causa de
    // uma consulta que falhou.
    expect(enviou, 1);
  });

  testWidgets('recusa do servidor é traduzida (quando escapa da checagem)', (
    tester,
  ) async {
    final politica = _PoliticaFalsa();
    await tester.pumpWidget(
      _tela(
        politica: politica,
        onRegister:
            ({
              required fullName,
              required email,
              required cpf,
              required password,
            }) async {
              throw Exception('Disposable email domains are not allowed');
            },
      ),
    );

    await _preenche(tester, email: 'ana@gmail.com');
    await tester.tap(find.text('Criar conta'));
    await tester.pumpAndSettle();

    // A MESMA frase da checagem prévia: ninguém lê duas explicações
    // diferentes para o mesmo não.
    expect(find.textContaining(_recado), findsOneWidget);
  });
}
