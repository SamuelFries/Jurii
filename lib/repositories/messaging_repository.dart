import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../services/supabase_config.dart';

class MessagingRepository {
  const MessagingRepository();

  Future<List<Conversation>> fetchConversations() async {
    final rows = await SupabaseConfig.client
        .from('conversations')
        .select()
        .order('last_message_at', ascending: false);

    return rows.map<Conversation>(_conversationFromRow).toList();
  }

  Future<List<ChatMessage>> fetchMessages(String conversationId) async {
    final rows = await SupabaseConfig.client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at');

    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;

    return rows
        .map<ChatMessage>(
          (row) => _messageFromRow(row, currentUserId: currentUserId),
        )
        .toList();
  }

  Future<void> sendMessage({
    required String conversationId,
    required String body,
    required String senderType,
  }) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) throw StateError('User must be authenticated.');

    await SupabaseConfig.client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': user.id,
      'sender_type': senderType,
      'body': body,
    });
  }

  Conversation _conversationFromRow(Map<String, dynamic> row) {
    return Conversation(
      initials: _initialsFor(row['title'] as String? ?? ''),
      officeName: row['title'] as String,
      specialty: row['specialty'] as String? ?? '',
      lastMessage: row['last_message'] as String? ?? '',
      time: '',
      unreadCount: 0,
    );
  }

  ChatMessage _messageFromRow(
    Map<String, dynamic> row, {
    required String? currentUserId,
  }) {
    final senderId = row['sender_id'] as String?;

    return ChatMessage(
      id: row['id'] as String,
      conversationKey: row['conversation_id'] as String,
      author: senderId == currentUserId
          ? MessageAuthor.me
          : MessageAuthor.other,
      text: row['body'] as String,
      time: '',
      read: row['read_at'] != null,
    );
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
