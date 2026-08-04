import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/firm_role.dart';

void main() {
  test('owner é rotulado como Sócio, mas o valor do banco não muda', () {
    // 'owner' é identificador: dezenas de RPCs fazem
    // `roles && array['owner', 'admin']`. Trocar o value quebraria todos os
    // gates do escritório em silêncio — o rótulo é a única coisa que muda.
    expect(FirmRole.owner.value, 'owner');
    expect(FirmRole.owner.label, 'Sócio(a)');
    expect(FirmRole.owner.shortLabel, 'Sócio');
    expect(FirmRole.fromValue('owner'), FirmRole.owner);
    expect([FirmRole.owner, FirmRole.admin].values, ['owner', 'admin']);
  });

  test('nenhuma tela do fluxo de escritório ainda diz "dono"', () {
    // Varredura de fonte: as mensagens vivem espalhadas por snackbars e
    // tradutores de erro do servidor, e um "dono" esquecido num deles só
    // apareceria no momento exato da falha.
    final telas = [
      'lib/models/firm_role.dart',
      'lib/screens/firm_team_screen.dart',
      'lib/screens/firm_cases_screen.dart',
      'lib/screens/firm_profile_screen.dart',
      'lib/screens/firm_messages_screen.dart',
      'lib/screens/law_firm_verification_screen.dart',
    ];

    for (final caminho in telas) {
      final fonte = File(caminho).readAsStringSync();
      expect(
        RegExp(r'[Dd]ono').hasMatch(fonte),
        isFalse,
        reason: '$caminho ainda usa "dono"',
      );
    }
  });
}
