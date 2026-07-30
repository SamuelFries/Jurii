import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Barreira anti-injeção no lado do cliente.
///
/// No supabase-dart, `.eq()`, `.rpc(params:)` e afins são parametrizados e
/// seguros. Já `.or()`, `.filter()`, `.not()`, `.textSearch()`, `.like()` e
/// `.ilike()` recebem uma STRING interpretada pela sintaxe do PostgREST:
/// interpolar entrada do usuário ali permite reescrever a lógica do filtro
/// (vazar linhas que a consulta não pretendia) e injetar curinga de LIKE.
///
/// A auditoria de 30/07/2026 mostrou que hoje o app não tem NENHUM desses
/// pontos. Estes testes existem para que isso continue verdade por barreira,
/// e não por lembrança de quem revisa o PR.
void main() {
  final dartSources = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();

  /// Linhas de código (sem comentários) que casam com [pattern].
  List<String> hits(RegExp pattern) {
    final found = <String>[];
    for (final file in dartSources) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (pattern.hasMatch(line)) found.add('${file.path}:${i + 1}: $line');
      }
    }
    return found;
  }

  test('há código Dart para inspecionar', () {
    expect(dartSources, isNotEmpty);
  });

  test('nenhum filtro montado com a sintaxe de string do PostgREST', () {
    // Estes métodos interpretam a string recebida como expressão de filtro.
    // Se um deles for necessário um dia, o valor precisa ser constante e a
    // exceção documentada aqui.
    final forbidden = RegExp(r'\.(or|textSearch|ilike|like|not|match)\s*\(');
    expect(
      hits(forbidden),
      isEmpty,
      reason:
          'Filtro por string do PostgREST é injetável quando recebe entrada '
          'do usuário. Prefira .eq()/.inFilter() ou uma RPC com params.',
    );
  });

  test('nome de RPC é sempre literal', () {
    // .rpc(variavel) permitiria ao chamador escolher a função executada.
    final dynamicRpc = RegExp(r"""\.rpc\(\s*[^'"\s)]""");
    expect(hits(dynamicRpc), isEmpty);
  });

  test('nome de tabela é sempre literal', () {
    // client.from(variavel) permitiria consultar tabela arbitrária.
    final dynamicTable = RegExp(r"""client\.from\(\s*[^'"\s)]""");
    expect(hits(dynamicTable), isEmpty);
  });

  test('.filter() não interpola valor na expressão', () {
    // .filter(coluna, operador, valor): os três viram sintaxe PostgREST.
    final interpolatedFilter = RegExp(r'\.filter\([^)]*\$');
    expect(hits(interpolatedFilter), isEmpty);
  });

  test('nome de coluna em comparação e ordenação é sempre literal', () {
    // .eq('$campo', ...) ou .order('$campo') permitiriam escolher a coluna,
    // vazando dado de outra coluna ou ordenando por campo não previsto.
    final dynamicColumn = RegExp(
      r"""\.(eq|neq|gt|gte|lt|lte|inFilter|order|contains|overlaps)\(\s*['"]?\$""",
    );
    expect(hits(dynamicColumn), isEmpty);
  });
}
