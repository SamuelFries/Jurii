import 'dart:async';

import 'package:flutter/material.dart';

import '../data/mock/mock_messages.dart';
import '../models/conversation.dart';
import '../repositories/messaging_repository.dart';
import '../services/realtime_refresh.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../utils/inbox_filters.dart';
import '../widgets/conversation_card.dart';
import '../widgets/jurii_empty_state.dart';
import '../widgets/jurii_error_state.dart';
import '../widgets/jurii_filter_chip_row.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/jurii_no_results_state.dart';
import '../widgets/jurii_search_field.dart';
import 'chat_screen.dart';

class LawyerMessagesScreen extends StatefulWidget {
  const LawyerMessagesScreen({super.key});

  @override
  State<LawyerMessagesScreen> createState() => _LawyerMessagesScreenState();
}

class _LawyerMessagesScreenState extends State<LawyerMessagesScreen>
    with RealtimeRefresh<LawyerMessagesScreen> {
  final MessagingRepository _repository = const MessagingRepository();
  late Future<List<Conversation>> _conversationsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _onlyUnread = false;

  @override
  void initState() {
    super.initState();
    _conversationsFuture = _loadConversations();
    // Mensagem nova mexe nesta lista (último texto, horário, ordem). Assina
    // `conversations`, não `messages`: o trigger
    // messages_set_conversation_last_message atualiza a conversa a cada
    // mensagem, então é UM evento por conversa em vez de um por mensagem — e
    // o filtro por lawyer_id corta no SERVIDOR, sem depender da RLS para a
    // privacidade nem trazer o corpo da mensagem no payload.
    final userId = SupabaseConfig.isReady
        ? SupabaseConfig.client.auth.currentUser?.id
        : null;
    if (userId != null) {
      subscribeToRealtime(
        channelPrefix: 'lawyer_conversations',
        table: 'conversations',
        filterColumn: 'lawyer_id',
        filterValue: userId,
        onChange: _refreshSilently,
      );
    }
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
        scope: ConversationScope.lawyer,
      );
      if (conversations.isNotEmpty || SupabaseConfig.isReady) {
        return conversations;
      }
      return mockLawyerConversations;
    } catch (error) {
      // Erro sobe para o FutureBuilder: falha de rede não pode virar
      // "Nenhuma conversa" — advogado sem sinal acharia que perdeu clientes.
      debugPrint('Supabase lawyer conversations fetch failed: $error');
      if (SupabaseConfig.isReady) rethrow;
      return mockLawyerConversations;
    }
  }

  void _retry() {
    setState(() => _conversationsFuture = _loadConversations()..ignore());
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

          if (snapshot.hasError && conversations == null) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _MessagesHeader(
                    title: 'Mensagens',
                    subtitle: 'Converse com clientes e acompanhe contatos.',
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
            return const _EmptyMessagesState();
          }

          final visiveis = filterConversations(
            conversations,
            query: _searchQuery,
            onlyUnread: _onlyUnread,
          );

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const _MessagesHeader(
                title: 'Mensagens',
                subtitle: 'Converse com clientes e acompanhe contatos.',
              ),
              const SizedBox(height: 20),
              JuriiSearchField(
                controller: _searchController,
                hintText: 'Buscar por cliente ou área',
                semanticLabel: 'Buscar nas suas conversas',
                onChanged: _onSearchChanged,
              ),
              const SizedBox(height: 12),
              JuriiFilterChipRow(
                total: conversations.length,
                filters: [
                  JuriiListFilter(
                    label: 'Não lidas',
                    matches: conversations
                        .where((c) => c.unreadCount > 0)
                        .length,
                    selected: _onlyUnread,
                    onToggle: () => setState(() => _onlyUnread = !_onlyUnread),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (visiveis.isEmpty)
                JuriiNoResultsState(
                  message: _mensagemSemResultado(conversations.length),
                  onClear: _clearFilters,
                )
              else
                for (var index = 0; index < visiveis.length; index++) ...[
                  JuriiStaggeredItem(
                    key: ValueKey(
                      'lawyer_conversation_${visiveis[index].id ?? visiveis[index].officeName}',
                    ),
                    index: index,
                    child: ConversationCard(
                      conversation: visiveis[index],
                      onTap: () => _openChat(visiveis[index]),
                    ),
                  ),
                  if (index < visiveis.length - 1) const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value.trim());
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _onlyUnread = false;
    });
  }

  /// Diz o que continua existindo: filtrar até zerar não pode parecer perda.
  String _mensagemSemResultado(int total) {
    final conversas = total == 1 ? 'conversa' : 'conversas';
    return _onlyUnread && _searchQuery.isEmpty
        ? 'Nenhuma conversa não lida. Suas $total $conversas continuam aqui.'
        : 'Nenhuma conversa combina com esse filtro. Suas $total $conversas continuam aqui.';
  }

  Future<void> _openChat(Conversation conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(conversation: conversation, isLawyer: true),
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
