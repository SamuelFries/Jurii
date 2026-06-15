import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/mock/mock_chat_messages.dart';
import '../models/case_request.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../repositories/case_repository.dart';
import '../repositories/law_firm_repository.dart';
import '../repositories/lawyer_profile_repository.dart';
import '../repositories/messaging_repository.dart';
import '../repositories/profile_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_theme.dart';
import 'client_profile_screen.dart';
import 'law_firm_profile_screen.dart';
import 'lawyer_profile_screen.dart';

class ChatScreen extends StatefulWidget {
  final Conversation conversation;
  final bool isLawyer;

  const ChatScreen({
    super.key,
    required this.conversation,
    required this.isLawyer,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final MessagingRepository _repository = const MessagingRepository();
  final CaseRepository _caseRepository = const CaseRepository();
  final ProfileRepository _profileRepository = const ProfileRepository();
  final LawyerProfileRepository _lawyerProfileRepository =
      const LawyerProfileRepository();
  final LawFirmRepository _lawFirmRepository = const LawFirmRepository();
  RealtimeChannel? _messagesChannel;
  List<ChatMessage> _messages = const [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isOpeningProfile = false;
  bool _isCreatingCaseRequest = false;
  String? _respondingCaseRequestId;

  bool get _usesSupabase => widget.conversation.id != null;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    final channel = _messagesChannel;
    if (channel != null && SupabaseConfig.isReady) {
      SupabaseConfig.client.removeChannel(channel);
    }
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);

    if (!_usesSupabase) {
      setState(() {
        _messages = _mockMessages();
        _isLoading = false;
      });
      _scrollToBottom();
      return;
    }

    try {
      final messages = await _messagesWithPendingCaseRequestFallback(
        await _repository.fetchMessages(widget.conversation.id!),
      );
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages = _usesSupabase ? const [] : _mockMessages();
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _subscribeToMessages() {
    final conversationId = widget.conversation.id;
    if (conversationId == null || !SupabaseConfig.isReady) return;

    _messagesChannel = SupabaseConfig.client
        .channel('conversation_messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            final message = _repository.messageFromRow(
              payload.newRecord,
              currentUserId: SupabaseConfig.client.auth.currentUser?.id,
            );
            _appendMessage(message);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            final message = _repository.messageFromRow(
              payload.newRecord,
              currentUserId: SupabaseConfig.client.auth.currentUser?.id,
            );
            _upsertMessage(message);
          },
        )
        .subscribe();
  }

  List<ChatMessage> _mockMessages() {
    return mockChatMessages
        .where(
          (message) =>
              message.conversationKey == widget.conversation.officeName,
        )
        .toList();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    _messageController.clear();

    if (!_usesSupabase) {
      _appendMessage(
        ChatMessage(
          id: 'local_${DateTime.now().microsecondsSinceEpoch}',
          conversationKey: widget.conversation.officeName,
          author: MessageAuthor.me,
          text: text,
          time: 'Agora',
          read: false,
        ),
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      final message = await _repository.sendMessage(
        conversationId: widget.conversation.id!,
        body: text,
        senderType: widget.isLawyer ? 'lawyer' : 'client',
      );
      if (!mounted) return;
      _appendMessage(message);
      setState(() => _isSending = false);
    } catch (error) {
      debugPrint('Supabase message send failed: $error');
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível enviar a mensagem.')),
      );
      _messageController.text = text;
    }
  }

  void _appendMessage(ChatMessage message) {
    if (!mounted ||
        _shouldHideCaseRequestStatusText(message) ||
        _messages.any((item) => item.id == message.id)) {
      return;
    }
    setState(() => _messages = [..._messages, message]);
    _scrollToBottom();
  }

  void _upsertMessage(ChatMessage message) {
    if (!mounted) return;

    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index == -1) {
      if (_shouldHideCaseRequestStatusText(message)) return;
      setState(() => _messages = [..._messages, message]);
      _scrollToBottom();
      return;
    }

    final nextMessages = [..._messages];
    nextMessages[index] = message;
    setState(() => _messages = nextMessages);
  }

