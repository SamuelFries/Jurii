import 'package:flutter/material.dart';

import '../data/mock/mock_messages.dart';
import 'chat_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/conversation_card.dart';

class MessagesScreen extends StatelessWidget {
  final VoidCallback? onFindLawFirms;

  const MessagesScreen({super.key, this.onFindLawFirms});

  @override
  Widget build(BuildContext context) {
    const conversations = mockClientConversations;

    return SafeArea(
      child: conversations.isEmpty
          ? _EmptyMessagesState(onFindLawFirms: onFindLawFirms)
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const _MessagesHeader(
                  title: 'Conversas',
                  subtitle: 'Acompanhe seus atendimentos jurídicos.',
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
                            isLawyer: false,
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
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
        ),
      ],
    );
  }
}

class _EmptyMessagesState extends StatelessWidget {
  final VoidCallback? onFindLawFirms;

  const _EmptyMessagesState({this.onFindLawFirms});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Conversas',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Suas conversas com escritórios aparecerão nesta área.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
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
                  'Nenhuma conversa iniciada',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  'Quando você solicitar atendimento a um escritório, suas conversas aparecerão aqui.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
                ),

                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: onFindLawFirms,
                  child: const Text('Encontrar Escritórios'),
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
