import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/jurii_notification.dart';
import '../repositories/notification_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_theme.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({
    super.key,
    required this.scope,
    this.lawFirmId,
    this.iconColor = AppTheme.primary,
    this.backgroundColor = AppTheme.card,
    this.borderColor = AppTheme.softBorder,
    this.onChanged,
    this.repository = const NotificationRepository(),
  });

  final NotificationScope scope;
  final String? lawFirmId;
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;
  final Future<void> Function()? onChanged;
  final NotificationRepository repository;

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
    final notifications = await widget.repository.fetchLatest(
      scope: widget.scope,
      lawFirmId: widget.lawFirmId,
    );
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.card,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: widget.backgroundColor,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: _openNotifications,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                border: Border.all(color: widget.borderColor),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.notifications_none_outlined,
                color: widget.iconColor,
              ),
            ),
          ),
        ),
        if (_unreadCount > 0)
          Positioned(
            right: -3,
            top: -3,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: AppTheme.danger,
                border: Border.all(color: AppTheme.card, width: 2),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Center(
                child: Text(
                  _unreadCount > 9 ? '9+' : '$_unreadCount',
                  style: const TextStyle(
                    color: AppTheme.card,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
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

  @override
  void initState() {
    super.initState();
    _notifications = widget.notifications;
  }

  Future<void> _reload() async {
    final notifications = await widget.repository.fetchLatest(
      scope: widget.scope,
      lawFirmId: widget.lawFirmId,
    );
    if (!mounted) return;
    setState(() => _notifications = notifications);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notificações',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            if (_notifications.isEmpty)
              _EmptyNotifications(scope: widget.scope)
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _notifications.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    return _NotificationTile(
                      notification: _notifications[index],
                      repository: widget.repository,
                      onChanged: _reload,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications({required this.scope});

  final NotificationScope scope;

  @override
  Widget build(BuildContext context) {
    final colors = _emptyColorsForScope(scope);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Text(
        'Nada novo por enquanto.',
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  ({Color surface, Color border}) _emptyColorsForScope(
    NotificationScope scope,
  ) {
    return switch (scope) {
      NotificationScope.client => (
        surface: AppTheme.lightGold,
        border: AppTheme.lightGoldBorder,
      ),
      NotificationScope.lawyer => (
        surface: AppTheme.lightBlue,
        border: AppTheme.lightBlueBorder,
      ),
      NotificationScope.firm => (
        surface: AppTheme.officePurpleSurface,
        border: AppTheme.officePurpleBorder,
      ),
    };
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.repository,
    required this.onChanged,
  });

  final JuriiNotification notification;
  final NotificationRepository repository;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = _colorsForScope(notification.scope, notification.isUnread);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
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
                Text(
                  notification.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  notification.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
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
  ) {
    return switch (scope) {
      NotificationScope.client => (
        surface: isUnread ? AppTheme.lightGold : AppTheme.card,
        border: AppTheme.lightGoldBorder,
        icon: AppTheme.accent,
      ),
      NotificationScope.lawyer => (
        surface: isUnread ? AppTheme.lightBlue : AppTheme.card,
        border: AppTheme.lightBlueBorder,
        icon: AppTheme.primary,
      ),
      NotificationScope.firm => (
        surface: isUnread ? AppTheme.officePurpleSurface : AppTheme.card,
        border: AppTheme.officePurpleBorder,
        icon: AppTheme.officePurple,
      ),
    };
  }

  IconData _iconForType(String type) {
    return switch (type) {
      'team_invite' => Icons.group_add_outlined,
      'message' => Icons.mark_chat_unread_outlined,
      'case_request' => Icons.assignment_add,
      'case_request_response' => Icons.assignment_turned_in_outlined,
      'firm_case_started' => Icons.business_center_outlined,
      'case_update' => Icons.folder_special_outlined,
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton(
          onPressed: _isSubmitting ? null : () => _respond(accepted: true),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.success,
            foregroundColor: AppTheme.card,
            minimumSize: const Size(96, 40),
          ),
          child: const Text('Aceitar'),
        ),
        OutlinedButton(
          onPressed: _isSubmitting ? null : () => _respond(accepted: false),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.danger,
            side: const BorderSide(color: AppTheme.danger),
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
    final accepted = status == 'accepted';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accepted ? AppTheme.successSurface : AppTheme.warningSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        accepted ? 'Convite aceito' : 'Convite recusado',
        style: TextStyle(
          color: accepted ? AppTheme.success : AppTheme.warningText,
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton(
          onPressed: _isSubmitting ? null : () => _respond(accepted: true),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.success,
            foregroundColor: AppTheme.card,
            minimumSize: const Size(112, 40),
          ),
          child: const Text('Aceitar caso'),
        ),
        OutlinedButton(
          onPressed: _isSubmitting ? null : () => _respond(accepted: false),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.danger,
            side: const BorderSide(color: AppTheme.danger),
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
    final accepted = status == 'accepted';
    final declined = status == 'declined';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accepted
            ? AppTheme.successSurface
            : declined
            ? AppTheme.warningSurface
            : AppTheme.lightBlue,
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
              ? AppTheme.success
              : declined
              ? AppTheme.warningText
              : AppTheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
