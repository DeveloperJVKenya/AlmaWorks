// ScheduleMonitor Model - Dynamic categorization collection
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:almaworks/core/l10n/l10n.dart';

// Status types for ScheduleMonitor collection (dynamically computed)
enum MonitorStatus { overdue, ongoing, upcoming, completed }

// Sub-category for Upcoming tasks
enum UpcomingCategory { startingSoon, otherUpcoming }

class ScheduleMonitorData {
  final String id; // Document ID in ScheduleMonitor collection
  final String scheduleTaskId; // Reference to original Schedule collection document
  final String projectId;
  final String projectName;
  final String taskName;

  // Date fields (copied from Schedule collection)
  final DateTime startDate;
  final DateTime endDate;
  final DateTime? actualStartDate;
  final DateTime? actualEndDate;

  // User-controlled status from Schedule collection
  final String? taskStatus; // 'STARTED' or 'COMPLETED' from Schedule.taskStatus

  // Dynamically computed status (stored for querying efficiency)
  MonitorStatus status;

  // Sub-category for upcoming tasks
  UpcomingCategory? upcomingCategory;

  // Duration (computed)
  final int duration;

  // Resource info (optional display fields)
  final String? resourceId;
  final String? resourceQuantity;

  // Metadata
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastStatusUpdate;

  ScheduleMonitorData({
    required this.id,
    required this.scheduleTaskId,
    required this.projectId,
    required this.projectName,
    required this.taskName,
    required this.startDate,
    required this.endDate,
    this.actualStartDate,
    this.actualEndDate,
    this.taskStatus,
    required this.status,
    this.upcomingCategory,
    required this.duration,
    this.resourceId,
    this.resourceQuantity,
    required this.createdAt,
    required this.updatedAt,
    required this.lastStatusUpdate,
  });

  // Compute status dynamically based on dates and taskStatus
  static MonitorStatus computeStatus({
    required DateTime startDate,
    required DateTime endDate,
    DateTime? actualStartDate,
    DateTime? actualEndDate,
    String? taskStatus,
  }) {
    final DateTime now = DateTime.now();

    // Priority 1: Check if completed (user marked as completed OR has actualEndDate)
    if (taskStatus == 'COMPLETED' || actualEndDate != null) {
      return MonitorStatus.completed;
    }

    // Priority 2: Check if started (user marked as started OR has actualStartDate)
    // This is "Ongoing" status
    if (taskStatus == 'STARTED' || actualStartDate != null) {
      return MonitorStatus.ongoing;
    }

    // Priority 3: Check if overdue (start date passed but not started)
    if (startDate.isBefore(now)) {
      return MonitorStatus.overdue;
    }

    // Priority 4: Default to upcoming (future start date, not started)
    return MonitorStatus.upcoming;
  }

  // Compute upcoming sub-category
  static UpcomingCategory? computeUpcomingCategory(DateTime startDate) {
    final DateTime now = DateTime.now();
    final int daysUntilStart = startDate.difference(now).inDays;

    if (daysUntilStart <= 3 && daysUntilStart > 0) {
      return UpcomingCategory.startingSoon;
    } else if (daysUntilStart > 3) {
      return UpcomingCategory.otherUpcoming;
    }

    return null;
  }

  // Factory constructor from Firestore
  factory ScheduleMonitorData.fromFirestore(
    String docId,
    Map<String, dynamic> data,
  ) {
    final startDate = (data['startDate'] as Timestamp).toDate();
    final endDate = (data['endDate'] as Timestamp).toDate();
    final actualStartDate = (data['actualStartDate'] as Timestamp?)?.toDate();
    final actualEndDate = (data['actualEndDate'] as Timestamp?)?.toDate();
    final taskStatus = data['taskStatus'] as String?;

    // Compute status dynamically
    final status = computeStatus(
      startDate: startDate,
      endDate: endDate,
      actualStartDate: actualStartDate,
      actualEndDate: actualEndDate,
      taskStatus: taskStatus,
    );

    // Compute upcoming category if status is upcoming
    UpcomingCategory? upcomingCategory;
    if (status == MonitorStatus.upcoming) {
      upcomingCategory = computeUpcomingCategory(startDate);
    }

    return ScheduleMonitorData(
      id: docId,
      scheduleTaskId: data['scheduleTaskId'] as String,
      projectId: data['projectId'] as String,
      projectName: data['projectName'] as String,
      taskName: data['taskName'] as String,
      startDate: startDate,
      endDate: endDate,
      actualStartDate: actualStartDate,
      actualEndDate: actualEndDate,
      taskStatus: taskStatus,
      status: status,
      upcomingCategory: upcomingCategory,
      duration: data['duration'] as int,
      resourceId: data['resourceId'] as String?,
      resourceQuantity: data['resourceQuantity'] as String?,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      lastStatusUpdate: (data['lastStatusUpdate'] as Timestamp).toDate(),
    );
  }

