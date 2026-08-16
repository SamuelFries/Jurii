import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_attachment.dart';
import '../models/chat_message.dart';
import '../models/discovery_page.dart';
import '../models/conversation.dart';
import '../models/law_firm.dart';
import '../models/lawyer_profile_summary.dart';
import '../utils/discovery_pagination.dart';
import '../models/report_reason.dart';
import '../services/supabase_config.dart';

enum ConversationScope { client, lawyer, firmClient, firmTeam }

/// Casa os resultados de assinatura com os caminhos PEDIDOS.
///
/// A chave do mapa tem que ser o caminho que nós pedimos, porque é por ele que
/// o balão procura a URL depois. A API promete um resultado por caminho, na
/// mesma ordem, mas confiar só na posição significaria que uma resposta fora
/// de ordem mostraria a foto de uma mensagem dentro de outra — então o
/// caminho que o servidor devolve manda, quando ele é um dos que pedimos, e a
/// posição só entra como reserva. Caminho nenhum é inventado.
Map<String, String> signedUrlsByRequestedPath(
  List<String> requestedPaths,
  List<SignedUrlResult> results,
) {
  final requested = requestedPaths.toSet();
  final sameLength = results.length == requestedPaths.length;
  final urls = <String, String>{};

  for (var index = 0; index < results.length; index++) {
    final result = results[index];
    if (result is! SignedUrlSuccess) continue;

    final String? key;
    if (requested.contains(result.path)) {
      key = result.path;
    } else if (sameLength) {
      key = requestedPaths[index];
    } else {
      key = null;
    }

    if (key == null || key.isEmpty) continue;
    urls[key] = result.signedUrl;
  }

  return urls;
}

class MessagingRepository {
  const MessagingRepository();

  static const _chatAttachmentsBucket = 'chat-attachments';
  static const _attachmentSelectColumns =
      'id, message_id, conversation_id, file_name, mime_type, file_size_bytes, storage_path, kind, created_at';

  Future<List<Conversation>> fetchConversations({
    required ConversationScope scope,
    String? lawFirmId,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return const [];
    }

    if ((scope == ConversationScope.firmClient ||
            scope == ConversationScope.firmTeam) &&
        lawFirmId == null) {
      return const [];
    }

    final rows = await SupabaseConfig.client.rpc(
      'fetch_conversations_for_current_user',
      params: {'scope_value': scope.name, 'law_firm_id_value': lawFirmId},
    );

    final conversations = (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(_conversationFromRow)
        .toList();

    // Carregar a lista É a entrega: a partir daqui o aparelho de quem recebe
    // sabe que estas mensagens existem, que é exatamente o que o segundo tique
    // afirma. Fica aqui, e não nas telas, porque são TRÊS listas (cliente,
    // advogado e escritório) e esquecer numa delas daria um tique que só
    // aparece dependendo de quem abriu.
    //
    // Sem await de propósito: confirmação de entrega nunca pode atrasar nem
    // derrubar o carregamento da conversa.
    unawaited(
      markMessagesDelivered(
        conversations
            .map((conversation) => conversation.id)
            .whereType<String>()
            .toList(),
      ),
    );

    return conversations;
  }

  /// Apaga as mensagens SÓ para quem chamou. Continuam inteiras para o outro
  /// lado; o servidor passa a escondê-las de mim em toda leitura (a regra vive
  /// na RLS de messages, então vale também para o tempo real).
  Future<int> deleteMessagesForMe(List<String> messageIds) async {
    return _deleteMessages('delete_messages_for_me', messageIds);
  }

  /// Apaga o CONTEÚDO para todos, deixando a lápide. O servidor recusa o que
  /// não for meu, o que estiver fora da janela e o que for mensagem de sistema.
  Future<int> deleteMessagesForEveryone(List<String> messageIds) async {
    return _deleteMessages('delete_messages_for_everyone', messageIds);
  }

  Future<int> _deleteMessages(String rpc, List<String> messageIds) async {
    if (messageIds.isEmpty ||
        !SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return 0;
    }

    final deleted = await SupabaseConfig.client.rpc(
      rpc,
      params: {'message_ids_value': messageIds},
    );
    return (deleted as num?)?.toInt() ?? 0;
  }

  /// Marca como VISTAS as mensagens que a outra parte mandou nesta conversa.
  /// Devolve quantas mudaram — zero quando não havia nada por ler.
  Future<int> markConversationRead(String conversationId) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return 0;
    }

