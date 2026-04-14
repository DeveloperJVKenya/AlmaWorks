import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

// ══════════════════════════════════════════════════════════════════
// INTERNAL DATA MODEL
// ══════════════════════════════════════════════════════════════════

class _TpmTask {
  final String taskId;
  final String taskName;
  final String projectId;
  final String? projectName;

  /// true  → task has a "Work Done – Completed" (X) mark → displayed as COMPLETED
  /// false → task has only "Work Done – Ongoing" (D) marks → displayed as ONGOING
  final bool isCompleted;

  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? completedDate;

  /// 0.0–1.0  (1.0 when isCompleted == true)
  final double progress;

  /// Number of daily "done" marks (D codes)
  final int checkedDays;

  /// Working days expected between startDate and endDate
  final int expectedDays;

  const _TpmTask({
    required this.taskId,
    required this.taskName,
    required this.projectId,
    this.projectName,
    required this.isCompleted,
    this.startDate,
    this.endDate,
    this.completedDate,
    required this.progress,
    required this.checkedDays,
    required this.expectedDays,
  });
}

// ══════════════════════════════════════════════════════════════════
// HELPERS
// ══════════════════════════════════════════════════════════════════

int _countWorkDays(DateTime start, DateTime end) {
  int count = 0;
  DateTime cur = DateTime(start.year, start.month, start.day);
  final endN = DateTime(end.year, end.month, end.day);
  while (!cur.isAfter(endN)) {
    if (cur.weekday != DateTime.sunday) count++;
    cur = cur.add(const Duration(days: 1));
  }
  return count;
}

/// Parse a single TaskProgressMonitor document into a list of [_TpmTask]s.
/// Only returns tasks that have at least one D or X daily-status mark.
List<_TpmTask> _parseDocument(DocumentSnapshot snap) {
  if (!snap.exists) return [];
  final data = snap.data() as Map<String, dynamic>? ?? {};
  final rawRows = data['rows'] as List<dynamic>? ?? [];
  final rawStatus =
      Map<String, dynamic>.from(data['dailyStatuses'] as Map? ?? {});
  final projectName = data['projectName'] as String?;
  final projectId = snap.id;

  final tasks = <_TpmTask>[];

  for (final entry in rawRows) {
    final row = Map<String, dynamic>.from(entry as Map);
    if ((row['type'] as String?) != 'task') continue;

    final taskId = row['id'] as String? ?? '';
    final taskName = (row['taskName'] as String? ?? '').trim();
    if (taskId.isEmpty || taskName.isEmpty) continue;

    final startDate = (row['startDate'] as Timestamp?)?.toDate();
    final endDate = (row['endDate'] as Timestamp?)?.toDate();

    bool hasCompleted = false;
    bool hasOngoing = false;
    DateTime? completedDate;
    int checkedDays = 0;

    final prefix = '${taskId}_';
    for (final kv in rawStatus.entries) {
      if (!kv.key.startsWith(prefix)) continue;
      final code = kv.value as String?;

      if (code == 'X') {
        hasCompleted = true;
        // Parse date from key suffix  (format: taskId_yyyyMMdd)
        final sep = kv.key.lastIndexOf('_');
        if (sep >= 0 && kv.key.length - sep - 1 == 8) {
          final ds = kv.key.substring(sep + 1);
          try {
            completedDate = DateTime(
              int.parse(ds.substring(0, 4)),
              int.parse(ds.substring(4, 6)),
              int.parse(ds.substring(6, 8)),
            );
          } catch (_) {}
        }
      } else if (code == 'D' ||
          code == 'S' ||
          code == 'O' ||
          code == 'C') {
        // D = done-ongoing; legacy S/O/C map to done as well
        hasOngoing = true;
        checkedDays++;
      }
    }

    // Only include tasks that have been worked on at least once
    if (!hasCompleted && !hasOngoing) continue;

    final expectedDays = (startDate != null && endDate != null)
        ? _countWorkDays(startDate, endDate)
        : 0;

    double progress;
    if (hasCompleted) {
      progress = 1.0;
    } else if (expectedDays == 0) {
      progress = 0.0;
    } else {
      progress = (checkedDays / expectedDays).clamp(0.0, 1.0);
    }

    tasks.add(_TpmTask(
      taskId: taskId,
      taskName: taskName,
      projectId: projectId,
      projectName: projectName,
      isCompleted: hasCompleted,
      startDate: startDate,
      endDate: endDate,
      completedDate: completedDate,
      progress: progress,
      checkedDays: checkedDays,
      expectedDays: expectedDays,
    ));
  }

  return tasks;
}

// ══════════════════════════════════════════════════════════════════
// WIDGET
// ══════════════════════════════════════════════════════════════════

class TaskProgressWidget extends StatefulWidget {
  /// Single-project mode (ProjectSummaryScreen).
  final String? projectId;

  /// Dashboard mode: pass the project IDs the current user may see.
  /// Pass an empty list to see ALL projects (admin).
  final List<String> projectIds;

  /// Set to true in the dashboard; false when viewing a single project.
  final bool showAllProjects;

