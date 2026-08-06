import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import '../data/mock/mock_notifications.dart';
import '../models/jurii_notification.dart';
import '../services/supabase_config.dart';

class NotificationRepository {
  const NotificationRepository();

  Future<List<JuriiNotification>> fetchLatest({
    required NotificationScope scope,
    String? lawFirmId,
    int limit = 10,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return mockNotifications
          .where((notification) => notification.scope == scope)
          .take(limit)
          .toList();
    }

    try {
      var query = SupabaseConfig.client
          .from('notifications')
          .select('id, title, body, type, scope, metadata, read_at, created_at')
          .eq('scope', scope.databaseValue);

      if (scope == NotificationScope.firm && lawFirmId != null) {
        query = query.eq('law_firm_id', lawFirmId);
      }

      final rows = await query
          .order('created_at', ascending: false)
          .limit(limit);

      return rows.map<JuriiNotification>(_fromRow).toList();
    } catch (error) {
      // Nunca cair para mocks com usuário real: as notificações mock têm
      // ações reais (aceitar convite) com ids inválidos. E o erro sobe:
      // painel vazio em falha de rede diria "zero notificações", que é
      // mentira — quem chama decide o que mostrar.
      debugPrint('Supabase notifications fetch failed: $error');
      rethrow;
    }
  }

  /// Quantas notificações esperam em CADA fluxo.
  ///
  /// Existe para o seletor de modo poder marcar onde há algo esperando: o sino
  /// de cada fluxo conta só o próprio escopo, então quem está no modo cliente
  /// não fica sabendo que chegou uma solicitação de caso no modo advogado.
  /// Para quem tem os três fluxos, isso não é atrito de navegação — é lead que
  /// só aparece quando a pessoa lembra de trocar de modo.
  ///
  /// Falha em silêncio devolvendo zeros: contador é enfeite de navegação, e
  /// derrubar a tela por causa dele seria trocar um problema por um pior.
  Future<Map<NotificationScope, int>> fetchUnreadCountsByScope({
    String? lawFirmId,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return {
        for (final scope in NotificationScope.values)
          scope: mockNotifications
              .where((n) => n.scope == scope && n.isUnread)
              .length,
      };
    }

    try {
      final rows = await SupabaseConfig.client.rpc(
        'fetch_unread_notification_counts',
        params: {'law_firm_id_value': lawFirmId},
      );

      final porEscopo = <NotificationScope, int>{
        for (final scope in NotificationScope.values) scope: 0,
      };
      for (final row in (rows as List<dynamic>).cast<Map<String, dynamic>>()) {
        final scope = NotificationScope.values.firstWhere(
          (value) => value.databaseValue == row['scope'],
          orElse: () => NotificationScope.client,
        );
        porEscopo[scope] = (row['unread'] as num?)?.toInt() ?? 0;
      }
      return porEscopo;
    } catch (error) {
      debugPrint('Unread counts by scope failed: $error');
      return {for (final scope in NotificationScope.values) scope: 0};
    }
  }

  Future<int> fetchUnreadCount({
    required NotificationScope scope,
    String? lawFirmId,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return mockNotifications
          .where(
            (notification) =>
                notification.scope == scope && notification.isUnread,
          )
          .length;
    }

    try {
      var query = SupabaseConfig.client
          .from('notifications')
          .select('id')
          .eq('scope', scope.databaseValue)
          .filter('read_at', 'is', null);

      if (scope == NotificationScope.firm && lawFirmId != null) {
        query = query.eq('law_firm_id', lawFirmId);
      }

      // Contagem no servidor — evita materializar todas as linhas não lidas.
      final response = await query.count(CountOption.exact);
      return response.count;
    } catch (error) {
      debugPrint('Supabase notifications count failed: $error');
      return 0;
    }
  }

  Future<void> markAllAsRead({
    required NotificationScope scope,
    String? lawFirmId,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return;
    }

    try {
      var query = SupabaseConfig.client
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('scope', scope.databaseValue)
          .filter('read_at', 'is', null);

      if (scope == NotificationScope.firm && lawFirmId != null) {
        query = query.eq('law_firm_id', lawFirmId);
      }

      await query;
    } catch (error) {
      debugPrint('Supabase notifications mark read failed: $error');
      return;
    }
  }

  /// Uma notificação pelo id. O push carrega só `notification_id` (o metadata
  /// com os ids do caso/conversa fica fora do payload, que trafega e repousa
  /// no dispositivo); ao tocar, buscamos a linha para saber para onde ir.
  /// O RLS garante que só o destinatário lê a própria notificação.
  Future<JuriiNotification?> fetchById(String notificationId) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return null;
    }

    try {
      final row = await SupabaseConfig.client
          .from('notifications')
          .select('id, title, body, type, scope, metadata, read_at, created_at')
          .eq('id', notificationId)
          .maybeSingle();

      if (row == null) return null;
      return _fromRow(row);
    } catch (error) {
      debugPrint('Supabase notification fetch failed: $error');
      return null;
    }
  }

  /// Marca uma única notificação como lida (ao tocar nela). O RLS já limita ao
  /// destinatário; sem isso, abrir o sino teria que marcar tudo de uma vez.
  Future<void> markAsRead(String notificationId) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return;
    }

    try {
      await SupabaseConfig.client
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', notificationId)
          .filter('read_at', 'is', null);
    } catch (error) {
      debugPrint('Supabase notification mark read failed: $error');
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return;
    }

    await SupabaseConfig.client
        .from('notifications')
        .delete()
        .eq('id', notificationId);
  }

  Future<void> acceptTeamInvite(String membershipId) async {
    await _respondToTeamInvite(membershipId: membershipId, accepted: true);
  }

  Future<void> declineTeamInvite(String membershipId) async {
    await _respondToTeamInvite(membershipId: membershipId, accepted: false);
  }

  Future<void> acceptCaseRequest(String caseRequestId) async {
    await _respondToCaseRequest(caseRequestId: caseRequestId, accepted: true);
  }

  Future<void> declineCaseRequest(String caseRequestId) async {
    await _respondToCaseRequest(caseRequestId: caseRequestId, accepted: false);
  }

  Future<void> _respondToTeamInvite({
    required String membershipId,
    required bool accepted,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      throw StateError('A conexão com o Supabase não está ativa.');
    }

    await SupabaseConfig.client.rpc(
      'respond_to_law_firm_invite',
      params: {'membership_id_value': membershipId, 'accepted_value': accepted},
    );
  }

  Future<void> _respondToCaseRequest({
    required String caseRequestId,
    required bool accepted,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      throw StateError('A conexão com o Supabase não está ativa.');
    }

    await SupabaseConfig.client.rpc(
      'respond_to_case_request',
      params: {'request_id_value': caseRequestId, 'accepted_value': accepted},
    );
  }

  JuriiNotification _fromRow(Map<String, dynamic> row) {
    return JuriiNotification(
      id: row['id'] as String,
      title: row['title'] as String? ?? 'Notificação',
      body: row['body'] as String? ?? '',
      type: row['type'] as String? ?? 'system',
      scope: NotificationScope.fromDatabase(row['scope'] as String?),
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      readAt: DateTime.tryParse(row['read_at'] as String? ?? ''),
      metadata: _metadataFromRow(row['metadata']),
    );
  }

  Map<String, dynamic> _metadataFromRow(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }
}
