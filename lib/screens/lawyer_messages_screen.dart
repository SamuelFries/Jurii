import 'package:flutter/material.dart';
import '../data/mock/mock_messages.dart';
import 'chat_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/conversation_card.dart';

class LawyerMessagesScreen extends StatelessWidget {
  const LawyerMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const conversations = mockLawyerConversations;

    return SafeArea(
      child: conversations.isEmpty
          ? const _EmptyMessagesState()
          : ListView(
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
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            conversation: conversations[index],
                            isLawyer: true,
                          ),
                        ),
                      );
                    },
                  ),
                  if (index < conversations.length - 1)
                    const SizedBox(height: 12),
                ],
              ],
            ),
    );
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
