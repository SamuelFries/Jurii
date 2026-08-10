import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// O DEFEITO QUE ISTO TRAVA: "Permissões da equipe", no perfil do escritório,
/// abria um snackbar "Em preparação. Disponível em breve." enquanto a edição
/// de permissões JÁ EXISTIA e funcionava na aba Equipe, com toggles de papel
/// ligados até a RPC update_law_firm_member_roles.
///
/// Não era feature por fazer: era link morto para coisa pronta. Item de menu
/// que anuncia, aceita o toque e não faz nada é pior que item ausente, porque
/// a pessoa toca de novo achando que errou a mira. É também o placeholder que
/// a revisão da loja reprova.
void main() {
  test('nenhuma tela promete "em breve" para o usuário', () {
    final telas = Directory('lib/screens')
        .listSync(recursive: true)
        .whereType<File>()
        .where((arquivo) => arquivo.path.endsWith('.dart'));

    final acusadas = <String>[];
    for (final tela in telas) {
      for (final linha in tela.readAsLinesSync()) {
        final semComentario = linha.trim();
        // Comentário pode CONTAR a história ("até aqui abria em breve") sem
        // ser promessa na tela. O que não pode é a frase dentro de uma string
        // que a pessoa lê.
        if (semComentario.startsWith('//') || semComentario.startsWith('///')) {
          continue;
        }
        final minuscula = semComentario.toLowerCase();
        if (!minuscula.contains("'") && !minuscula.contains('"')) continue;
        // "Em preparação" sozinho é STATUS verdadeiro: a verificação do
        // escritório está mesmo em análise. O que não pode é prometer prazo
        // para funcionalidade que não existe.
        if (minuscula.contains('em breve') ||
            minuscula.contains('em construção')) {
          acusadas.add('${tela.path}: $semComentario');
        }
      }
    }

    expect(
      acusadas,
      isEmpty,
      reason:
          'tela prometendo o que não entrega:\n${acusadas.join('\n')}\n'
          'Se a funcionalidade existe, aponte o item para ela. Se não '
          'existe, tire o item em vez de anunciá-lo.',
    );
  });
}
