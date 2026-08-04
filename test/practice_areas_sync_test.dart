import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/data/legal_practice_areas.dart';

void main() {
  test('a lista do app e a allowlist do banco não divergem', () {
    // Desde a 20260805180000 a área de atuação é validada no servidor contra
    // public.legal_practice_areas. Se o app oferecer uma área que a tabela
    // não tem, o advogado marca e o salvamento estoura com "Invalid practice
    // area" — falha só no momento de gravar, que é o pior lugar para
    // descobrir. Área nova = INSERT na migration E entrada aqui.
    final migration = File(
      'supabase/migrations/20260805180000_practice_areas_allowlist.sql',
    ).readAsStringSync();

    final seed = RegExp(r"^  \('([^']+)'\),?$", multiLine: true)
        .allMatches(migration)
        .map((m) => m.group(1)!)
        .toSet();

    expect(seed, isNotEmpty, reason: 'seed da allowlist não foi encontrado');
    expect(
      legalPracticeAreas.toSet(),
      seed,
      reason: 'lista do app diverge da allowlist do banco',
    );
  });
}
