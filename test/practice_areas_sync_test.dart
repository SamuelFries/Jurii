import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/data/legal_practice_areas.dart';

/// Áreas semeadas por uma migration: linhas `  ('Direito X'),` do insert.
///
/// O insert de apelidos da 20260816120000 tem outra forma
/// (`  ('Apelido', array[...]),`) e não casa aqui de propósito.
Set<String> _seedDeAreas(String migration) => RegExp(
  r"^  \('([^']+)'\),?$",
  multiLine: true,
).allMatches(migration).map((m) => m.group(1)!).toSet();

String _migration(String nome) =>
    File('supabase/migrations/$nome').readAsStringSync();

void main() {
  final allowlist = _migration('20260805180000_practice_areas_allowlist.sql');
  final expansao = _migration('20260816120000_practice_areas_expansion.sql');

  test('a lista do app e a allowlist do banco não divergem', () {
    // Desde a 20260805180000 a área de atuação é validada no servidor contra
    // public.legal_practice_areas. Se o app oferecer uma área que a tabela
    // não tem, o profissional marca e o salvamento estoura com "Invalid
    // practice area" — falha só no momento de gravar, que é o pior lugar para
    // descobrir. Área nova = INSERT na migration E entrada aqui.
    final seed = {..._seedDeAreas(allowlist), ..._seedDeAreas(expansao)};

    expect(seed, isNotEmpty, reason: 'seed da allowlist não foi encontrado');
    expect(
      legalPracticeAreas.toSet(),
      seed,
      reason: 'lista do app diverge da allowlist do banco',
    );
  });

  test('todo apelido do banco aponta para uma área que o app oferece', () {
    // Apelido que aponta para área inexistente mapeia o cadastro para o nada,
    // e o nada não aparece em busca nenhuma — em silêncio. O gatilho do banco
    // barra isso na escrita; aqui a barreira é para quem REMOVER uma área da
    // lista sem olhar quem apontava para ela.
    final apelidos = RegExp(
      r"^  \('[^']+', array\[([^\]]+)\]\),?$",
      multiLine: true,
    ).allMatches(expansao);

    expect(apelidos, isNotEmpty, reason: 'seed de apelidos não foi encontrado');

    final alvos = apelidos
        .expand(
          (m) => RegExp(r"'([^']+)'").allMatches(m.group(1)!).map(
            (alvo) => alvo.group(1)!,
          ),
        )
        .toSet();

    expect(
      alvos.difference(legalPracticeAreas.toSet()),
      isEmpty,
      reason: 'apelido aponta para área que a lista do app não tem',
    );
  });

  test('os termos de busca do app e do banco são os mesmos', () {
    // legalSearchIntentRules filtra a busca no modo demo; legal_search_intents
    // faz o mesmo no servidor, para todo mundo. Divergir aqui significa um
    // resultado no app e outro em produção para a MESMA busca — e o de
    // produção é o que o cliente vê.
    //
    // Migrations posteriores podem RESSEMEAR uma área (desativar tudo dela e
    // reinserir a lista completa, como a 20260825120000 faz com Trabalhista).
    // Por isso a leitura é por área com o arquivo mais novo vencendo: o bloco
    // mais recente de uma área é a verdade dela, não a união histórica —
    // união impediria qualquer migration de REMOVER um termo.
    final blocoDeSeed = RegExp(
      r"\n    \(\n"
      r"      array\['([^']+)'\]::text\[\],\n"
      r"      \d+,\n"
      r"      array\[\n"
      r"((?:.|\n)*?)\n"
      r"      \]::text\[\]\n"
      r"    \)",
    );

    // A 20260816 é o marco zero: ela canonicaliza tudo que veio antes (a área
    // "Acidente de Trânsito" do baseline, por exemplo, virou apelido de
    // Direito Cível). Seed anterior a ela descreve um mundo que a própria
    // migration reescreveu, então não entra na comparação.
    final arquivosComSeed =
        Directory('supabase/migrations')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sql'))
            .where((f) => f.uri.pathSegments.last.compareTo('20260816') >= 0)
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final doBanco = <String, Set<String>>{};
    var arquivosLidos = 0;
    for (final arquivo in arquivosComSeed) {
      final blocos = blocoDeSeed.allMatches(arquivo.readAsStringSync());
      if (blocos.isEmpty) continue;
      arquivosLidos++;
      // Dentro do mesmo arquivo, blocos repetidos da área se somam; entre
      // arquivos, o mais novo substitui.
      final doArquivo = <String, Set<String>>{};
      for (final bloco in blocos) {
        final area = bloco.group(1)!;
        final termos = RegExp(r"^        '((?:[^']|'')*)',?$", multiLine: true)
            .allMatches(bloco.group(2)!)
            .map((m) => m.group(1)!.replaceAll("''", "'"))
            .toSet();
        doArquivo.putIfAbsent(area, () => <String>{}).addAll(termos);
      }
      doArquivo.forEach((area, termos) => doBanco[area] = termos);
    }

    expect(
      arquivosLidos,
      greaterThanOrEqualTo(1),
      reason: 'seed de termos não foi encontrado em migration nenhuma',
    );

    final doApp = <String, Set<String>>{};
    for (final regra in legalSearchIntentRules) {
      for (final area in regra.practiceAreas) {
        doApp.putIfAbsent(area, () => <String>{}).addAll(regra.terms);
      }
    }

    expect(
      doBanco.keys.toSet(),
      doApp.keys.toSet(),
      reason: 'as áreas com termos diferem entre app e banco',
    );
    for (final area in doApp.keys) {
      expect(
        doBanco[area],
        doApp[area],
        reason: 'os termos de $area diferem entre app e banco',
      );
    }
  });

  test('toda área da lista tem termo de busca', () {
    // Área sem termo só é achável por quem digita o nome exato dela. Ninguém
    // procura advogado digitando "Direito Securitário"; digita "seguradora
    // negou".
    final comTermo = legalSearchIntentRules
        .expand((regra) => regra.practiceAreas)
        .toSet();

    expect(
      legalPracticeAreas.toSet().difference(comTermo),
      isEmpty,
      reason: 'área sem nenhum termo de busca livre',
    );
  });

  test('nenhum termo de busca aponta para área fora da lista', () {
    final areas = legalPracticeAreas.toSet();
    final orfas = legalSearchIntentRules
        .expand((regra) => regra.practiceAreas)
        .toSet()
        .difference(areas);

    expect(orfas, isEmpty, reason: 'regra de busca aponta para área inexistente');
  });
}
