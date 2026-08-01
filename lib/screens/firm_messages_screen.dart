import 'dart:async';

import 'package:flutter/material.dart';

import '../data/mock/mock_firm_workspace.dart';
import '../models/conversation.dart';
import '../models/firm_workspace.dart';
import '../repositories/messaging_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../widgets/conversation_card.dart';
import '../widgets/jurii_empty_state.dart';
import '../widgets/jurii_error_state.dart';
import '../widgets/jurii_motion.dart';
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
    // Mock apenas no modo demo (Supabase não configurado); usuário real com
    // workspace ainda não sincronizado vê o empty state, não dados fake.
    if (!SupabaseConfig.isReady) {
      return selectedSegment == 0
          ? mockFirmClientConversations
          : mockFirmTeamConversations;
    }

    // Só consulta o Supabase quando o workspace é real (ids locais como
    // 'approved_firm' não são uuid e quebrariam a query).
    final lawFirmId = widget.workspace?.fromSupabase == true
        ? widget.workspace?.firm.id
        : null;

    if (lawFirmId == null) return const [];

    try {
      return await _repository.fetchConversations(
        scope: selectedSegment == 0
            ? ConversationScope.firmClient
            : ConversationScope.firmTeam,
        lawFirmId: lawFirmId,
      );
    } catch (error) {
      // Erro sobe para o FutureBuilder: falha de rede não pode virar
      // "Nenhuma conversa encontrada" no painel do escritório.
      debugPrint('Supabase firm conversations fetch failed: $error');
      rethrow;
    }
  }

  void _retry() {
    setState(() => _conversationsFuture = _loadConversations()..ignore());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return SafeArea(
      child: FutureBuilder<List<Conversation>>(
        future: _conversationsFuture,
        builder: (context, snapshot) {
          final conversations = snapshot.data;

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Mensagens',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Centralize conversas com clientes e equipe do escritório.',
                style: TextStyle(color: colors.textSecondary, fontSize: 16),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colors.officePurpleSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.officePurpleBorder),
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
                  padding: EdgeInsets.only(top: 4),
                  child: JuriiSkeletonList(itemCount: 4, itemHeight: 86),
                )
              else if (snapshot.hasError && conversations == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: JuriiErrorState(
                    title: 'Não foi possível carregar as conversas.',
                    onRetry: _retry,
                  ),
                )
              else if (conversations == null || conversations.isEmpty)
                const _EmptyFirmMessagesState()
              else
                for (var index = 0; index < conversations.length; index++) ...[
                  JuriiStaggeredItem(
                    key: ValueKey(
                      'firm_conversation_${selectedSegment}_${conversations[index].id ?? conversations[index].officeName}',
                    ),
                    index: index,
                    child: ConversationCard(
                      conversation: conversations[index],
                      onTap: () => _openChat(context, conversations[index]),
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

  void _selectSegment(int index) {
    if (selectedSegment == index) return;
    setState(() {
      selectedSegment = index;
      _conversationsFuture = _loadConversations()..ignore();
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
          // O escritório não propõe caso: ele sugere um advogado da equipe, e o
          // caso nasce depois, na conversa entre cliente e advogado.
          canRequestCase: false,
          canRecommendLawyer:
              selectedSegment == 0 &&
              widget.workspace?.canRecommendLawyers == true,
          // Quem abre o chat aqui é o escritório, nunca o cliente — a triagem
          // não pode aparecer (nem no chat interno de equipe, que também usa
          // isLawyer=false).
          allowTriage: false,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      _conversationsFuture = _loadConversations()..ignore();
    });
  }
}

class _EmptyFirmMessagesState extends StatelessWidget {
  const _EmptyFirmMessagesState();

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: JuriiEmptyState(
        icon: Icons.mark_chat_unread_outlined,
        title: 'Nenhuma conversa encontrada',
        message:
            'As conversas do escritório com clientes e equipe aparecerão aqui.',
        accentColor: colors.officePurple,
        surfaceColor: colors.officePurpleSurface,
        borderColor: colors.officePurpleBorder,
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
    final colors = context.jColors;

    return JuriiPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      semanticLabel: label,
      child: AnimatedContainer(
        duration: JuriiMotion.fast,
        curve: JuriiMotion.ease,
        decoration: BoxDecoration(
          color: selected ? colors.card : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: SizedBox(
          height: 42,
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: JuriiMotion.fast,
              curve: JuriiMotion.ease,
              style: TextStyle(
                color: selected ? colors.officePurple : colors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}
