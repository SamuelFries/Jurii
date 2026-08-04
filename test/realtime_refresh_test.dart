import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/services/realtime_refresh.dart';

/// Host mínimo: sem Supabase inicializado o mixin não assina nada, que é
/// exatamente o contrato do modo demo/teste — nenhuma exceção, nenhum canal.
class _Host extends StatefulWidget {
  const _Host({required this.onChange});
  final VoidCallback onChange;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with RealtimeRefresh<_Host> {
  @override
  void initState() {
    super.initState();
    subscribeToRealtime(
      channelName: 'teste',
      table: 'messages',
      event: PostgresChangeEvent.insert,
      onChange: widget.onChange,
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  testWidgets('sem Supabase pronto não assina nem quebra', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(home: _Host(onChange: () => calls++)),
    );
    await tester.pumpAndSettle();

    expect(calls, 0);

    // dispose do mixin não pode estourar sem canal aberto.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
  });

  test('as três listas de conversa assinam messages', () {
    // O ganho é a lista mexer sozinha quando chega mensagem; se alguém
    // remover a assinatura de uma delas, a tela volta a congelar em silêncio
    // (nenhum teste de widget pega isso sem Supabase real).
    for (final path in [
      'lib/screens/messages_screen.dart',
      'lib/screens/lawyer_messages_screen.dart',
      'lib/screens/firm_messages_screen.dart',
    ]) {
      final fonte = File(path).readAsStringSync();
      expect(
        fonte.contains('subscribeToRealtime('),
        isTrue,
        reason: '$path deixou de assinar o realtime',
      );
      expect(
        fonte.contains("table: 'messages'"),
        isTrue,
        reason: '$path não assina a tabela messages',
      );
      // Refetch silencioso: realtime não pode piscar skeleton nem derrubar
      // a lista para o estado de erro.
      expect(
        fonte.contains('_refreshSilently'),
        isTrue,
        reason: '$path não usa recarga silenciosa',
      );
    }
  });

  test('detalhe do caso assina case_movements filtrado pelo caso', () {
    final fonte = File(
      'lib/screens/case_details_screen.dart',
    ).readAsStringSync();
    expect(fonte.contains("table: 'case_movements'"), isTrue);
    expect(fonte.contains("filterColumn: 'case_id'"), isTrue);
  });

  test('case_movements está publicada no realtime', () {
    // Sem isto a assinatura do detalhe do caso nunca recebe evento.
    final migration = File(
      'supabase/migrations/20260804210000_case_movements_realtime.sql',
    ).readAsStringSync();
    expect(
      migration.contains('add table public.case_movements'),
      isTrue,
    );
  });
}