  bool _shouldHideCaseRequestStatusText(ChatMessage message) {
    if (message.isCaseRequest || message.author != MessageAuthor.system) {
      return false;
    }

    final text = message.text.trim().toLowerCase();
    return text == 'solicitação de caso aceita pelo cliente.' ||
        text == 'solicitação de caso recusada pelo cliente.';
  }

  Future<void> _refreshMessagesSilently() async {
    final conversationId = widget.conversation.id;
    if (conversationId == null) return;

    final messages = await _messagesWithPendingCaseRequestFallback(
      await _repository.fetchMessages(conversationId),
    );
    if (!mounted) return;
    setState(() => _messages = messages);
    _scrollToBottom();
  }

  Future<List<ChatMessage>> _messagesWithPendingCaseRequestFallback(
    List<ChatMessage> messages,
  ) async {
    final conversationId = widget.conversation.id;
    if (widget.isLawyer || conversationId == null || !SupabaseConfig.isReady) {
      return messages;
    }

    try {
      final requests = await _caseRepository.fetchClientCaseRequests();
      final fallbackMessages = requests
          .where((request) => request.conversationId == conversationId)
          .where(
            (request) =>
                !messages.any((message) => message.caseRequestId == request.id),
          )
          .map(_caseRequestFallbackMessage)
          .toList();

      return [
        ...messages.where(
          (message) => !_shouldHideCaseRequestStatusText(message),
        ),
        ...fallbackMessages,
      ];
    } catch (error) {
      debugPrint('Supabase case request fallback fetch failed: $error');
      return messages;
    }
  }