  /// Maximum items shown before the "View All" link appears.
  /// Defaults to 4 — callers may override to match their container height.
  final int maxInitialDisplay;

  final Logger? logger;

  const TaskProgressWidget({
    super.key,
    this.projectId,
    this.projectIds = const [],
    this.showAllProjects = false,
    this.maxInitialDisplay = 4,
    this.logger,
  });

  @override
  State<TaskProgressWidget> createState() => _TaskProgressWidgetState();
}

class _TaskProgressWidgetState extends State<TaskProgressWidget> {
  // ── Design constants ─────────────────────────────────────────────
  static const _navy = Color(0xFF0A2E5A);
  static const _ongoingColor = Color(0xFF1565C0); // blue
  static const _completedColor = Color(0xFF2E7D32); // green
  static const _ongoingBg = Color(0xFFE3F0FF);
  static const _completedBg = Color(0xFFE8F5E9);

  bool _isExpanded = false;

  // ── Firestore stream ─────────────────────────────────────────────
  Stream<List<_TpmTask>> _getStream() {
    final fs = FirebaseFirestore.instance;

    // ── 1. Single-project mode ──────────────────────────────────────
    if (widget.projectId != null && widget.projectId!.isNotEmpty) {
      return fs
          .collection('TaskProgressMonitor')
          .doc(widget.projectId)
          .snapshots()
          .map((snap) => _parseDocument(snap));
    }

    // ── 2. Dashboard: no project IDs restriction → all projects (admin)
    if (widget.showAllProjects && widget.projectIds.isEmpty) {
      return fs
          .collection('TaskProgressMonitor')
          .snapshots()
          .map((qs) => qs.docs.expand(_parseDocument).toList());
    }

    // ── 3. Dashboard: restricted to granted project IDs (client) ────
    if (widget.showAllProjects && widget.projectIds.isNotEmpty) {
      if (widget.projectIds.length <= 10) {
        return fs
            .collection('TaskProgressMonitor')
            .where(FieldPath.documentId, whereIn: widget.projectIds)
            .snapshots()
            .map((qs) => qs.docs.expand(_parseDocument).toList());
      } else {
        // >10 IDs: fetch all and filter in memory
        return fs
            .collection('TaskProgressMonitor')
            .snapshots()
            .map((qs) => qs.docs
                .where((d) => widget.projectIds.contains(d.id))
                .expand(_parseDocument)
                .toList());
      }
    }

    return Stream.value([]);
  }

