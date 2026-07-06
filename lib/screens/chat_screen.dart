import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/mock/mock_chat_messages.dart';
import '../models/case_request.dart';
import '../models/chat_attachment.dart';
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
  final bool canRequestCase;

  const ChatScreen({
    super.key,
    required this.conversation,
    required this.isLawyer,
    this.canRequestCase = true,
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
  bool _loadFailed = false;
  bool _hasSubscribedOnce = false;
  bool _isSending = false;
  bool _isUploadingAttachment = false;
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
        _loadFailed = false;
      });
      _scrollToBottom();
    } catch (error) {
      debugPrint('Supabase messages fetch failed: $error');
      if (!mounted) return;
      setState(() {
        _messages = _usesSupabase ? const [] : _mockMessages();
        _isLoading = false;
        // Falha de rede não pode parecer conversa vazia: mostra erro + retry.
        _loadFailed = _usesSupabase;
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
            unawaited(_appendRealtimeMessage(payload.newRecord));
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
            unawaited(_upsertRealtimeMessage(payload.newRecord));
          },
        )
        .subscribe((status, [error]) {
          // O Supabase não reenvia eventos perdidos: ao reassinar depois de
          // uma queda, refaz o fetch (o dedupe por id absorve repetidos).
          if (status == RealtimeSubscribeStatus.subscribed) {
            if (_hasSubscribedOnce) {
              unawaited(_refreshMessagesSilently());
            }
            _hasSubscribedOnce = true;
          }
        });
  }

  Future<void> _appendRealtimeMessage(Map<String, dynamic> row) async {
    final message = await _repository.messageFromRowWithAttachment(
      row,
      currentUserId: SupabaseConfig.client.auth.currentUser?.id,
    );
    _appendMessage(message);
  }

  Future<void> _upsertRealtimeMessage(Map<String, dynamic> row) async {
    final message = await _repository.messageFromRowWithAttachment(
      row,
      currentUserId: SupabaseConfig.client.auth.currentUser?.id,
    );
    _upsertMessage(message);
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
      // Restaura o texto só se o usuário não começou outro rascunho.
      if (_messageController.text.trim().isEmpty) {
        _messageController.text = text;
      }
    }
  }

  Future<void> _sendAttachment() async {
    if (_isUploadingAttachment) return;

    if (!_usesSupabase || !SupabaseConfig.isReady) {
      _showSnackBar('Anexos estão disponíveis apenas em conversas online.');
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      withData: true,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'pdf',
        'doc',
        'docx',
      ],
    );

    final file = picked?.files.single;
    if (file == null) return;

    final mimeType = _mimeTypeForFile(file.name);
    final kind = _attachmentKindForMime(mimeType);
    final bytes = file.bytes;

    if (!mounted) return;

    if (mimeType == null || kind == null) {
      _showSnackBar('Envie apenas fotos, PDF, DOC ou DOCX.');
      return;
    }

    if (bytes == null || bytes.isEmpty) {
      _showSnackBar('Não foi possível ler o arquivo selecionado.');
      return;
    }

    if (!_bytesMatchMimeType(bytes, mimeType)) {
      _showSnackBar('Arquivo inválido ou corrompido.');
      return;
    }

    final maxSize = kind == ChatAttachmentKind.image
        ? 5 * 1024 * 1024
        : 10 * 1024 * 1024;
    if (file.size > maxSize) {
      _showSnackBar(
        kind == ChatAttachmentKind.image
            ? 'Fotos podem ter no máximo 5 MB.'
            : 'Documentos podem ter no máximo 10 MB.',
      );
      return;
    }

    setState(() => _isUploadingAttachment = true);
    try {
      final message = await _repository.sendAttachment(
        conversationId: widget.conversation.id!,
        fileName: file.name,
        mimeType: mimeType,
        fileSizeBytes: file.size,
        bytes: Uint8List.fromList(bytes),
        kind: kind,
        senderType: widget.isLawyer ? 'lawyer' : 'client',
      );
      if (!mounted) return;
      _appendMessage(message);
    } catch (error) {
      debugPrint('Supabase attachment send failed: $error');
      if (!mounted) return;
      _showSnackBar(_friendlyAttachmentError(error));
    } finally {
      if (mounted) setState(() => _isUploadingAttachment = false);
    }
  }

  Future<void> _openAttachment(ChatAttachment attachment) async {
    if (!SupabaseConfig.isReady) return;

    try {
      final signedUrl = await _repository.createSignedAttachmentUrl(attachment);
      if (!mounted) return;

      if (attachment.isImage) {
        await showDialog<void>(
          context: context,
          builder: (_) => _ImageAttachmentDialog(
            attachment: attachment,
            signedUrl: signedUrl,
          ),
        );
        return;
      }

      final uri = Uri.parse(signedUrl);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        _showSnackBar('Não foi possível abrir o arquivo.');
      }
    } catch (error) {
      debugPrint('Supabase attachment open failed: $error');
      if (!mounted) return;
      _showSnackBar('Não foi possível abrir o anexo.');
    }
  }

  /// Confere a assinatura (magic bytes) do arquivo contra o MIME derivado da
  /// extensão — impede binário arbitrário renomeado para .pdf/.jpg.
  bool _bytesMatchMimeType(List<int> bytes, String mimeType) {
    bool startsWith(List<int> signature) {
      if (bytes.length < signature.length) return false;
      for (var i = 0; i < signature.length; i++) {
        if (bytes[i] != signature[i]) return false;
      }
      return true;
    }

    switch (mimeType) {
      case 'application/pdf':
        return startsWith(const [0x25, 0x50, 0x44, 0x46]); // %PDF
      case 'image/jpeg':
        return startsWith(const [0xFF, 0xD8, 0xFF]);
      case 'image/png':
        return startsWith(const [0x89, 0x50, 0x4E, 0x47]);
      case 'image/webp':
        return bytes.length >= 12 &&
            startsWith(const [0x52, 0x49, 0x46, 0x46]) && // RIFF
            bytes[8] == 0x57 &&
            bytes[9] == 0x45 &&
            bytes[10] == 0x42 &&
            bytes[11] == 0x50; // WEBP
      case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        return startsWith(const [0x50, 0x4B]); // ZIP (PK)
      case 'application/msword':
        // .doc legado (OLE) ou salvo como zip por editores modernos.
        return startsWith(const [0xD0, 0xCF, 0x11, 0xE0]) ||
            startsWith(const [0x50, 0x4B]);
      default:
        return false;
    }
  }

  String _friendlyAttachmentError(Object error) {
    final message = error.toString().toLowerCase();
    debugPrint('Chat attachment error: $error');
    if ((message.contains('metadata') && message.contains('ambiguous')) ||
        message.contains('42702')) {
      return 'Não foi possível enviar o anexo. Tente novamente mais tarde.';
    }
    if (message.contains('send_chat_attachment') ||
        message.contains('chat-attachments') ||
        message.contains('message_attachments') ||
        message.contains('pgrst202') ||
        message.contains('schema cache')) {
      return 'Não foi possível enviar o anexo. Tente novamente mais tarde.';
    }
    if (message.contains('row-level security') ||
        message.contains('permission denied')) {
      return 'Você não tem permissão para enviar anexos nesta conversa.';
    }
    return 'Não foi possível enviar o anexo.';
  }

  String? _mimeTypeForFile(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      _ => null,
    };
  }

  ChatAttachmentKind? _attachmentKindForMime(String? mimeType) {
    if (mimeType == null) return null;
    if (mimeType.startsWith('image/')) return ChatAttachmentKind.image;
    if (mimeType == 'application/pdf' ||
        mimeType == 'application/msword' ||
        mimeType ==
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
      return ChatAttachmentKind.document;
    }
    return null;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _appendMessage(ChatMessage message) {
    if (!mounted ||
        _shouldHideCaseRequestStatusText(message) ||
        _messages.any((item) => item.id == message.id)) {
      return;
    }
    setState(
      () => _messages = [..._withoutDuplicateCaseRequest(message), message],
    );
    _scrollToBottom();
  }

  void _upsertMessage(ChatMessage message) {
    if (!mounted) return;

    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index == -1) {
      if (_shouldHideCaseRequestStatusText(message)) return;
      setState(
        () => _messages = [..._withoutDuplicateCaseRequest(message), message],
      );
      _scrollToBottom();
      return;
    }

    final nextMessages = [..._messages];
    nextMessages[index] = message;
    setState(() => _messages = nextMessages);
  }

  /// Remove o card sintético de solicitação de caso (id `case_request_<id>`)
  /// quando a mensagem real da mesma solicitação chega via realtime —
  /// sem isso o cliente veria a solicitação duplicada com dois pares de botões.
  List<ChatMessage> _withoutDuplicateCaseRequest(ChatMessage incoming) {
    final requestId = incoming.caseRequestId;
    if (requestId == null) return _messages;
    return _messages
        .where(
          (item) => item.id == incoming.id || item.caseRequestId != requestId,
        )
        .toList(growable: false);
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
        widget.canRequestCase &&
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

    if (!mounted || draft == null || widget.conversation.id == null) return;
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
                  : _loadFailed && _messages.isEmpty
                  ? _ChatLoadErrorState(onRetry: _loadMessages)
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
                          onOpenAttachment: _openAttachment,
                        );
                      },
                    ),
            ),
            _Composer(
              controller: _messageController,
              isLawyer: widget.isLawyer,
              isSending: _isSending,
              isUploadingAttachment: _isUploadingAttachment,
              onSend: _sendMessage,
              onAttach: _sendAttachment,
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

class _ChatLoadErrorState extends StatelessWidget {
  const _ChatLoadErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Não foi possível carregar as mensagens.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
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
  final ValueChanged<ChatAttachment> onOpenAttachment;

  const _MessageBubble({
    required this.message,
    required this.counterpartName,
    required this.counterpartInitials,
    required this.canRespondToCaseRequest,
    required this.isRespondingCaseRequest,
    required this.onAcceptCaseRequest,
    required this.onDeclineCaseRequest,
    required this.onOpenAttachment,
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
              if (message.attachment != null) ...[
                _AttachmentTile(
                  attachment: message.attachment!,
                  isMine: isMine,
                  onTap: () => onOpenAttachment(message.attachment!),
                ),
                if (message.text.trim().isNotEmpty) const SizedBox(height: 8),
              ],
              if (message.text.trim().isNotEmpty)
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

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.isMine,
    required this.onTap,
  });

  final ChatAttachment attachment;
  final bool isMine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = attachment.isImage
        ? Icons.image_outlined
        : attachment.mimeType == 'application/pdf'
        ? Icons.picture_as_pdf_outlined
        : Icons.description_outlined;
    final surfaceColor = isMine
        ? AppTheme.card.withValues(alpha: 0.14)
        : AppTheme.lightBlue;
    final foregroundColor = isMine ? AppTheme.card : AppTheme.textPrimary;
    final secondaryColor = isMine
        ? AppTheme.card.withValues(alpha: 0.72)
        : AppTheme.textSecondary;

    return Material(
      color: surfaceColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minWidth: 210),
          padding: const EdgeInsets.all(10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isMine
                      ? AppTheme.card.withValues(alpha: 0.16)
                      : AppTheme.card,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: foregroundColor, size: 20),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foregroundColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      attachment.isImage
                          ? 'Foto - ${attachment.sizeLabel}'
                          : 'Documento - ${attachment.sizeLabel}',
                      style: TextStyle(
                        color: secondaryColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.open_in_new, color: secondaryColor, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageAttachmentDialog extends StatelessWidget {
  const _ImageAttachmentDialog({
    required this.attachment,
    required this.signedUrl,
  });

  final ChatAttachment attachment;
  final String signedUrl;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          maxWidth: 720,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Fechar',
                  ),
                ],
              ),
            ),
            Flexible(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(18),
                ),
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Image.network(
                    signedUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const SizedBox(
                        height: 320,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.primary,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox(
                        height: 260,
                        child: Center(
                          child: Text(
                            'Não foi possível carregar a imagem.',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
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
  final bool isUploadingAttachment;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  const _Composer({
    required this.controller,
    required this.isLawyer,
    required this.isSending,
    required this.isUploadingAttachment,
    required this.onSend,
    required this.onAttach,
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
            onPressed: isUploadingAttachment || isSending ? null : onAttach,
            icon: isUploadingAttachment
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: AppTheme.primary,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.attach_file),
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
