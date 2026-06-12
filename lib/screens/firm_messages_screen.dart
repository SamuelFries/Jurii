import 'package:flutter/material.dart';

import '../data/mock/mock_firm_workspace.dart';
import '../models/conversation.dart';
import '../theme/app_theme.dart';
import '../widgets/conversation_card.dart';
import 'chat_screen.dart';

class FirmMessagesScreen extends StatefulWidget {
  const FirmMessagesScreen({super.key});

  @override
  State<FirmMessagesScreen> createState() => _FirmMessagesScreenState();
}

class _FirmMessagesScreenState extends State<FirmMessagesScreen> {
  int selectedSegment = 0;

  @override
  Widget build(BuildContext context) {
    final conversations = selectedSegment == 0
        ? mockFirmClientConversations
        : mockFirmTeamConversations;

    return SafeArea(
      child: ListView(
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
                    onTap: () => setState(() => selectedSegment = 0),
                  ),
                ),
                Expanded(
                  child: _SegmentButton(
                    label: 'Equipe',
                    selected: selectedSegment == 1,
                    onTap: () => setState(() => selectedSegment = 1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          for (var index = 0; index < conversations.length; index++) ...[
            ConversationCard(
              conversation: conversations[index],
              onTap: () => _openChat(context, conversations[index]),
            ),
            if (index < conversations.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  void _openChat(BuildContext context, Conversation conversation) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversation: conversation,
          isLawyer: selectedSegment == 0,
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
