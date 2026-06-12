import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../services/supabase_config.dart';

enum ConversationScope { client, lawyer, firmClient, firmTeam }

class MessagingRepository {
  const MessagingRepository();

  Future<List<Conversation>> fetchConversations({
    required ConversationScope scope,
    String? lawFirmId,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return const [];
    }

    var query = SupabaseConfig.client
        .from('conversations')
        .select(
          'id, type, title, specialty, last_message, last_message_at, law_firm_id',
        );

    switch (scope) {
      case ConversationScope.client:
        query = query.eq(
          'client_id',
          SupabaseConfig.client.auth.currentUser!.id,
        );
      case ConversationScope.lawyer:
        query = query.eq(
          'lawyer_id',
          SupabaseConfig.client.auth.currentUser!.id,
        );
      case ConversationScope.firmClient:
        if (lawFirmId == null) return const [];
        query = query.eq('law_firm_id', lawFirmId).neq('type', 'firm_internal');
      case ConversationScope.firmTeam:
        if (lawFirmId == null) return const [];
        query = query.eq('law_firm_id', lawFirmId).eq('type', 'firm_internal');
    }

    final rows = await query.order('last_message_at', ascending: false);
    return rows.map<Conversation>(_conversationFromRow).toList();
  }

  Future<List<ChatMessage>> fetchMessages(String conversationId) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return const [];
    }

    final rows = await SupabaseConfig.client
        .from('messages')
        .select(
          'id, conversation_id, sender_id, sender_type, body, read_at, created_at',
        )
        .eq('conversation_id', conversationId)
        .order('created_at');

    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;

    return rows
        .map<ChatMessage>(
          (row) => _messageFromRow(row, currentUserId: currentUserId),
        )
        .toList();
  }

  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String body,
    required String senderType,
  }) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) throw StateError('User must be authenticated.');

    final row = await SupabaseConfig.client
        .from('messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': user.id,
          'sender_type': senderType,
          'body': body,
        })
        .select(
          'id, conversation_id, sender_id, sender_type, body, read_at, created_at',
        )
        .single();

    return _messageFromRow(row, currentUserId: user.id);
  }

  Conversation _conversationFromRow(Map<String, dynamic> row) {
    final title = row['title'] as String? ?? 'Conversa';
    return Conversation(
      id: row['id'] as String?,
      initials: _initialsFor(title),
      officeName: title,
      specialty: row['specialty'] as String? ?? 'Atendimento jurídico',
      lastMessage: row['last_message'] as String? ?? 'Conversa iniciada.',
      time: _relativeTime(row['last_message_at'] as String?),
      unreadCount: 0,
      type: row['type'] as String? ?? 'client_firm',
      lawFirmId: row['law_firm_id'] as String?,
    );
  }

  ChatMessage _messageFromRow(
    Map<String, dynamic> row, {
    required String? currentUserId,
  }) {
    final senderId = row['sender_id'] as String?;
    final senderType = row['sender_type'] as String? ?? 'client';

    return ChatMessage(
      id: row['id'] as String,
      conversationKey: row['conversation_id'] as String,
      author: senderType == 'system'
          ? MessageAuthor.system
          : senderId == currentUserId
          ? MessageAuthor.me
          : MessageAuthor.other,
      text: row['body'] as String? ?? '',
      time: _relativeTime(row['created_at'] as String?),
      read: row['read_at'] != null,
    );
  }

  String _relativeTime(String? value) {
    final date = DateTime.tryParse(value ?? '')?.toLocal();
    if (date == null) return '';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(date.year, date.month, date.day);
    final difference = today.difference(messageDay).inDays;

    if (difference == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    if (difference == 1) return 'Ontem';
    if (difference < 7) return '${difference}d';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }

  String _initialsFor(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'J';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
