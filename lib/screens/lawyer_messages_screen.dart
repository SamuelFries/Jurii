import 'package:flutter/material.dart';

import '../data/mock/mock_messages.dart';
import '../models/conversation.dart';
import '../repositories/messaging_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../widgets/conversation_card.dart';
import '../widgets/jurii_empty_state.dart';
import '../widgets/jurii_motion.dart';
import 'chat_screen.dart';

class LawyerMessagesScreen extends StatefulWidget {
  const LawyerMessagesScreen({super.key});

  @override
  State<LawyerMessagesScreen> createState() => _LawyerMessagesScreenState();
}

class _LawyerMessagesScreenState extends State<LawyerMessagesScreen> {
  final MessagingRepository _repository = const MessagingRepository();
  late Future<List<Conversation>> _conversationsFuture;

  @override
  void initState() {
    super.initState();
    _conversationsFuture = _loadConversations();
  }

  Future<List<Conversation>> _loadConversations() async {
    try {
      final conversations = await _repository.fetchConversations(
        scope: ConversationScope.lawyer,
      );
      if (conversations.isNotEmpty || SupabaseConfig.isReady) {
        return conversations;
      }
      return mockLawyerConversations;
    } catch (_) {
      return SupabaseConfig.isReady ? const [] : mockLawyerConversations;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<List<Conversation>>(
        future: _conversationsFuture,
        builder: (context, snapshot) {
          final conversations = snapshot.data;

          if (snapshot.connectionState == ConnectionState.waiting &&
              conversations == null) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MessagesHeader(
                    title: 'Mensagens',
                    subtitle: 'Converse com clientes e acompanhe contatos.',
                  ),
                  SizedBox(height: 20),
                  JuriiSkeletonList(itemCount: 4, itemHeight: 86),
                ],
              ),
            );
          }

          if (conversations == null || conversations.isEmpty) {
            return const _EmptyMessagesState();
          }

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const _MessagesHeader(
                title: 'Mensagens',
                subtitle: 'Converse com clientes e acompanhe contatos.',
              ),
              const SizedBox(height: 20),
              for (var index = 0; index < conversations.length; index++) ...[
                JuriiStaggeredItem(
                  key: ValueKey(
                    'lawyer_conversation_${conversations[index].id ?? conversations[index].officeName}',
                  ),
                  index: index,
                  child: ConversationCard(
                    conversation: conversations[index],
                    onTap: () => _openChat(conversations[index]),
                  ),
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

  Future<void> _openChat(Conversation conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(conversation: conversation, isLawyer: true),
      ),
    );

    if (!mounted) return;
    setState(() {
      _conversationsFuture = _loadConversations();
    });
  }
}

class _MessagesHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _MessagesHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 16,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

class _EmptyMessagesState extends StatelessWidget {
  const _EmptyMessagesState();

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mensagens',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Mensagens de clientes e contatos profissionais.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 16,
              decoration: TextDecoration.none,
            ),
          ),
          const Spacer(),
          const Center(
            child: JuriiEmptyState(
              icon: Icons.chat_bubble_outline,
              title: 'Nenhuma mensagem recebida',
              message:
                  'Quando clientes entrarem em contato, as conversas aparecerão aqui.',
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
