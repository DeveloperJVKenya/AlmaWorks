import 'package:almaworks/models/gantt_row_model.dart';
import 'package:almaworks/models/notification_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Logger logger;
  String? _deviceId;
  final String? userId;
  late SharedPreferences _prefs;
  bool _isInitialized = false;

  NotificationService({required this.logger, this.userId});

  // FIXED: Better initialization with error handling and validation
  Future<void> initialize() async {
    if (_isInitialized) {
      logger.d('NotificationService already initialized');
      return;
    }

    try {
      logger.d('Starting NotificationService initialization...');
      
      // Step 1: Get device ID
      _deviceId = await _getDeviceId();
      logger.i('✅ Device ID obtained: $_deviceId');
      
      // Step 2: Initialize SharedPreferences
      _prefs = await SharedPreferences.getInstance();
      logger.i('✅ SharedPreferences initialized');
      
      // Step 3: Cleanup old cache
      await _cleanupExpiredCache();
      logger.i('✅ Cache cleanup completed');
      
      _isInitialized = true;
      logger.i('✅ NotificationService fully initialized');
    } catch (e, stackTrace) {
      logger.e('❌ NotificationService initialization failed', error: e, stackTrace: stackTrace);
      // Don't rethrow - allow graceful degradation
      _isInitialized = false;
    }
  }

  Future<String> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        final deviceId = 'web_${webInfo.userAgent?.hashCode ?? 'unknown'}';
        logger.d('Web device ID: $deviceId');
        return deviceId;
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        final deviceId = 'android_${androidInfo.id}';
        logger.d('Android device ID: $deviceId');
        return deviceId;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        final deviceId = 'ios_${iosInfo.identifierForVendor ?? 'unknown'}';
        logger.d('iOS device ID: $deviceId');
        return deviceId;
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        final deviceId = 'windows_${windowsInfo.deviceId}';
        logger.d('Windows device ID: $deviceId');
        return deviceId;
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        final deviceId = 'macos_${macInfo.systemGUID ?? 'unknown'}';
        logger.d('MacOS device ID: $deviceId');
        return deviceId;
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        final deviceId = 'linux_${linuxInfo.machineId ?? 'unknown'}';
        logger.d('Linux device ID: $deviceId');
        return deviceId;
      }
    } catch (e) {
      logger.e('Error getting device ID', error: e);
    }
    final fallbackId = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
    logger.w('Using fallback device ID: $fallbackId');
    return fallbackId;
  }

  // FIXED: Local cache methods with better error handling
  String _getCacheKey(String projectId, String taskId) {
    final today = DateTime.now();
    final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return 'notification_triggered_${projectId}_${taskId}_$dateStr';
  }

  Future<bool> wasTriggeredToday(String projectId, String taskId) async {
    try {
      if (!_isInitialized) {
        logger.w('Service not initialized, cannot check cache');
        return false;
      }
      final key = _getCacheKey(projectId, taskId);
      final result = _prefs.getBool(key) ?? false;
      logger.d('Cache check for $taskId: $result');
      return result;
    } catch (e) {
      logger.e('Error checking cache', error: e);
      return false; // Fail open - allow notification attempt
    }
  }

  Future<void> markAsTriggered(String projectId, String taskId, int notificationId) async {
    try {
      if (!_isInitialized) {
        logger.w('Service not initialized, cannot mark as triggered');
        return;
      }
      final key = _getCacheKey(projectId, taskId);
      await _prefs.setBool(key, true);
      logger.i('✅ Marked as triggered in cache: $taskId');
    } catch (e) {
      logger.e('Error marking as triggered in cache', error: e);
    }
  }

  Future<void> _cleanupExpiredCache() async {
    try {
      final now = DateTime.now();
      final keys = _prefs.getKeys().where((k) => k.startsWith('notification_triggered_')).toList();
      int cleaned = 0;
      
      for (var key in keys) {
        final parts = key.split('_');
        if (parts.length >= 5) {
          // Extract date from key (last 3 parts are YYYY-MM-DD)
          final dateStr = parts.sublist(parts.length - 3).join('-');
          final cacheDate = DateTime.tryParse(dateStr);
          
          if (cacheDate == null || cacheDate.isBefore(now.subtract(const Duration(days: 2)))) {
            await _prefs.remove(key);
            cleaned++;
          }
        }
      }
      
      if (cleaned > 0) {
        logger.i('✅ Cleaned up $cleaned expired cache entries');
      }
    } catch (e) {
      logger.e('Error cleaning up cache', error: e);
    }
  }

  // FIXED: Better Firestore check with proper error handling
  Future<bool> wasNotificationTriggeredToday(String projectId, String taskId) async {
    try {
      await _ensureInitialized();
      
      logger.d('Checking if notification was triggered for task: $taskId');
      
      // Step 1: Check local cache first (fast)
      if (await wasTriggeredToday(projectId, taskId)) {
        logger.i('✅ Found in cache - notification already triggered today for task: $taskId');
        return true;
      }
      
      // Step 2: Check Firestore
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      
      Query query = _firestore
          .collection('ScheduleNotifications')
          .where('projectId', isEqualTo: projectId)
          .where('taskId', isEqualTo: taskId)
          .where('deviceId', isEqualTo: _deviceId)
          .where('isTriggered', isEqualTo: true)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .limit(1);
      
      if (userId != null) {
        query = query.where('userId', isEqualTo: userId);
      }
      
      logger.d('Executing Firestore query for task: $taskId');
      final snapshot = await query.get();
      final wasTriggered = snapshot.docs.isNotEmpty;
      
      if (wasTriggered) {
        logger.i('✅ Found in Firestore - notification already triggered today for task: $taskId');
        // Update cache to avoid future Firestore queries
        final doc = snapshot.docs.first;
        final data = doc.data() as Map<String, dynamic>;
        await markAsTriggered(projectId, taskId, data['notificationId'] ?? 0);
      } else {
        logger.d('❌ No triggered notification found for task: $taskId');
      }
      
      return wasTriggered;
    } catch (e, stackTrace) {
      logger.e('❌ Error checking notification history for task: $taskId', error: e, stackTrace: stackTrace);
      return false; // Fail open - allow notification attempt on error
    }
  }

  // FIXED: Lock mechanism with better expiry handling and consistency
  Future<bool> acquireLock(String projectId, String taskId) async {
    try {
      await _ensureInitialized();
      
      final today = DateTime.now();
      final dateStr = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
      final lockId = '${projectId}_${taskId}_$dateStr'; // Daily scoped lock
      
      logger.d('Attempting to acquire lock: $lockId');
      
      final lockAcquired = await _firestore.runTransaction<bool>((transaction) async {
        final lockRef = _firestore.collection('NotificationLocks').doc(lockId);
        final snapshot = await transaction.get(lockRef);
        
        if (snapshot.exists) {
          final data = snapshot.data()!;
          final lockedAt = (data['lockedAt'] as Timestamp).toDate();
          final lockAge = DateTime.now().difference(lockedAt);
          
          // FIXED: Consistent 5-minute expiry
          if (lockAge < const Duration(minutes: 5)) {
            logger.d('Lock already held by device: ${data['deviceId']}, age: ${lockAge.inSeconds}s');
            return false; // Lock still held
          } else {
            logger.i('Lock expired (age: ${lockAge.inMinutes}m), will override');
          }
        }
        
        // Acquire or refresh lock
        transaction.set(lockRef, {
          'projectId': projectId,
          'taskId': taskId,
          'deviceId': _deviceId,
          'lockedAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 5))),
          'processId': kIsWeb ? 'web' : 'app',
          'lockType': 'daily_trigger',
          'date': dateStr,
        }, SetOptions(merge: true));
        
        logger.i('✅ Lock acquired: $lockId');
        return true;
      });
      
      return lockAcquired;
    } catch (e, stackTrace) {
      logger.e('❌ Lock acquisition failed for $projectId/$taskId', error: e, stackTrace: stackTrace);
      return false; // Fail closed - don't allow notification on lock error
    }
  }

  // FIXED: Lock release with better error handling
  Future<void> releaseLock(String projectId, String taskId) async {
    try {
      final today = DateTime.now();
      final dateStr = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
      final lockId = '${projectId}_${taskId}_$dateStr';
      
      logger.d('Releasing lock: $lockId');
      await _firestore.collection('NotificationLocks').doc(lockId).delete();
      logger.i('✅ Lock released: $lockId');
    } catch (e) {
      logger.e('❌ Lock release failed', error: e);
      // Don't rethrow - lock will expire naturally
    }
  }

  // FIXED: Save notification with comprehensive error handling and validation
  Future<String?> saveNotification({
    required String projectId,
    required String taskId,
    required String taskName,
    required DateTime startDate,
    required String message,
    required bool isTriggered,
    required String triggerSource,
    DateTime? triggeredAt,
    int? notificationId,
    required DateTime expiresAt,
    required String type,
  }) async {
    try {
      await _ensureInitialized();
      
      logger.d('Saving notification for task: $taskId (type: $type, isTriggered: $isTriggered)');

      final notification = ScheduleNotification(
        id: '',
        projectId: projectId,
        taskId: taskId,
        taskName: taskName,
        startDate: startDate,
        message: message,
        createdAt: DateTime.now(),
        isRead: false,
        userId: userId,
        deviceId: _deviceId!,
        isTriggered: isTriggered,
        triggeredAt: triggeredAt,
        notificationId: notificationId,
        openedFromTray: false,
        openedAt: null,
        dismissedAt: null,
        deliveryStatus: isTriggered ? 'delivered' : 'pending',
        readSource: null,
        triggerSource: triggerSource,
        lastAttemptAt: DateTime.now(),
        attemptCount: 1,
        expiresAt: expiresAt,
        type: type,
      );

      final docRef = await _firestore
          .collection('ScheduleNotifications')
          .add(notification.toFirestore());

      logger.i('✅ Notification saved with ID: ${docRef.id} (type: $type, task: $taskName)');
      
      // Update cache if triggered
      if (isTriggered && notificationId != null) {
        await markAsTriggered(projectId, taskId, notificationId);
      }
      
      return docRef.id;
    } catch (e, stackTrace) {
      logger.e('❌ Error saving notification for task: $taskId', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<Map<String, bool>> batchCheckNotificationsTriggeredToday(
    String projectId, 
    List<String> taskIds,
  ) async {
    try {
      await _ensureInitialized();
      
      if (taskIds.isEmpty) {
        logger.d('No tasks to check');
        return {};
      }
      
      logger.d('Batch checking ${taskIds.length} tasks');
      
      final Map<String, bool> results = {};
      final List<String> toCheckFirestore = [];
      
      // Step 1: Check cache for all tasks
      for (var taskId in taskIds) {
        final cached = await wasTriggeredToday(projectId, taskId);
        results[taskId] = cached;
        if (!cached) toCheckFirestore.add(taskId);
      }
      
      if (toCheckFirestore.isEmpty) {
        logger.d('All tasks found in cache');
        return results;
      }
      
      logger.d('Checking ${toCheckFirestore.length} tasks in Firestore');
      
      // Step 2: Check Firestore in batches of 10 (Firestore whereIn limit)
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final Set<String> triggeredTaskIds = {};
      
      for (var i = 0; i < toCheckFirestore.length; i += 10) {
        final chunk = toCheckFirestore.skip(i).take(10).toList();
        
        Query query = _firestore
            .collection('ScheduleNotifications')
            .where('projectId', isEqualTo: projectId)
            .where('taskId', whereIn: chunk)
            .where('deviceId', isEqualTo: _deviceId)
            .where('isTriggered', isEqualTo: true)
            .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay));
        
        if (userId != null) {
          query = query.where('userId', isEqualTo: userId);
        }
        
        final snapshot = await query.get();
        logger.d('Batch query returned ${snapshot.docs.length} triggered notifications');
        
        for (var doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final taskId = data['taskId'] as String;
          triggeredTaskIds.add(taskId);
          
          // Update cache
          await markAsTriggered(projectId, taskId, data['notificationId'] ?? 0);
        }
      }
      
      // Step 3: Update results
      for (var taskId in toCheckFirestore) {
        results[taskId] = triggeredTaskIds.contains(taskId);
      }
      
      logger.i('✅ Batch check complete: ${triggeredTaskIds.length} already triggered');
      return results;
    } catch (e, stackTrace) {
      logger.e('❌ Error batch checking notification history', error: e, stackTrace: stackTrace);
      // On error, assume not triggered to allow sending
      final Map<String, bool> safeResults = {};
      for (var id in taskIds) {
        safeResults[id] = false;
      }
      return safeResults;
    }
  }

  // FIXED: Batch save with better error handling
  Future<List<String>> batchSaveNotifications({
    required String projectId,
    required List<Map<String, dynamic>> notificationsData,
  }) async {
    try {
      await _ensureInitialized();
      
      if (notificationsData.isEmpty) {
        logger.d('No notifications to save');
        return [];
      }

      logger.d('Batch saving ${notificationsData.length} notifications');

      final batch = _firestore.batch();
      final List<String> docIds = [];
      final now = DateTime.now();

      for (var data in notificationsData) {
        final docRef = _firestore.collection('ScheduleNotifications').doc();
        docIds.add(docRef.id);

        final notification = ScheduleNotification(
          id: docRef.id,
          projectId: projectId,
          taskId: data['taskId'] as String,
          taskName: data['taskName'] as String,
          startDate: data['startDate'] as DateTime,
          message: data['message'] as String,
          createdAt: now,
          isRead: false,
          userId: userId,
          deviceId: _deviceId!,
          isTriggered: data['isTriggered'] as bool,
          triggeredAt: data['triggeredAt'] as DateTime?,
          notificationId: data['notificationId'] as int?,
          openedFromTray: false,
          openedAt: null,
          dismissedAt: null,
          deliveryStatus: (data['isTriggered'] as bool) ? 'delivered' : 'pending',
          readSource: null,
          triggerSource: data['triggerSource'] as String,
          lastAttemptAt: now,
          attemptCount: 1,
          expiresAt: data['expiresAt'] as DateTime,
          type: data['type'] as String,
        );

        batch.set(docRef, notification.toFirestore());
        
        // Update cache if triggered
        if (notification.isTriggered && notification.notificationId != null) {
          await markAsTriggered(projectId, notification.taskId, notification.notificationId!);
        }
      }

      await batch.commit();
      logger.i('✅ Batch saved ${notificationsData.length} notifications');
      return docIds;
    } catch (e, stackTrace) {
      logger.e('❌ Error batch saving notifications', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  // Remaining methods stay the same...
  Future<void> markAsRead(String notificationId, {String? readSource}) async {
    try {
      final updates = <String, dynamic>{
        'isRead': true,
      };
      if (readSource != null) updates['readSource'] = readSource;
      await _firestore
          .collection('ScheduleNotifications')
          .doc(notificationId)
          .update(updates);
      logger.i('✅ Notification $notificationId marked as read');
    } catch (e) {
      logger.e('Error marking notification as read', error: e);
    }
  }

  Future<void> markAllAsRead(String projectId) async {
    try {
      await _ensureInitialized();

      Query query = _firestore
          .collection('ScheduleNotifications')
          .where('projectId', isEqualTo: projectId)
          .where('deviceId', isEqualTo: _deviceId)
          .where('isRead', isEqualTo: false);
      
      if (userId != null) {
        query = query.where('userId', isEqualTo: userId);
      }
      
      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        logger.i('ℹ️ No unread notifications to mark');
        return;
      }

      final chunks = <List<QueryDocumentSnapshot>>[];
      for (var i = 0; i < snapshot.docs.length; i += 500) {
        chunks.add(snapshot.docs.skip(i).take(500).toList());
      }

      for (var chunk in chunks) {
        final batch = _firestore.batch();
        for (var doc in chunk) {
          batch.update(doc.reference, {'isRead': true});
        }
        await batch.commit();
      }
      
      logger.i('✅ Marked ${snapshot.docs.length} notifications as read for project $projectId');
    } catch (e, stackTrace) {
      logger.e('Error marking all notifications as read', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Stream<int> getUnreadCount(String projectId) {
    return Stream.fromFuture(_ensureInitialized()).asyncExpand((_) {
      Query query = _firestore
          .collection('ScheduleNotifications')
          .where('projectId', isEqualTo: projectId)
          .where('deviceId', isEqualTo: _deviceId)
          .where('isRead', isEqualTo: false);
      
      if (userId != null) {
        query = query.where('userId', isEqualTo: userId);
      }

      return query
          .snapshots()
          .map((snapshot) => snapshot.size);
    });
  }

  Stream<List<ScheduleNotification>> getNotifications(
    String projectId, {
    int limit = 50,
  }) {
    return Stream.fromFuture(_ensureInitialized()).asyncExpand((_) {
      Query query = _firestore
          .collection('ScheduleNotifications')
          .where('projectId', isEqualTo: projectId)
          .where('deviceId', isEqualTo: _deviceId);
      
      if (userId != null) {
        query = query.where('userId', isEqualTo: userId);
        logger.d('getNotifications: Including userId filter: $userId');
      } else {
        logger.d('getNotifications: No userId filter (null)');
      }

      logger.d('getNotifications: Executing query for projectId: $projectId, deviceId: $_deviceId, limit: $limit');

      return query
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snapshot) {
            logger.d('getNotifications: Received snapshot with ${snapshot.docs.length} docs');
            // Notifications persist as history and are never hidden by
            // expiry — only isRead reflects whether the user has seen one
            // (see NotificationsScreen, the single unified notification
            // center). expiresAt is kept on the model/doc for reference but
            // no longer drives visibility or deletion (see
            // cleanupOldNotifications, which nothing calls anymore).
            final list = snapshot.docs
                .map((doc) => ScheduleNotification.fromFirestore(doc.id, doc.data() as Map<String, dynamic>))
                .toList();
            return list;
          }).handleError((error) {
            logger.e('getNotifications: Stream error', error: error);
          });
    });
  }

  Future<void> cleanupOldNotifications({int daysToKeep = 30}) async {
    try {
      await _ensureInitialized();

      final now = DateTime.now();
      
      Query query = _firestore
          .collection('ScheduleNotifications')
          .where('deviceId', isEqualTo: _deviceId)
          .where('expiresAt', isLessThan: Timestamp.fromDate(now));
      
      if (userId != null) {
        query = query.where('userId', isEqualTo: userId);
      }
      
      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      
      logger.i('✅ Cleaned up ${snapshot.docs.length} expired notifications');
    } catch (e) {
      logger.e('Error cleaning up expired notifications', error: e);
    }
  }

  Future<void> markAsOpened(String notificationId) async {
    try {
      await _firestore
          .collection('ScheduleNotifications')
          .doc(notificationId)
          .update({
            'openedFromTray': true,
            'openedAt': FieldValue.serverTimestamp(),
          });
      logger.i('✅ Notification $notificationId marked as opened from tray');
    } catch (e) {
      logger.e('Error marking as opened', error: e);
    }
  }

  Future<void> markAsDismissed(String notificationId) async {
    try {
      await _firestore
          .collection('ScheduleNotifications')
          .doc(notificationId)
          .update({
            'dismissedAt': FieldValue.serverTimestamp(),
          });
      logger.i('✅ Notification $notificationId marked as dismissed');
    } catch (e) {
      logger.e('Error marking as dismissed', error: e);
    }
  }

  Future<List<Map<String, dynamic>>> getDailyNotifications(String projectId) async {
    try {
      final QuerySnapshot snapshot = await _firestore
          .collection('Schedule')
          .where('projectId', isEqualTo: projectId)
          .get();

      final List<GanttRowData> tasks = snapshot.docs.map((doc) {
        return GanttRowData.fromFirebaseMap(doc.id, doc.data() as Map<String, dynamic>);
      }).toList();

      final DateTime now = DateTime.now();

      final overdue = tasks.where((task) => task.status == TaskStatus.overdue).map((task) => {
        'taskId': task.firestoreId,
        'taskName': task.taskName,
        'startDate': task.startDate,
        'message': 'Task is overdue',
        'type': 'overdue',
        'expiresAt': now.add(const Duration(days: 7)),
      }).toList();

      final startingSoon = tasks.where((task) {
        if (task.startDate == null) return false;
        final diff = task.startDate!.difference(now).inDays;
        return diff <= 3 && diff > 0 && (task.status == null || task.status != TaskStatus.completed);
      }).map((task) => {
        'taskId': task.firestoreId,
        'taskName': task.taskName,
        'startDate': task.startDate,
        'message': 'Task starts soon',
        'type': 'starting_soon',
        'expiresAt': task.startDate!,
      }).toList();

      return [...overdue, ...startingSoon];
    } catch (e) {
      logger.e('Error getting daily notifications', error: e);
      return [];
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_isInitialized || _deviceId == null) {
      await initialize();
    }
    if (_deviceId == null) {
      throw Exception('NotificationService failed to initialize - deviceId is null');
    }
  }
}