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
  String? _realtimeChannelName;
  bool _hasSubscribedOnce = false;
  Timer? _debounce;

  /// Rajada de eventos (ex.: sync do processo inserindo 14 movimentos de uma
  /// vez) vira UM refetch. Sem isso, cada linha dispararia uma consulta.
  static const Duration _debounceWindow = Duration(milliseconds: 300);

  /// Assina [table] filtrando por [filterColumn] = [filterValue].
  ///
  /// O filtro é OBRIGATÓRIO de propósito: assinar uma tabela inteira apostando
  /// que a RLS corta por assinante deixa a privacidade dependendo do serviço de
  /// Realtime, e um evento indevido viria com a linha crua no payload. Corte
  /// por coluna no servidor; a RLS fica como segunda camada.
  ///
  /// O nome do canal é montado AQUI (prefixo + uid) porque interpolar o uid na
  /// chamada tocaria `SupabaseConfig.client` antes desta guarda — e no modo
  /// demo, sem Supabase inicializado, isso estoura `StateError` no initState.
  void subscribeToRealtime({
    required String channelPrefix,
    required String table,
    required String filterColumn,
    required String filterValue,
    required VoidCallback onChange,
    PostgresChangeEvent event = PostgresChangeEvent.all,
  }) {
    if (!SupabaseConfig.isReady) return;
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;

    final channelName = '$channelPrefix:$userId:$filterValue';
    // Mesmo canal: nada a fazer. Canal DIFERENTE (o filtro mudou — ex.: o
    // usuário trocou de escritório): derruba o antigo e assina o novo, senão
    // a tela ficaria recebendo eventos do alvo anterior para sempre.
    if (_realtimeChannel != null) {
      if (_realtimeChannelName == channelName) return;
      SupabaseConfig.client.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
      _hasSubscribedOnce = false;
    }
    _realtimeChannelName = channelName;

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
          filter: PostgresChangeFilter(
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
