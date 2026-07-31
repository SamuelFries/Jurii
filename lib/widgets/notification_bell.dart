import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/jurii_notification.dart';
import '../repositories/notification_repository.dart';
import '../services/notification_router.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../utils/relative_time.dart';
import 'jurii_empty_state.dart';
import 'jurii_form_motion.dart';
import 'jurii_motion.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({
    super.key,
    required this.scope,
    this.lawFirmId,
    this.iconColor,
    this.backgroundColor,
    this.borderColor,
    this.onChanged,
    this.repository = const NotificationRepository(),
    this.router = const NotificationRouter(),
  });

  final NotificationScope scope;
  final String? lawFirmId;
  final Color? iconColor;
  final Color? backgroundColor;
  final Color? borderColor;
  final Future<void> Function()? onChanged;
  final NotificationRepository repository;
  final NotificationRouter router;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unreadCount = 0;
  RealtimeChannel? _notificationsChannel;

  @override
  void initState() {
    super.initState();
    _loadCount();
    _subscribeToNotifications();
  }

  @override
  void dispose() {
    final channel = _notificationsChannel;
    if (channel != null && SupabaseConfig.isReady) {
      SupabaseConfig.client.removeChannel(channel);
    }
    super.dispose();
  }

  Future<void> _loadCount() async {
    final count = await widget.repository.fetchUnreadCount(
      scope: widget.scope,
      lawFirmId: widget.lawFirmId,
    );
    if (!mounted) return;
    setState(() => _unreadCount = count);
  }

  void _subscribeToNotifications() {
    if (!SupabaseConfig.isReady) return;
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;

    _notificationsChannel = SupabaseConfig.client
        .channel('notifications:${widget.scope.databaseValue}:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_profile_id',
            value: userId,
          ),
          callback: (_) => _handleNotificationChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_profile_id',
            value: userId,
          ),
          callback: (_) => _handleNotificationChanged(),
        )
        .subscribe();
  }

  void _handleNotificationChanged() {
    _loadCount();
    widget.onChanged?.call();
  }

  Future<void> _openNotifications() async {
    // Capturados antes do primeiro await: depois de abrir e fechar o painel o
    // analisador (com razão) não confia mais no context desta closure.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final notifications = await widget.repository.fetchLatest(
      scope: widget.scope,
      lawFirmId: widget.lawFirmId,
    );
    if (!mounted) return;

    // Abrir o painel NÃO marca tudo como lido: o destaque de não lida é o que
    // ajuda a achar o que falta ver. Marca-se ao tocar em cada uma, ou de uma
    // vez pelo botão do cabeçalho.
    final toOpen = await showModalBottomSheet<JuriiNotification>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _NotificationSheet(
          notifications: notifications,
          scope: widget.scope,
          lawFirmId: widget.lawFirmId,
          repository: widget.repository,
        );
      },
    );

    if (!mounted) return;
    await _loadCount();
    await widget.onChanged?.call();
    if (toOpen == null) return;

    // O destino (conversa ou caso) é decidido pelo mesmo resolvedor que o push
    // usa, para os dois caminhos abrirem sempre a mesma coisa.
    final opened = await widget.router.open(navigator, toOpen);
    if (!opened) {
      // Silêncio aqui seria pior que o comportamento antigo: o item anuncia
      // "Abrir", o painel fecha e nada acontece.
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir agora. Tente de novo.'),
        ),
      );
    }
    if (!mounted) return;
    await _loadCount();
    await widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: widget.backgroundColor ?? colors.card,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: _openNotifications,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                border: Border.all(
                  color: widget.borderColor ?? colors.softBorder,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.notifications_none_outlined,
                color: widget.iconColor ?? colors.primary,
              ),
            ),
          ),
        ),
        Positioned(
          right: -3,
          top: -3,
          child: AnimatedSwitcher(
            duration: JuriiMotion.fast,
            switchInCurve: JuriiMotion.ease,
            switchOutCurve: JuriiMotion.exitEase,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              );
            },
            child: _unreadCount > 0
                ? JuriiPulse(
                    key: ValueKey('badge_$_unreadCount'),
                    minScale: 0.96,
                    maxScale: 1.08,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: colors.danger,
                        border: Border.all(color: colors.card, width: 2),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Center(
                        child: Text(
                          _unreadCount > 9 ? '9+' : '$_unreadCount',
                          style: TextStyle(
                            color: colors.card,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('badge_empty')),
          ),
        ),
      ],
    );
  }
}

