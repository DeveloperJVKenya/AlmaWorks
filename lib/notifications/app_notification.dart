import 'package:almaworks/widgets/modern/modern_ui.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:almaworks/core/l10n/l10n.dart';

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
    NotificationCategory.safety => l10nNow.catSafety,
    NotificationCategory.projects => l10nNow.catProjects,
    NotificationCategory.inventory => l10nNow.catInventory,
    NotificationCategory.messages => l10nNow.catMessages,
    NotificationCategory.access => l10nNow.catAccess,
    NotificationCategory.other => l10nNow.catOther,
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
  final String _title;
  final String _body;

  /// Other-language versions of the title/body (`{'it': {'title', 'body'}}`,
  /// see `notificationText` in core/l10n). Read at display time, so the
  /// inbox follows a language change without reloading.
  final Map<String, dynamic>? i18n;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final bool isRead;

  const AppNotification({
    required this.id,
    required this.collection,
    required String title,
    required String body,
    this.i18n,
    required this.payload,
    required this.createdAt,
    required this.isRead,
  }) : _title = title,
       _body = body;

  String get title => localizedField({'title': _title, 'i18n': ?i18n}, 'title') ?? _title;
  String get body => localizedField({'body': _body, 'i18n': ?i18n}, 'body') ?? _body;

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
      title: data['title'] as String? ?? l10nNow.notificationFallbackTitle,
      body: data['body'] as String? ?? '',
      i18n: data['i18n'] is Map ? Map<String, dynamic>.from(data['i18n'] as Map) : null,
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
      title: data['taskName'] as String? ?? l10nNow.taskUpdate,
      // The stored message is fixed text; overdue / starting-soon alerts
      // are shown from their type instead so they follow the language.
      body: switch (data['type']) {
        'overdue' => l10nNow.taskIsOverdue,
        'starting_soon' => l10nNow.taskStartsSoon,
        _ => data['message'] as String? ?? '',
      },
      i18n: data['i18n'] is Map ? Map<String, dynamic>.from(data['i18n'] as Map) : null,
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
  if (diff <= 0) return l10nNow.today;
  if (diff == 1) return l10nNow.yesterday;
  // Weekday / month names follow the app language (Intl.defaultLocale).
  if (diff < 7) return toBeginningOfSentenceCase(DateFormat('EEEE').format(when));
  return DateFormat(when.year == now.year ? 'd MMM' : 'd MMM y').format(when);
}

/// "just now" / "5m ago" / "3h ago" / "2d ago".
String relativeTime(DateTime when, DateTime now) {
  final d = now.difference(when);
  final l = l10nNow;
  if (d.inMinutes < 1) return l.justNow;
  if (d.inMinutes < 60) return l.minutesAgo(d.inMinutes);
  if (d.inHours < 24) return l.hoursAgo(d.inHours);
  if (d.inDays < 30) return l.daysAgo(d.inDays);
  return l.monthsAgo((d.inDays / 30).floor());
}