  // ── UI ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return StreamBuilder<List<_TpmTask>>(
      stream: _getStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildShell(isMobile, child: _buildLoading());
        }
        if (snapshot.hasError) {
          widget.logger?.e(
              '❌ TaskProgressWidget: stream error ${snapshot.error}');
          return _buildShell(isMobile, child: _buildError(isMobile));
        }

        final allTasks = snapshot.data ?? [];

        // ── Sort: ongoing first (soonest end-date), completed last ──
        final ongoing = allTasks
            .where((t) => !t.isCompleted)
            .toList()
          ..sort((a, b) {
            if (a.endDate == null && b.endDate == null) return 0;
            if (a.endDate == null) return 1;
            if (b.endDate == null) return -1;
            return a.endDate!.compareTo(b.endDate!);
          });

        final completed = allTasks
            .where((t) => t.isCompleted)
            .toList()
          ..sort((a, b) {
            if (a.completedDate == null && b.completedDate == null) return 0;
            if (a.completedDate == null) return 1;
            if (b.completedDate == null) return -1;
            // Most recently completed first
            return b.completedDate!.compareTo(a.completedDate!);
          });

        if (ongoing.isEmpty && completed.isEmpty) {
          return _buildShell(isMobile, child: _buildEmpty(isMobile));
        }

        return _buildShell(
          isMobile,
          child: _buildList(
            isMobile: isMobile,
            ongoing: ongoing,
            completed: completed,
          ),
        );
      },
    );
  }

  // ── Outer card shell ─────────────────────────────────────────────
  Widget _buildShell(bool isMobile, {required Widget child}) {
    return Card(
      elevation: 2,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isMobile),
            const SizedBox(height: 12),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────
  Widget _buildHeader(bool isMobile) {
    return Row(
      children: [
        Icon(Icons.task_alt_rounded, color: _navy, size: isMobile ? 20 : 24),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Task Progress',
            style: TextStyle(
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Legend chips
        _legendChip('ONGOING', _ongoingColor, _ongoingBg, isMobile),
        const SizedBox(width: 6),
        _legendChip('COMPLETED', _completedColor, _completedBg, isMobile),
      ],
    );
  }

  Widget _legendChip(
      String label, Color color, Color bg, bool isMobile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: isMobile ? 7 : 8,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  // ── Main list ────────────────────────────────────────────────────
  Widget _buildList({
    required bool isMobile,
    required List<_TpmTask> ongoing,
    required List<_TpmTask> completed,
  }) {
    final total = ongoing.length + completed.length;
    final limit = widget.maxInitialDisplay;
    final hasMore = total > limit;

    // Decide how many from each group to show in collapsed mode.
    // Ongoing tasks fill slots first (they are the priority/active ones),
    // then completed tasks fill remaining slots.
    List<_TpmTask> visibleOngoing;
    List<_TpmTask> visibleCompleted;

    if (_isExpanded) {
      visibleOngoing = ongoing;
      visibleCompleted = completed;
    } else {
      final ongoingSlots = ongoing.length.clamp(0, limit);
      final completedSlots = completed.length.clamp(0, limit - ongoingSlots);
      visibleOngoing = ongoing.take(ongoingSlots).toList();
      visibleCompleted = completed.take(completedSlots).toList();
    }

    final items = <Widget>[];

    if (visibleOngoing.isNotEmpty) {
      items.add(_sectionHeader(
        'Ongoing',
        visibleOngoing.length,
        ongoing.length,
        _ongoingColor,
        isMobile,
      ));
      for (final t in visibleOngoing) {
        items.add(_buildTaskItem(t, isMobile));
      }
    }

    if (visibleCompleted.isNotEmpty) {
      items.add(_sectionHeader(
        'Completed',
        visibleCompleted.length,
        completed.length,
        _completedColor,
        isMobile,
      ));
      for (final t in visibleCompleted) {
        items.add(_buildTaskItem(t, isMobile));
      }
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: items,
          ),
        ),
        if (hasMore || _isExpanded)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _isExpanded = !_isExpanded),
                icon: Icon(
                  _isExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: isMobile ? 18 : 20,
                ),
                label: Text(
                  _isExpanded
                      ? 'Show Less'
                      : 'View All  ($total tasks)',
                  style: TextStyle(
                    fontSize: isMobile ? 12 : 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Section header ───────────────────────────────────────────────
  Widget _sectionHeader(String title, int shown, int total, Color color,
      bool isMobile) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: isMobile ? 12 : 13,
              fontWeight: FontWeight.w700,
              color: color.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              total.toString(),
              style: TextStyle(
                fontSize: isMobile ? 10 : 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Single task item ─────────────────────────────────────────────
  Widget _buildTaskItem(_TpmTask task, bool isMobile) {
    final isCompleted = task.isCompleted;
    final color = isCompleted ? _completedColor : _ongoingColor;
    final bg = isCompleted ? _completedBg : _ongoingBg;

    final statusLabel = isCompleted ? 'COMPLETED' : 'ONGOING';
    final statusIcon = isCompleted
        ? Icons.check_circle_rounded
        : Icons.play_circle_filled_rounded;

    final subtitleText = isCompleted
        ? task.completedDate != null
            ? 'Completed ${DateFormat('d MMM yyyy').format(task.completedDate!)}'
            : 'Work Done – Completed'
        : task.endDate != null
            ? 'Due ${DateFormat('d MMM yyyy').format(task.endDate!)}'
            : 'Work Done – Ongoing';

    final progressLabel = isCompleted
        ? '100%'
        : '${(task.progress * 100).toStringAsFixed(0)}%  '
            '(${task.checkedDays}/${task.expectedDays} days)';

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: EdgeInsets.all(isMobile ? 9 : 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Status icon ─────────────────────────────────────────
          Container(
            width: isMobile ? 32 : 36,
            height: isMobile ? 32 : 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.30), width: 1.5),
            ),
            child: Icon(statusIcon, color: color, size: isMobile ? 16 : 18),
          ),
          const SizedBox(width: 10),

          // ── Content ──────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Task name
                Text(
                  task.taskName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: isMobile ? 12 : 14,
                    color: Colors.grey[850],
                  ),
                ),
                const SizedBox(height: 3),

                // Subtitle (date / description)
                Row(
                  children: [
                    Icon(Icons.access_time_rounded,
                        size: isMobile ? 11 : 12, color: color),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        subtitleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isMobile ? 10 : 11,
                          color: color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),

                // Project name (dashboard mode only)
                if (widget.showAllProjects && task.projectName != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.folder_outlined,
                          size: isMobile ? 10 : 11,
                          color: Colors.grey[600]),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          task.projectName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isMobile ? 9 : 10,
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 5),

                // Mini progress bar + percentage
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: task.progress,
                          minHeight: 4,
                          backgroundColor: color.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      progressLabel,
                      style: TextStyle(
                        fontSize: isMobile ? 9 : 10,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // ── Status badge ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: color,
                fontSize: isMobile ? 7 : 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── States ───────────────────────────────────────────────────────
  Widget _buildLoading() => const Center(child: CircularProgressIndicator());

  Widget _buildError(bool isMobile) => Center(
        child: Text(
          'Error loading task progress',
          style: TextStyle(
              color: Colors.red[600], fontSize: isMobile ? 12 : 14),
        ),
      );

  Widget _buildEmpty(bool isMobile) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined,
                size: isMobile ? 40 : 48, color: Colors.grey[350]),
            const SizedBox(height: 8),
            Text(
              'No active tasks yet',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: isMobile ? 12 : 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Ongoing and Completed tasks \nwill appear here',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: isMobile ? 10 : 12,
                ),
              ),
            ),
          ],
        ),
      );
}