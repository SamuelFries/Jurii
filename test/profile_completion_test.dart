import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/lawyer_status.dart';
import 'package:jurii/models/user_profile.dart';
import 'package:jurii/screens/complete_profile_screen.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/utils/validators.dart';

UserProfile _profile({
  String name = 'Maria Silva',
  String email = 'maria.silva@gmail.com',
  String? cpf = '52998224725',
}) {
  return UserProfile(
    id: 'user-1',
    name: name,
    email: email,
    initials: 'MS',
    memberSince: 'Cliente desde 2026',
    lawyerStatus: LawyerStatus.client,
    cpf: cpf,
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(theme: AppTheme.lightTheme, home: child);
}

void main() {
  group('isCompleteName', () {
    test('exige nome e sobrenome', () {
      expect(isCompleteName('Maria Silva'), isTrue);
      expect(isCompleteName('  Maria   de Souza '), isTrue);
      expect(isCompleteName('Maria'), isFalse);
      expect(isCompleteName(''), isFalse);
    });

    test('inicial solta não conta como sobrenome', () {
      expect(isCompleteName('Maria S'), isFalse);
    });
  });

  group('UserProfile.needsProfileCompletion', () {
    test('perfil completo passa direto', () {
      expect(_profile().needsProfileCompletion, isFalse);
    });

    test('login social sem CPF é barrado (Google entrega nome, não CPF)', () {
      expect(_profile(cpf: null).needsProfileCompletion, isTrue);
    });

    test('CPF inválido é barrado', () {
      expect(_profile(cpf: '11111111111').needsProfileCompletion, isTrue);
    });

    test('nome derivado do e-mail é barrado (Apple sem nome)', () {
      final profile = _profile(
        name: 'pedro.fries68',
        email: 'pedro.fries68@icloud.com',
      );
      expect(profile.needsProfileCompletion, isTrue);
    });

    test('fallback do gatilho é barrado', () {
      expect(_profile(name: 'Usuário Jurii').needsProfileCompletion, isTrue);
    });
  });

  testWidgets('cobra nome completo e CPF válido antes de liberar', (
    tester,
  ) async {
    var submits = 0;

    await tester.pumpWidget(
      _wrap(
        CompleteProfileScreen(
          profile: _profile(name: 'pedro', email: 'pedro@icloud.com', cpf: null),
          onSubmit: ({required String fullName, required String cpf}) async =>
              submits++,
          onLogout: () {},
        ),
      ),
    );

    // Nome derivado do e-mail não pré-preenche o campo.
    expect(find.text('pedro'), findsNothing);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('Informe seu nome completo'), findsOneWidget);
    expect(find.text('Informe um CPF válido'), findsOneWidget);
    expect(submits, 0);

    await tester.enterText(find.byType(TextFormField).first, 'Pedro');
    await tester.enterText(find.byType(TextFormField).last, '111.111.111-11');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('Informe nome e sobrenome'), findsOneWidget);
    expect(find.text('Informe um CPF válido'), findsOneWidget);
    expect(submits, 0);
  });

  testWidgets('envia nome limpo e CPF só com dígitos', (tester) async {
    String? sentName;
    String? sentCpf;

    await tester.pumpWidget(
      _wrap(
        CompleteProfileScreen(
          profile: _profile(name: 'Maria Silva', cpf: null),
          onSubmit: ({required String fullName, required String cpf}) async {
            sentName = fullName;
            sentCpf = cpf;
          },
          onLogout: () {},
        ),
      ),
    );

    // Nome real vindo do Google entra pré-preenchido: o usuário só confere.
    expect(find.text('Maria Silva'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).last, '529.982.247-25');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(sentName, 'Maria Silva');
    expect(sentCpf, '52998224725');
  });

  testWidgets('CPF de outra conta explica o motivo, não pede "CPF válido"', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CompleteProfileScreen(
          profile: _profile(cpf: null),
          onSubmit: ({required String fullName, required String cpf}) async {
            throw Exception('PostgrestException: CPF already registered');
          },
          onLogout: () {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).last, '529.982.247-25');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('já está em uso em outra conta'),
      findsOneWidget,
    );
    expect(find.text('Informe um CPF válido.'), findsNothing);
  });

  testWidgets('sempre há saída: sair da conta', (tester) async {
    var loggedOut = 0;

    await tester.pumpWidget(
      _wrap(
        CompleteProfileScreen(
          profile: _profile(cpf: null),
          onSubmit: ({required String fullName, required String cpf}) async {},
          onLogout: () => loggedOut++,
        ),
      ),
    );

    await tester.tap(find.text('Sair da conta'));
    expect(loggedOut, 1);
  });
}
