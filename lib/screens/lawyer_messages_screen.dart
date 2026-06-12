import 'package:flutter/material.dart';

import '../data/mock/mock_messages.dart';
import '../models/conversation.dart';
import '../repositories/messaging_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_theme.dart';
import '../widgets/conversation_card.dart';
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
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
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
                ConversationCard(
                  conversation: conversations[index],
                  onTap: () => _openChat(conversations[index]),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppTheme.textSecondary,
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mensagens',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Mensagens de clientes e contatos profissionais.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 16,
              decoration: TextDecoration.none,
            ),
          ),
          const Spacer(),
          Center(
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppTheme.lightBlue,
                    borderRadius: BorderRadius.circular(48),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline,
                    size: 42,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Nenhuma mensagem recebida',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Quando clientes entrarem em contato, as conversas aparecerão aqui.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 15,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
