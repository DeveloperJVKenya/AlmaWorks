import 'package:almaworks/notifications/notification_providers.dart';
import 'package:almaworks/screens/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// App-bar bell with the live unread count (from the same provider the
/// notification center lists), opening the notification center.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key, required this.logger, this.color = Colors.white});

  final Logger logger;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);
    return IconButton(
      tooltip: unread == 0 ? 'Notifications' : 'Notifications ($unread unread)',
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(logger: logger))),
      icon: Badge(
        isLabelVisible: unread > 0,
        backgroundColor: const Color(0xFFE5484D),
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Icon(unread > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, color: color),
      ),
    );
  }
}
