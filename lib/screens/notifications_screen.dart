import 'package:almaworks/notifications/app_notification.dart';
import 'package:almaworks/notifications/notification_providers.dart';
import 'package:almaworks/notifications/notification_router.dart';
import 'package:almaworks/widgets/modern/modern_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

/// The app-wide notification center: everything queued for the signed-in
/// user (UserNotificationQueue, by uid), their role (AdminNotificationQueue,
/// by targetRoles) and their task alerts (ScheduleNotifications), merged
/// into one live list — filterable, grouped by day, with per-item read /
/// unread / remove actions. Tapping an item marks it read and opens what
/// it's about (see [NotificationRouter], the same routing an OS-tray tap
/// uses); items with nowhere to go open their full details instead.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key, this.logger});

  final Logger? logger;

  static const _filters = <NotificationFilter>[
    AllNotifications(),
    UnreadNotifications(),
    CategoryNotifications(NotificationCategory.safety),
    CategoryNotifications(NotificationCategory.projects),
    CategoryNotifications(NotificationCategory.inventory),
    CategoryNotifications(NotificationCategory.messages),
    CategoryNotifications(NotificationCategory.access),
    CategoryNotifications(NotificationCategory.other),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationCountProvider);
    final filter = ref.watch(notificationFilterProvider);
    final all = async.valueOrNull ?? const <AppNotification>[];
    final failedSources = ref.watch(notificationSourceErrorsProvider);

    return Scaffold(
      backgroundColor: AppPalette.canvas,
      appBar: modernAppBar(
        context,
        title: 'Notifications',
        subtitle: unread == 0 ? 'You\'re all caught up' : '$unread unread',
        actions: [
          if (unread > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () => _markAllRead(context, ref, all),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: Text(
                  'Mark all read',
                  style: appText(12.5, weight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Couldn\'t load notifications',
          message: 'Check your connection and try again.',
          action: OutlinedButton(onPressed: () => ref.invalidate(notificationUserProvider), child: const Text('Retry')),
        ),
        data: (_) {
          final visible = all.where(filter.matches).toList();
          return ResponsiveCenter(
            maxWidth: 860,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SummaryStrip(all: all),
                        const SizedBox(height: 14),
                        FilterChipBar<NotificationFilter>(
                          options: [
                            for (final f in _filters)
                              if (f is! CategoryNotifications || all.any(f.matches)) f,
                          ],
                          selected: filter,
                          onSelected: (f) => ref.read(notificationFilterProvider.notifier).state = f,
                          label: (f) => f.label,
                          count: (f) => f is AllNotifications ? 0 : all.where((n) => f.matches(n) && !n.isRead).length,
                          icon: (f) => switch (f) {
                            CategoryNotifications(:final category) => category.icon,
                            UnreadNotifications() => Icons.mark_email_unread_rounded,
                            _ => Icons.inbox_rounded,
                          },
                        ),
                        if (failedSources > 0) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Some notifications couldn\'t be loaded — the list may be incomplete.',
                            style: appText(12, color: AppPalette.orange),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: filter is UnreadNotifications
                          ? Icons.mark_email_read_rounded
                          : Icons.notifications_none_rounded,
                      title: filter is UnreadNotifications ? 'No unread notifications' : 'Nothing here yet',
                      message: filter is AllNotifications
                          ? 'Updates about your projects, inventory, safety training and messages will appear here.'
                          : 'Try another filter to see more.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    sliver: SliverList.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final n = visible[i];
                        final now = DateTime.now();
                        final day = notificationDayLabel(n.createdAt, now);
                        final showHeader = i == 0 || notificationDayLabel(visible[i - 1].createdAt, now) != day;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showHeader)
                              Padding(
                                padding: EdgeInsets.only(top: i == 0 ? 6 : 18, bottom: 8, left: 4),
                                child: Text(
                                  day.toUpperCase(),
                                  style: appText(11.5, weight: FontWeight.w700, color: AppPalette.inkFaint),
                                ),
                              ),
                            StaggeredEntrance(
                              index: i,
                              child: _NotificationTile(
                                key: ValueKey('${n.collection}/${n.id}'),
                                notification: n,
                                logger: logger ?? Logger(),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _markAllRead(BuildContext context, WidgetRef ref, List<AppNotification> all) async {
    final user = ref.read(notificationUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref.read(notificationRepositoryProvider).markAllRead(all, user.uid);
      if (context.mounted) showAppSnack(context, 'All notifications marked as read');
    } catch (e) {
      logger?.e('❌ NotificationsScreen: mark all read failed', error: e);
      if (context.mounted) showAppSnack(context, 'Couldn\'t mark notifications as read', error: true);
    }
  }
}

/// Unread count per category, as compact colored tiles.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.all});

  final List<AppNotification> all;

  @override
  Widget build(BuildContext context) {
    final unread = all.where((n) => !n.isRead).toList();
    final today = all.where((n) => notificationDayLabel(n.createdAt, DateTime.now()) == 'Today').length;
    final safety = unread.where((n) => n.category == NotificationCategory.safety).length;
    return ResponsiveTiles(
      minTileWidth: 150,
      children: [
        StatTile(label: 'Unread', value: '${unread.length}', icon: Icons.mark_email_unread_rounded),
        StatTile(label: 'Today', value: '$today', icon: Icons.today_rounded, color: AppPalette.violet),
        StatTile(
          label: 'Safety (unread)',
          value: '$safety',
          icon: Icons.health_and_safety_rounded,
          color: AppPalette.teal,
        ),
        StatTile(label: 'Total', value: '${all.length}', icon: Icons.inbox_rounded, color: AppPalette.orange),
      ],
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({super.key, required this.notification, required this.logger});

  final AppNotification notification;
  final Logger logger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = notification;
    final access = _AccessOutcome.of(n, ref);
    final (icon, color) = access?.visual ?? n.visual;
    final title = access?.title ?? n.title;
    final body = access?.body ?? n.body;
    final now = DateTime.now();
    final canOpen = NotificationRouter.hasDestination(n.payload);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey('dismiss-${n.collection}/${n.id}'),
        background: _swipeBackground(
          alignment: Alignment.centerLeft,
          color: AppPalette.brightBlue,
          icon: n.isRead ? Icons.mark_email_unread_rounded : Icons.mark_email_read_rounded,
          label: n.isRead ? 'Mark unread' : 'Mark read',
        ),
        secondaryBackground: _swipeBackground(
          alignment: Alignment.centerRight,
          color: AppPalette.coral,
          icon: Icons.delete_outline_rounded,
          label: 'Remove',
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            await _setRead(context, ref, !n.isRead);
            return false; // toggled in place — keep the tile
          }
          return true;
        },
        onDismissed: (_) => _remove(context, ref),
        child: AppCard(
          highlighted: !n.isRead,
          accent: n.isRead ? null : color,
          padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
          onTap: () => _open(context, ref),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon: icon, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: appText(14, weight: n.isRead ? FontWeight.w500 : FontWeight.w700),
                          ),
                        ),
                        if (!n.isRead)
                          Container(
                            width: 9,
                            height: 9,
                            margin: const EdgeInsets.only(left: 8),
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: appText(13, color: AppPalette.inkMuted, height: 1.4),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusPill(label: n.category.label, color: n.category.color, icon: n.category.icon),
                        if (access != null)
                          StatusPill(label: access.pill, color: access.visual.$2, icon: access.visual.$1),
                        Text(
                          '${relativeTime(n.createdAt, now)} · ${DateFormat('MMM d, HH:mm').format(n.createdAt)}',
                          style: appText(11.5, color: AppPalette.inkFaint),
                        ),
                        if (canOpen)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Open',
                                style: appText(11.5, weight: FontWeight.w600, color: AppPalette.brightBlue),
                              ),
                              const Icon(Icons.chevron_right_rounded, size: 16, color: AppPalette.brightBlue),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert_rounded, color: AppPalette.inkFaint),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onSelected: (action) {
                  switch (action) {
                    case 'open':
                      _open(context, ref);
                    case 'details':
                      _showDetails(context, ref);
                    case 'toggle':
                      _setRead(context, ref, !n.isRead);
                    case 'remove':
                      _remove(context, ref);
                  }
                },
                itemBuilder: (_) => [
                  if (canOpen) _menuItem('open', Icons.open_in_new_rounded, 'Open'),
                  _menuItem('details', Icons.article_outlined, 'View details'),
                  _menuItem(
                    'toggle',
                    n.isRead ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined,
                    n.isRead ? 'Mark as unread' : 'Mark as read',
                  ),
                  _menuItem('remove', Icons.delete_outline_rounded, 'Remove', color: AppPalette.coral),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label, {Color color = AppPalette.ink}) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 12),
          Text(label, style: appText(13.5, color: color)),
        ],
      ),
    );
  }

  Widget _swipeBackground({
    required Alignment alignment,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    final left = alignment == Alignment.centerLeft;
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!left)
            Text(
              label,
              style: appText(13, weight: FontWeight.w600, color: Colors.white),
            ),
          if (!left) const SizedBox(width: 8),
          Icon(icon, color: Colors.white),
          if (left) const SizedBox(width: 8),
          if (left)
            Text(
              label,
              style: appText(13, weight: FontWeight.w600, color: Colors.white),
            ),
        ],
      ),
    );
  }

  Future<void> _setRead(BuildContext context, WidgetRef ref, bool read) async {
    final user = ref.read(notificationUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref.read(notificationRepositoryProvider).setRead(notification, user.uid, read: read);
    } catch (e) {
      logger.e('❌ NotificationsScreen: set read failed', error: e);
      if (context.mounted) showAppSnack(context, 'Couldn\'t update the notification', error: true);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final user = ref.read(notificationUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref.read(notificationRepositoryProvider).remove(notification, user.uid);
      if (context.mounted) showAppSnack(context, 'Notification removed');
    } catch (e) {
      logger.e('❌ NotificationsScreen: remove failed', error: e);
      if (context.mounted) showAppSnack(context, 'Couldn\'t remove the notification', error: true);
    }
  }

  /// Marks read, then opens the destination — or the details sheet when
  /// the notification isn't about anything openable.
  Future<void> _open(BuildContext context, WidgetRef ref) async {
    if (!notification.isRead) _setRead(context, ref, true);
    if (NotificationRouter.hasDestination(notification.payload)) {
      await NotificationRouter.of(context, logger).open(notification.payload);
    } else {
      _showDetails(context, ref);
    }
  }

  void _showDetails(BuildContext context, WidgetRef ref) {
    final n = notification;
    final access = _AccessOutcome.of(n, ref);
    final (icon, color) = access?.visual ?? n.visual;
    if (!n.isRead) _setRead(context, ref, true);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppPalette.surface,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBadge(icon: icon, color: color, size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(access?.title ?? n.title, style: appText(17, weight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                (access?.body ?? n.body).isEmpty ? 'No further details.' : (access?.body ?? n.body),
                style: appText(14.5, height: 1.55),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(label: n.category.label, color: n.category.color, icon: n.category.icon),
                  if (access != null) StatusPill(label: access.pill, color: access.visual.$2, icon: access.visual.$1),
                  StatusPill(
                    label: DateFormat('EEE, MMM d yyyy · HH:mm').format(n.createdAt),
                    color: AppPalette.inkMuted,
                    icon: Icons.schedule_rounded,
                  ),
                ],
              ),
              if (NotificationRouter.hasDestination(n.payload)) ...[
                const SizedBox(height: 22),
                PrimaryButton(
                  label: 'Open',
                  icon: Icons.open_in_new_rounded,
                  expand: true,
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    NotificationRouter.of(context, logger).open(n.payload);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// What became of the access request an admin alert is about — read live
/// from ClientRequests, so every admin's copy of the alert shows the same,
/// current outcome ("Approved by Jane as Technician · Oct 2") no matter
/// which admin acted or when.
class _AccessOutcome {
  const _AccessOutcome({required this.title, required this.body, required this.pill, required this.visual});

  final String? title;
  final String? body;
  final String pill;
  final (IconData, Color) visual;

  static _AccessOutcome? of(AppNotification n, WidgetRef ref) {
    final id = n.accessRequestId;
    if (id == null) return null;
    final async = ref.watch(accessRequestProvider(id));
    final request = async.valueOrNull;
    if (async.isLoading && request == null) return null;
    if (request == null) {
      return const _AccessOutcome(
        title: null,
        body: null,
        pill: 'Request no longer exists',
        visual: (Icons.help_outline_rounded, AppPalette.inkMuted),
      );
    }
    final who = request.clientUsername.isEmpty ? 'This user' : request.clientUsername;
    final by = (request.approvedBy ?? '').isEmpty ? 'an admin' : request.approvedBy!;
    final when = request.approvalDate == null ? '' : ' · ${DateFormat('MMM d, HH:mm').format(request.approvalDate!)}';
    switch (request.status) {
      case 'approved':
        final count = request.grantedProjects.length;
        return _AccessOutcome(
          title: '✅ Access approved — $who',
          body: '$who was approved as ${request.grantedRole} with access to $count project${count == 1 ? '' : 's'}.',
          pill: 'Approved by $by$when',
          visual: (Icons.verified_user_rounded, AppPalette.green),
        );
      case 'denied':
        final reason = request.denialReason;
        return _AccessOutcome(
          title: '❌ Access denied — $who',
          body: reason == null || reason.isEmpty ? '$who\'s access request was denied.' : 'Reason: $reason',
          pill: 'Denied by $by$when',
          visual: (Icons.block_rounded, AppPalette.coral),
        );
      default:
        return const _AccessOutcome(
          title: null,
          body: null,
          pill: 'Awaiting a decision',
          visual: (Icons.hourglass_top_rounded, AppPalette.amber),
        );
    }
  }
}
