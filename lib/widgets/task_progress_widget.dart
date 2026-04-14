import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

// ══════════════════════════════════════════════════════════════════
// INTERNAL PARSE HELPERS
// ══════════════════════════════════════════════════════════════════

/// Mutable accumulator built while scanning dailyStatuses for one task.
class _TaskStat {
  bool hasCompleted = false;
  DateTime? completedDate;
  int checkedDays = 0;
}

/// Lightweight record used for phase-progress weighting.
class _PhaseTaskData {
  final int expectedDays;
  final double progress;
  const _PhaseTaskData({required this.expectedDays, required this.progress});
}

// ══════════════════════════════════════════════════════════════════
// INTERNAL DATA MODELS
// ══════════════════════════════════════════════════════════════════

class _TpmTask {
  final String taskId;
  final String taskName;
  final String projectId;
  final String? projectName;
  final String? parentPhaseId;

  /// Resolved phase name for display (null when task has no parent phase).
  final String? phaseName;

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
    this.parentPhaseId,
    this.phaseName,
    required this.isCompleted,
    this.startDate,
    this.endDate,
    this.completedDate,
    required this.progress,
    required this.checkedDays,
    required this.expectedDays,
  });
}

// ── Phase model ──────────────────────────────────────────────────

class _TpmPhase {
  final String phaseId;
  final String phaseName;
  final String projectId;
  final String? projectName;

  /// 0.0–1.0 weighted progress across ALL tasks in this phase.
  /// Unstarted tasks contribute 0 %, completed tasks contribute 100 %.
  final double progress;

  const _TpmPhase({
    required this.phaseId,
    required this.phaseName,
    required this.projectId,
    this.projectName,
    required this.progress,
  });
}

// ── Combined parse result ────────────────────────────────────────

class _TpmDocResult {
  final List<_TpmTask> tasks;
  final List<_TpmPhase> phases;

  const _TpmDocResult({required this.tasks, required this.phases});

