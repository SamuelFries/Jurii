import 'package:flutter/material.dart';

import '../data/mock/mock_firm_workspace.dart';
import '../models/conversation.dart';
import '../models/firm_workspace.dart';
import '../repositories/messaging_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_theme.dart';
import '../widgets/conversation_card.dart';
import 'chat_screen.dart';

class FirmMessagesScreen extends StatefulWidget {
  const FirmMessagesScreen({super.key, this.workspace});

  final FirmWorkspace? workspace;

  @override
  State<FirmMessagesScreen> createState() => _FirmMessagesScreenState();
}

class _FirmMessagesScreenState extends State<FirmMessagesScreen> {
  final MessagingRepository _repository = const MessagingRepository();
  int selectedSegment = 0;
  late Future<List<Conversation>> _conversationsFuture;

  @override
  void initState() {
    super.initState();
    _conversationsFuture = _loadConversations();
  }

  @override
  void didUpdateWidget(covariant FirmMessagesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace?.firm.id != widget.workspace?.firm.id) {
      _conversationsFuture = _loadConversations();
    }
  }

  Future<List<Conversation>> _loadConversations() async {
    final fallback = selectedSegment == 0
        ? mockFirmClientConversations
        : mockFirmTeamConversations;
    final lawFirmId = SupabaseConfig.isReady
        ? widget.workspace?.firm.id
        : widget.workspace?.fromSupabase == true
        ? widget.workspace?.firm.id
        : null;

    if (lawFirmId == null) return fallback;

    try {
      return await _repository.fetchConversations(
        scope: selectedSegment == 0
            ? ConversationScope.firmClient
            : ConversationScope.firmTeam,
        lawFirmId: lawFirmId,
      );
    } catch (_) {
      return SupabaseConfig.isReady ? const [] : fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<List<Conversation>>(
        future: _conversationsFuture,
        builder: (context, snapshot) {
          final conversations = snapshot.data;

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Mensagens',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Centralize conversas com clientes e equipe do escritório.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.officePurpleSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.officePurpleBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _SegmentButton(
                        label: 'Clientes',
                        selected: selectedSegment == 0,
                        onTap: () => _selectSegment(0),
                      ),
                    ),
                    Expanded(
                      child: _SegmentButton(
                        label: 'Equipe',
                        selected: selectedSegment == 1,
                        onTap: () => _selectSegment(1),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (snapshot.connectionState == ConnectionState.waiting &&
                  conversations == null)
                const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.officePurple,
                    ),
                  ),
                )
              else if (conversations == null || conversations.isEmpty)
                const _EmptyFirmMessagesState()
              else
                for (var index = 0; index < conversations.length; index++) ...[
                  ConversationCard(
                    conversation: conversations[index],
                    onTap: () => _openChat(context, conversations[index]),
                  ),
                  if (index < conversations.length - 1)
                    const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }

  void _selectSegment(int index) {
    if (selectedSegment == index) return;
    setState(() {
      selectedSegment = index;
      _conversationsFuture = _loadConversations();
    });
  }

  Future<void> _openChat(
    BuildContext context,
    Conversation conversation,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversation: conversation,
          isLawyer: selectedSegment == 0,
        ),
      ),
    );

    if (!mounted) return;
    setState(() => _conversationsFuture = _loadConversations());
  }
}

class _EmptyFirmMessagesState extends StatelessWidget {
  const _EmptyFirmMessagesState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.officePurpleBorder),
      ),
      child: const Text(
        'Nenhuma conversa encontrada para este escritório.',
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.card : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 42,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? AppTheme.officePurple
                    : AppTheme.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
