import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/law_firm.dart';
import '../models/lawyer_profile_summary.dart';
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
          'id, type, title, specialty, last_message, last_message_at, law_firm_id, client_id, lawyer_id',
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
    return _conversationsFromRows(rows, scope: scope);
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
        .order('created_at', ascending: true);

    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;

    return rows
        .map<ChatMessage>(
          (row) => messageFromRow(row, currentUserId: currentUserId),
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

    return messageFromRow(row, currentUserId: user.id);
  }

  Future<Conversation> startLawFirmConversation({
    required LawFirm lawFirm,
    String? initialMessage,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return _fallbackLawFirmConversation(lawFirm);
    }

    try {
      final conversationId = await SupabaseConfig.client.rpc(
        'start_or_get_law_firm_conversation',
        params: {
          'law_firm_id_value': lawFirm.id,
          'initial_message_value': initialMessage ?? '',
        },
      );

      return await fetchConversationById(conversationId as String);
    } catch (_) {
      rethrow;
    }
  }

  Future<Conversation> startLawyerConversation({
    required LawyerProfileSummary lawyer,
    String? initialMessage,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return _fallbackLawyerConversation(lawyer);
    }

    try {
      final conversationId = await SupabaseConfig.client.rpc(
        'start_or_get_lawyer_conversation',
        params: {
          'lawyer_profile_id_value': lawyer.id,
          'initial_message_value': initialMessage ?? '',
        },
      );

      return await fetchConversationById(conversationId as String);
    } catch (_) {
      rethrow;
    }
  }

  Future<Conversation> fetchConversationById(String conversationId) async {
    final row = await SupabaseConfig.client
        .from('conversations')
        .select(
          'id, type, title, specialty, last_message, last_message_at, law_firm_id, client_id, lawyer_id',
        )
        .eq('id', conversationId)
        .single();

    return _conversationFromRow(row);
  }

  Future<List<Conversation>> _conversationsFromRows(
    List<dynamic> rows, {
    required ConversationScope scope,
  }) async {
    final mappedRows = rows.cast<Map<String, dynamic>>();
    if (scope != ConversationScope.lawyer &&
        scope != ConversationScope.firmClient) {
      return mappedRows.map(_conversationFromRow).toList();
    }

    final clientIds = mappedRows
        .map((row) => row['client_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    final profilesById = await _fetchProfilesById(clientIds);

    return mappedRows.map((row) {
      final clientId = row['client_id'] as String?;
      final profile = clientId == null ? null : profilesById[clientId];
      return _conversationFromRow(row, displayProfile: profile);
    }).toList();
  }

  Future<Map<String, _ConversationProfile>> _fetchProfilesById(
    List<String> profileIds,
  ) async {
    if (profileIds.isEmpty) return const {};

    try {
      final rows = await SupabaseConfig.client
          .from('profiles')
          .select('id, full_name, initials')
          .inFilter('id', profileIds);

      return {
        for (final row in rows)
          row['id'] as String: _ConversationProfile(
            name: row['full_name'] as String? ?? 'Cliente',
            initials: row['initials'] as String? ?? '',
          ),
      };
    } catch (_) {
      return const {};
    }
  }

  Conversation _conversationFromRow(
    Map<String, dynamic> row, {
    _ConversationProfile? displayProfile,
  }) {
    final title = displayProfile?.name ?? row['title'] as String? ?? 'Conversa';
    final initials = displayProfile?.initials.isNotEmpty == true
        ? displayProfile!.initials
        : _initialsFor(title);
    return Conversation(
      id: row['id'] as String?,
      initials: initials,
      officeName: title,
      specialty: row['specialty'] as String? ?? 'Atendimento jurídico',
      lastMessage: row['last_message'] as String? ?? 'Conversa iniciada.',
      time: _relativeTime(row['last_message_at'] as String?),
      unreadCount: 0,
      type: row['type'] as String? ?? 'client_firm',
      lawFirmId: row['law_firm_id'] as String?,
      clientId: row['client_id'] as String?,
      lawyerId: row['lawyer_id'] as String?,
    );
  }

  ChatMessage messageFromRow(
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

  Conversation _fallbackLawFirmConversation(LawFirm lawFirm) {
    return Conversation(
      initials: lawFirm.initials,
      officeName: lawFirm.name,
      specialty: lawFirm.specialty,
      lastMessage: 'Conversa iniciada.',
      time: 'Agora',
      unreadCount: 0,
      type: 'client_firm',
      lawFirmId: lawFirm.id,
    );
  }

  Conversation _fallbackLawyerConversation(LawyerProfileSummary lawyer) {
    return Conversation(
      initials: lawyer.initials,
      officeName: lawyer.name,
      specialty: lawyer.primaryArea,
      lastMessage: 'Conversa iniciada.',
      time: 'Agora',
      unreadCount: 0,
      type: 'client_lawyer',
      lawyerId: lawyer.id,
    );
  }
}

class _ConversationProfile {
  final String name;
  final String initials;

  const _ConversationProfile({required this.name, required this.initials});
}
