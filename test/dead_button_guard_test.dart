import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Botão morto é pior que botão nenhum: `onTap: () {}` faz o item PARECER
/// habilitado e não responder (os componentes já tratam `null` como
/// desabilitado). Foi assim que Central de Ajuda e Suporte ficaram mudos
/// por meses — e é reprovação clássica de revisão de loja (Apple 2.1).
void main() {
  test('nenhum handler vazio em lib/ (onTap/onPressed: () {})', () {
    final offenders = <String>[];
    final pattern = RegExp(r'on(Tap|Pressed):\s*\(\)\s*\{\s*\}');

    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Handler vazio encontrado. Ou o item ganha uma ação real, ou '
          'recebe null (vira desabilitado), ou sai da tela:\n'
          '${offenders.join('\n')}',
    );
  });
}
