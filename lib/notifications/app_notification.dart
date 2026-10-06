import 'package:almaworks/widgets/modern/modern_ui.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// The three Firestore sources the notification center merges.
class NotificationSources {
  NotificationSources._();

  /// Targeted at one person (`targetUid`).
  static const user = 'UserNotificationQueue';

  /// Broadcast to roles (`targetRoles`); one doc is shared by every
  /// recipient, so read/dismissed state is tracked per person in
  /// `readBy` / `hiddenFor` rather than a single `isRead` flag.
  static const admin = 'AdminNotificationQueue';

  /// Task overdue / starting-soon alerts (`userId`), with their own shape.
  static const schedule = 'ScheduleNotifications';
}

enum NotificationCategory { safety, projects, inventory, messages, access, other }

extension NotificationCategoryX on NotificationCategory {
  String get label => switch (this) {
    NotificationCategory.safety => 'Safety',
    NotificationCategory.projects => 'Projects',
    NotificationCategory.inventory => 'Inventory',
    NotificationCategory.messages => 'Messages',
    NotificationCategory.access => 'Access',
    NotificationCategory.other => 'Other',
  };

  IconData get icon => switch (this) {
    NotificationCategory.safety => Icons.health_and_safety_rounded,
    NotificationCategory.projects => Icons.timeline_rounded,
    NotificationCategory.inventory => Icons.inventory_2_rounded,
    NotificationCategory.messages => Icons.forum_rounded,
    NotificationCategory.access => Icons.key_rounded,
    NotificationCategory.other => Icons.notifications_rounded,
  };

  Color get color => switch (this) {
    NotificationCategory.safety => AppPalette.teal,
    NotificationCategory.projects => AppPalette.brightBlue,
    NotificationCategory.inventory => AppPalette.orange,
    NotificationCategory.messages => AppPalette.violet,
    NotificationCategory.access => AppPalette.pink,
    NotificationCategory.other => AppPalette.inkMuted,
  };
}

/// One notification from any of the three sources, normalized to one shape.
class AppNotification {
  final String id;
  final String collection;
  final String title;
  final String body;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final bool isRead;

  const AppNotification({
    required this.id,
    required this.collection,
    required this.title,
    required this.body,
    required this.payload,
    required this.createdAt,
    required this.isRead,
  });

  String get type => payload['type']?.toString() ?? '';

  NotificationCategory get category => categoryForType(type);

  /// The access request an admin-side "new access request" alert is about
  /// (null for the requester's own approved/denied notices, which carry no
  /// request id).
  String? get accessRequestId {
    if (type != 'client_request') return null;
    final id = payload['requestId']?.toString();
    return id == null || id.isEmpty || id == 'null' ? null : id;
  }

  static NotificationCategory categoryForType(String type) {
    if (type.startsWith('safety_training')) return NotificationCategory.safety;
    if (type.startsWith('project_date_extension') ||
        type.startsWith('task_date_extension') ||
        type.startsWith('schedule')) {
      return NotificationCategory.projects;
    }
    if (type.startsWith('inventory')) return NotificationCategory.inventory;
    if (type == 'communication') return NotificationCategory.messages;
    if (type == 'client_request') return NotificationCategory.access;
    return NotificationCategory.other;
  }

  /// A more specific icon/color than the category's, where one exists.
  (IconData, Color) get visual {
    switch (type) {
      case 'safety_training_attempt':
        return (Icons.assignment_turned_in_rounded, AppPalette.brightBlue);
      case 'safety_training_review':
        return (Icons.verified_rounded, AppPalette.green);
      case 'safety_training_feedback':
        return (Icons.rate_review_rounded, AppPalette.violet);
      case 'safety_training_escalation':
        return (Icons.report_rounded, AppPalette.coral);
      case 'safety_training_retraining_overdue':
        return (Icons.alarm_rounded, AppPalette.coral);
      case 'safety_training_retraining_due':
        return (Icons.event_rounded, AppPalette.amber);
      case 'safety_training_clearance_expired':
        return (Icons.history_toggle_off_rounded, AppPalette.orange);
      case 'project_date_extension_approved':
        return (Icons.check_circle_rounded, AppPalette.green);
      case 'project_date_extension_rejected':
        return (Icons.cancel_rounded, AppPalette.coral);
      case 'schedule_overdue':
        return (Icons.schedule_rounded, AppPalette.coral);
      case 'schedule_starting_soon':
        return (Icons.schedule_rounded, AppPalette.amber);
    }
    return (category.icon, category.color);
  }

  /// From UserNotificationQueue / AdminNotificationQueue. Returns null for an
  /// admin-queue doc this user has dismissed.
  static AppNotification? fromQueueDoc(DocumentSnapshot doc, String collection, String uid) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    final isShared = collection == NotificationSources.admin;
    if (isShared && _listContains(data['hiddenFor'], uid)) return null;
    return AppNotification(
      id: doc.id,
      collection: collection,
      title: data['title'] as String? ?? 'Notification',
      body: data['body'] as String? ?? '',
      payload: Map<String, dynamic>.from(data['payload'] as Map? ?? const {}),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      // Shared docs: read is per person. A legacy shared doc marked isRead
      // before readBy existed stays read for everyone, as it was.
      isRead: isShared ? (_listContains(data['readBy'], uid) || data['isRead'] == true) : data['isRead'] == true,
    );
  }

  /// ScheduleNotifications docs use taskName/message/type instead of
  /// title/body/payload.
  factory AppNotification.fromScheduleDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    return AppNotification(
      id: doc.id,
      collection: NotificationSources.schedule,
      title: data['taskName'] as String? ?? 'Task update',
      body: data['message'] as String? ?? '',
      payload: {
        'type': 'schedule_${data['type'] ?? 'unknown'}',
        'projectId': data['projectId'],
        'taskId': data['taskId'],
      },
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: data['isRead'] == true,
    );
  }

  static bool _listContains(Object? list, String value) => list is List && list.contains(value);
}

/// "Today" / "Yesterday" / weekday / date — the section a notification is
/// grouped under.
String notificationDayLabel(DateTime when, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(when.year, when.month, when.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) {
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return names[when.weekday - 1];
  }
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${when.day} ${months[when.month - 1]}${when.year == now.year ? '' : ' ${when.year}'}';
}

/// "just now" / "5m ago" / "3h ago" / "2d ago".
String relativeTime(DateTime when, DateTime now) {
  final d = now.difference(when);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 30) return '${d.inDays}d ago';
  return '${(d.inDays / 30).floor()}mo ago';
}