  // Factory constructor from Schedule collection data
  factory ScheduleMonitorData.fromScheduleData({
    required String scheduleTaskId,
    required Map<String, dynamic> scheduleData,
  }) {
    final startDate = (scheduleData['startDate'] as Timestamp).toDate();
    final endDate = (scheduleData['endDate'] as Timestamp).toDate();
    final actualStartDate = (scheduleData['actualStartDate'] as Timestamp?)?.toDate();
    final actualEndDate = (scheduleData['actualEndDate'] as Timestamp?)?.toDate();
    final taskStatus = scheduleData['taskStatus'] as String?;
    final now = DateTime.now();

    // Compute status
    final status = computeStatus(
      startDate: startDate,
      endDate: endDate,
      actualStartDate: actualStartDate,
      actualEndDate: actualEndDate,
      taskStatus: taskStatus,
    );

    // Compute upcoming category
    UpcomingCategory? upcomingCategory;
    if (status == MonitorStatus.upcoming) {
      upcomingCategory = computeUpcomingCategory(startDate);
    }

    // Compute duration
    final duration = endDate.difference(startDate).inDays + 1;

    return ScheduleMonitorData(
      id: '', // Will be set by Firestore
      scheduleTaskId: scheduleTaskId,
      projectId: scheduleData['projectId'] as String,
      projectName: scheduleData['projectName'] as String,
      taskName: scheduleData['taskName'] as String,
      startDate: startDate,
      endDate: endDate,
      actualStartDate: actualStartDate,
      actualEndDate: actualEndDate,
      taskStatus: taskStatus,
      status: status,
      upcomingCategory: upcomingCategory,
      duration: duration,
      resourceId: scheduleData['resourceId'] as String?,
      resourceQuantity: scheduleData['resourceQuantity'] as String?,
      createdAt: now,
      updatedAt: now,
      lastStatusUpdate: now,
    );
  }

  // Convert to Firestore map
  Map<String, dynamic> toFirestore() {
    return {
      'scheduleTaskId': scheduleTaskId,
      'projectId': projectId,
      'projectName': projectName,
      'taskName': taskName,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'actualStartDate': actualStartDate != null ? Timestamp.fromDate(actualStartDate!) : null,
      'actualEndDate': actualEndDate != null ? Timestamp.fromDate(actualEndDate!) : null,
      'taskStatus': taskStatus,
      'status': status.toString().split('.').last.toUpperCase(),
      'upcomingCategory': upcomingCategory?.toString().split('.').last.toUpperCase(),
      'duration': duration,
      'resourceId': resourceId,
      'resourceQuantity': resourceQuantity,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'lastStatusUpdate': Timestamp.fromDate(lastStatusUpdate),
    };
  }

  // Copy with method for updates
  ScheduleMonitorData copyWith({
    String? id,
    String? scheduleTaskId,
    String? projectId,
    String? projectName,
    String? taskName,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? actualStartDate,
    DateTime? actualEndDate,
    String? taskStatus,
    MonitorStatus? status,
    UpcomingCategory? upcomingCategory,
    int? duration,
    String? resourceId,
    String? resourceQuantity,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastStatusUpdate,
  }) {
    return ScheduleMonitorData(
      id: id ?? this.id,
      scheduleTaskId: scheduleTaskId ?? this.scheduleTaskId,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      taskName: taskName ?? this.taskName,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      actualStartDate: actualStartDate ?? this.actualStartDate,
      actualEndDate: actualEndDate ?? this.actualEndDate,
      taskStatus: taskStatus ?? this.taskStatus,
      status: status ?? this.status,
      upcomingCategory: upcomingCategory ?? this.upcomingCategory,
      duration: duration ?? this.duration,
      resourceId: resourceId ?? this.resourceId,
      resourceQuantity: resourceQuantity ?? this.resourceQuantity,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastStatusUpdate: lastStatusUpdate ?? this.lastStatusUpdate,
    );
  }

  // Helper getters
  String get statusDisplayText {
    switch (status) {
      case MonitorStatus.overdue:
        return l10nNow.monitorOverdue;
      case MonitorStatus.ongoing:
        return l10nNow.monitorOngoing;
      case MonitorStatus.upcoming:
        return l10nNow.monitorUpcoming;
      case MonitorStatus.completed:
        return l10nNow.taskCompleted;
    }
  }

  String get formattedDateRange {
    final formatter = DateFormat.yMMMd();
    return '${formatter.format(startDate)} - ${formatter.format(endDate)}';
  }

  String get actualDatesDisplayText {
    if (actualStartDate == null && actualEndDate == null) {
      return '';
    } else if (actualStartDate != null && actualEndDate != null) {
      return '${DateFormat('MM/dd/yy').format(actualStartDate!)} - ${DateFormat('MM/dd/yy').format(actualEndDate!)}';
    } else if (actualStartDate != null) {
      return '${DateFormat('MM/dd/yy').format(actualStartDate!)} - ...';
    } else {
      return '... - ${DateFormat('MM/dd/yy').format(actualEndDate!)}';
    }
  }

  bool get isOverdue => status == MonitorStatus.overdue;
  bool get isOngoing => status == MonitorStatus.ongoing;
  bool get isUpcoming => status == MonitorStatus.upcoming;
  bool get isCompleted => status == MonitorStatus.completed;
  bool get isStartingSoon => upcomingCategory == UpcomingCategory.startingSoon;

  int get daysUntilStart {
    final now = DateTime.now();
    return startDate.difference(now).inDays;
  }

  int get daysUntilEnd {
    final now = DateTime.now();
    return endDate.difference(now).inDays;
  }

  @override
  String toString() {
    return 'ScheduleMonitorData(id: $id, scheduleTaskId: $scheduleTaskId, taskName: $taskName, status: $status, startDate: $startDate, endDate: $endDate)';
  }
}