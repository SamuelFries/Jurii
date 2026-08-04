import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/screens/firm_messages_screen.dart';
import 'package:jurii/screens/lawyer_messages_screen.dart';
import 'package:jurii/screens/messages_screen.dart';
import 'package:jurii/services/realtime_refresh.dart';
import 'package:jurii/theme/app_theme.dart';

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
      channelPrefix: 'teste',
      table: 'conversations',
      filterColumn: 'client_id',
      filterValue: 'qualquer-uid',
      event: PostgresChangeEvent.insert,
      onChange: widget.onChange,
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('sem Supabase pronto não assina nem quebra', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: _Host(onChange: () => calls++)));
    await tester.pumpAndSettle();

    expect(calls, 0);

    // dispose do mixin não pode estourar sem canal aberto.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
  });

  group('modo demo: as listas de conversa abrem sem Supabase', () {
    // REGRESSÃO: a primeira versão interpolava o uid no nome do canal na
    // própria chamada — `SupabaseConfig.client` era tocado ANTES da guarda do
    // mixin e o initState estourava StateError em modo demo. Nenhum teste
    // renderizava estas telas, então a suíte seguiu verde com o crash dentro.
    testWidgets('cliente', (tester) async {
      await tester.pumpWidget(_host(const MessagesScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Conversas'), findsOneWidget);
    });

    testWidgets('advogado', (tester) async {
      await tester.pumpWidget(_host(const LawyerMessagesScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('escritório sem workspace', (tester) async {
      // workspace nulo é o caminho em que não há firma para filtrar: não pode
      // assinar nem quebrar.
      await tester.pumpWidget(_host(const FirmMessagesScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  test('as três listas assinam conversations por participante', () {
    // O filtro é o que garante a privacidade no servidor. Se alguém trocar
    // de volta para `messages` sem filtro, o corte passa a depender da RLS do
    // Realtime e o payload traria o corpo da mensagem.
    const esperado = {
      'lib/screens/messages_screen.dart': "filterColumn: 'client_id'",
      'lib/screens/lawyer_messages_screen.dart': "filterColumn: 'lawyer_id'",
      'lib/screens/firm_messages_screen.dart': "filterColumn: 'law_firm_id'",
    };

    esperado.forEach((caminho, filtro) {
      final fonte = File(caminho).readAsStringSync();
      expect(
        fonte.contains("table: 'conversations'"),
        isTrue,
        reason: '$caminho não assina conversations',
      );
      expect(fonte.contains(filtro), isTrue, reason: '$caminho sem $filtro');
      // Refetch silencioso: realtime não pode piscar skeleton nem derrubar a
      // lista para o estado de erro.
      expect(
        fonte.contains('_refreshSilently'),
        isTrue,
        reason: '$caminho não usa recarga silenciosa',
      );
    });
  });

  test('detalhe do caso assina case_movements filtrado pelo caso', () {
    final fonte = File(
      'lib/screens/case_details_screen.dart',
    ).readAsStringSync();
    expect(fonte.contains("table: 'case_movements'"), isTrue);
    expect(fonte.contains("filterColumn: 'case_id'"), isTrue);
  });

  test('as duas tabelas novas estão publicadas no realtime', () {
    // Sem a publicação, a assinatura nunca recebe evento.
    const publicacoes = {
      '20260804210000_case_movements_realtime.sql': 'case_movements',
      '20260804230000_conversations_realtime.sql': 'conversations',
    };

    publicacoes.forEach((arquivo, tabela) {
      final migration = File('supabase/migrations/$arquivo').readAsStringSync();
      expect(
        migration.contains('add table public.$tabela'),
        isTrue,
        reason: '$arquivo não publica $tabela',
      );
    });
  });
}