  ChatMessage _caseRequestFallbackMessage(CaseRequest request) {
    return ChatMessage(
      id: 'case_request_${request.id}',
      conversationKey: request.conversationId,
      author: MessageAuthor.system,
      text: 'Solicitação de aceite do caso: ${request.title}',
      time: request.createdAtLabel,
      read: false,
      metadata: {
        'type': 'case_request',
        'case_request_id': request.id,
        'request_status': 'pending',
        'conversation_id': request.conversationId,
        'title': request.title,
        'area': request.area,
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _openCounterpartProfile() async {
    if (_isOpeningProfile || !SupabaseConfig.isReady) return;
    setState(() => _isOpeningProfile = true);

    try {
      if (widget.isLawyer && widget.conversation.clientId != null) {
        final profile = await _profileRepository.fetchProfileById(
          widget.conversation.clientId!,
        );
        if (!mounted) return;
        if (profile == null) throw StateError('Client profile not found.');
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ClientProfileScreen(profile: profile),
          ),
        );
        return;
      }

      if (!widget.isLawyer && widget.conversation.lawFirmId != null) {
        final lawFirm = await _lawFirmRepository.fetchLawFirmById(
          widget.conversation.lawFirmId!,
        );
        if (!mounted) return;
        if (lawFirm == null) throw StateError('Law firm profile not found.');
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LawFirmProfileScreen(lawFirm: lawFirm),
          ),
        );
        return;
      }

      if (!widget.isLawyer && widget.conversation.lawyerId != null) {
        final lawyer = await _lawyerProfileRepository.fetchLawyerById(
          widget.conversation.lawyerId!,
        );
        if (!mounted) return;
        if (lawyer == null) throw StateError('Lawyer profile not found.');
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LawyerProfileScreen(lawyer: lawyer),
          ),
        );
        return;
      }

      throw StateError('Conversation profile not available.');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o perfil.')),
      );
    } finally {
      if (mounted) setState(() => _isOpeningProfile = false);
    }
  }

  bool get _canRequestCase {
    return widget.isLawyer &&
        _usesSupabase &&
        widget.conversation.clientId != null;
  }

  Future<void> _openCaseRequestSheet() async {
    if (_isCreatingCaseRequest) return;

    final draft = await showModalBottomSheet<_CaseRequestDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          _CaseRequestSheet(initialTitle: widget.conversation.specialty),
    );

    if (draft == null || widget.conversation.id == null) return;
    setState(() => _isCreatingCaseRequest = true);

    try {
      await _caseRepository.createCaseRequest(
        conversationId: widget.conversation.id!,
        title: draft.title,
        area: draft.area,
        summary: draft.summary,
      );
      await _refreshMessagesSilently();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitação enviada ao cliente.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível enviar a solicitação.')),
      );
    } finally {
      if (mounted) setState(() => _isCreatingCaseRequest = false);
    }
  }

  Future<void> _respondToCaseRequestFromChat(
    ChatMessage message, {
    required bool accepted,
  }) async {
    final requestId = message.caseRequestId;
    if (requestId == null || _respondingCaseRequestId != null) return;

    setState(() => _respondingCaseRequestId = requestId);

    try {
      await _caseRepository.respondToCaseRequest(
        requestId: requestId,
        accepted: accepted,
      );
      await _refreshMessagesSilently();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accepted ? 'Caso aceito.' : 'Caso recusado.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível responder ao caso.')),
      );
    } finally {
      if (mounted) setState(() => _respondingCaseRequestId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        titleSpacing: 0,
        title: InkWell(
          onTap: _isOpeningProfile ? null : _openCounterpartProfile,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: widget.isLawyer
                      ? AppTheme.lightGold
                      : AppTheme.lightBlue,
                  child: _isOpeningProfile
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          widget.conversation.initials,
                          style: TextStyle(
                            color: widget.isLawyer
                                ? AppTheme.accent
                                : AppTheme.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.conversation.officeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        widget.conversation.specialty,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (_canRequestCase)
            IconButton(
              onPressed: _isCreatingCaseRequest ? null : _openCaseRequestSheet,
              icon: _isCreatingCaseRequest
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.assignment_add),
              tooltip: 'Enviar solicitação de caso',
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    )
                  : _messages.isEmpty
                  ? const _EmptyChatState()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        return _MessageBubble(
                          message: message,
                          counterpartName: widget.conversation.officeName,
                          counterpartInitials: widget.conversation.initials,
                          canRespondToCaseRequest:
                              !widget.isLawyer && message.isPendingCaseRequest,
                          isRespondingCaseRequest:
                              _respondingCaseRequestId == message.caseRequestId,
                          onAcceptCaseRequest: () =>
                              _respondToCaseRequestFromChat(
                                message,
                                accepted: true,
                              ),
                          onDeclineCaseRequest: () =>
                              _respondToCaseRequestFromChat(
                                message,
                                accepted: false,
                              ),
                        );
                      },
                    ),
            ),
            _Composer(
              controller: _messageController,
              isLawyer: widget.isLawyer,
              isSending: _isSending,
              onSend: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}

class _CaseRequestSheet extends StatefulWidget {
  const _CaseRequestSheet({required this.initialTitle});

  final String initialTitle;

  @override
  State<_CaseRequestSheet> createState() => _CaseRequestSheetState();
}