  static const empty =
      _TpmDocResult(tasks: <_TpmTask>[], phases: <_TpmPhase>[]);
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

/// Parse a single TaskProgressMonitor document into tasks + phases.
///
/// Tasks   → only those with at least one D or X daily-status mark
///            (same filter as before) end up in the display list.
/// Phases  → ALL tasks inside a phase (including unstarted ones that
///            contribute 0 %) are used for the weighted-average
///            progress, matching the logic in TaskProgressMonitorScreen.
_TpmDocResult _parseDocument(DocumentSnapshot snap) {
  if (!snap.exists) return _TpmDocResult.empty;
  final data = snap.data() as Map<String, dynamic>? ?? {};
  final rawRows = data['rows'] as List<dynamic>? ?? [];
  final rawStatus =
      Map<String, dynamic>.from(data['dailyStatuses'] as Map? ?? {});
  final projectName = data['projectName'] as String?;
  final projectId = snap.id;

  // ── 1. Pre-scan dailyStatuses once → per-task stats ──────────
  // Key format: <taskId>_<yyyyMMdd>.
  // TaskIds are UUIDs (hyphens only, no underscores) → lastIndexOf('_') safe.
  final taskStats = <String, _TaskStat>{};

  for (final kv in rawStatus.entries) {
    final sep = kv.key.lastIndexOf('_');
    if (sep < 0) continue;
    final taskId = kv.key.substring(0, sep);
    final dateStr = kv.key.substring(sep + 1);
    final code = kv.value as String?;

    final stat = taskStats.putIfAbsent(taskId, () => _TaskStat());

    if (code == 'X') {
      stat.hasCompleted = true;
      if (dateStr.length == 8) {
        try {
          stat.completedDate = DateTime(
            int.parse(dateStr.substring(0, 4)),
            int.parse(dateStr.substring(4, 6)),
            int.parse(dateStr.substring(6, 8)),
          );
        } catch (_) {}
      }
    } else if (code == 'D' || code == 'S' || code == 'O' || code == 'C') {
      stat.checkedDays++;
    }
  }

  // ── 1b. Build a phase-name map: phaseId → phaseName ─────────
  final phaseNames = <String, String>{};
  for (final entry in rawRows) {
    final row = Map<String, dynamic>.from(entry as Map);
    if ((row['type'] as String?) != 'phase') continue;
    final phaseId = row['id'] as String? ?? '';
    final phaseName = (row['taskName'] as String? ?? '').trim();
    if (phaseId.isNotEmpty && phaseName.isNotEmpty) {
      phaseNames[phaseId] = phaseName;
    }
  }

  // ── 2. First pass: collect per-phase task data (all tasks) ───
  // We need ALL tasks (even unstarted) so the phase % matches the
  // TaskProgressMonitorScreen's weighted average.
  final phaseTaskData = <String, List<_PhaseTaskData>>{};

  for (final entry in rawRows) {
    final row = Map<String, dynamic>.from(entry as Map);
    if ((row['type'] as String?) != 'task') continue;

    final taskId = row['id'] as String? ?? '';
    if (taskId.isEmpty) continue;
    final parentPhaseId = row['parentPhaseId'] as String?;
    if (parentPhaseId == null) continue;

    final startDate = (row['startDate'] as Timestamp?)?.toDate();
    final endDate = (row['endDate'] as Timestamp?)?.toDate();
    if (startDate == null || endDate == null) continue;

    final expectedDays = _countWorkDays(startDate, endDate);
    if (expectedDays == 0) continue;

    final stat = taskStats[taskId];
    final double taskProgress;
    if (stat != null && stat.hasCompleted) {
      taskProgress = 1.0;
    } else if (stat != null && stat.checkedDays > 0) {
      taskProgress = (stat.checkedDays / expectedDays).clamp(0.0, 1.0);
    } else {
      taskProgress = 0.0; // not started
    }

    phaseTaskData
        .putIfAbsent(parentPhaseId, () => [])
        .add(_PhaseTaskData(
            expectedDays: expectedDays, progress: taskProgress));
  }

  // ── 3. Second pass: build display tasks + phases ─────────────
  final displayTasks = <_TpmTask>[];
  final phaseList = <_TpmPhase>[];

  for (final entry in rawRows) {
    final row = Map<String, dynamic>.from(entry as Map);
    final type = row['type'] as String?;

    // ── Phase rows ─────────────────────────────────────────────
    if (type == 'phase') {
      final phaseId = row['id'] as String? ?? '';
      final phaseName = (row['taskName'] as String? ?? '').trim();
      if (phaseId.isEmpty || phaseName.isEmpty) continue;

      final phaseTasks = phaseTaskData[phaseId] ?? <_PhaseTaskData>[];
      double phaseProgress = 0.0;
      if (phaseTasks.isNotEmpty) {
        double weightedSum = 0.0;
        int totalWeight = 0;
        for (final t in phaseTasks) {
          weightedSum += t.progress * t.expectedDays;
          totalWeight += t.expectedDays;
        }
        if (totalWeight > 0) {
          phaseProgress = (weightedSum / totalWeight).clamp(0.0, 1.0);
        }
      }

      phaseList.add(_TpmPhase(
        phaseId: phaseId,
        phaseName: phaseName,
        projectId: projectId,
        projectName: projectName,
        progress: phaseProgress,
      ));
    }

    // ── Task rows (only worked-on tasks enter the display list) ─
    else if (type == 'task') {
      final taskId = row['id'] as String? ?? '';
      final taskName = (row['taskName'] as String? ?? '').trim();
      if (taskId.isEmpty || taskName.isEmpty) continue;

      final stat = taskStats[taskId];
      if (stat == null || (!stat.hasCompleted && stat.checkedDays == 0)) {
        continue; // never touched — skip
      }

      final startDate = (row['startDate'] as Timestamp?)?.toDate();
      final endDate = (row['endDate'] as Timestamp?)?.toDate();
      final parentPhaseId = row['parentPhaseId'] as String?;

      final expectedDays = (startDate != null && endDate != null)
          ? _countWorkDays(startDate, endDate)
          : 0;

      final double progress;
      if (stat.hasCompleted) {
        progress = 1.0;
      } else if (expectedDays == 0) {
        progress = 0.0;
      } else {
        progress = (stat.checkedDays / expectedDays).clamp(0.0, 1.0);
      }

      displayTasks.add(_TpmTask(
        taskId: taskId,
        taskName: taskName,
        projectId: projectId,
        projectName: projectName,
        parentPhaseId: parentPhaseId,
        phaseName: parentPhaseId != null ? phaseNames[parentPhaseId] : null,
        isCompleted: stat.hasCompleted,
        startDate: startDate,
        endDate: endDate,
        completedDate: stat.completedDate,
        progress: progress,
        checkedDays: stat.checkedDays,
        expectedDays: expectedDays,
      ));
    }
  }

  return _TpmDocResult(tasks: displayTasks, phases: phaseList);
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

  /// When true a collapsible "Phase Breakdown" section is shown above the
  /// task list, displaying each phase's completion percentage (no days).
  /// Defaults to true.
  final bool showPhaseBreakdown;

  final Logger? logger;

  const TaskProgressWidget({
    super.key,
    this.projectId,
    this.projectIds = const [],
    this.showAllProjects = false,
    this.maxInitialDisplay = 4,
    this.showPhaseBreakdown = true,
    this.logger,
  });

  @override
  State<TaskProgressWidget> createState() => _TaskProgressWidgetState();
}

class _TaskProgressWidgetState extends State<TaskProgressWidget> {
  // ── Design constants ─────────────────────────────────────────────
  static const _navy = Color(0xFF0A2E5A);
  static const _ongoingColor = Color(0xFF1565C0);
  static const _completedColor = Color(0xFF2E7D32);
  static const _ongoingBg = Color(0xFFE3F0FF);
  static const _completedBg = Color(0xFFE8F5E9);

