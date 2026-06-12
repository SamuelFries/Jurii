import 'package:flutter/material.dart';

import '../data/mock/mock_chat_messages.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../repositories/messaging_repository.dart';
import '../theme/app_theme.dart';

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
  final MessagingRepository _repository = const MessagingRepository();
  List<ChatMessage> _messages = const [];
  bool _isLoading = true;
  bool _isSending = false;

  bool get _usesSupabase => widget.conversation.id != null;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
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
      return;
    }

    try {
      final messages = await _repository.fetchMessages(widget.conversation.id!);
      if (!mounted) return;
      setState(() {
        _messages = messages.isEmpty ? _mockMessages() : messages;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages = _mockMessages();
        _isLoading = false;
      });
    }
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
      setState(() {
        _messages = [
          ..._messages,
          ChatMessage(
            id: 'local_${DateTime.now().microsecondsSinceEpoch}',
            conversationKey: widget.conversation.officeName,
            author: MessageAuthor.me,
            text: text,
            time: 'Agora',
            read: false,
          ),
        ];
      });
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
      setState(() {
        _messages = [..._messages, message];
        _isSending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível enviar a mensagem.')),
      );
      _messageController.text = text;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: widget.isLawyer
                  ? AppTheme.lightGold
                  : AppTheme.lightBlue,
              child: Text(
                widget.conversation.initials,
                style: TextStyle(
                  color: widget.isLawyer ? AppTheme.accent : AppTheme.primary,
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
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadMessages,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar conversa',
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
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[_messages.length - 1 - index];
                        return _MessageBubble(message: message);
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

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
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
