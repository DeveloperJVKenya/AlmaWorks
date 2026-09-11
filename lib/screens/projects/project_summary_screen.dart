import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/documents_screen.dart';
import 'package:almaworks/screens/drawings_screen.dart';
import 'package:almaworks/screens/projects/edit_project_screen.dart';
import 'package:almaworks/screens/projects/projects_main_screen.dart';
import 'package:almaworks/widgets/task_progress_widget.dart';
import 'package:almaworks/widgets/dashboard_card.dart';
import 'package:almaworks/widgets/weather_widget.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:almaworks/screens/schedule/notification_center_screen.dart';
import 'package:almaworks/services/notification_service.dart';

class ProjectSummaryScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;

  const ProjectSummaryScreen({
    super.key,
    required this.project,
    required this.logger,
  });

  @override
  State<ProjectSummaryScreen> createState() => _ProjectSummaryScreenState();
}

class _ProjectSummaryScreenState extends State<ProjectSummaryScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final NotificationService _notificationService =
      NotificationService(logger: Logger());

  // Local, refreshable copy of the project — widget.project is a snapshot
  // taken at navigation time and never changes, so every read in this
  // screen goes through this field instead, which _navigateToEditProject
  // refetches from Firestore after Edit Project closes.
  late ProjectModel _currentProject;

  @override
  void initState() {
    super.initState();
    _currentProject = widget.project;
  }

  // ── Single TPM stream reused by both the metrics row and header card ──
  late final Stream<DocumentSnapshot> _tpmStream = FirebaseFirestore.instance
      .collection('TaskProgressMonitor')
      .doc(_currentProject.id)
      .snapshots();

  // ─────────────────────────────────────────────────────────────────
  // HELPERS – mirror TaskProgressMonitorScreen formula exactly
  // ─────────────────────────────────────────────────────────────────

  /// project % = EQUAL-weight average across phases — every phase counts as
  /// 1/N of the project regardless of task count or day-span (4 phases →
  /// 25% each, 5 phases → 20% each, etc.), matching TaskProgressMonitorScreen.
  static double _computeOverallProgress(Map<String, dynamic> data) {
    final rawRows   = data['rows']          as List<dynamic>?        ?? [];
    final rawStatus = data['dailyStatuses'] as Map<String, dynamic>? ?? {};

    final phaseIds = <String>{};
    final phaseWeightedSum = <String, double>{};
    final phaseTotalWeight = <String, int>{};

    for (final entry in rawRows) {
      final m = Map<String, dynamic>.from(entry as Map);
      if ((m['type'] as String?) == 'phase') {
        final id = m['id'] as String? ?? '';
        if (id.isNotEmpty) phaseIds.add(id);
      }
    }

    for (final entry in rawRows) {
      final m = Map<String, dynamic>.from(entry as Map);
      if ((m['type'] as String?) != 'task') continue;

      final id            = m['id']           as String? ?? '';
      final parentPhaseId = m['parentPhaseId'] as String?;
      final start         = (m['startDate'] as Timestamp?)?.toDate();
      final end           = (m['endDate']   as Timestamp?)?.toDate();
      if (start == null || end == null || id.isEmpty || parentPhaseId == null) {
        continue;
      }

      final expected = _countWorkDays(start, end);
      if (expected == 0) continue;

      bool hasCompleted = false;
      int checkedDays = 0;
      final prefix = '${id}_';
      for (final kv in rawStatus.entries) {
        if (!kv.key.startsWith(prefix)) continue;
        final code = kv.value as String?;
        if (code == 'X') {
          hasCompleted = true;
        } else if (code == 'D' || code == 'S' || code == 'O' || code == 'C') {
          checkedDays++;
        }
      }

      final taskProgress = hasCompleted
          ? 1.0
          : (checkedDays / expected).clamp(0.0, 1.0);

      phaseWeightedSum[parentPhaseId] =
          (phaseWeightedSum[parentPhaseId] ?? 0.0) + taskProgress * expected;
      phaseTotalWeight[parentPhaseId] =
          (phaseTotalWeight[parentPhaseId] ?? 0) + expected;
    }

    if (phaseIds.isEmpty) return 0.0;

    double total = 0.0;
    for (final phaseId in phaseIds) {
      final weight = phaseTotalWeight[phaseId] ?? 0;
      final sum    = phaseWeightedSum[phaseId] ?? 0.0;
      total += weight > 0 ? (sum / weight).clamp(0.0, 1.0) : 0.0;
    }
    return (total / phaseIds.length).clamp(0.0, 1.0);
  }

  static ({DateTime? start, DateTime? end}) _tpmDateRange(
      Map<String, dynamic> data) {
    final rawRows = data['rows'] as List<dynamic>? ?? [];
    DateTime? earliest, latest;
    for (final entry in rawRows) {
      final m = Map<String, dynamic>.from(entry as Map);
      if ((m['type'] as String?) != 'task') continue;
      final s = (m['startDate'] as Timestamp?)?.toDate();
      final e = (m['endDate']   as Timestamp?)?.toDate();
      if (s != null && (earliest == null || s.isBefore(earliest))) earliest = s;
      if (e != null && (latest   == null || e.isAfter(latest)))    latest   = e;
    }
    return (start: earliest, end: latest);
  }

  static int _countWorkDays(DateTime start, DateTime end) {
    int count = 0;
    var cur = DateTime(start.year, start.month, start.day);
    final fin = DateTime(end.year, end.month, end.day);
    while (!cur.isAfter(fin)) {
      if (cur.weekday != DateTime.sunday) count++;
      cur = cur.add(const Duration(days: 1));
    }
    return count;
  }

  static ({String label, Color color}) _deriveHealth({
    required double progress,
    required DateTime? start,
    required DateTime? end,
  }) {
    if (progress >= 1.0) return (label: 'Completed',         color: Colors.green);
    if (start == null || end == null) {
      if (progress >= 0.75) return (label: 'On Track',        color: Colors.green);
      if (progress >= 0.40) return (label: 'In Progress',     color: Colors.blue);
      return                        (label: 'Early Stage',     color: Colors.purple);
    }
    final now = DateTime.now();
    if (now.isAfter(end)) return   (label: 'Overdue',          color: Colors.red);
    final total   = end.difference(start).inDays;
    final elapsed = now.difference(start).inDays.clamp(0, total);
    final expected = total == 0 ? 1.0 : elapsed / total;
    final delta   = progress - expected;
    if (delta >=  0.10) return     (label: 'Ahead of Schedule', color: Colors.blue);
    if (delta >= -0.05) return     (label: 'On Track',           color: Colors.green);
    if (delta >= -0.15) return     (label: 'Slight Delay',       color: Colors.orange);
    return                         (label: 'At Risk',             color: Colors.red);
  }

  // ─────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    widget.logger.d(
        '🎨 ProjectSummaryScreen: Building for: ${_currentProject.name}');

    return BaseLayout(
      title: _currentProject.name,
      project: _currentProject,
      logger: widget.logger,
      selectedMenuItem: 'Overview',
      onMenuItemSelected: _handleMenuNavigation,
      actions: [
        StreamBuilder<int>(
          stream: _notificationService.getUnreadCount(_currentProject.id),
          builder: (context, snapshot) {
            final count = snapshot.data ?? 0;
            return Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications),
                  onPressed: () {
                    widget.logger.i('🔔 Notifications pressed');
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NotificationCenterScreen(
                          projectId: _currentProject.id,
                          notificationService: _notificationService,
                          logger: widget.logger,
                        ),
                      ),
                    );
                  },
                ),
                if (count > 0)
                  Positioned(
                    right: 6, top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text('$count',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10),
                          textAlign: TextAlign.center),
                    ),
                  ),
              ],
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () {
            widget.logger.i('✏️ Edit pressed');
            _navigateToEditProject();
          },
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProjectContent(context),
                _buildFooter(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // NAVIGATION
  // ─────────────────────────────────────────────────────────────────

  void _handleMenuNavigation(String menuItem) {
    widget.logger.d('🧭 Navigate to: $menuItem');
    switch (menuItem) {
      case 'Switch Project':
        Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (_) => ProjectsMainScreen(logger: widget.logger)));
        break;
      case 'Overview': break;
      case 'Documents': _navigateToDocuments(); break;
      case 'Drawings':  _navigateToDrawings();  break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$menuItem section coming soon',
              style: GoogleFonts.poppins()),
        ));
    }
  }

  void _navigateToEditProject() {
    if (!mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => EditProjectScreen(
            project: _currentProject, logger: widget.logger)))
        .then((result) async {
      if (result == true && mounted) {
        final doc = await FirebaseFirestore.instance
            .collection('Projects')
            .doc(_currentProject.id)
            .get();
        if (doc.exists && mounted) {
          setState(() {
            _currentProject = ProjectModel.fromFirestore(doc);
          });
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Project updated successfully'),
            backgroundColor: Colors.green,
          ));
        }
      }
    });
  }

  void _navigateToDocuments() {
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
        DocumentsScreen(project: _currentProject, logger: widget.logger)));
  }

  void _navigateToDrawings() {
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
        DrawingsScreen(project: _currentProject, logger: widget.logger)));
  }

  // ─────────────────────────────────────────────────────────────────
  // CONTENT SCAFFOLD
  // ─────────────────────────────────────────────────────────────────

  Widget _buildProjectContent(BuildContext context) {
    final w        = MediaQuery.of(context).size.width;
    final isMobile  = w < 600;
    final isTablet  = w >= 600  && w < 1200;
    final isDesktop = w >= 1200;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 16),
          child: Text(
            'Project Overview',
            style: GoogleFonts.poppins(
              fontSize: isMobile ? 20 : 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        _buildProjectMetrics(context, isMobile, isTablet, isDesktop),
        const SizedBox(height: 16),
        _buildProjectHeader(isMobile),
        const SizedBox(height: 16),
        _buildContentSection(context, isMobile, isTablet, isDesktop),
        const SizedBox(height: 32),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // METRICS ROW  (budget removed; Progress Live + Team Members)
  // ─────────────────────────────────────────────────────────────────

  Widget _buildProjectMetrics(
    BuildContext context,
    bool isMobile,
    bool isTablet,
    bool isDesktop,
  ) {
    widget.logger.d('📊 Building metrics');

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
      child: Row(
        children: [
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: _tpmStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return DashboardCard(
                    title: 'Progress',
                    value: '…',
                    icon: Icons.trending_up,
                    color: Colors.blue.withValues(alpha: 0.4),
                    onTap: () {},
                  );
                }

                double progress;
                bool isLive = false;
                if (snapshot.hasData && snapshot.data!.exists) {
                  progress = _computeOverallProgress(
                      snapshot.data!.data() as Map<String, dynamic>? ?? {});
                  isLive = true;
                } else {
                  progress = _currentProject.progress / 100.0;
                }

                final pct = (progress * 100).toStringAsFixed(0);
                final color = isLive
                    ? (progress >= 1.0
                        ? Colors.green
                        : _currentProject.isActive
                            ? Colors.blue
                            : Colors.grey)
                    : Colors.grey;

                return DashboardCard(
                  title: isLive ? 'Progress (Live)' : 'Progress',
                  value: '$pct%',
                  icon: Icons.trending_up,
                  color: color,
                  onTap: () => widget.logger.i(
                      '👆 Progress card tapped — $pct% (live: $isLive)'),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DashboardCard(
              title: 'Team Members',
              value: '${_currentProject.teamMembers.length}',
              icon: Icons.people,
              color: Colors.purple,
              onTap: () {
                widget.logger.i('👆 Team members card tapped');
                _showTeamMembers(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // ★  PROJECT HEADER CARD  ★
  // Exact same fields as the original:
  //   • avatar (status colour) + location + status chip
  //   • description
  //   • Project Manager | Team Size
  //   • Start Date | End Date  ← now sourced from TPM
  //   • Days Remaining | Health Status  ← health now derived from TPM progress
  //   • Slim overall-progress bar (new, but lightweight)
  // Only styling is modernised; no extra sections added.
  // ─────────────────────────────────────────────────────────────────

  Widget _buildProjectHeader(bool isMobile) {
    widget.logger.d('🏗️ Building project header');

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
      child: StreamBuilder<DocumentSnapshot>(
        stream: _tpmStream,
        builder: (context, snapshot) {
          // ── Resolve live values ─────────────────────────────
          double progress = _currentProject.progress / 100.0;
          DateTime? tpmStart, tpmEnd;

          if (snapshot.hasData && snapshot.data!.exists) {
            final data =
                snapshot.data!.data() as Map<String, dynamic>? ?? {};
            progress = _computeOverallProgress(data);
            final r  = _tpmDateRange(data);
            tpmStart = r.start;
            tpmEnd   = r.end;
          }

          tpmStart ??= _currentProject.startDate;
          tpmEnd   ??= _currentProject.endDate;

          int? daysRemaining;
          if (tpmEnd != null) {
            daysRemaining = tpmEnd.difference(DateTime.now()).inDays;
          } else {
            daysRemaining = _currentProject.daysRemaining;
          }

          final health = _deriveHealth(
            progress: progress,
            start: tpmStart,
            end: tpmEnd,
          );

          final statusColor = _getStatusColor(_currentProject.status);

          // ── Card ────────────────────────────────────────────
          return Card(
            elevation: 1,
            shadowColor: const Color(0xFF0A2E5A).withValues(alpha: 0.10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.12), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Avatar + location + status chip ──────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.30),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            _currentProject.name
                                .substring(0, 1)
                                .toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 19,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 13,
                                color: Colors.grey[500]),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                _currentProject.location,
                                style: GoogleFonts.poppins(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildStatusChip(_currentProject.status, statusColor),
                    ],
                  ),

                  // ── Description ──────────────────────────────
                  if (_currentProject.description.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      _currentProject.description,
                      style: GoogleFonts.poppins(
                        color: Colors.grey[700],
                        fontSize: 13,
                        height: 1.55,
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),
                  Divider(height: 1,
                      color: Colors.grey.withValues(alpha: 0.15)),
                  const SizedBox(height: 14),

                  // ── Project Manager | Team Size ───────────────
                  Row(
                    children: [
                      Expanded(child: _buildInfoItem(
                          'Project Manager',
                          _currentProject.projectManager)),
                      Expanded(child: _buildInfoItem(
                          'Team Size',
                          '${_currentProject.teamMembers.length} members')),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ── Start Date | End Date (from TPM) ──────────
                  Row(
                    children: [
                      Expanded(child: _buildInfoItem(
                          'Start Date',
                          _formatDate(tpmStart))),
                      Expanded(child: _buildInfoItem(
                          'End Date',
                          tpmEnd != null
                              ? _formatDate(tpmEnd)
                              : 'TBD')),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ── Days Remaining | Health Status ────────────
                  Row(
                    children: [
                      Expanded(child: _buildInfoItem(
                          'Days Remaining',
                          daysRemaining != null
                              ? daysRemaining > 0
                                  ? '$daysRemaining days'
                                  : daysRemaining == 0
                                      ? 'Due today'
                                      : '${daysRemaining.abs()}d overdue'
                              : '—')),
                      Expanded(child: _buildHealthItem(health)),
                    ],
                  ),

                  // ── Slim overall progress bar ─────────────────
                  const SizedBox(height: 14),
                  Divider(height: 1,
                      color: Colors.grey.withValues(alpha: 0.15)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('Overall Progress',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          )),
                      const Spacer(),
                      Text('${(progress * 100).toStringAsFixed(0)}%',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0A2E5A),
                          )),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 7,
                      backgroundColor:
                          const Color(0xFF0A2E5A).withValues(alpha: 0.09),
                      valueColor: AlwaysStoppedAnimation(
                        progress >= 1.0
                            ? Colors.green[600]!
                            : const Color(0xFF1565C0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // SMALL REUSABLE WIDGETS
  // ─────────────────────────────────────────────────────────────────

  Widget _buildStatusChip(String? status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Text(
        _getStatusText(status ?? ''),
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            )),
        const SizedBox(height: 2),
        Text(value,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A2744),
            )),
      ],
    );
  }

  Widget _buildHealthItem(({String label, Color color}) h) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Health Status',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            )),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: h.color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            h.label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: h.color,
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // ★  TEAM MEMBERS – modernised bottom sheet  ★
  // ─────────────────────────────────────────────────────────────────

  void _showTeamMembers(BuildContext context) {
    widget.logger.i('👥 Showing team members');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final members = _currentProject.teamMembers;
        return DraggableScrollableSheet(
          initialChildSize: 0.60,
          minChildSize: 0.35,
          maxChildSize: 0.90,
          builder: (_, sc) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              children: [
                // Drag handle
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Container(
                    width: 38, height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                  color: const Color(0xFF0A2E5A),
                  child: Row(
                    children: [
                      const Icon(Icons.group_rounded,
                          color: Colors.white70, size: 20),
                      const SizedBox(width: 10),
                      Text('Team Members',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          )),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('${members.length}',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ],
                  ),
                ),
                // List
                Expanded(
                  child: ListView.separated(
                    controller: sc,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                    itemCount: members.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, idx) {
                      final member = members[idx];
                      // Prefer the reliable uid match (set only on the one
                      // entry EditProjectScreen auto-syncs for the linked PM
                      // — see TeamMember.uid) over the old plain name-string
                      // comparison, which silently drifts if the free-text
                      // projectManager field and the linked account's name
                      // ever differ. Falls back to the name match so a
                      // project with a manager only ever set via the old
                      // free-text field (no linked account) still badges.
                      final isManager = _currentProject.projectManagerUid != null
                          ? member.uid == _currentProject.projectManagerUid
                          : member.name == _currentProject.projectManager;
                      final initials  = member.name
                          .trim()
                          .split(' ')
                          .where((s) => s.isNotEmpty)
                          .take(2)
                          .map((s) => s[0].toUpperCase())
                          .join();
                      const palette = [
                        Color(0xFF0A2E5A), Color(0xFF6A1B9A),
                        Color(0xFF2E7D32), Color(0xFFE65100),
                        Color(0xFF00838F), Color(0xFFAD1457),
                      ];
                      final avatarColor = palette[idx % palette.length];

                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: isManager
                              ? const Color(0xFFFFF8E1)
                              : const Color(0xFFF8FAFD),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isManager
                                ? const Color(0xFFFFD54F)
                                : const Color(0xFFE8ECF0),
                            width: isManager ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Coloured avatar
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                  color: avatarColor,
                                  shape: BoxShape.circle),
                              child: Center(
                                child: Text(
                                  initials.isEmpty ? '?' : initials,
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Name + role pills
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(member.name,
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: const Color(0xFF1A2744),
                                            )),
                                      ),
                                      if (isManager) ...[
                                        const Icon(Icons.star_rounded,
                                            size: 13,
                                            color: Color(0xFFFFB300)),
                                        const SizedBox(width: 2),
                                        Text('PM',
                                            style: GoogleFonts.poppins(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color:
                                                  const Color(0xFF795548),
                                            )),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    children: [
                                      _rolePill(
                                          StringExtension(member.role)
                                              .capitalize(),
                                          const Color(0xFF0A2E5A),
                                          const Color(0xFFE8EEF6)),
                                      if (member.category != null)
                                        _rolePill(
                                            member.category!,
                                            const Color(0xFF6A1B9A),
                                            const Color(0xFFF3E5F5)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _rolePill(String label, Color textColor, Color bgColor) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: bgColor, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: textColor,
            )),
      );

  // ─────────────────────────────────────────────────────────────────
  // CONTENT SECTION (carousel: TaskProgressWidget + WeatherWidget)
  // ─────────────────────────────────────────────────────────────────

  Widget _buildContentSection(
    BuildContext context,
    bool isMobile,
    bool isTablet,
    bool isDesktop,
  ) {
    final screenWidth   = MediaQuery.of(context).size.width;
    final sidebarWidth  = isMobile ? 0 : (isTablet ? 280 : 300);
    final availableWidth =
        screenWidth - sidebarWidth - (isMobile ? 24 : 32);
    const double widgetHeight = 400.0;

    widget.logger.d(
        '🏗️ Building content section, availableWidth: $availableWidth');

    final widgets = [
      SizedBox(
        width: availableWidth,
        height: widgetHeight,
        child: TaskProgressWidget(
          projectId: _currentProject.id,
          showAllProjects: false,
          logger: widget.logger,
          maxInitialDisplay: 5,
          showPhaseBreakdown: true,
        ),
      ),
      SizedBox(
        width: availableWidth,
        height: widgetHeight,
        child: WeatherWidget(projectLocation: _currentProject.location),
      ),
    ];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            height: widgetHeight,
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemCount: widgets.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: widgets[i],
              ),
              physics: const NeverScrollableScrollPhysics(),
              pageSnapping: false,
              scrollBehavior: const ScrollBehavior()
                  .copyWith(scrollbars: false, overscroll: false),
            ),
          ),
          Positioned(
            left: 0,
            child: _currentPage > 0
                ? FloatingActionButton(
                    onPressed: () => _pageController.previousPage(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOutCubic,
                    ),
                    mini: true,
                    backgroundColor: const Color(0xFF0A2E5A),
                    child: const Icon(Icons.arrow_left,
                        color: Colors.white, size: 30, weight: 800),
                  )
                : const SizedBox.shrink(),
          ),
          Positioned(
            right: 0,
            child: _currentPage < widgets.length - 1
                ? FloatingActionButton(
                    onPressed: () => _pageController.nextPage(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOutCubic,
                    ),
                    mini: true,
                    backgroundColor: const Color(0xFF0A2E5A),
                    child: const Icon(Icons.arrow_right,
                        color: Colors.white, size: 30, weight: 800),
                  )
                : const SizedBox.shrink(),
          ),
          Positioned(
            bottom: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widgets.length,
                (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == i
                        ? const Color(0xFF0A2E5A)
                        : Colors.grey.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // FOOTER
  // ─────────────────────────────────────────────────────────────────

  Widget _buildFooter(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      color: const Color(0xFF0A2E5A),
      child: Text(
        '© 2025 JV Alma C.I.S Site Management System',
        style: TextStyle(
          color: Colors.white,
          fontSize: isMobile ? 12 : 14,
          fontWeight: FontWeight.w400,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // UTILS
  // ─────────────────────────────────────────────────────────────────

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'active':    return Colors.green;
      case 'completed': return Colors.orange;
      default:          return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'active':    return 'Active';
      case 'completed': return 'Completed';
      default:          return 'Untracked';
    }
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}

extension StringExtension on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}