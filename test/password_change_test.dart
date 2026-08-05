import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/repositories/auth_repository.dart';
import 'package:jurii/screens/change_password_screen.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/utils/password_change.dart';

/// Conta com senha própria, que é o caso comum.
class _FakeAuth extends AuthRepository {
  _FakeAuth({this.hasPassword = true, this.erro});

  final bool hasPassword;
  final Object? erro;

  String? senhaAtualRecebida;
  String? senhaNovaRecebida;
  int chamadas = 0;

  @override
  bool get hasEmailPassword => hasPassword;

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    chamadas++;
    senhaAtualRecebida = currentPassword;
    senhaNovaRecebida = newPassword;
    if (erro != null) throw erro!;
  }
}

void main() {
  group('regras da troca', () {
    test('senha atual é obrigatória para quem tem senha', () {
      final r = validatePasswordChange(
        currentPassword: '',
        newPassword: 'novaSenha1!',
        confirmation: 'novaSenha1!',
        requiresCurrentPassword: true,
      );
      expect(r.isValid, isFalse);
      expect(r.error, contains('senha atual'));
    });

    test('quem entrou por Google não precisa da senha atual', () {
      // Exigir uma senha que nunca existiu seria um beco sem saída.
      final r = validatePasswordChange(
        currentPassword: '',
        newPassword: 'novaSenha1!',
        confirmation: 'novaSenha1!',
        requiresCurrentPassword: false,
      );
      expect(r.isValid, isTrue);
    });

    test('confirmação diferente é recusada', () {
      final r = validatePasswordChange(
        currentPassword: 'atual123',
        newPassword: 'novaSenha1!',
        confirmation: 'novaSenha1?',
        requiresCurrentPassword: true,
      );
      expect(r.isValid, isFalse);
      expect(r.error, contains('confirmação'));
    });

    test('nova igual à atual não é troca', () {
      // Sem isto a pessoa sai da tela achando que girou a credencial, e ela
      // continua a mesma.
      final r = validatePasswordChange(
        currentPassword: 'mesmaSenha1!',
        newPassword: 'mesmaSenha1!',
        confirmation: 'mesmaSenha1!',
        requiresCurrentPassword: true,
      );
      expect(r.isValid, isFalse);
      expect(r.error, contains('diferente'));
    });

    test('senha curta é recusada pela política do app', () {
      final r = validatePasswordChange(
        currentPassword: 'atual123',
        newPassword: 'curta',
        confirmation: 'curta',
        requiresCurrentPassword: true,
      );
      expect(r.isValid, isFalse);
    });
  });

  group('erro do servidor vira texto que faz sentido nesta tela', () {
    test('credencial inválida vira "senha atual incorreta"', () {
      // A senha atual é conferida com um login; o servidor responde o mesmo
      // "invalid login credentials" do login normal, que aqui não faz sentido
      // nenhum — a pessoa já está logada.
      expect(
        friendlyPasswordChangeError(
          Exception('AuthApiException: Invalid login credentials'),
        ),
        'Senha atual incorreta.',
      );
    });

    test('limite de tentativas é explicado, não escondido', () {
      expect(
        friendlyPasswordChangeError(Exception('Rate limit exceeded')),
        contains('Muitas tentativas'),
      );
    });

    test('erro desconhecido não vaza detalhe técnico', () {
      final texto = friendlyPasswordChangeError(
        Exception('PostgrestException(code: 42501, details: ...)'),
      );
      expect(texto, 'Não foi possível alterar a senha. Tente novamente.');
    });
  });

  group('força da senha', () {
    test('cresce com tamanho, caixa e símbolo', () {
      expect(passwordStrength('curta'), 0);
      expect(passwordStrength('somenteminuscula'), 1);
      expect(passwordStrength('ComMaiuscula1'), 2);
      expect(passwordStrength('ComMaiuscula1!'), 3);
    });
  });

  group('tela', () {
    Widget app(AuthRepository repo) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: ChangePasswordScreen(repository: repo),
    );

    testWidgets('pede a senha atual de quem tem senha', (tester) async {
      await tester.pumpWidget(app(_FakeAuth()));
      await tester.pumpAndSettle();

      expect(find.text('Senha atual'), findsOneWidget);
      expect(find.text('Nova senha'), findsOneWidget);
      expect(find.text('Confirmar nova senha'), findsOneWidget);
    });

    testWidgets('não pede senha atual de quem entra por Google', (
      tester,
    ) async {
      await tester.pumpWidget(app(_FakeAuth(hasPassword: false)));
      await tester.pumpAndSettle();

      expect(find.text('Senha atual'), findsNothing);
      expect(find.textContaining('Google'), findsOneWidget);
    });

    testWidgets('envia as duas senhas ao repositório', (tester) async {
      final repo = _FakeAuth();
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'atualSenha1!');
      await tester.enterText(find.byType(TextFormField).at(1), 'novaSenha1!');
      await tester.enterText(find.byType(TextFormField).at(2), 'novaSenha1!');
      await tester.tap(find.text('Salvar nova senha'));
      await tester.pumpAndSettle();

      expect(repo.senhaAtualRecebida, 'atualSenha1!');
      expect(repo.senhaNovaRecebida, 'novaSenha1!');
    });

    testWidgets('senha atual errada não fecha a tela', (tester) async {
      final repo = _FakeAuth(
        erro: Exception('AuthApiException: Invalid login credentials'),
      );
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'errada123');
      await tester.enterText(find.byType(TextFormField).at(1), 'novaSenha1!');
      await tester.enterText(find.byType(TextFormField).at(2), 'novaSenha1!');
      await tester.tap(find.text('Salvar nova senha'));
      await tester.pumpAndSettle();

      // Fechar a tela num erro faria a pessoa achar que trocou.
      expect(find.text('Senha atual incorreta.'), findsOneWidget);
      expect(find.text('Salvar nova senha'), findsOneWidget);
    });

    testWidgets('confirmação diferente nem chega ao servidor', (tester) async {
      final repo = _FakeAuth();
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'atualSenha1!');
      await tester.enterText(find.byType(TextFormField).at(1), 'novaSenha1!');
      await tester.enterText(find.byType(TextFormField).at(2), 'outraCoisa1!');
      await tester.tap(find.text('Salvar nova senha'));
      await tester.pumpAndSettle();

      expect(repo.chamadas, 0);
    });
  });
}
