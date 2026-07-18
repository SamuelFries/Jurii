import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/lawyer_status.dart';
import 'package:jurii/models/profile_avatar_file.dart';
import 'package:jurii/models/user_profile.dart';
import 'package:jurii/screens/edit_profile_screen.dart';
import 'package:jurii/screens/profile_screen.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/utils/phone_input_formatter.dart';
import 'package:jurii/utils/validators.dart';

const _profile = UserProfile(
  id: 'user-1',
  name: 'Ana Souza',
  email: 'ana@jurii.dev',
  initials: 'AS',
  memberSince: 'Cliente desde 2026',
  lawyerStatus: LawyerStatus.client,
  cpf: '52998224725',
  phone: '51999998888',
);

Widget _app(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: child),
  );
}

Future<void> _openEditor(
  WidgetTester tester, {
  required ProfileEditSubmit onSubmit,
  UserProfile profile = _profile,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) =>
                      EditProfileScreen(profile: profile, onSubmit: onSubmit),
                ),
              ),
              child: const Text('Abrir edição'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir edição'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('preenche dados atuais e protege e-mail e CPF', (tester) async {
    Future<void> submit({
      required String fullName,
      required String phone,
      ProfileAvatarFile? avatar,
      required bool removeAvatar,
    }) async {}

    await tester.pumpWidget(
      _app(EditProfileScreen(profile: _profile, onSubmit: submit)),
    );

    expect(find.text('Editar perfil'), findsOneWidget);
    expect(find.text('Ana Souza'), findsOneWidget);
    expect(find.text('(51) 99999-8888'), findsOneWidget);
    expect(find.text('ana@jurii.dev'), findsOneWidget);
    expect(find.text('529.982.247-25'), findsOneWidget);
    expect(find.text('Vinculado ao método de acesso da conta'), findsOneWidget);
    expect(find.text('Dado de identificação protegido'), findsOneWidget);
  });

  testWidgets('valida nome completo e telefone antes de salvar', (
    tester,
  ) async {
    var submissions = 0;
    Future<void> submit({
      required String fullName,
      required String phone,
      ProfileAvatarFile? avatar,
      required bool removeAvatar,
    }) async {
      submissions++;
    }

    await tester.pumpWidget(
      _app(EditProfileScreen(profile: _profile, onSubmit: submit)),
    );
    await tester.enterText(find.byKey(const Key('edit_profile_name')), 'Ana');
    await tester.enterText(
      find.byKey(const Key('edit_profile_phone')),
      '51999',
    );
    final save = find.byKey(const Key('edit_profile_save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();

    expect(find.text('Informe nome e sobrenome'), findsOneWidget);
    expect(find.text('Informe um telefone com DDD'), findsOneWidget);
    expect(submissions, 0);
  });

  testWidgets('envia dados normalizados e volta após sucesso', (tester) async {
    String? submittedName;
    String? submittedPhone;
    bool? submittedRemoval;
    Future<void> submit({
      required String fullName,
      required String phone,
      ProfileAvatarFile? avatar,
      required bool removeAvatar,
    }) async {
      submittedName = fullName;
      submittedPhone = phone;
      submittedRemoval = removeAvatar;
    }

    await _openEditor(tester, onSubmit: submit);
    await tester.enterText(
      find.byKey(const Key('edit_profile_name')),
      '  Ana Maria  ',
    );
    await tester.enterText(
      find.byKey(const Key('edit_profile_phone')),
      '+55 (51) 3333-4444',
    );
    final save = find.byKey(const Key('edit_profile_save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(submittedName, 'Ana Maria');
    expect(submittedPhone, '5133334444');
    expect(submittedRemoval, isFalse);
    expect(find.text('Abrir edição'), findsOneWidget);
  });

  testWidgets('envia telefone vazio para solicitar remoção', (tester) async {
    String? submittedPhone;
    Future<void> submit({
      required String fullName,
      required String phone,
      ProfileAvatarFile? avatar,
      required bool removeAvatar,
    }) async {
      submittedPhone = phone;
    }

    await _openEditor(tester, onSubmit: submit);
    await tester.enterText(find.byKey(const Key('edit_profile_phone')), '');
    final save = find.byKey(const Key('edit_profile_save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(submittedPhone, '');
  });

  testWidgets('impede telefone gigante sem causar overflow', (tester) async {
    Future<void> submit({
      required String fullName,
      required String phone,
      ProfileAvatarFile? avatar,
      required bool removeAvatar,
    }) async {}

    await tester.pumpWidget(
      _app(EditProfileScreen(profile: _profile, onSubmit: submit)),
    );
    final phoneFinder = find.byKey(const Key('edit_profile_phone'));
    final field = tester.widget<TextFormField>(phoneFinder);

    await tester.enterText(phoneFinder, '519999988881234567890123456789');
    await tester.pump();

    expect(field.controller!.text, '(51) 99999-8888');
    expect(
      field.controller!.text.length,
      lessThanOrEqualTo(maxFormattedBrazilianPhoneCharacters),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('limita nome gigante sem causar overflow', (tester) async {
    Future<void> submit({
      required String fullName,
      required String phone,
      ProfileAvatarFile? avatar,
      required bool removeAvatar,
    }) async {}

    await tester.pumpWidget(
      _app(EditProfileScreen(profile: _profile, onSubmit: submit)),
    );
    final nameFinder = find.byKey(const Key('edit_profile_name'));
    final field = tester.widget<TextFormField>(nameFinder);

    await tester.enterText(nameFinder, 'Ana ${List.filled(500, 'S').join()}');
    await tester.pump();

    expect(field.controller!.text.length, kMaxFullNameCharacters);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bloqueia submissão duplicada enquanto salva', (tester) async {
    final completion = Completer<void>();
    var submissions = 0;
    Future<void> submit({
      required String fullName,
      required String phone,
      ProfileAvatarFile? avatar,
      required bool removeAvatar,
    }) {
      submissions++;
      return completion.future;
    }

    await _openEditor(tester, onSubmit: submit);
    final save = find.byKey(const Key('edit_profile_save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    await tester.tap(save);

    expect(submissions, 1);
    completion.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('marca a foto atual para remoção', (tester) async {
    bool? submittedRemoval;
    Future<void> submit({
      required String fullName,
      required String phone,
      ProfileAvatarFile? avatar,
      required bool removeAvatar,
    }) async {
      submittedRemoval = removeAvatar;
    }

    await _openEditor(
      tester,
      onSubmit: submit,
      profile: _profile.copyWith(
        avatarUrl: 'https://example.com/storage/avatar.png',
      ),
    );
    await tester.tap(find.text('Remover foto'));
    await tester.pump();
    expect(find.text('Foto removida'), findsOneWidget);

    final save = find.byKey(const Key('edit_profile_save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(submittedRemoval, isTrue);
  });

  testWidgets('mantém a tela e informa erro quando persistência falha', (
    tester,
  ) async {
    Future<void> submit({
      required String fullName,
      required String phone,
      ProfileAvatarFile? avatar,
      required bool removeAvatar,
    }) async {
      throw StateError('storage unavailable');
    }

    await _openEditor(tester, onSubmit: submit);
    final save = find.byKey(const Key('edit_profile_save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(find.text('Editar perfil'), findsOneWidget);
    expect(
      find.text('Não foi possível atualizar a foto. Tente outra imagem.'),
      findsOneWidget,
    );
  });

  testWidgets('lápis do perfil abre a edição', (tester) async {
    Future<void> submit({
      required String fullName,
      required String phone,
      ProfileAvatarFile? avatar,
      required bool removeAvatar,
    }) async {}

    await tester.pumpWidget(
      _app(ProfileScreen(user: _profile, onEditProfile: submit)),
    );
    await tester.tap(find.byKey(const Key('profile_edit_button')));
    await tester.pumpAndSettle();

    expect(find.byType(EditProfileScreen), findsOneWidget);
  });

  testWidgets('Dados Pessoais abre a mesma edição', (tester) async {
    Future<void> submit({
      required String fullName,
      required String phone,
      ProfileAvatarFile? avatar,
      required bool removeAvatar,
    }) async {}

    await tester.pumpWidget(
      _app(ProfileScreen(user: _profile, onEditProfile: submit)),
    );
    final personalData = find.text('Dados Pessoais');
    await tester.scrollUntilVisible(
      personalData,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(personalData);
    await tester.pumpAndSettle();

    expect(find.byType(EditProfileScreen), findsOneWidget);
  });
}
