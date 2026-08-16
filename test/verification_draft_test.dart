import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/lawyer_status.dart';
import 'package:jurii/models/user_profile.dart';
import 'package:jurii/screens/lawyer_verification_form_screen.dart';
import 'package:jurii/services/form_draft_store.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// O rascunho da verificação.
///
/// O formulário tem onze passos; uma ligação no meio e tudo que a pessoa
/// digitou evaporava. O rascunho devolve os CAMPOS na volta — os arquivos
/// não (bytes vivem só na memória, decisão antiga e boa), e re-escolher dois
/// arquivos custa dois toques contra redigitar o formulário inteiro.
const _user = UserProfile(
  id: 'u1',
  name: 'Advogada Rascunho',
  email: 'r@x.com',
  initials: 'AR',
  memberSince: '2026-01-01',
  lawyerStatus: LawyerStatus.client,
);

Widget _form({FormDraftStore store = const FormDraftStore()}) => MaterialApp(
  theme: AppTheme.lightTheme,
  home: LawyerVerificationFormScreen(user: _user, draftStore: store),
);

/// Um store cujo load só aterrissa quando o teste mandar: é o único jeito de
/// provar a corrida "pessoa digitou antes de o disco responder".
class _StoreLento extends FormDraftStore {
  _StoreLento();

  final Completer<Map<String, dynamic>?> _entrega = Completer();

  @override
  Future<Map<String, dynamic>?> load(String key) => _entrega.future;

  void entrega(Map<String, dynamic> draft) => _entrega.complete(draft);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FormDraftStore', () {
    test('salva, devolve e limpa', () async {
      const store = FormDraftStore();
      await store.save(FormDraftStore.lawyerVerificationKey, {
        'oab': '123456',
        'uf': 'RS',
        'areas': ['Direito Cível'],
      });

      final draft = await store.load(FormDraftStore.lawyerVerificationKey);
      expect(draft?['oab'], '123456');
      expect(draft?['uf'], 'RS');
      expect(draft?['areas'], ['Direito Cível']);

      await store.clear(FormDraftStore.lawyerVerificationKey);
      expect(
        await store.load(FormDraftStore.lawyerVerificationKey),
        isNull,
      );
    });

    test('rascunho todo vazio vira rascunho nenhum', () async {
      // Guardar "{}" faria a volta parecer restauração de algo.
      const store = FormDraftStore();
      await store.save(FormDraftStore.lawyerVerificationKey, {
        'oab': '  ',
        'uf': null,
        'areas': const <String>[],
      });
      expect(
        await store.load(FormDraftStore.lawyerVerificationKey),
        isNull,
      );
    });
  });

  group('formulário do advogado', () {
    testWidgets('o que se digita sobrevive a fechar e voltar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '987654');
      await tester.pumpAndSettle();

      // "Fechar o app": derruba a árvore inteira.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // "Abrir de novo": o campo volta preenchido.
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();

      final campo = tester.widget<TextField>(find.byType(TextField).first);
      expect(campo.controller?.text, '987654');
    });

    testWidgets('rascunho não atropela o que a pessoa já digitou', (
      tester,
    ) async {
      // A restauração é assíncrona. Com o mock de prefs o load aterrissa
      // antes de qualquer digitação e a corrida real nunca acontece no
      // teste; o store lento segura a entrega até DEPOIS de digitar, que é
      // a ordem em que o rascunho velho poderia engolir o texto novo.
      final store = _StoreLento();

      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_form(store: store));
      await tester.enterText(find.byType(TextField).first, '222222');
      await tester.pump();

      store.entrega({'oab': '111111', 'uf': null, 'areas': const []});
      await tester.pumpAndSettle();

      final campo = tester.widget<TextField>(find.byType(TextField).first);
      expect(campo.controller?.text, '222222');
    });
  });
}
