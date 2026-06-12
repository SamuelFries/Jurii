import '../data/mock/mock_notifications.dart';
import '../models/jurii_notification.dart';
import '../services/supabase_config.dart';

class NotificationRepository {
  const NotificationRepository();

  Future<List<JuriiNotification>> fetchLatest({int limit = 10}) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return mockNotifications.take(limit).toList();
    }

    try {
      final rows = await SupabaseConfig.client
          .from('notifications')
          .select('id, title, body, type, read_at, created_at')
          .order('created_at', ascending: false)
          .limit(limit);

      return rows.map<JuriiNotification>(_fromRow).toList();
    } catch (error) {
      return mockNotifications.take(limit).toList();
    }
  }

  Future<int> fetchUnreadCount() async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return mockNotifications
          .where((notification) => notification.isUnread)
          .length;
    }

    try {
      final rows = await SupabaseConfig.client
          .from('notifications')
          .select('id')
          .filter('read_at', 'is', null);

      return rows.length;
    } catch (error) {
      return mockNotifications
          .where((notification) => notification.isUnread)
          .length;
    }
  }

  Future<void> markAllAsRead() async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return;
    }

    try {
      await SupabaseConfig.client
          .from('notifications')
          .update({'read_at': DateTime.now().toIso8601String()})
          .filter('read_at', 'is', null);
    } catch (_) {
      return;
    }
  }

  JuriiNotification _fromRow(Map<String, dynamic> row) {
    return JuriiNotification(
      id: row['id'] as String,
      title: row['title'] as String? ?? 'Notificação',
      body: row['body'] as String? ?? '',
      type: row['type'] as String? ?? 'system',
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      readAt: DateTime.tryParse(row['read_at'] as String? ?? ''),
    );
  }
}