class _CaseRequestSheetState extends State<_CaseRequestSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _areaController;
  final TextEditingController _summaryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: 'Novo caso jurídico');
    _areaController = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _areaController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    final area = _areaController.text.trim();
    if (title.isEmpty || area.isEmpty) return;

    Navigator.of(context).pop(
      _CaseRequestDraft(
        title: title,
        area: area,
        summary: _summaryController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Solicitar aceite do caso',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'O cliente poderá aceitar ou recusar pelo sino, pelo chat ou pela aba Meus Casos.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Título do caso',
              hintText: 'Ex.: Rescisão trabalhista',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _areaController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Área jurídica',
              hintText: 'Ex.: Direito Trabalhista',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _summaryController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Resumo para o cliente',
              hintText: 'Explique o escopo inicial do atendimento',
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submit,
              child: const Text('Enviar solicitação'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CaseRequestDraft {
  final String title;
  final String area;
  final String summary;

  const _CaseRequestDraft({
    required this.title,
    required this.area,
    required this.summary,
  });
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Nenhuma mensagem nesta conversa.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String counterpartName;
  final String counterpartInitials;
  final bool canRespondToCaseRequest;
  final bool isRespondingCaseRequest;
  final VoidCallback onAcceptCaseRequest;
  final VoidCallback onDeclineCaseRequest;

  const _MessageBubble({
    required this.message,
    required this.counterpartName,
    required this.counterpartInitials,
    required this.canRespondToCaseRequest,
    required this.isRespondingCaseRequest,
    required this.onAcceptCaseRequest,
    required this.onDeclineCaseRequest,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isCaseRequest) {
      return _CaseRequestMessageCard(
        message: message,
        requesterName: counterpartName,
        requesterInitials: counterpartInitials,
        canRespond: canRespondToCaseRequest,
        isSubmitting: isRespondingCaseRequest,
        onAccept: onAcceptCaseRequest,
        onDecline: onDeclineCaseRequest,
      );
    }

    final isMine = message.author == MessageAuthor.me;
    final isSystem = message.author == MessageAuthor.system;
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor = isSystem
        ? AppTheme.lightGold
        : isMine
        ? AppTheme.primary
        : AppTheme.card;
    final textColor = isMine ? AppTheme.card : AppTheme.textPrimary;

    return Align(
      alignment: isSystem ? Alignment.center : alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 16),
            ),
            border: isMine ? null : Border.all(color: AppTheme.lightBlueBorder),
          ),
          child: Column(
            crossAxisAlignment: isMine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(
                message.text,
                style: TextStyle(color: textColor, height: 1.35),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.time,
                    style: TextStyle(
                      color: isMine
                          ? AppTheme.card.withValues(alpha: 0.70)
                          : AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isMine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.read ? Icons.done_all : Icons.done,
                      size: 14,
                      color: AppTheme.card.withValues(alpha: 0.70),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaseRequestMessageCard extends StatelessWidget {
  const _CaseRequestMessageCard({
    required this.message,
    required this.requesterName,
    required this.requesterInitials,
    required this.canRespond,
    required this.isSubmitting,
    required this.onAccept,
    required this.onDecline,
  });

  final ChatMessage message;
  final String requesterName;
  final String requesterInitials;
  final bool canRespond;
  final bool isSubmitting;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final status = message.caseRequestStatus ?? 'pending';

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.88,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.card,
            border: Border.all(color: AppTheme.lightGoldBorder),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppTheme.lightGold,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        requesterInitials,
                        style: const TextStyle(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.caseRequestTitle ?? 'Solicitação de caso',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$requesterName · ${message.caseRequestArea ?? 'Atendimento jurídico'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (canRespond) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isSubmitting ? null : onDecline,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.danger,
                          side: const BorderSide(color: AppTheme.divider),
                          minimumSize: const Size(0, 56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text('Recusar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isSubmitting ? null : onAccept,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.card,
                                ),
                              )
                            : const Text('Aceitar caso'),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 12),
                _CaseRequestStatusChip(status: status),
              ],
              const SizedBox(height: 8),
              Text(
                message.time,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaseRequestStatusChip extends StatelessWidget {
  const _CaseRequestStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final accepted = status == 'accepted';
    final declined = status == 'declined';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accepted
            ? AppTheme.successSurface
            : declined
            ? AppTheme.danger.withValues(alpha: 0.10)
            : AppTheme.lightGold,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        accepted
            ? 'Caso aceito'
            : declined
            ? 'Caso recusado'
            : 'Aguardando aceite do cliente',
        style: TextStyle(
          color: accepted
              ? AppTheme.success
              : declined
              ? AppTheme.danger
              : AppTheme.accent,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool isLawyer;
  final bool isSending;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.isLawyer,
    required this.isSending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: AppTheme.card,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.attach_file),
            tooltip: 'Anexar',
          ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: isLawyer
                    ? 'Responder ao cliente'
                    : 'Mensagem para o escritório',
                filled: true,
                fillColor: AppTheme.background,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            height: 44,
            child: ElevatedButton(
              onPressed: isSending ? null : onSend,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: AppTheme.card,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
