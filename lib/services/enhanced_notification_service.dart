import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:almaworks/models/schedule_monitor_model.dart';
import 'package:almaworks/services/notification_preferences.dart';
import 'package:almaworks/services/notification_service.dart';

class EnhancedNotificationService {
  final Logger logger;
  final NotificationService notificationService;
  static bool _isInitialized = false;

  EnhancedNotificationService({
    required this.logger,
    required this.notificationService,
  });

  // Initialize Awesome Notifications
  Future<void> initialize() async {
    if (_isInitialized) {
      logger.d('EnhancedNotificationService already initialized');
      return;
    }

    try {
      logger.i('🔔 Initializing AwesomeNotifications...');
      
      await AwesomeNotifications().initialize(
        null, // Use default app icon
        [
          // Overdue notification channel - RED theme
          NotificationChannel(
            channelKey: 'schedule_overdue',
            channelName: 'Overdue Tasks',
            channelDescription: 'Notifications for overdue tasks',
            defaultColor: Colors.red,
            ledColor: Colors.red,
            importance: NotificationImportance.High,
            channelShowBadge: true,
            playSound: true,
            enableVibration: true,
            criticalAlerts: true,
          ),
          // Starting Soon notification channel - ORANGE theme
          NotificationChannel(
            channelKey: 'schedule_starting_soon',
            channelName: 'Starting Soon Tasks',
            channelDescription: 'Notifications for tasks starting soon',
            defaultColor: Colors.orange,
            ledColor: Colors.orange,
            importance: NotificationImportance.High,
            channelShowBadge: true,
            playSound: true,
            enableVibration: true,
          ),
          // Group summary channel
          NotificationChannel(
            channelKey: 'schedule_summary',
            channelName: 'Task Summary',
            channelDescription: 'Grouped task notifications',
            defaultColor: Colors.blue,
            ledColor: Colors.blue,
            importance: NotificationImportance.Max,
            channelShowBadge: true,
            playSound: true,
            enableVibration: true,
          ),
        ],
        debug: true,
      );

      // Request permissions
      bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
      if (!isAllowed) {
        await AwesomeNotifications().requestPermissionToSendNotifications();
      }

      // Set up listeners for user actions
      AwesomeNotifications().setListeners(
        onActionReceivedMethod: _onActionReceivedMethod,
        onNotificationCreatedMethod: _onNotificationCreatedMethod,
        onNotificationDisplayedMethod: _onNotificationDisplayedMethod,
        onDismissActionReceivedMethod: _onDismissActionReceivedMethod,
      );

      _isInitialized = true;
      logger.i('✅ AwesomeNotifications initialized successfully');
    } catch (e, stackTrace) {
      logger.e('❌ Failed to initialize AwesomeNotifications', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Callback when notification is created
  @pragma('vm:entry-point')
  static Future<void> _onNotificationCreatedMethod(ReceivedNotification receivedNotification) async {
    final logger = Logger();
    logger.d('📬 Notification created: ${receivedNotification.id}');
  }

  // Callback when notification is displayed
  @pragma('vm:entry-point')
  static Future<void> _onNotificationDisplayedMethod(ReceivedNotification receivedNotification) async {
    final logger = Logger();
    logger.i('📱 Notification displayed: ${receivedNotification.id} - ${receivedNotification.title}');
  }

  // Callback when notification is dismissed
  @pragma('vm:entry-point')
  static Future<void> _onDismissActionReceivedMethod(ReceivedAction receivedAction) async {
    final logger = Logger();
    logger.d('🗑️ Notification dismissed: ${receivedAction.id}');
    
    // Mark as dismissed in Firestore
    if (receivedAction.payload != null && receivedAction.payload!.containsKey('notificationId')) {
      try {
        final notifId = receivedAction.payload!['notificationId']!;
        await FirebaseFirestore.instance
            .collection('ScheduleNotifications')
            .doc(notifId)
            .update({'dismissedAt': FieldValue.serverTimestamp()});
      } catch (e) {
        logger.e('Error marking notification as dismissed', error: e);
      }
    }
  }

  // Callback when user taps on notification
  @pragma('vm:entry-point')
  static Future<void> _onActionReceivedMethod(ReceivedAction receivedAction) async {
    final logger = Logger();
    logger.i('👆 Notification action received: ${receivedAction.buttonKeyPressed}');
    
    // Handle different actions
    if (receivedAction.buttonKeyPressed == 'MARK_READ') {
      // Mark as read and opened
      if (receivedAction.payload != null && receivedAction.payload!.containsKey('notificationId')) {
        try {
          final notifId = receivedAction.payload!['notificationId']!;
          await FirebaseFirestore.instance
              .collection('ScheduleNotifications')
              .doc(notifId)
              .update({
                'isRead': true,
                'openedFromTray': true,
                'openedAt': FieldValue.serverTimestamp(),
                'readSource': 'system_tray',
              });
          logger.i('✅ Marked notification as read: $notifId');
        } catch (e) {
          logger.e('Error marking notification as read', error: e);
        }
      }
    }
    // Navigation will be handled by the main app
  }

  // Show individual task notification with floating behavior
  Future<void> showTaskNotification({
    required String projectId,
    required ScheduleMonitorData task,
    required String type,
    required String firestoreNotificationId,
  }) async {
    if (!await NotificationPreferences.isEnabled()) return;
    try {
      final notificationId = '${projectId}_${task.scheduleTaskId}'.hashCode;
      final channelKey = type == 'overdue' ? 'schedule_overdue' : 'schedule_starting_soon';
      final color = type == 'overdue' ? Colors.red : Colors.orange;
      
      final title = type == 'overdue' 
          ? '⚠️ Overdue: ${task.taskName}'
          : '📅 Starting Soon: ${task.taskName}';
      
      final body = type == 'overdue'
          ? 'This task is overdue and needs attention!'
          : 'Starts in ${task.daysUntilStart} day${task.daysUntilStart == 1 ? '' : 's'}';

      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: notificationId,
          channelKey: channelKey,
          title: title,
          body: body,
          bigPicture: null,
          notificationLayout: NotificationLayout.BigText,
          color: color,
          backgroundColor: color,
          category: NotificationCategory.Reminder,
          wakeUpScreen: true,
          fullScreenIntent: false,
          locked: type == 'overdue',
          autoDismissible: true,
          displayOnForeground: true,
          displayOnBackground: true,
          payload: {
            'projectId': projectId,
            'taskId': task.scheduleTaskId,
            'type': type,
            'notificationId': firestoreNotificationId,
          },
        ),
        actionButtons: [
          NotificationActionButton(
            key: 'MARK_READ',
            label: 'Mark Read',
            autoDismissible: true,
          ),
        ],
      );

      logger.i('✅ Task notification shown: ${task.taskName} (ID: $notificationId)');
    } catch (e, stackTrace) {
      logger.e('❌ Error showing task notification', error: e, stackTrace: stackTrace);
    }
  }

  // Show grouped notification summary
  Future<void> showGroupedNotification({
    required String projectId,
    required List<Map<String, dynamic>> taskGroups,
    required int totalCount,
  }) async {
    if (!await NotificationPreferences.isEnabled()) return;
    try {
      final groupId = projectId.hashCode;
      
      // Count by type
      final overdueCount = taskGroups.where((t) => t['type'] == 'overdue').length;
      final startingSoonCount = taskGroups.where((t) => t['type'] == 'starting_soon').length;
      
      String summaryText = '';
      if (overdueCount > 0 && startingSoonCount > 0) {
        summaryText = '$overdueCount overdue, $startingSoonCount starting soon';
      } else if (overdueCount > 0) {
        summaryText = '$overdueCount overdue task${overdueCount == 1 ? '' : 's'}';
      } else {
        summaryText = '$startingSoonCount starting soon';
      }

      // Build task list for big text
      final taskList = taskGroups.take(5).map((t) {
        final task = t['task'] as ScheduleMonitorData;
        final typeIcon = t['type'] == 'overdue' ? '⚠️' : '📅';
        return '$typeIcon ${task.taskName}';
      }).join('\n');

      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: groupId,
          channelKey: 'schedule_summary',
          title: '🔔 $totalCount Task Alert${totalCount > 1 ? 's' : ''}',
          body: summaryText,
          summary: taskList,
          notificationLayout: NotificationLayout.BigText,
          color: Colors.blue,
          backgroundColor: Colors.blue,
          category: NotificationCategory.Reminder,
          wakeUpScreen: true,
          fullScreenIntent: false,
          autoDismissible: false,
          displayOnForeground: true,
          displayOnBackground: true,
          payload: {
            'projectId': projectId,
            'isGroupSummary': 'true',
            'count': totalCount.toString(),
          },
        ),
        actionButtons: [
          NotificationActionButton(
            key: 'VIEW_ALL',
            label: 'View All',
            autoDismissible: false,
          ),
        ],
      );

      logger.i('✅ Group summary notification shown: $totalCount tasks');
    } catch (e, stackTrace) {
      logger.e('❌ Error showing group notification', error: e, stackTrace: stackTrace);
    }
  }

  // Cancel a specific notification
  Future<void> cancelNotification(int notificationId) async {
    try {
      await AwesomeNotifications().cancel(notificationId);
      logger.d('🗑️ Cancelled notification: $notificationId');
    } catch (e) {
      logger.e('Error cancelling notification', error: e);
    }
  }

  // Cancel all notifications for a project
  Future<void> cancelAllProjectNotifications(String projectId) async {
    try {
      await AwesomeNotifications().cancelNotificationsByGroupKey(projectId);
      logger.i('🗑️ Cancelled all notifications for project: $projectId');
    } catch (e) {
      logger.e('Error cancelling project notifications', error: e);
    }
  }

  // Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    return await AwesomeNotifications().isNotificationAllowed();
  }

  // Request notification permissions
  Future<bool> requestPermissions() async {
    return await AwesomeNotifications().requestPermissionToSendNotifications();
  }
}