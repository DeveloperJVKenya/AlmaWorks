import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/models/schedule_monitor_model.dart';
import 'package:almaworks/services/enhanced_notification_service.dart';
import 'package:almaworks/services/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:elegant_notification/elegant_notification.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:workmanager/workmanager.dart' hide TaskStatus;
import 'dart:async';

// NEW: Helper method for notification colors based on type

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    final logger = Logger();
    
    try {
      logger.i('🔄 Background task started: $taskName');
      
      tzdata.initializeTimeZones();

      final String? projectId = inputData?['projectId'] as String?;
      final String? userId = inputData?['userId'] as String?;

      if (projectId == null) {
        logger.e('❌ Background task: projectId is null');
        return Future.value(false);
      }

      logger.d('📋 Background task processing project: $projectId');

      // STEP 1: Initialize services
      final notificationService = NotificationService(
        logger: logger,
        userId: userId,
      );
      
      await notificationService.initialize();
      logger.i('✅ NotificationService initialized in background');

      final enhancedNotificationService = EnhancedNotificationService(
        logger: logger,
        notificationService: notificationService,
      );
      
      await enhancedNotificationService.initialize();
      logger.i('✅ EnhancedNotificationService initialized in background');

      // STEP 2: Fetch and update tasks from ScheduleMonitor
      logger.d('🔥 Fetching tasks from ScheduleMonitor...');
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('ScheduleMonitor')
          .where('projectId', isEqualTo: projectId)
          .get();

      if (snapshot.docs.isEmpty) {
        logger.i('ℹ️ No tasks found for project $projectId');
        return Future.value(true);
      }

      final List<ScheduleMonitorData> tasks = snapshot.docs
          .map((doc) => ScheduleMonitorData.fromFirestore(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
      
      logger.d('📊 Loaded ${tasks.length} tasks from ScheduleMonitor');

      final DateTime now = DateTime.now();

      // STEP 3: Update statuses in ScheduleMonitor
      logger.d('🔄 Updating task statuses...');
      int updatedCount = 0;
      final batch = FirebaseFirestore.instance.batch();
      
      for (var task in tasks) {
        final newStatus = ScheduleMonitorData.computeStatus(
          startDate: task.startDate,
          endDate: task.endDate,
          actualStartDate: task.actualStartDate,
          actualEndDate: task.actualEndDate,
          taskStatus: task.taskStatus,
        );
        
        UpcomingCategory? newUpcomingCategory;
        if (newStatus == MonitorStatus.upcoming) {
          newUpcomingCategory = ScheduleMonitorData.computeUpcomingCategory(task.startDate);
        }
        
        if (newStatus != task.status || newUpcomingCategory != task.upcomingCategory) {
          batch.update(
            FirebaseFirestore.instance.collection('ScheduleMonitor').doc(task.id),
            {
              'status': newStatus.toString().split('.').last.toUpperCase(),
              'upcomingCategory': newUpcomingCategory?.toString().split('.').last.toUpperCase(),
              'updatedAt': FieldValue.serverTimestamp(),
              'lastStatusUpdate': FieldValue.serverTimestamp(),
            },
          );
          updatedCount++;
        }
      }
      
      if (updatedCount > 0) {
        await batch.commit();
        logger.i('✅ Updated $updatedCount task statuses');
      }

      // Re-fetch updated tasks
      final updatedSnapshot = await FirebaseFirestore.instance
          .collection('ScheduleMonitor')
          .where('projectId', isEqualTo: projectId)
          .get();
      
      final updatedTasks = updatedSnapshot.docs
          .map((doc) => ScheduleMonitorData.fromFirestore(doc.id, doc.data()))
          .toList();

      // STEP 4: Categorize and sort tasks
      final List<ScheduleMonitorData> overdueTasks = updatedTasks
          .where((task) => task.status == MonitorStatus.overdue)
          .toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));

      final List<ScheduleMonitorData> startingSoonTasks = updatedTasks
          .where((task) => task.status == MonitorStatus.upcoming && task.isStartingSoon)
          .toList()
        ..sort((a, b) => a.daysUntilStart.compareTo(b.daysUntilStart));

      logger.i('📋 Found ${overdueTasks.length} overdue, ${startingSoonTasks.length} starting soon');

      final List<ScheduleMonitorData> notifyTasks = [...overdueTasks, ...startingSoonTasks];

      if (notifyTasks.isEmpty) {
        logger.i('✅ No tasks need notifications');
        return Future.value(true);
      }

      // STEP 5: Batch check notification status
      logger.d('🔍 Batch checking notification status...');
      final taskIds = notifyTasks.map((t) => t.scheduleTaskId).toList();
      final triggeredMap = await notificationService.batchCheckNotificationsTriggeredToday(
        projectId,
        taskIds,
      );

      final List<Map<String, dynamic>> unsentTasks = [];
      
      for (var task in notifyTasks) {
        final wasTriggered = triggeredMap[task.scheduleTaskId] ?? false;
        
        if (!wasTriggered) {
          final type = task.isOverdue ? 'overdue' : 'starting_soon';
          unsentTasks.add({
            'task': task,
            'type': type,
          });
          logger.d('🔖 Task "${task.taskName}" queued for notification');
        }
      }

      if (unsentTasks.isEmpty) {
        logger.i('✅ All tasks already notified');
        return Future.value(true);
      }

      logger.i('🔔 Triggering ${unsentTasks.length} notifications');

      // STEP 6: Save and show notifications
      for (var item in unsentTasks) {
        final task = item['task'] as ScheduleMonitorData;
        final type = item['type'] as String;
        
        try {
          final body = type == 'overdue'
              ? 'This task is overdue and needs attention!'
              : 'Starts in ${task.daysUntilStart} day(s)';

          // Save to Firestore
          final savedId = await notificationService.saveNotification(
            projectId: projectId,
            taskId: task.scheduleTaskId,
            taskName: task.taskName,
            startDate: task.startDate,
            message: body,
            isTriggered: true,
            triggerSource: 'background_task',
            triggeredAt: now,
            notificationId: '$projectId}_${task.scheduleTaskId}'.hashCode,
            expiresAt: task.startDate,
            type: type,
          );

          if (savedId != null) {
            // Show notification
            await enhancedNotificationService.showTaskNotification(
              projectId: projectId,
              task: task,
              type: type,
              firestoreNotificationId: savedId,
            );
            
            logger.i('✅ Notification shown and saved: ${task.taskName}');
            
            // Small delay for floating effect
            await Future.delayed(const Duration(milliseconds: 300));
          }
        } catch (e, stackTrace) {
          logger.e('❌ Error showing notification for ${task.taskName}', 
                   error: e, stackTrace: stackTrace);
        }
      }

      // STEP 7: Show group summary if multiple notifications
      if (unsentTasks.length > 1) {
        logger.d('📦 Creating group summary notification');
        
        await enhancedNotificationService.showGroupedNotification(
          projectId: projectId,
          taskGroups: unsentTasks,
          totalCount: unsentTasks.length,
        );
      }

      logger.i('🎉 Background task completed - sent ${unsentTasks.length} notifications');
      return Future.value(true);

    } catch (e, stackTrace) {
      logger.e('❌ Background task failed', error: e, stackTrace: stackTrace);
      return Future.value(false);
    }
  });
}
class ScheduleMonitorScreen extends StatefulWidget {
  final String projectId;
  final String projectName;
  final Logger logger;
  final ProjectModel project;