  /// Cycling palette — visually distinct colours for phase bars.
  static const _phaseColors = [
    Color(0xFF1565C0), // blue
    Color(0xFF00695C), // teal
    Color(0xFF6A1B9A), // purple
    Color(0xFFE65100), // deep-orange
    Color(0xFF558B2F), // green
    Color(0xFF0277BD), // light-blue
    Color(0xFF6D4C41), // brown
  ];

  bool _isExpanded = false;

  /// Phase breakdown section is expanded by default.
  bool _phaseExpanded = true;

  // ── Firestore stream ─────────────────────────────────────────────
  Stream<_TpmDocResult> _getStream() {
    final fs = FirebaseFirestore.instance;

    // ── 1. Single-project mode ──────────────────────────────────────
    if (widget.projectId != null && widget.projectId!.isNotEmpty) {
      return fs
          .collection('TaskProgressMonitor')
          .doc(widget.projectId)
          .snapshots()
          .map(_parseDocument);
    }

    // ── 2. Dashboard: no project IDs restriction → all projects (admin)
    if (widget.showAllProjects && widget.projectIds.isEmpty) {
      return fs
          .collection('TaskProgressMonitor')
          .snapshots()
          .map((qs) => _mergeResults(qs.docs.map(_parseDocument)));
    }

    // ── 3. Dashboard: restricted to granted project IDs (client) ────
    if (widget.showAllProjects && widget.projectIds.isNotEmpty) {
      if (widget.projectIds.length <= 10) {
        return fs
            .collection('TaskProgressMonitor')
            .where(FieldPath.documentId, whereIn: widget.projectIds)
            .snapshots()
            .map((qs) => _mergeResults(qs.docs.map(_parseDocument)));
      } else {
        // >10 IDs: fetch all and filter in memory
        return fs
            .collection('TaskProgressMonitor')
            .snapshots()
            .map((qs) => _mergeResults(qs.docs
                .where((d) => widget.projectIds.contains(d.id))
                .map(_parseDocument)));
      }
    }

    return Stream.value(_TpmDocResult.empty);
  }

  /// Flatten multiple per-document results into one combined result.
  static _TpmDocResult _mergeResults(Iterable<_TpmDocResult> results) {
    final tasks = <_TpmTask>[];
    final phases = <_TpmPhase>[];
    for (final r in results) {
      tasks.addAll(r.tasks);
      phases.addAll(r.phases);
    }
    return _TpmDocResult(tasks: tasks, phases: phases);
  }

  // ── UI ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return StreamBuilder<_TpmDocResult>(
      stream: _getStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildShell(isMobile,
              phases: const [], child: _buildLoading());
        }
        if (snapshot.hasError) {
          widget.logger
              ?.e('❌ TaskProgressWidget: stream error ${snapshot.error}');
          return _buildShell(isMobile,
              phases: const [], child: _buildError(isMobile));
        }