class _NotificationSheet extends StatefulWidget {
  const _NotificationSheet({
    required this.notifications,
    required this.scope,
    this.lawFirmId,
    required this.repository,
  });

  final List<JuriiNotification> notifications;
  final NotificationScope scope;
  final String? lawFirmId;
  final NotificationRepository repository;

  @override
  State<_NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends State<_NotificationSheet> {
  late List<JuriiNotification> _notifications;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _notifications = widget.notifications;
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null && SupabaseConfig.isReady) {
      SupabaseConfig.client.removeChannel(channel);
    }
    super.dispose();
  }

  void _subscribeToRealtime() {
    if (!SupabaseConfig.isReady) return;
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;

    // Enquanto o painel está aberto, uma notificação nova (ou removida em outro
    // dispositivo) precisa aparecer sem fechar e reabrir. O RLS já restringe ao
    // recipient; o refetch reaplica o filtro de escopo.
    _channel = SupabaseConfig.client
        .channel('notifications_sheet:${widget.scope.databaseValue}:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_profile_id',
            value: userId,
          ),
          callback: (_) => unawaited(_onRealtimeChange()),
        )
        .subscribe();
  }

  Future<void> _onRealtimeChange() async {
    final fresh = await widget.repository.fetchLatest(
      scope: widget.scope,
      lawFirmId: widget.lawFirmId,
    );
    if (!mounted) return;
    setState(() => _notifications = fresh);
  }

  Future<void> _markAllAsRead() async {
    final now = DateTime.now();
    setState(() {
      _notifications = _notifications
          .map(
            (notification) => notification.isUnread
                ? notification.copyWith(readAt: now)
                : notification,
          )
          .toList();
    });

    await widget.repository.markAllAsRead(
      scope: widget.scope,
      lawFirmId: widget.lawFirmId,
    );
  }

  /// Tocar marca como lida e, quando a notificação leva a algum lugar,
  /// devolve-a ao sino, que faz a navegação com o contexto ainda vivo.
  Future<void> _handleTap(JuriiNotification notification) async {
    final navigator = Navigator.of(context);
    final opensSomething =
        destinationFor(notification) != NotificationDestinationKind.none;

    if (notification.isUnread) {
      final now = DateTime.now();
      setState(() {
        _notifications = _notifications
            .map(
              (item) => item.id == notification.id
                  ? item.copyWith(readAt: now)
                  : item,
            )
            .toList();
      });
      await widget.repository.markAsRead(notification.id);
    }

    // O markAsRead acima é um await: sem reconfirmar o mounted, um painel já
    // fechado desempilharia a tela de baixo.
    if (opensSomething && mounted) navigator.pop(notification);
  }

  Future<void> _reload() async {
    final notifications = await widget.repository.fetchLatest(
      scope: widget.scope,
      lawFirmId: widget.lawFirmId,
    );
    if (!mounted) return;
    setState(() => _notifications = notifications);
  }

  Future<void> _dismissNotification(JuriiNotification notification) async {
    final removedIndex = _notifications.indexWhere(
      (item) => item.id == notification.id,
    );
    if (removedIndex == -1) return;

    setState(() => _notifications.removeAt(removedIndex));

    try {
      await widget.repository.deleteNotification(notification.id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _notifications.insert(removedIndex, notification));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível excluir a notificação.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Teto explícito: dentro do JuriiModalSheetScaffold a Column não repassa
    // altura limitada, então Flexible quebraria com lista longa.
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.55;

    final hasUnread = _notifications.any(
      (notification) => notification.isUnread,
    );

    return JuriiModalSheetScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Notificações',
                  style: TextStyle(
                    color: context.jColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (hasUnread)
                TextButton(
                  onPressed: _markAllAsRead,
                  child: const Text('Marcar todas como lidas'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (_notifications.isEmpty)
            _EmptyNotifications(scope: widget.scope)
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxListHeight),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _notifications.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final notification = _notifications[index];
                  return JuriiStaggeredItem(
                    index: index,
                    beginOffset: const Offset(0, 10),
                    child: Dismissible(
                      key: ValueKey('notification_${notification.id}'),
                      direction: DismissDirection.endToStart,
                      resizeDuration: const Duration(milliseconds: 180),
                      movementDuration: const Duration(milliseconds: 260),
                      dismissThresholds: const {
                        DismissDirection.endToStart: 0.28,
                      },
                      background: const SizedBox.shrink(),
                      secondaryBackground: _DismissNotificationBackground(
                        scope: notification.scope,
                      ),
                      onDismissed: (_) => _dismissNotification(notification),
                      child: _NotificationTile(
                        notification: notification,
                        repository: widget.repository,
                        onChanged: _reload,
                        opensDestination:
                            destinationFor(notification) !=
                            NotificationDestinationKind.none,
                        onTap: () => _handleTap(notification),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _DismissNotificationBackground extends StatelessWidget {
  const _DismissNotificationBackground({required this.scope});

  final NotificationScope scope;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final accentColor = switch (scope) {
      NotificationScope.client => colors.accent,
      NotificationScope.lawyer => colors.primary,
      NotificationScope.firm => colors.officePurple,
    };

    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: colors.danger,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            'Excluir',
            style: TextStyle(
              color: colors.card,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          Icon(Icons.delete_outline, color: colors.card, size: 22),
        ],
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications({required this.scope});

  final NotificationScope scope;

  @override
  Widget build(BuildContext context) {
    final colors = _emptyColorsForScope(scope, context.jColors);

    return JuriiEmptyState(
      icon: Icons.notifications_none_outlined,
      title: 'Nada novo por enquanto',
      message: 'Quando houver novidades importantes, elas aparecerão aqui.',
      accentColor: colors.accent,
      surfaceColor: colors.surface,
      borderColor: colors.border,
    );
  }

  ({Color surface, Color border, Color accent}) _emptyColorsForScope(
    NotificationScope scope,
    AppColors colors,
  ) {
    return switch (scope) {
      NotificationScope.client => (
        surface: colors.lightGold,
        border: colors.lightGoldBorder,
        accent: colors.accent,
      ),
      NotificationScope.lawyer => (
        surface: colors.lightBlue,
        border: colors.lightBlueBorder,
        accent: colors.primary,
      ),
      NotificationScope.firm => (
        surface: colors.officePurpleSurface,
        border: colors.officePurpleBorder,
        accent: colors.officePurple,
      ),
    };
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.repository,
    required this.onChanged,
    required this.opensDestination,
    required this.onTap,
  });

  final JuriiNotification notification;
  final NotificationRepository repository;
  final Future<void> Function() onChanged;

  /// Tocar leva a algum lugar (muda o rótulo acessível e mostra a seta).
  final bool opensDestination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _colorsForScope(
      notification.scope,
      notification.isUnread,
      context.jColors,
    );
    return Semantics(
      button: true,
      label: opensDestination
          ? '${notification.title}. Abrir.'
          : '${notification.title}. Marcar como lida.',
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: _buildBody(context, colors),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ({Color surface, Color border, Color icon}) colors,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconForType(notification.type), color: colors.icon, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        notification.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.jColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatRelativeTime(notification.createdAt),
                      style: TextStyle(
                        color: context.jColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (opensDestination) ...[
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: context.jColors.textSecondary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  notification.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.jColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (notification.isPendingTeamInvite) ...[
                  const SizedBox(height: 12),
                  _TeamInviteActions(
                    membershipId: notification.membershipId!,
                    repository: repository,
                    onChanged: onChanged,
                  ),
                ] else if (notification.isPendingCaseRequest) ...[
                  const SizedBox(height: 12),
                  _CaseRequestActions(
                    caseRequestId: notification.caseRequestId!,
                    repository: repository,
                    onChanged: onChanged,
                  ),
                ] else if (notification.inviteStatus != null) ...[
                  const SizedBox(height: 10),
                  _InviteStatusPill(status: notification.inviteStatus!),
                ] else if (notification.caseRequestStatus != null) ...[
                  const SizedBox(height: 10),
                  _CaseRequestStatusPill(
                    status: notification.caseRequestStatus!,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  ({Color surface, Color border, Color icon}) _colorsForScope(
    NotificationScope scope,
    bool isUnread,
    AppColors colors,
  ) {
    return switch (scope) {
      NotificationScope.client => (
        surface: isUnread ? colors.lightGold : colors.card,
        border: colors.lightGoldBorder,
        icon: colors.accent,
      ),
      NotificationScope.lawyer => (
        surface: isUnread ? colors.lightBlue : colors.card,
        border: colors.lightBlueBorder,
        icon: colors.primary,
      ),
      NotificationScope.firm => (
        surface: isUnread ? colors.officePurpleSurface : colors.card,
        border: colors.officePurpleBorder,
        icon: colors.officePurple,
      ),
    };
  }

  IconData _iconForType(String type) {
    return switch (type) {
      'team_invite' => Icons.group_add_outlined,
      'message' => Icons.mark_chat_unread_outlined,
      'case_request' => Icons.assignment_add,
      'case_request_response' => Icons.assignment_turned_in_outlined,
      'lawyer_recommendation' || 'lawyer_recommended' =>
        Icons.recommend_outlined,
      'firm_case_started' => Icons.business_center_outlined,
      'case_update' => Icons.folder_special_outlined,
      'appointment_reminder' => Icons.event_available_outlined,
      _ => Icons.notifications_none_outlined,
    };
  }
}

class _TeamInviteActions extends StatefulWidget {
  const _TeamInviteActions({
    required this.membershipId,
    required this.repository,
    required this.onChanged,
  });

  final String membershipId;
  final NotificationRepository repository;
  final Future<void> Function() onChanged;

  @override
  State<_TeamInviteActions> createState() => _TeamInviteActionsState();
}

class _TeamInviteActionsState extends State<_TeamInviteActions> {
  bool _isSubmitting = false;

  Future<void> _respond({required bool accepted}) async {
    setState(() => _isSubmitting = true);

    try {
      if (accepted) {
        await widget.repository.acceptTeamInvite(widget.membershipId);
      } else {
        await widget.repository.declineTeamInvite(widget.membershipId);
      }

      await widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accepted ? 'Convite aceito.' : 'Convite recusado.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível responder ao convite.')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton(
          onPressed: _isSubmitting ? null : () => _respond(accepted: true),
          style: FilledButton.styleFrom(
            backgroundColor: colors.success,
            foregroundColor: colors.card,
            minimumSize: const Size(96, 40),
          ),
          child: const Text('Aceitar'),
        ),
        OutlinedButton(
          onPressed: _isSubmitting ? null : () => _respond(accepted: false),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.danger,
            side: BorderSide(color: colors.danger),
            minimumSize: const Size(96, 40),
          ),
          child: const Text('Recusar'),
        ),
      ],
    );
  }
}

class _InviteStatusPill extends StatelessWidget {
  const _InviteStatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final accepted = status == 'accepted';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accepted ? colors.successSurface : colors.warningSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        accepted ? 'Convite aceito' : 'Convite recusado',
        style: TextStyle(
          color: accepted ? colors.success : colors.warningText,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CaseRequestActions extends StatefulWidget {
  const _CaseRequestActions({
    required this.caseRequestId,
    required this.repository,
    required this.onChanged,
  });

  final String caseRequestId;
  final NotificationRepository repository;
  final Future<void> Function() onChanged;

  @override
  State<_CaseRequestActions> createState() => _CaseRequestActionsState();
}

class _CaseRequestActionsState extends State<_CaseRequestActions> {
  bool _isSubmitting = false;

  Future<void> _respond({required bool accepted}) async {
    setState(() => _isSubmitting = true);

    try {
      if (accepted) {
        await widget.repository.acceptCaseRequest(widget.caseRequestId);
      } else {
        await widget.repository.declineCaseRequest(widget.caseRequestId);
      }

      await widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accepted ? 'Caso aceito.' : 'Caso recusado.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível responder ao caso.')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton(
          onPressed: _isSubmitting ? null : () => _respond(accepted: true),
          style: FilledButton.styleFrom(
            backgroundColor: colors.success,
            foregroundColor: colors.card,
            minimumSize: const Size(112, 40),
          ),
          child: const Text('Aceitar caso'),
        ),
        OutlinedButton(
          onPressed: _isSubmitting ? null : () => _respond(accepted: false),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.danger,
            side: BorderSide(color: colors.danger),
            minimumSize: const Size(96, 40),
          ),
          child: const Text('Recusar'),
        ),
      ],
    );
  }
}

class _CaseRequestStatusPill extends StatelessWidget {
  const _CaseRequestStatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final accepted = status == 'accepted';
    final declined = status == 'declined';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accepted
            ? colors.successSurface
            : declined
            ? colors.warningSurface
            : colors.lightBlue,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        accepted
            ? 'Caso aceito'
            : declined
            ? 'Caso recusado'
            : 'Solicitação pendente',
        style: TextStyle(
          color: accepted
              ? colors.success
              : declined
              ? colors.warningText
              : colors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