  const ScheduleMonitorScreen({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.logger,
    required this.project,
  });

  @override
  State<ScheduleMonitorScreen> createState() => _ScheduleMonitorScreenState();
}

class _ScheduleMonitorScreenState extends State<ScheduleMonitorScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late NotificationService _notificationService;
  bool _isCheckingNotifications = false;
  late EnhancedNotificationService _enhancedNotificationService;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  Timer? _refreshTimer;
  Timer? _realtimeStatusTimer; // FIX: saved reference so dispose() can cancel it

  @override
  void initState() {
    super.initState();
    
    widget.logger.i('🚀 Initializing ScheduleMonitorScreen for project: ${widget.projectId}');
    
    // Initialize notification service
    _notificationService = NotificationService(
      logger: widget.logger,
      userId: null,
    );
    
    // UPDATED: Initialize enhanced notification service
    _enhancedNotificationService = EnhancedNotificationService(
      logger: widget.logger,
      notificationService: _notificationService,
    );
    
    // Initialize services
    _notificationService.initialize().then((_) async {
      widget.logger.i('✅ NotificationService initialized successfully');
      
      // Initialize enhanced notifications
      await _enhancedNotificationService.initialize();
      widget.logger.i('✅ EnhancedNotificationService initialized successfully');
      
      // Sync Schedule to ScheduleMonitor collection
      await _syncScheduleToMonitor();
      
      if (mounted && !kIsWeb) {
        widget.logger.i('📱 Platform supports notifications, scheduling initial check');
        
        // Initial check after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            widget.logger.i('🔔 Running initial notification check');
            _scheduleNotificationCheck();
          }
        });
      } else if (kIsWeb) {
        widget.logger.w('🌐 Web platform - background notifications not fully supported');
      }
    }).catchError((error) {
      widget.logger.e('❌ NotificationService initialization failed', error: error);
    });
    
    
    // Animation setup
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    
    // Initialize timezone data
    tzdata.initializeTimeZones();
    
    // Platform-specific initialization
    if (!kIsWeb) {
      _initializeBackgroundTasks();
    }

    // Search controller listener
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });

    // Periodic check every hour
    _refreshTimer = Timer.periodic(const Duration(hours: 1), (timer) {
      if (mounted && !kIsWeb) {
        widget.logger.d('⏰ Periodic notification check triggered');
        _scheduleNotificationCheck();
      }
    });
    
    // Start real-time status updater
    _startRealtimeStatusUpdater();
    
    widget.logger.i('✅ ScheduleMonitorScreen initialization complete');
  }

  Future<void> _syncScheduleToMonitor() async {
    try {
      widget.logger.i('🔄 Syncing Schedule to ScheduleMonitor collection...');
      
      final firestore = FirebaseFirestore.instance;
      final now = DateTime.now();
      
      // Get all tasks from Schedule collection for this project (only TaskType = "Task")
      final scheduleSnapshot = await firestore
          .collection('Schedule')
          .where('projectId', isEqualTo: widget.projectId)
          .where('taskType', isEqualTo: 'Task')
          .get();
      
      widget.logger.d('📋 Found ${scheduleSnapshot.docs.length} tasks in Schedule collection');
      
      // Get existing ScheduleMonitor documents
      final monitorSnapshot = await firestore
          .collection('ScheduleMonitor')
          .where('projectId', isEqualTo: widget.projectId)
          .get();
      
      // Create a map of existing monitor documents by scheduleTaskId
      final existingMonitorMap = <String, String>{};
      for (var doc in monitorSnapshot.docs) {
        final scheduleTaskId = doc.data()['scheduleTaskId'] as String;
        existingMonitorMap[scheduleTaskId] = doc.id;
      }
      
      widget.logger.d('📊 Found ${existingMonitorMap.length} existing monitor records');
      
      // Batch write for efficiency
      final batch = firestore.batch();
      int createCount = 0;
      int updateCount = 0;
      
      for (var scheduleDoc in scheduleSnapshot.docs) {
        final scheduleData = scheduleDoc.data();
        
        // Validate required fields
        if (scheduleData['startDate'] == null || 
            scheduleData['endDate'] == null ||
            scheduleData['taskName'] == null) {
          widget.logger.w('⚠️ Skipping task ${scheduleDoc.id} - missing required fields');
          continue;
        }
        
        // Extract dates and normalize them
        final startDate = _normalizeToMidnight((scheduleData['startDate'] as Timestamp).toDate());
        final endDate = _normalizeToMidnight((scheduleData['endDate'] as Timestamp).toDate());
        final actualStartDate = scheduleData['actualStartDate'] != null 
            ? _normalizeToMidnight((scheduleData['actualStartDate'] as Timestamp).toDate())
            : null;
        final actualEndDate = scheduleData['actualEndDate'] != null 
            ? _normalizeToMidnight((scheduleData['actualEndDate'] as Timestamp).toDate())
            : null;
        final taskStatus = scheduleData['taskStatus'] as String?;
        
        // Compute status using normalized dates
        final status = _computeStatusWithNormalizedDates(
          startDate: startDate,
          endDate: endDate,
          actualStartDate: actualStartDate,
          actualEndDate: actualEndDate,
          taskStatus: taskStatus,
          now: now,
        );
        
        // Compute upcoming category if status is upcoming
        UpcomingCategory? upcomingCategory;
        if (status == MonitorStatus.upcoming) {
          upcomingCategory = _computeUpcomingCategoryWithNormalizedDates(startDate, now);
        }
        
        // Compute duration
        final duration = _calculateDaysBetween(startDate, endDate) + 1;
        
        // Create monitor data map
        final monitorData = {
          'scheduleTaskId': scheduleDoc.id,
          'projectId': scheduleData['projectId'],
          'projectName': scheduleData['projectName'],
          'taskName': scheduleData['taskName'],
          'startDate': Timestamp.fromDate(startDate),
          'endDate': Timestamp.fromDate(endDate),
          'actualStartDate': actualStartDate != null ? Timestamp.fromDate(actualStartDate) : null,
          'actualEndDate': actualEndDate != null ? Timestamp.fromDate(actualEndDate) : null,
          'taskStatus': taskStatus,
          'status': status.toString().split('.').last.toUpperCase(),
          'upcomingCategory': upcomingCategory?.toString().split('.').last.toUpperCase(),
          'duration': duration,
          'resourceId': scheduleData['resourceId'],
          'resourceQuantity': scheduleData['resourceQuantity'],
          'updatedAt': Timestamp.fromDate(now),
          'lastStatusUpdate': Timestamp.fromDate(now),
        };
        
        // Check if document exists using the map
        if (existingMonitorMap.containsKey(scheduleDoc.id)) {
          // Update existing document
          final monitorDocId = existingMonitorMap[scheduleDoc.id]!;
          batch.update(
            firestore.collection('ScheduleMonitor').doc(monitorDocId),
            monitorData,
          );
          updateCount++;
        } else {
          // Create new document with createdAt
          final newDocRef = firestore.collection('ScheduleMonitor').doc();
          monitorData['createdAt'] = Timestamp.fromDate(now);
          batch.set(newDocRef, monitorData);
          createCount++;
        }
      }
      
      // Delete orphaned ScheduleMonitor documents (tasks deleted from Schedule)
      final scheduleTaskIds = scheduleSnapshot.docs.map((doc) => doc.id).toSet();
      int deleteCount = 0;
      
      for (var entry in existingMonitorMap.entries) {
        if (!scheduleTaskIds.contains(entry.key)) {
          batch.delete(firestore.collection('ScheduleMonitor').doc(entry.value));
          deleteCount++;
        }
      }
      
      // Commit batch
      await batch.commit();
      
      widget.logger.i('✅ Sync complete: Created $createCount, Updated $updateCount, Deleted $deleteCount');
      
    } catch (e, stackTrace) {
      widget.logger.e('❌ Error syncing to ScheduleMonitor', error: e, stackTrace: stackTrace);
    }
  }

  /// Computes status with normalized dates for accurate day calculation
  MonitorStatus _computeStatusWithNormalizedDates({
    required DateTime startDate,
    required DateTime endDate,
    DateTime? actualStartDate,
    DateTime? actualEndDate,
    String? taskStatus,
    required DateTime now,
  }) {
    final normalizedNow = _normalizeToMidnight(now);
    final normalizedStart = _normalizeToMidnight(startDate);
    
    // Priority 1: Check if completed (user marked as completed OR has actualEndDate)
    if (taskStatus == 'COMPLETED' || actualEndDate != null) {
      return MonitorStatus.completed;
    }
    
    // Priority 2: Check if started (user marked as started OR has actualStartDate)
    if (taskStatus == 'STARTED' || actualStartDate != null) {
      return MonitorStatus.ongoing;
    }
    
    // Priority 3: Check if overdue (start date passed but not started)
    if (normalizedStart.isBefore(normalizedNow)) {
      return MonitorStatus.overdue;
    }
    
    // Priority 4: Default to upcoming (future start date, not started)
    return MonitorStatus.upcoming;
  }

  /// Computes upcoming category with normalized dates
  UpcomingCategory? _computeUpcomingCategoryWithNormalizedDates(DateTime startDate, DateTime now) {
    final normalizedNow = _normalizeToMidnight(now);
    final normalizedStart = _normalizeToMidnight(startDate);
    final daysUntilStart = _calculateDaysBetween(normalizedNow, normalizedStart);
    
    if (daysUntilStart <= 3 && daysUntilStart > 0) {
      return UpcomingCategory.startingSoon;
    } else if (daysUntilStart > 3) {
      return UpcomingCategory.otherUpcoming;
    }
    
    return null;
  }

  /// Normalizes a DateTime to midnight in the device's local timezone
  DateTime _normalizeToMidnight(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Calculates calendar days between two dates
  int _calculateDaysBetween(DateTime from, DateTime to) {
    final normalizedFrom = _normalizeToMidnight(from);
    final normalizedTo = _normalizeToMidnight(to);
    return normalizedTo.difference(normalizedFrom).inDays;
  }

  void _startRealtimeStatusUpdater() {
    // Update statuses every minute to catch date changes.
    // FIX: Store the timer so dispose() can cancel it immediately, preventing
    // a stale Firestore write on the tick after the widget is unmounted.
    _realtimeStatusTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      try {
        final firestore = FirebaseFirestore.instance;
        final now = DateTime.now();
        final normalizedNow = _normalizeToMidnight(now);
        
        // Get all ScheduleMonitor documents for this project
        final snapshot = await firestore
            .collection('ScheduleMonitor')
            .where('projectId', isEqualTo: widget.projectId)
            .get();
        
        final batch = firestore.batch();
        int updateCount = 0;
        
        for (var doc in snapshot.docs) {
          final data = doc.data();
          
          // Extract and normalize dates
          final startDate = _normalizeToMidnight((data['startDate'] as Timestamp).toDate());
          final endDate = _normalizeToMidnight((data['endDate'] as Timestamp).toDate());
          final actualStartDate = data['actualStartDate'] != null
              ? _normalizeToMidnight((data['actualStartDate'] as Timestamp).toDate())
              : null;
          final actualEndDate = data['actualEndDate'] != null
              ? _normalizeToMidnight((data['actualEndDate'] as Timestamp).toDate())
              : null;
          final taskStatus = data['taskStatus'] as String?;
          
          // Get current status from document
          final currentStatusStr = data['status'] as String?;
          final currentStatus = currentStatusStr != null
              ? MonitorStatus.values.firstWhere(
                  (e) => e.toString().split('.').last.toUpperCase() == currentStatusStr,
                  orElse: () => MonitorStatus.upcoming,
                )
              : MonitorStatus.upcoming;
          
          // Recompute status with normalized dates
          final newStatus = _computeStatusWithNormalizedDates(
            startDate: startDate,
            endDate: endDate,
            actualStartDate: actualStartDate,
            actualEndDate: actualEndDate,
            taskStatus: taskStatus,
            now: now,
          );
          
          // Recompute upcoming category
          UpcomingCategory? newUpcomingCategory;
          if (newStatus == MonitorStatus.upcoming) {
            newUpcomingCategory = _computeUpcomingCategoryWithNormalizedDates(startDate, now);
          }
          
          // Get current upcoming category
          final currentUpcomingCategoryStr = data['upcomingCategory'] as String?;
          final currentUpcomingCategory = currentUpcomingCategoryStr != null
              ? UpcomingCategory.values.firstWhere(
                  (e) => e.toString().split('.').last.toUpperCase() == currentUpcomingCategoryStr,
                  orElse: () => UpcomingCategory.otherUpcoming,
                )
              : null;
          
          // Update if status or category changed
          if (newStatus != currentStatus || newUpcomingCategory != currentUpcomingCategory) {
            batch.update(doc.reference, {
              'status': newStatus.toString().split('.').last.toUpperCase(),
              'upcomingCategory': newUpcomingCategory?.toString().split('.').last.toUpperCase(),
              'updatedAt': Timestamp.fromDate(now),
              'lastStatusUpdate': Timestamp.fromDate(now),
            });
            updateCount++;
            
            widget.logger.d('📊 Status changed for "${data['taskName']}": $currentStatus -> $newStatus (Days until start: ${_calculateDaysBetween(normalizedNow, startDate)})');
          }
        }
        
        if (updateCount > 0) {
          await batch.commit();
          widget.logger.d('🔄 Real-time updater: Updated $updateCount task statuses');
        }
        
      } catch (e) {
        widget.logger.e('❌ Error in real-time status updater', error: e);
      }
    });
  }

  @override
  void dispose() {
    widget.logger.d('🧹 Disposing ScheduleMonitorScreen');
    
    _refreshTimer?.cancel();
    _realtimeStatusTimer?.cancel(); // FIX: cancel the realtime status updater
    _animationController.dispose();
    _searchController.dispose();
    _isCheckingNotifications = false;
    
    widget.logger.d('✅ ScheduleMonitorScreen disposed');
    super.dispose();
  }

  void _initializeBackgroundTasks() {
    widget.logger.i('⏰ Initializing background tasks');
    
    Workmanager().initialize(callbackDispatcher); // FIXED: Removed isInDebugMode

    // FIXED: Changed to every 6 hours (from 4) to reduce battery drain
    Workmanager().registerPeriodicTask(
      "${widget.projectId}_periodic_check",
      "scheduleMonitorTask",
      frequency: const Duration(hours: 6),
      inputData: {
        'projectId': widget.projectId,
        'userId': null,
      },
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.connected, // FIXED: Require network
      ),
    );
    
    widget.logger.i('✅ Background task registered for project ${widget.projectId}');
  }

  Future<void> _scheduleNotificationCheck() async {
    if (_isCheckingNotifications) {
      widget.logger.w('⚠️ Notification check already in progress, skipping');
      return;
    }
    
    widget.logger.i('🔍 Starting notification check for project: ${widget.projectId}');
    
    setState(() {
      _isCheckingNotifications = true;
    });

    try {
      // STEP 1: Verify notification permissions
      final permissionsGranted = await _enhancedNotificationService.areNotificationsEnabled();
      if (!permissionsGranted) {
        widget.logger.w('⚠️ Notification permission not granted, requesting...');
        final granted = await _enhancedNotificationService.requestPermissions();
        if (!granted) {
          widget.logger.w('⚠️ User denied notification permissions');
          return;
        }
      }
      widget.logger.d('✅ Permission verified');

      // STEP 2: Fetch tasks from ScheduleMonitor collection
      widget.logger.d('🔥 Fetching tasks from ScheduleMonitor...');
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('ScheduleMonitor')
          .where('projectId', isEqualTo: widget.projectId)
          .get();

      if (snapshot.docs.isEmpty) {
        widget.logger.i('ℹ️ No tasks found in ScheduleMonitor');
        return;
      }

      final List<ScheduleMonitorData> allTasks = snapshot.docs
          .map((doc) => ScheduleMonitorData.fromFirestore(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
      
      widget.logger.d('📊 Loaded ${allTasks.length} tasks from ScheduleMonitor');

      // STEP 3: Filter and categorize tasks that need notifications
      final List<ScheduleMonitorData> overdueTasks = [];
      final List<ScheduleMonitorData> startingSoonTasks = [];

      for (var task in allTasks) {
        if (task.status == MonitorStatus.overdue) {
          overdueTasks.add(task);
        } else if (task.status == MonitorStatus.upcoming && task.isStartingSoon) {
          startingSoonTasks.add(task);
        }
      }

      // Sort: Overdue by start date (earliest first), Starting Soon by days until start
      overdueTasks.sort((a, b) => a.startDate.compareTo(b.startDate));
      startingSoonTasks.sort((a, b) => a.daysUntilStart.compareTo(b.daysUntilStart));

      widget.logger.i('📋 Found ${overdueTasks.length} overdue, ${startingSoonTasks.length} starting soon');

      final List<ScheduleMonitorData> notifyTasks = [...overdueTasks, ...startingSoonTasks];

      if (notifyTasks.isEmpty) {
        widget.logger.i('✅ No tasks require notifications');
        return;
      }

      // STEP 4: Check which tasks haven't been notified today using batch check
      widget.logger.d('🔍 Batch checking notification status...');
      final taskIds = notifyTasks.map((t) => t.scheduleTaskId).toList();
      final triggeredMap = await _notificationService.batchCheckNotificationsTriggeredToday(
        widget.projectId,
        taskIds,
      );

      final List<Map<String, dynamic>> unsentTasks = [];
      
      for (var task in notifyTasks) {
        final wasTriggered = triggeredMap[task.scheduleTaskId] ?? false;
        
        if (!wasTriggered) {
          final type = task.isOverdue ? 'overdue' : 'starting_soon';
          unsentTasks.add({
            'task': task,
            'type': type,
          });
          widget.logger.d('🔖 Task "${task.taskName}" needs notification (type: $type)');
        } else {
          widget.logger.d('⭐ Task "${task.taskName}" already notified today');
        }
      }

      if (unsentTasks.isEmpty) {
        widget.logger.i('✅ All tasks already notified today');
        return;
      }

      widget.logger.i('🔔 Triggering ${unsentTasks.length} notifications');

      // STEP 5: Save all notifications to Firestore first, then show them
      final now = DateTime.now();

      for (var item in unsentTasks) {
        final task = item['task'] as ScheduleMonitorData;
        final type = item['type'] as String;
        
        final body = type == 'overdue'
            ? 'This task is overdue and needs attention!'
            : 'Starts in ${task.daysUntilStart} day(s)';

        // Save to Firestore
        final savedId = await _notificationService.saveNotification(
          projectId: widget.projectId,
          taskId: task.scheduleTaskId,
          taskName: task.taskName,
          startDate: task.startDate,
          message: body,
          isTriggered: true,
          triggerSource: 'foreground_app',
          triggeredAt: now,
          notificationId: '${widget.projectId}_${task.scheduleTaskId}'.hashCode,
          expiresAt: task.startDate,
          type: type,
        );

        if (savedId != null) {
          item['firestoreNotificationId'] = savedId;
          widget.logger.i('✅ Notification saved to Firestore: $savedId');
        }
      }

      // STEP 6: Show individual notifications using EnhancedNotificationService
      for (var item in unsentTasks) {
        if (item.containsKey('firestoreNotificationId')) {
          final task = item['task'] as ScheduleMonitorData;
          final type = item['type'] as String;
          
          await _enhancedNotificationService.showTaskNotification(
            projectId: widget.projectId,
            task: task,
            type: type,
            firestoreNotificationId: item['firestoreNotificationId'],
          );
          
          // Add small delay between notifications for floating effect
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      // STEP 7: Show grouped summary if multiple notifications
      if (unsentTasks.length > 1) {
        widget.logger.d('📦 Creating group summary notification');
        
        await _enhancedNotificationService.showGroupedNotification(
          projectId: widget.projectId,
          taskGroups: unsentTasks,
          totalCount: unsentTasks.length,
        );
      }

      widget.logger.i('🎉 Notification check complete - sent ${unsentTasks.length} notifications');

    } catch (e, stackTrace) {
      widget.logger.e('❌ Error during notification check', error: e, stackTrace: stackTrace);
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingNotifications = false;
        });
      }
    }
  }

  Future<void> _updateTaskStatus(ScheduleMonitorData task, String action) async {
    try {
      // REMOVED: final now = DateTime.now(); (was unused)
      final firestore = FirebaseFirestore.instance;
      final updateTime = DateTime.now(); // Use different name to avoid confusion
      
      // Determine new taskStatus and actual dates
      String? newTaskStatus;
      DateTime? newActualStart;
      DateTime? newActualEnd;
      
      if (action == 'started') {
        newTaskStatus = 'STARTED';
        newActualStart = task.actualStartDate ?? updateTime;
      } else if (action == 'completed') {
        newTaskStatus = 'COMPLETED';
        newActualStart = task.actualStartDate ?? updateTime;
        newActualEnd = task.actualEndDate ?? updateTime;
      }
      
      // Update Schedule collection (source of truth for taskStatus)
      final scheduleUpdateData = {
        'taskStatus': ?newTaskStatus,
        if (newActualStart != null) 'actualStartDate': Timestamp.fromDate(newActualStart),
        if (newActualEnd != null) 'actualEndDate': Timestamp.fromDate(newActualEnd),
        'updatedAt': Timestamp.now(),
      };
      
      await firestore
          .collection('Schedule')
          .doc(task.scheduleTaskId)
          .update(scheduleUpdateData);
      
      widget.logger.i('✅ Updated Schedule collection for task: ${task.taskName}');
      
      // Compute new status for ScheduleMonitor
      final newStatus = ScheduleMonitorData.computeStatus(
        startDate: task.startDate,
        endDate: task.endDate,
        actualStartDate: newActualStart,
        actualEndDate: newActualEnd,
        taskStatus: newTaskStatus,
      );
      
      UpcomingCategory? newUpcomingCategory;
      if (newStatus == MonitorStatus.upcoming) {
        newUpcomingCategory = ScheduleMonitorData.computeUpcomingCategory(task.startDate);
      }
      
      // Update ScheduleMonitor collection
      final monitorUpdateData = {
        'taskStatus': newTaskStatus,
        'actualStartDate': newActualStart != null ? Timestamp.fromDate(newActualStart) : null,
        'actualEndDate': newActualEnd != null ? Timestamp.fromDate(newActualEnd) : null,
        'status': newStatus.toString().split('.').last.toUpperCase(),
        'upcomingCategory': newUpcomingCategory?.toString().split('.').last.toUpperCase(),
        'updatedAt': Timestamp.fromDate(updateTime),
        'lastStatusUpdate': Timestamp.fromDate(updateTime),
      };
      
      await firestore
          .collection('ScheduleMonitor')
          .doc(task.id)
          .update(monitorUpdateData);
      
      widget.logger.i('✅ Updated ScheduleMonitor collection for task: ${task.taskName}');
      
      if (!mounted) return;
      
      ElegantNotification.success(
        title: const Text('Task Updated'),
        description: Text('${task.taskName} marked as $action'),
      ).show(context);
      
    } catch (e, stackTrace) {
      widget.logger.e('❌ Error updating task status', error: e, stackTrace: stackTrace);
      if (!mounted) return;
      ElegantNotification.error(
        title: const Text('Error'),
        description: const Text('Failed to update task status'),
      ).show(context);
    }
  }


  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final Color overdueColor = Colors.red.shade700;
    final Color ongoingColor = Colors.blue.shade600;
    final Color startingSoonColor = Colors.orange.shade700;
    final Color upcomingColor = Colors.grey.shade700;
    final Color completedColor = Colors.green.shade600;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ScheduleMonitor')
          .where('projectId', isEqualTo: widget.projectId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          widget.logger.e('❌ ScheduleMonitor: Error in stream', error: snapshot.error);
          return Center(
            child: Text(
              'Error loading data',
              style: GoogleFonts.poppins(color: Colors.red),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        List<ScheduleMonitorData> allTasks = [];
        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final task = ScheduleMonitorData.fromFirestore(doc.id, data);
          allTasks.add(task);
        }

        // Categorize tasks by status
        final overdueTasks = allTasks.where((t) => t.isOverdue).toList();
        final ongoingTasks = allTasks.where((t) => t.isOngoing).toList();
        final startingSoonTasks = allTasks.where((t) => t.isUpcoming && t.isStartingSoon).toList();
        final otherUpcomingTasks = allTasks.where((t) => t.isUpcoming && !t.isStartingSoon).toList();
        final completedTasks = allTasks.where((t) => t.isCompleted).toList();

        // Apply search filter
        final filteredOverdue = _filterMonitorTasks(overdueTasks);
        final filteredOngoing = _filterMonitorTasks(ongoingTasks);
        final filteredStartingSoon = _filterMonitorTasks(startingSoonTasks);
        final filteredOtherUpcoming = _filterMonitorTasks(otherUpcomingTasks);
        final filteredCompleted = _filterMonitorTasks(completedTasks);
        final upcomingCount = filteredStartingSoon.length + filteredOtherUpcoming.length;

        _animationController.forward();

        if (allTasks.isEmpty) return _buildEmptyState();

        return DefaultTabController(
          length: 4,
          child: RefreshIndicator(
            onRefresh: () async {
              await _syncScheduleToMonitor();
              _scheduleNotificationCheck();
            },
            child: Column(
              children: [
                // Search bar — notifications live in BaseLayout's single,
                // unified appbar bell now (see notifications_screen.dart),
                // not a second icon duplicated per section.
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Search Tasks',
                      suffixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                ),
                // Tabs
                TabBar(
                  tabs: [
                    Tab(text: 'Overdue (${filteredOverdue.length})'),
                    Tab(text: 'Ongoing (${filteredOngoing.length})'),
                    Tab(text: 'Upcoming ($upcomingCount)'),
                    Tab(text: 'Completed (${filteredCompleted.length})'),
                  ],
                ),
                // Tab views
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildMonitorCategoryView(filteredOverdue, overdueColor, 'Overdue'),
                      _buildMonitorCategoryView(filteredOngoing, ongoingColor, 'Ongoing'),
                      _buildMonitorUpcomingView(filteredStartingSoon, filteredOtherUpcoming, startingSoonColor, upcomingColor),
                      _buildMonitorCategoryView(filteredCompleted, completedColor, 'Completed'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<ScheduleMonitorData> _filterMonitorTasks(List<ScheduleMonitorData> tasks) {
    if (_searchQuery.isEmpty) return tasks;
    return tasks.where((task) => task.taskName.toLowerCase().contains(_searchQuery)).toList();
  }

  Widget _buildMonitorCategoryView(List<ScheduleMonitorData> filteredTasks, Color color, String title) {
    if (filteredTasks.isEmpty) {
      return _buildNoTasksWidget(title);
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(title, color, filteredTasks.length),
              ...filteredTasks.map((task) => _buildMonitorTaskItem(task, color)),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMonitorUpcomingView(List<ScheduleMonitorData> filteredStartingSoon, List<ScheduleMonitorData> filteredOtherUpcoming, Color startingColor, Color upcomingColor) {
    if (filteredStartingSoon.isEmpty && filteredOtherUpcoming.isEmpty) {
      return _buildNoTasksWidget('Upcoming');
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (filteredStartingSoon.isNotEmpty) ...[
                _buildSectionHeader('Starting Soon (≤3 days)', startingColor, filteredStartingSoon.length),
                ...filteredStartingSoon.map((task) => _buildMonitorTaskItem(task, startingColor)),
              ],
              if (filteredOtherUpcoming.isNotEmpty) ...[
                _buildSectionHeader('Other Upcoming', upcomingColor, filteredOtherUpcoming.length),
                ...filteredOtherUpcoming.map((task) => _buildMonitorTaskItem(task, upcomingColor)),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMonitorTaskItem(ScheduleMonitorData task, Color accentColor) {
    final DateTime now = DateTime.now();
    final normalizedNow = _normalizeToMidnight(now);
    final normalizedStartDate = _normalizeToMidnight(task.startDate);
    final normalizedEndDate = _normalizeToMidnight(task.endDate);
    
    // Use normalized dates for accurate day calculations
    final int daysUntilStart = _calculateDaysBetween(normalizedNow, normalizedStartDate);
    final int daysUntilEnd = _calculateDaysBetween(normalizedNow, normalizedEndDate);
    
    String urgencyText = '';
    IconData urgencyIcon = Icons.info_outline;
    
    // Set distinguished colors based on status
    Color itemColor = accentColor;
    if (task.isOverdue) {
      itemColor = Colors.red;
      final overdueDays = _calculateDaysBetween(normalizedStartDate, normalizedNow);
      urgencyText = overdueDays == 0 ? 'Overdue today!' : 'Overdue by $overdueDays day${overdueDays == 1 ? '' : 's'}!';
      urgencyIcon = Icons.warning_amber_outlined;
    } else if (task.isStartingSoon) {
      itemColor = Colors.orange;
      urgencyText = daysUntilStart == 0 
          ? 'Starting today!' 
          : 'Starts in $daysUntilStart day${daysUntilStart == 1 ? '' : 's'}';
      urgencyIcon = Icons.timer_outlined;
    } else if (task.isOngoing && daysUntilEnd <= 3 && daysUntilEnd >= 0) {
      urgencyText = daysUntilEnd == 0
          ? 'Due today!'
          : 'Due in $daysUntilEnd day${daysUntilEnd == 1 ? '' : 's'}';
      urgencyIcon = Icons.warning_amber_outlined;
    } else if (task.isUpcoming && daysUntilStart > 0) {
      urgencyText = 'Starts in $daysUntilStart day${daysUntilStart == 1 ? '' : 's'}';
      urgencyIcon = Icons.schedule_outlined;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: itemColor.withValues(alpha: 0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: itemColor.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      itemColor,
                      itemColor.withValues(alpha: 0.7),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: itemColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              task.taskName,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ),
                          Material(
                            color: Colors.transparent,
                            child: PopupMenuButton<String>(
                              icon: Icon(
                                Icons.more_vert,
                                color: Colors.grey.shade600,
                                size: 20,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              onSelected: (value) {
                                _updateTaskStatus(task, value);
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'started',
                                  child: Row(
                                    children: [
                                      Icon(Icons.play_circle_outline, 
                                          size: 20, 
                                          color: Colors.blue.shade600),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Mark Started',
                                        style: GoogleFonts.poppins(fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'completed',
                                  child: Row(
                                    children: [
                                      Icon(Icons.check_circle_outline, 
                                          size: 20, 
                                          color: Colors.green.shade600),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Mark Completed',
                                        style: GoogleFonts.poppins(fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, 
                              size: 14, 
                              color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Text(
                            task.formattedDateRange,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      
                      Row(
                        children: [
                          Icon(Icons.timelapse_outlined, 
                              size: 14, 
                              color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Text(
                            'Duration: ${task.duration} day${task.duration == 1 ? '' : 's'}',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      
                      // Display actual dates if available
                      if (task.actualStartDate != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.play_arrow_outlined, 
                                size: 14, 
                                color: Colors.blue.shade600),
                            const SizedBox(width: 6),
                            Text(
                              'Started: ${DateFormat('MMM dd, yyyy').format(task.actualStartDate!)}',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: Colors.blue.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (task.actualEndDate != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.check_circle_outlined, 
                                size: 14, 
                                color: Colors.green.shade600),
                            const SizedBox(width: 6),
                            Text(
                              'Completed: ${DateFormat('MMM dd, yyyy').format(task.actualEndDate!)}',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: Colors.green.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                      
                      // Display task status badge
                      if (task.taskStatus != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: task.taskStatus == 'COMPLETED' 
                                ? Colors.green.shade50 
                                : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: task.taskStatus == 'COMPLETED' 
                                  ? Colors.green.shade300 
                                  : Colors.blue.shade300,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                task.taskStatus == 'COMPLETED' 
                                    ? Icons.check_circle 
                                    : Icons.play_circle,
                                size: 12,
                                color: task.taskStatus == 'COMPLETED' 
                                    ? Colors.green.shade700 
                                    : Colors.blue.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                task.taskStatus == 'COMPLETED' ? 'Completed' : 'Started',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: task.taskStatus == 'COMPLETED' 
                                      ? Colors.green.shade700 
                                      : Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      
                      if (urgencyText.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: itemColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: itemColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                urgencyIcon,
                                size: 14,
                                color: itemColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                urgencyText,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: itemColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── FIXED: Dynamic sizing prevents RenderFlex overflow on small screens ───
  Widget _buildNoTasksWidget(String title) {
    final bool isSearch = _searchQuery.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableHeight = constraints.maxHeight;
        final double availableWidth = constraints.maxWidth;

        // Clamp icon and font sizes to a safe range based on available space
        final double iconSize = (availableHeight * 0.12).clamp(28.0, 72.0);
        final double fontSize = (availableWidth * 0.04).clamp(11.0, 18.0);
        final double verticalSpacing = (availableHeight * 0.025).clamp(6.0, 20.0);
        final double horizontalPadding = (availableWidth * 0.08).clamp(12.0, 40.0);

        return Center(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalSpacing,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSearch ? Icons.search_off : Icons.timeline,
                  size: iconSize,
                  color: Colors.grey.shade400,
                ),
                SizedBox(height: verticalSpacing),
                Text(
                  isSearch ? 'No tasks match your search' : 'No $title tasks',
                  style: GoogleFonts.poppins(
                    fontSize: fontSize,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, Color color, int count) {
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: color,
            width: 4,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timeline, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 24),
            Text(
              'No Schedule Data Available',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Add tasks in the Gantt Chart to see schedule monitoring',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

}