        final result = snapshot.data ?? _TpmDocResult.empty;
        final allTasks = result.tasks;
        final allPhases = widget.showPhaseBreakdown
            ? result.phases
            : const <_TpmPhase>[];

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
            return b.completedDate!.compareTo(a.completedDate!);
          });

        if (ongoing.isEmpty && completed.isEmpty) {
          return _buildShell(isMobile,
              phases: allPhases, child: _buildEmpty(isMobile));
        }

        return _buildShell(
          isMobile,
          phases: allPhases,
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
  Widget _buildShell(bool isMobile,
      {required List<_TpmPhase> phases, required Widget child}) {
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
            // Phase breakdown sits between the header and the task list.
            if (phases.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildPhaseSection(phases, isMobile),
            ],
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
        _legendChip('ONGOING', _ongoingColor, _ongoingBg, isMobile),
        const SizedBox(width: 6),
        _legendChip('COMPLETED', _completedColor, _completedBg, isMobile),
      ],
    );
  }

  Widget _legendChip(String label, Color color, Color bg, bool isMobile) {
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

  // ══════════════════════════════════════════════════════════════════
  // PHASE BREAKDOWN SECTION
  // ══════════════════════════════════════════════════════════════════

  Widget _buildPhaseSection(List<_TpmPhase> phases, bool isMobile) {
    // Dashboard (multi-project) → group phases under their project name.
    // Single-project → flat list, no project headers needed.
    final showProjectHeaders = widget.showAllProjects;

    // Build an ordered project list preserving document order.
    final seenProjects = <String>[];
    final byProject = <String, List<_TpmPhase>>{};
    for (final p in phases) {
      if (!byProject.containsKey(p.projectId)) {
        seenProjects.add(p.projectId);
      }
      byProject.putIfAbsent(p.projectId, () => []).add(p);
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4FA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFD0DCF0), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Collapsible section header ─────────────────────────
            InkWell(
              onTap: () =>
                  setState(() => _phaseExpanded = !_phaseExpanded),
              borderRadius: _phaseExpanded
                  ? const BorderRadius.vertical(top: Radius.circular(7))
                  : BorderRadius.circular(7),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 10 : 12,
                  vertical: isMobile ? 6 : 7,
                ),
                child: Row(
                  children: [
                    Icon(Icons.stacked_bar_chart_rounded,
                        size: isMobile ? 14 : 15, color: _navy),
                    const SizedBox(width: 6),
                    Text(
                      'Phase Breakdown',
                      style: TextStyle(
                        fontSize: isMobile ? 11 : 12,
                        fontWeight: FontWeight.w700,
                        color: _navy,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${phases.length} phase${phases.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: isMobile ? 9 : 10,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _phaseExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: isMobile ? 16 : 18,
                      color: _navy.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
            ),

            // ── Phase rows (visible when expanded) ─────────────────
            if (_phaseExpanded) ...[
              Divider(
                  height: 1,
                  thickness: 0.8,
                  color: const Color(0xFFD0DCF0)),
              Padding(
                padding: EdgeInsets.all(isMobile ? 8 : 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: showProjectHeaders
                      ? _buildGroupedPhaseRows(
                          seenProjects, byProject, isMobile)
                      : _buildFlatPhaseRows(phases, isMobile),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Flat list — used in single-project (ProjectSummaryScreen) mode.
  List<Widget> _buildFlatPhaseRows(
      List<_TpmPhase> phases, bool isMobile) {
    return phases.asMap().entries.map((e) {
      return Padding(
        padding: e.key < phases.length - 1
            ? const EdgeInsets.only(bottom: 5)
            : EdgeInsets.zero,
        child: _buildPhaseRow(e.value, e.key, isMobile),
      );
    }).toList();
  }

  /// Grouped list — used in dashboard (multi-project) mode.
  /// Each project gets a small folder-icon header; its phases are indented.
  List<Widget> _buildGroupedPhaseRows(
      List<String> projectOrder,
      Map<String, List<_TpmPhase>> byProject,
      bool isMobile) {
    final widgets = <Widget>[];
    for (int pi = 0; pi < projectOrder.length; pi++) {
      final projectId = projectOrder[pi];
      final projectPhases = byProject[projectId]!;
      final projName = projectPhases.first.projectName ?? projectId;

      // Project label
      widgets.add(Padding(
        padding:
            EdgeInsets.only(top: pi > 0 ? 8 : 0, bottom: isMobile ? 4 : 5),
        child: Row(
          children: [
            Icon(Icons.folder_outlined,
                size: isMobile ? 11 : 12, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                projName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isMobile ? 9 : 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[700],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ));

      // Phase rows indented under the project
      for (int i = 0; i < projectPhases.length; i++) {
        widgets.add(Padding(
          padding: EdgeInsets.only(
            left: 10,
            bottom: i < projectPhases.length - 1 ? 5 : 0,
          ),
          child: _buildPhaseRow(projectPhases[i], i, isMobile),
        ));
      }
    }
    return widgets;
  }

  /// One phase row: name | thin progress bar | % badge.
  /// No days are shown here — percentages only.
  Widget _buildPhaseRow(_TpmPhase phase, int colorIndex, bool isMobile) {
    final color = _phaseColors[colorIndex % _phaseColors.length];
    final isComplete = phase.progress >= 1.0;
    final effectiveColor = isComplete ? const Color(0xFF2E7D32) : color;
    final pct = '${(phase.progress * 100).toStringAsFixed(0)}%';

    return Row(
      children: [
        // Phase name
        Expanded(
          flex: 3,
          child: Text(
            phase.phaseName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: isMobile ? 10 : 11,
              fontWeight: FontWeight.w500,
              color: Colors.grey[800],
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Thin progress bar (percentage only, no day count)
        Expanded(
          flex: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: phase.progress,
              minHeight: isMobile ? 5 : 6,
              backgroundColor: effectiveColor.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(effectiveColor),
            ),
          ),
        ),
        const SizedBox(width: 6),

        // Percentage badge
        Container(
          width: isMobile ? 36 : 40,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: effectiveColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: effectiveColor.withValues(alpha: 0.30), width: 0.8),
          ),
          child: Text(
            pct,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isMobile ? 9 : 10,
              fontWeight: FontWeight.w700,
              color: effectiveColor,
            ),
          ),
        ),
      ],
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
          'Ongoing', visibleOngoing.length, ongoing.length, _ongoingColor, isMobile));
      for (final t in visibleOngoing) {
        items.add(_buildTaskItem(t, isMobile));
      }
    }

    if (visibleCompleted.isNotEmpty) {
      items.add(_sectionHeader(
          'Completed', visibleCompleted.length, completed.length, _completedColor, isMobile));
      for (final t in visibleCompleted) {
        items.add(_buildTaskItem(t, isMobile));
      }
    }

    return Column(
      children: [
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: items),
        ),
        if (hasMore || _isExpanded)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Center(
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _isExpanded = !_isExpanded),
                icon: Icon(
                  _isExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: isMobile ? 18 : 20,
                ),
                label: Text(
                  _isExpanded ? 'Show Less' : 'View All  ($total tasks)',
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
  Widget _sectionHeader(
      String title, int shown, int total, Color color, bool isMobile) {
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

    // Ongoing: plain label only. Completed: show the completion date.
    final subtitleText = isCompleted
        ? task.completedDate != null
            ? 'Completed ${DateFormat('d MMM yyyy').format(task.completedDate!)}'
            : 'Completed'
        : 'Ongoing';

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
          // Status icon
          Container(
            width: isMobile ? 32 : 36,
            height: isMobile ? 32 : 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border:
                  Border.all(color: color.withValues(alpha: 0.30), width: 1.5),
            ),
            child: Icon(statusIcon, color: color, size: isMobile ? 16 : 18),
          ),
          const SizedBox(width: 10),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Phase badge
                if (task.phaseName != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _navy.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: _navy.withValues(alpha: 0.18), width: 0.8),
                    ),
                    child: Text(
                      task.phaseName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isMobile ? 8 : 9,
                        fontWeight: FontWeight.w700,
                        color: _navy.withValues(alpha: 0.75),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],

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

                // Status line (Ongoing / Completed date)
                Row(
                  children: [
                    Icon(
                      isCompleted
                          ? Icons.event_available_rounded
                          : Icons.access_time_rounded,
                      size: isMobile ? 11 : 12,
                      color: color,
                    ),
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
                          size: isMobile ? 10 : 11, color: Colors.grey[600]),
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

                // Progress bar + 100% — completed tasks only
                if (isCompleted) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: 1.0,
                            minHeight: 4,
                            backgroundColor:
                                _completedColor.withValues(alpha: 0.12),
                            valueColor:
                                const AlwaysStoppedAnimation(_completedColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '100%',
                        style: TextStyle(
                          fontSize: isMobile ? 9 : 10,
                          fontWeight: FontWeight.w700,
                          color: _completedColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Status badge
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
  Widget _buildLoading() =>
      const Center(child: CircularProgressIndicator());

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