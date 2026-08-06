import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('o seletor pede os bytes na web, senão nada é lido lá', () {
    // Não dá para exercitar isto num teste: kIsWeb é falso aqui. Então a
    // barreira é de código-fonte, e ela existe porque a falha é silenciosa e
    // total.
    //
    // Sem `withData`, o file_picker devolve `bytes: null` na web, e
    // PlatformFile.xFile faz `XFile.fromData(bytes!)` — o `!` estoura, a
    // leitura vira null e TODO seletor do app responde "não foi possível ler
    // o arquivo": foto de perfil, documento do chat, vídeo e documento de
    // verificação, todos de uma vez, sem pista nenhuma da causa.
    final fonte = File('lib/utils/safe_file_picker.dart').readAsStringSync();

    expect(
      fonte,
      contains('withData: kIsWeb'),
      reason: 'sem isto, nenhum arquivo é lido no navegador',
    );
  });

  test('e NÃO pede os bytes no celular', () {
    // `withData: true` fixo carregaria o arquivo inteiro na memória já na
    // escolha — antes da checagem de tamanho. Um vídeo de 800 MB escolhido
    // por engano viraria OOM, que é exatamente o que SafePickedFile evita.
    final fonte = File('lib/utils/safe_file_picker.dart').readAsStringSync();

    expect(fonte, isNot(contains('withData: true')));
  });
}
