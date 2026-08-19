import 'dart:async';

import 'package:flutter/material.dart';

import '../models/jurii_notification.dart';
import '../repositories/case_repository.dart';
import '../repositories/messaging_repository.dart';
import '../screens/case_details_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/firm_join_requests.dart';
import 'supabase_config.dart';

/// Para onde uma notificação leva quando tocada.
///
/// `joinRequests`: os pedidos de entrada da banca (quem decide toca no
/// "Pedido para entrar na equipe" e cai na lista com Aprovar/Recusar).
/// `firmWorkspace`: a área da banca que acabou de aprovar a pessoa (o
/// "Você entrou na equipe" leva para dentro, não para uma tela sobre isso).
enum NotificationDestinationKind {
  none,
  conversation,
  legalCase,
  joinRequests,
  firmWorkspace,
}

/// O título que o servidor grava quando APROVA (migration
/// `o_link_pede_em_vez_de_conceder`). O `firm_join_decided` não tem metadata
/// e a recusa usa outro título; este é o único sinal de que há para onde ir.
/// Um teste em test/ confere que a migration ainda grava exatamente isto.
const String tituloDeEntradaAprovada = 'Você entrou na equipe';

/// Decide o destino de uma notificação a partir do metadata que o servidor
/// gravou. Fonte única para o sino e para o push, que chegam por caminhos
/// diferentes mas devem abrir a mesma coisa.
///
/// Precedência: conversa antes de caso. Tipos como `case_request_response`
/// carregam os dois, e a conversa é o lugar onde a pessoa continua o assunto.
///
/// O escopo do ESCRITÓRIO não abre conversa: o painel do escritório abre o
/// chat com limites próprios (não propõe caso, sem triagem) e abrir daqui, com
/// os padrões do [ChatScreen], reintroduziria os dois. Para ele sobra o caso,
/// que é neutro.
NotificationDestinationKind destinationFor(JuriiNotification notification) {
  final isFirm = notification.scope == NotificationScope.firm;
  // Pedido de entrada por link: precisa saber DE QUAL banca; sem o id não
  // há Equipe certa para abrir, e "none" é mais honesto que abrir a errada.
  if (notification.type == 'firm_join_requested') {
    return notification.lawFirmId == null
        ? NotificationDestinationKind.none
        : NotificationDestinationKind.joinRequests;
  }
  // Decisão do pedido: só a aprovação leva a algum lugar (para dentro da
  // banca). A recusa se explica no próprio texto e não abre nada.
  if (notification.type == 'firm_join_decided') {
    return notification.lawFirmId != null &&
            notification.title == tituloDeEntradaAprovada
        ? NotificationDestinationKind.firmWorkspace
        : NotificationDestinationKind.none;
  }
  if (!isFirm && notification.conversationId != null) {
    return NotificationDestinationKind.conversation;
  }
  if (notification.caseId != null) {
    return NotificationDestinationKind.legalCase;
  }
  return NotificationDestinationKind.none;
}

/// Abre o destino da notificação usando o [navigator] informado.
///
/// Devolve `true` quando **empilhou** a tela — não quando o usuário voltou
/// dela. A diferença importa: `Navigator.push` só completa no pop, então
/// esperar por ele deixaria a notificação sem marcar como lida enquanto a
/// pessoa estivesse justamente lendo o conteúdo.
class NotificationRouter {
  const NotificationRouter({
    this.caseRepository = const CaseRepository(),
    this.messagingRepository = const MessagingRepository(),
  });

  final CaseRepository caseRepository;
  final MessagingRepository messagingRepository;

  /// Destino no topo da pilha, para não empilhar uma segunda cópia dele.
  /// Estático porque o app tem um navigator só e o roteador é `const`.
  static String? _topDestination;

  /// Entrar na área de uma banca não é empilhar tela: é o app trocar de
  /// modo e de escritório ativo, estado que mora na raiz (main.dart). A raiz
  /// registra aqui como fazer isso; o roteador só chama. Devolve `true`
  /// quando a pessoa de fato é da banca e a troca aconteceu.
  static Future<bool> Function(String lawFirmId)? enterFirmWorkspace;

  @visibleForTesting
  static void resetForTests() {
    _topDestination = null;
    enterFirmWorkspace = null;
  }

  Future<bool> open(
    NavigatorState navigator,
    JuriiNotification notification,
  ) async {
    switch (destinationFor(notification)) {
      case NotificationDestinationKind.conversation:
        return _openConversation(navigator, notification);
      case NotificationDestinationKind.legalCase:
        return _openCase(navigator, notification);
      case NotificationDestinationKind.joinRequests:
        return _openJoinRequests(navigator, notification);
      case NotificationDestinationKind.firmWorkspace:
        return _openFirmWorkspace(notification);
      case NotificationDestinationKind.none:
        return false;
    }
  }

  Future<bool> _openJoinRequests(
    NavigatorState navigator,
    JuriiNotification notification,
  ) async {
    final lawFirmId = notification.lawFirmId!;
    final key = 'join-requests/$lawFirmId';
    if (_topDestination == key) return true;
    if (!navigator.mounted) return false;
    _push(navigator, key, JoinRequestsScreen(lawFirmId: lawFirmId));
    return true;
  }

  Future<bool> _openFirmWorkspace(JuriiNotification notification) async {
    final entrar = enterFirmWorkspace;
    if (entrar == null) return false;
    try {
      return await entrar(notification.lawFirmId!);
    } catch (_) {
      return false;
    }
  }

  /// A sessão mudou durante a busca? Sem isto, um logout no meio do caminho
  /// empilharia a conversa do usuário anterior sobre a tela de login.
  bool _sessionStillValid(String? uidBefore, NavigatorState navigator) {
    if (!navigator.mounted) return false;
    final now = SupabaseConfig.isReady
        ? SupabaseConfig.client.auth.currentUser?.id
        : null;
    return now != null && now == uidBefore;
  }

  String? get _currentUid => SupabaseConfig.isReady
      ? SupabaseConfig.client.auth.currentUser?.id
      : null;

  Future<bool> _openConversation(
    NavigatorState navigator,
    JuriiNotification notification,
  ) async {
    final uidBefore = _currentUid;
    final key = 'chat/${notification.conversationId}';
    if (_topDestination == key) return true;

    try {
      final conversation = await messagingRepository.fetchConversationById(
        notification.conversationId!,
      );
      if (!_sessionStillValid(uidBefore, navigator)) return false;

      _push(
        navigator,
        key,
        ChatScreen(
          conversation: conversation,
          isLawyer: notification.scope == NotificationScope.lawyer,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _openCase(
    NavigatorState navigator,
    JuriiNotification notification,
  ) async {
    final uidBefore = _currentUid;
    final key = 'case/${notification.caseId}';
    if (_topDestination == key) return true;

    try {
      final target = await caseRepository.fetchCaseById(notification.caseId!);
      if (target == null) return false;
      if (!_sessionStillValid(uidBefore, navigator)) return false;

      _push(
        navigator,
        key,
        CaseDetailsScreen(
          caseId: target.id,
          title: target.title,
          subtitle: target.subtitle,
          canAddUpdates: target.canAddUpdates,
          cnjNumber: target.cnjNumber,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Empilha sem esperar o pop, e limpa a marca do topo quando a tela sai.
  void _push(NavigatorState navigator, String key, Widget screen) {
    _topDestination = key;
    unawaited(
      navigator
          .push(
            MaterialPageRoute(
              settings: RouteSettings(name: key),
              builder: (_) => screen,
            ),
          )
          .whenComplete(() {
            if (_topDestination == key) _topDestination = null;
          }),
    );
  }
}