    final marked = await SupabaseConfig.client.rpc(
      'mark_conversation_read',
      params: {'conversation_id_value': conversationId},
    );
    return (marked as num?)?.toInt() ?? 0;
  }

  /// Marca como ENTREGUES as mensagens recebidas nestas conversas. Falha em
  /// silêncio: é sinal de cortesia, não pode virar erro na cara de ninguém.
  Future<int> markMessagesDelivered(List<String> conversationIds) async {
    if (conversationIds.isEmpty ||
        !SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return 0;
    }

    try {
      final marked = await SupabaseConfig.client.rpc(
        'mark_messages_delivered',
        params: {'conversation_ids_value': conversationIds},
      );
      return (marked as num?)?.toInt() ?? 0;
    } catch (error) {
      debugPrint('Delivery receipt failed: $error');
      return 0;
    }
  }

  /// Estado de bloqueio da conversa. O bloqueio congela os dois lados; o
  /// servidor decide (trigger em messages), aqui é só leitura para a UI.
  Future<({bool isBlocked, bool blockedByMe})> fetchConversationBlockState(
    String conversationId,
  ) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return (isBlocked: false, blockedByMe: false);
    }
    final rows = await SupabaseConfig.client.rpc(
      'fetch_conversation_block_state',
      params: {'conversation_id_value': conversationId},
    );
    final row = (rows as List<dynamic>).cast<Map<String, dynamic>>().first;
    return (
      isBlocked: row['is_blocked'] == true,
      blockedByMe: row['blocked_by_me'] == true,
    );
  }

  Future<void> blockConversation(String conversationId) {
    return SupabaseConfig.client.rpc(
      'block_conversation',
      params: {'conversation_id_value': conversationId},
    );
  }

  Future<void> unblockConversation(String conversationId) {
    return SupabaseConfig.client.rpc(
      'unblock_conversation',
      params: {'conversation_id_value': conversationId},
    );
  }

  Future<void> reportConversation({
    required String conversationId,
    required ReportReason reason,
    String? details,
    String? messageId,
  }) {
    return SupabaseConfig.client.rpc(
      'report_conversation',
      params: {
        'conversation_id_value': conversationId,
        'reason_value': reason.databaseValue,
        'details_value': details,
        'message_id_value': messageId,
      },
    );
  }

  /// Tamanho da página do chat. Cinquenta cobre dias de conversa real numa
  /// tela só; quem precisa de mais rola para cima e a próxima página vem.
  static const int messagesPageSize = 50;

  Future<List<ChatMessage>> fetchMessages(String conversationId) async {
    final page = await fetchMessagesPage(conversationId);
    return page.items;
  }

  /// Uma página de mensagens, da mais recente para trás.
  ///
  /// Era um teto fixo de 100 com um TODO: conversa jurídica passa disso numa
  /// semana, e a mensagem 101 SUMIA em silêncio — o histórico parecia começar
  /// no meio. Agora é keyset por (created_at, id): estável sob mensagem nova
  /// chegando no meio da rolagem, que é onde offset duplicaria itens.
  ///
  /// O par no cursor não é excesso de zelo: duas mensagens no MESMO
  /// timestamp (lote de teste, importação) fariam o cursor só de created_at
  /// pular uma delas para sempre. O id (uuid) não ordena por tempo, e não
  /// precisa: só precisa desempatar IGUAL no order e no filtro.
  Future<DiscoveryPage<ChatMessage>> fetchMessagesPage(
    String conversationId, {
    ChatMessage? before,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return DiscoveryPage(items: const [], hasMore: false);
    }

    // RPC parametrizada em vez de filtro de string: o cursor composto só se
    // escreveria no PostgREST via `or=`, que é a família que a barreira
    // anti-injeção do app proíbe (query_safety_test). Na função, a
    // comparação (created_at, id) < (X, Y) é nativa e nada vira sintaxe.
    final beforeAt = before?.createdAt;
    final rows = List<Map<String, dynamic>>.from(
      await SupabaseConfig.client.rpc(
        'fetch_conversation_messages_page',
        params: {
          'conversation_id_value': conversationId,
          'before_created_at': beforeAt?.toUtc().toIso8601String(),
          'before_id': beforeAt == null ? null : before?.id,
          'page_size': messagesPageSize + 1,
        },
      ) as List<dynamic>,
    );

    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    final page = pageFromSentinel(rows, messagesPageSize);

    final messages = page.items.reversed
        .map<ChatMessage>(
          (row) => messageFromRow(row, currentUserId: currentUserId),
        )
        .toList();

    return DiscoveryPage(
      items: await _messagesWithAttachments(messages),
      hasMore: page.hasMore,
    );
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
          'id, conversation_id, sender_id, sender_type, body, metadata, read_at, delivered_at, deleted_for_all_at, created_at',
        )
        .single();

    return messageFromRow(row, currentUserId: user.id);
  }

  Future<ChatMessage> sendAttachment({
    required String conversationId,
    required String fileName,
    required String mimeType,
    required int fileSizeBytes,
    required Uint8List bytes,
    required ChatAttachmentKind kind,
    required String senderType,
  }) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) throw StateError('User must be authenticated.');

    final storagePath = _storagePathFor(
      userId: user.id,
      conversationId: conversationId,
      fileName: fileName,
    );

    await SupabaseConfig.client.storage
        .from(_chatAttachmentsBucket)
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );

    try {
      final rows = await SupabaseConfig.client.rpc(
        'send_chat_attachment',
        params: {
          'conversation_id_value': conversationId,
          'file_name_value': fileName,
          'mime_type_value': mimeType,
          'file_size_bytes_value': fileSizeBytes,
          'storage_path_value': storagePath,
          'kind_value': kind.value,
          'sender_type_value': senderType,
        },
      );

      final row = (rows as List<dynamic>).cast<Map<String, dynamic>>().first;
      return _messageWithAttachmentFromRpc(row, currentUserId: user.id);
    } catch (_) {
      await SupabaseConfig.client.storage.from(_chatAttachmentsBucket).remove([
        storagePath,
      ]);
      rethrow;
    }
  }

  Future<ChatMessage> messageFromRowWithAttachment(
    Map<String, dynamic> row, {
    required String? currentUserId,
  }) async {
    final message = messageFromRow(row, currentUserId: currentUserId);
    // Só consulta o anexo quando o metadata indica que existe um — evita uma
    // query extra para cada mensagem de texto recebida via realtime.
    if (message.metadata['type'] != 'chat_attachment') return message;
    final attachment = await fetchAttachmentForMessage(message.id);
    return attachment == null
        ? message
        : message.copyWith(attachment: attachment);
  }

  Future<ChatAttachment?> fetchAttachmentForMessage(String messageId) async {
    try {
      final row = await SupabaseConfig.client
          .from('message_attachments')
          .select(_attachmentSelectColumns)
          .eq('message_id', messageId)
          .maybeSingle();

      if (row == null) return null;
      return ChatAttachment.fromRow(row);
    } catch (_) {
      return null;
    }
  }

  Future<String> createSignedAttachmentUrl(ChatAttachment attachment) {
    return SupabaseConfig.client.storage
        .from(_chatAttachmentsBucket)
        .createSignedUrl(attachment.storagePath, 300);
  }

  /// Assina vários anexos numa chamada só — é o que permite abrir uma conversa
  /// com dez fotos sem dez idas ao servidor. Caminhos que o servidor não
  /// conseguiu assinar simplesmente não aparecem no mapa.
  Future<Map<String, String>> createSignedAttachmentUrls(
    List<String> storagePaths,
    Duration ttl,
  ) async {
    if (storagePaths.isEmpty) return const {};

    final results = await SupabaseConfig.client.storage
        .from(_chatAttachmentsBucket)
        .createSignedUrlsResult(storagePaths, ttl.inSeconds);

    return signedUrlsByRequestedPath(storagePaths, results);
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

  /// Abre (ou recupera) a conversa com um advogado a partir do id — é o que o
  /// card de sugestão tem em mãos, sem precisar do perfil inteiro.
  Future<Conversation> startLawyerConversationById(String lawyerId) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      throw StateError('A conexão com o Supabase não está ativa.');
    }

    final conversationId = await SupabaseConfig.client.rpc(
      'start_or_get_lawyer_conversation',
      params: {
        'lawyer_profile_id_value': lawyerId,
        'initial_message_value': '',
      },
    );

    return fetchConversationById(conversationId as String);
  }

  /// Escritório sugere um advogado da organização ao cliente. O servidor grava
  /// a mensagem com o retrato do advogado e notifica o cliente.
  Future<void> recommendLawyer({
    required String conversationId,
    required String lawyerId,
    String? note,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      throw StateError('A conexão com o Supabase não está ativa.');
    }

    await SupabaseConfig.client.rpc(
      'recommend_lawyer_to_client',
      params: {
        'conversation_id_value': conversationId,
        'lawyer_profile_id_value': lawyerId,
        'note_value': note,
      },
    );
  }

  Future<Conversation> fetchConversationById(String conversationId) async {
    try {
      final row = await SupabaseConfig.client
          .rpc(
            'fetch_conversation_for_current_user',
            params: {'conversation_id_value': conversationId},
          )
          .single();

      return _conversationFromRow(row);
    } catch (_) {
      final row = await SupabaseConfig.client
          .from('conversations')
          .select(
            'id, type, title, specialty, last_message, last_message_at, law_firm_id, client_id, lawyer_id',
          )
          .eq('id', conversationId)
          .single();

      return _conversationFromRow(row);
    }
  }

  Conversation _conversationFromRow(Map<String, dynamic> row) {
    final title = row['title'] as String? ?? 'Conversa';
    final initials = row['initials'] as String? ?? _initialsFor(title);
    return Conversation(
      id: row['id'] as String?,
      initials: initials,
      avatarUrl: _optionalText(row['avatar_url']),
      officeName: title,
      specialty: row['specialty'] as String? ?? 'Atendimento jurídico',
      lastMessage: row['last_message'] as String? ?? 'Conversa iniciada.',
      time: _relativeTime(row['last_message_at'] as String?),
      unreadCount: (row['unread_count'] as num?)?.toInt() ?? 0,
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
      status: MessageDeliveryStatus.resolve(
        delivered: row['delivered_at'] != null,
        read: row['read_at'] != null,
      ),
      metadata: _metadataFromRow(row['metadata']),
      createdAt: DateTime.tryParse(
        row['created_at'] as String? ?? '',
      )?.toLocal(),
      deletedForAll: row['deleted_for_all_at'] != null,
    );
  }

  Future<List<ChatMessage>> _messagesWithAttachments(
    List<ChatMessage> messages,
  ) async {
    if (messages.isEmpty) return messages;

    try {
      final rows = await SupabaseConfig.client
          .from('message_attachments')
          .select(_attachmentSelectColumns)
          .inFilter(
            'message_id',
            messages.map((message) => message.id).toList(),
          );

      final attachmentsByMessageId = {
        for (final row in rows)
          (row['message_id'] as String): ChatAttachment.fromRow(row),
      };

      return messages
          .map(
            (message) => message.copyWith(
              attachment: attachmentsByMessageId[message.id],
            ),
          )
          .toList();
    } catch (_) {
      return messages;
    }
  }

  ChatMessage _messageWithAttachmentFromRpc(
    Map<String, dynamic> row, {
    required String currentUserId,
  }) {
    final message = messageFromRow(row, currentUserId: currentUserId);
    final attachment = ChatAttachment.fromRow({
      'id': row['attachment_id'],
      'message_id': row['id'],
      'conversation_id': row['conversation_id'],
      'file_name': row['file_name'],
      'mime_type': row['mime_type'],
      'file_size_bytes': row['file_size_bytes'],
      'storage_path': row['storage_path'],
      'kind': row['kind'],
    });

    return message.copyWith(attachment: attachment);
  }

  String _storagePathFor({
    required String userId,
    required String conversationId,
    required String fileName,
  }) {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final safeName = _safeFileName(fileName);
    return '$userId/$conversationId/$timestamp-$safeName';
  }

  String _safeFileName(String fileName) {
    final name = fileName
        .split(RegExp(r'[\\/]'))
        .where((part) => part.trim().isNotEmpty)
        .lastOrNull;
    final sanitized = (name ?? 'arquivo')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();

    return sanitized.isEmpty ? 'arquivo' : sanitized;
  }

  Map<String, dynamic> _metadataFromRow(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
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

  String? _optionalText(Object? value) {
    final text = value is String ? value.trim() : '';
    return text.isEmpty ? null : text;
  }

  Conversation _fallbackLawFirmConversation(LawFirm lawFirm) {
    return Conversation(
      initials: lawFirm.initials,
      avatarUrl: lawFirm.avatarUrl,
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
      avatarUrl: lawyer.photoUrl,
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
