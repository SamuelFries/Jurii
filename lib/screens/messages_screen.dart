import 'dart:async';

import 'package:flutter/material.dart';

import '../data/mock/mock_messages.dart';
import '../models/conversation.dart';
import '../repositories/messaging_repository.dart';
import '../services/realtime_refresh.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../widgets/conversation_card.dart';
import '../widgets/jurii_empty_state.dart';
import '../widgets/jurii_error_state.dart';
import '../widgets/jurii_motion.dart';
import 'chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  final VoidCallback? onFindLawFirms;

  const MessagesScreen({super.key, this.onFindLawFirms});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with RealtimeRefresh<MessagesScreen> {
  final MessagingRepository _repository = const MessagingRepository();
  late Future<List<Conversation>> _conversationsFuture;

  @override
  void initState() {
    super.initState();
    _conversationsFuture = _loadConversations();
    // Mensagem nova em QUALQUER conversa do usuário mexe nesta lista (último
    // texto, horário, ordem). Sem filtro de coluna de propósito: quem corta é
    // a RLS de `messages` — o assinante só recebe o que já poderia ler.
    subscribeToRealtime(
      channelName: 'client_conversations:${SupabaseConfig.client.auth.currentUser?.id}',
      table: 'messages',
      event: PostgresChangeEvent.insert,
      onChange: _refreshSilently,
    );
  }

  /// Recarrega sem trocar o Future exibido: o realtime não pode piscar o
  /// skeleton nem derrubar a lista para o estado de erro.
  Future<void> _refreshSilently() async {
    try {
      final conversations = await _loadConversations();
      if (!mounted) return;
      setState(() => _conversationsFuture = Future.value(conversations));
    } catch (_) {
      // Mantém o que está na tela; o refresh manual e o retry seguem.
    }
  }

  Future<List<Conversation>> _loadConversations() async {
    try {
      final conversations = await _repository.fetchConversations(
        scope: ConversationScope.client,
      );
      if (conversations.isNotEmpty || SupabaseConfig.isReady) {
        return conversations;
      }
      return mockClientConversations;
    } catch (error) {
      // Erro sobe para o FutureBuilder: falha de rede não pode virar
      // "Nenhuma conversa iniciada".
      debugPrint('Supabase client conversations fetch failed: $error');
      if (SupabaseConfig.isReady) rethrow;
      return mockClientConversations;
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
                    title: 'Conversas',
                    subtitle: 'Acompanhe seus atendimentos jurídicos.',
                  ),
                  SizedBox(height: 20),
                  JuriiSkeletonList(itemCount: 4, itemHeight: 86),
                ],
              ),
            );
          }

          if (snapshot.hasError && conversations == null) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _MessagesHeader(
                    title: 'Conversas',
                    subtitle: 'Acompanhe seus atendimentos jurídicos.',
                  ),
                  Expanded(
                    child: JuriiErrorState(
                      title: 'Não foi possível carregar suas conversas.',
                      onRetry: _retry,
                    ),
                  ),
                ],
              ),
            );
          }

          if (conversations == null || conversations.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    // Altura fixa do viewport: os Spacer() do empty state
                    // precisam de altura limitada para funcionar.
                    height: constraints.maxHeight,
                    child: _EmptyMessagesState(
                      onFindLawFirms: widget.onFindLawFirms,
                    ),
                  ),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const _MessagesHeader(
                  title: 'Conversas',
                  subtitle: 'Acompanhe seus atendimentos jurídicos.',
                ),
                const SizedBox(height: 20),
                for (var index = 0; index < conversations.length; index++) ...[
                  JuriiStaggeredItem(
                    key: ValueKey(
                      'client_conversation_${conversations[index].id ?? conversations[index].officeName}',
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
            ),
          );
        },
      ),
    );
  }

  Future<void> _refresh() async {
    final future = _loadConversations();
    setState(() => _conversationsFuture = future);
    try {
      await future;
    } catch (_) {
      // O FutureBuilder exibe o estado de erro.
    }
  }

  void _retry() {
    setState(() => _conversationsFuture = _loadConversations()..ignore());
  }

  Future<void> _openChat(Conversation conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(conversation: conversation, isLawyer: false),
      ),
    );

    if (!mounted) return;
    setState(() {
      _conversationsFuture = _loadConversations()..ignore();
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
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(color: colors.textSecondary, fontSize: 16),
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
    final colors = context.jColors;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conversas',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Suas conversas com escritórios aparecerão nesta área.',
            style: TextStyle(color: colors.textSecondary, fontSize: 16),
          ),
          const Spacer(),
          Center(
            child: JuriiEmptyState(
              icon: Icons.chat_bubble_outline,
              title: 'Nenhuma conversa iniciada',
              message:
                  'Quando você solicitar atendimento a um escritório, suas conversas aparecerão aqui.',
              actionLabel: 'Encontrar Escritórios',
              onAction: onFindLawFirms,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
