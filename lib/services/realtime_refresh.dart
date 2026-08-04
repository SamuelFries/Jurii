import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reexporta PostgresChangeEvent: quem usa o mixin escolhe o evento sem
/// precisar importar o pacote do Supabase direto na tela.
export 'package:supabase_flutter/supabase_flutter.dart' show PostgresChangeEvent;

import 'supabase_config.dart';

/// Assina uma tabela no Realtime e chama [onChange] a cada evento, para a
/// tela refazer o próprio fetch.
///
/// Existe para as listas que só precisam saber "algo mudou, recarregue" —
/// diferente do chat, que aplica o payload linha a linha. Como o refetch é
/// a fonte da verdade, o payload é ignorado de propósito: nenhuma tela fica
/// dependente do formato da linha crua nem de RLS no cliente.
mixin RealtimeRefresh<T extends StatefulWidget> on State<T> {
  RealtimeChannel? _realtimeChannel;
  bool _hasSubscribedOnce = false;
  Timer? _debounce;

  /// Rajada de eventos (ex.: sync do processo inserindo 14 movimentos de uma
  /// vez) vira UM refetch. Sem isso, cada linha dispararia uma consulta.
  static const Duration _debounceWindow = Duration(milliseconds: 300);

  /// Assina [table]; com [filterColumn]/[filterValue] o servidor já corta o
  /// que não interessa. Sem eles, quem corta é a RLS da tabela — o
  /// assinante só recebe as linhas que já poderia ler.
  void subscribeToRealtime({
    required String channelName,
    required String table,
    required VoidCallback onChange,
    String? filterColumn,
    String? filterValue,
    PostgresChangeEvent event = PostgresChangeEvent.all,
  }) {
    if (!SupabaseConfig.isReady) return;
    if (SupabaseConfig.client.auth.currentUser == null) return;
    if (_realtimeChannel != null) return;

    void schedule() {
      _debounce?.cancel();
      _debounce = Timer(_debounceWindow, () {
        if (mounted) onChange();
      });
    }

    _realtimeChannel = SupabaseConfig.client
        .channel(channelName)
        .onPostgresChanges(
          event: event,
          schema: 'public',
          table: table,
          filter: filterColumn == null || filterValue == null
              ? null
              : PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: filterColumn,
                  value: filterValue,
                ),
          callback: (_) => schedule(),
        )
        .subscribe((status, [error]) {
          // O Supabase não reenvia eventos perdidos: ao reassinar depois de
          // uma queda, refaz o fetch para não ficar com a lista velha.
          if (status == RealtimeSubscribeStatus.subscribed) {
            if (_hasSubscribedOnce && mounted) onChange();
            _hasSubscribedOnce = true;
          }
        });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    final channel = _realtimeChannel;
    if (channel != null && SupabaseConfig.isReady) {
      SupabaseConfig.client.removeChannel(channel);
    }
    _realtimeChannel = null;
    super.dispose();
  }
}
