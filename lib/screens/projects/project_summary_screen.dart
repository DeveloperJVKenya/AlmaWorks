import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/documents_screen.dart';
import 'package:almaworks/screens/drawings_screen.dart';
import 'package:almaworks/screens/projects/edit_project_screen.dart';
import 'package:almaworks/screens/projects/projects_main_screen.dart';
//import 'package:almaworks/widgets/activity_feed.dart';
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
  final NotificationService _notificationService = NotificationService(logger: Logger());

  // ── Task Progress Monitor – real-time progress stream ────────────
  // Listens to the same Firestore document that TaskProgressMonitorScreen
  // writes, and recomputes project progress whenever the document changes.
  late final Stream<double> _tpmProgressStream = FirebaseFirestore.instance
      .collection('TaskProgressMonitor')
      .doc(widget.project.id)
      .snapshots()
      .map(_computeProgressFromSnapshot);

  /// Replicates the exact formula from TaskProgressMonitorScreen:
  ///   progress = Σ checkedDays(task) / Σ expectedWorkDays(task)
  /// where expectedWorkDays = Mon–Sat days between startDate and endDate
  /// and   checkedDays      = dailyStatus entries whose value is 'D' (done)
  ///                          or any legacy code that maps to done (S, O, C).
  static double _computeProgressFromSnapshot(DocumentSnapshot snap) {
    if (!snap.exists) return 0.0;

    final data       = snap.data() as Map<String, dynamic>? ?? {};
    final rawRows    = data['rows']         as List<dynamic>?       ?? [];
    final rawStatus  = data['dailyStatuses'] as Map<String, dynamic>? ?? {};

    int totalExpected = 0;
    int totalChecked  = 0;

    for (final entry in rawRows) {
      final m = Map<String, dynamic>.from(entry as Map);
      if ((m['type'] as String?) != 'task') continue;

      final id    = m['id'] as String? ?? '';
      final start = (m['startDate'] as Timestamp?)?.toDate();
      final end   = (m['endDate']   as Timestamp?)?.toDate();
      if (start == null || end == null || id.isEmpty) continue;

      totalExpected += _countWorkDays(start, end);

      final prefix = '${id}_';
      for (final kv in rawStatus.entries) {
        if (!kv.key.startsWith(prefix)) continue;
        if (_isDone(kv.value as String?)) totalChecked++;
      }
    }

    if (totalExpected == 0) return 0.0;
    return (totalChecked / totalExpected).clamp(0.0, 1.0);
  }

  static int _countWorkDays(DateTime start, DateTime end) {
    int count = 0;
    DateTime cur = DateTime(start.year, start.month, start.day);
    final endN   = DateTime(end.year,   end.month,   end.day);
    while (!cur.isAfter(endN)) {
      if (cur.weekday != DateTime.sunday) count++;
      cur = cur.add(const Duration(days: 1));
    }
    return count;
  }

  static bool _isDone(String? code) {
    switch (code) {
      case 'D':
      case 'S':
      case 'O':
      case 'C':
        return true;
      default:
        return false;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.logger.d(
      '🎨 ProjectSummaryScreen: Building project summary for: ${widget.project.name}',
    );

    return BaseLayout(
      title: widget.project.name,
      project: widget.project,
      logger: widget.logger,
      selectedMenuItem: 'Overview',
      onMenuItemSelected: _handleMenuNavigation,
      actions: [
        StreamBuilder<int>(
          stream: _notificationService.getUnreadCount(widget.project.id),
          builder: (context, snapshot) {
            final unreadCount = snapshot.data ?? 0;
            return Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications),
                  onPressed: () {
                    widget.logger.i('🔔 ProjectSummaryScreen: Notifications pressed for project: ${widget.project.id}');
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => NotificationCenterScreen(
                          projectId: widget.project.id,
                          notificationService: _notificationService,
                          logger: widget.logger,
                        ),
                      ),
                    );
                  },
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        '$unreadCount',
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () {
            widget.logger.i('✏️ ProjectSummaryScreen: Edit button pressed');
            _navigateToEditProject();
          },
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
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
          );
        },
      ),
    );
  }

  void _handleMenuNavigation(String menuItem) {
    widget.logger.d('🧭 ProjectSummaryScreen: Navigation to: $menuItem');

    switch (menuItem) {
      case 'Switch Project':
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ProjectsMainScreen(logger: widget.logger),
          ),
        );
        break;
      case 'Overview':
        break;
      case 'Documents':
        _navigateToDocuments();
        break;
      case 'Drawings':
        _navigateToDrawings();
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$menuItem section coming soon',
              style: GoogleFonts.poppins(),
            ),
          ),
        );
        break;
    }
  }

  void _navigateToEditProject() {
    widget.logger.i(
      '✏️ ProjectSummaryScreen: Navigating to edit project: ${widget.project.name}',
    );

    if (!mounted) return;

    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    navigator
        .push(
          MaterialPageRoute(
            builder: (context) => EditProjectScreen(
              project: widget.project,
              logger: widget.logger,
            ),
          ),
        )
        .then((result) {
          if (result == true && mounted) {
            widget.logger.d(
              '🔄 ProjectSummaryScreen: Project edited successfully, returning to summary',
            );
            scaffoldMessenger.showSnackBar(
              const SnackBar(
                content: Text('Project updated successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        });
  }

  void _navigateToDocuments() {
    widget.logger.i(
      '📂 ProjectSummaryScreen: Navigating to documents for project: ${widget.project.name}',
    );

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            DocumentsScreen(project: widget.project, logger: widget.logger),
      ),
    );
  }

  void _navigateToDrawings() {
    widget.logger.i(
      '🏗️ ProjectSummaryScreen: Navigating to drawings for project: ${widget.project.name}',
    );

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            DrawingsScreen(project: widget.project, logger: widget.logger),
      ),
    );
  }

  Widget _buildProjectContent(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile  = screenWidth < 600;
    final isTablet  = screenWidth >= 600 && screenWidth < 1200;
    final isDesktop = screenWidth >= 1200;

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

  Widget _buildProjectMetrics(
    BuildContext context,
    bool isMobile,
    bool isTablet,
    bool isDesktop,
  ) {
    widget.logger.d(
      '📊 ProjectSummaryScreen: Building project metrics, isMobile: $isMobile, isTablet: $isTablet, isDesktop: $isDesktop',
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
      child: Row(
        children: [
          Expanded(
            child: FutureBuilder<int>(
              future: Future.value(1),
              builder: (context, snapshot) {
                return DashboardCard(
                  title: 'Project Budget',
                  value: widget.project.budget != null
                      ? '\$${(widget.project.budget! / 1000000).toStringAsFixed(1)}M'
                      : 'TBD',
                  icon: Icons.attach_money,
                  color: Colors.green,
                  onTap: () {
                    widget.logger.i(
                      '👆 ProjectSummaryScreen: Budget card tapped',
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StreamBuilder<double>(
              stream: _tpmProgressStream,
              builder: (context, snapshot) {
                final double progress;
                final bool isLive;
                if (snapshot.hasError) {
                  progress = widget.project.progress / 100.0;
                  isLive   = false;
                } else if (!snapshot.hasData) {
                  return DashboardCard(
                    title: 'Progress',
                    value: '…',
                    icon: Icons.trending_up,
                    color: Colors.blue.withValues(alpha: 0.4),
                    onTap: () {},
                  );
                } else {
                  progress = snapshot.data!;
                  isLive   = true;
                }

                final pct = (progress * 100).toStringAsFixed(0);
                final cardColor = isLive
                    ? (progress >= 1.0
                        ? Colors.green
                        : widget.project.isActive
                            ? Colors.blue
                            : Colors.grey)
                    : Colors.grey;

                return DashboardCard(
                  title: isLive ? 'Progress (Live)' : 'Progress',
                  value: '$pct%',
                  icon: Icons.trending_up,
                  color: cardColor,
                  onTap: () {
                    widget.logger.i(
                      '👆 ProjectSummaryScreen: Progress card tapped — $pct% (live: $isLive)',
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DashboardCard(
              title: 'Team Members',
              value: '${widget.project.teamMembers.length}',
              icon: Icons.people,
              color: Colors.purple,
              onTap: () {
                widget.logger.i(
                  '👆 ProjectSummaryScreen: Team members card tapped',
                );
                _showTeamMembers(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectHeader(bool isMobile) {
    widget.logger.d('🏗️ ProjectSummaryScreen: Building project header');

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _getStatusColor(widget.project.status),
                    child: Text(
                      widget.project.name.substring(0, 1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.project.name,
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.project.location,
                          style: GoogleFonts.poppins(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.project.status != null)
                    Chip(
                      label: Text(_getStatusText(widget.project.status!)),
                      backgroundColor: _getStatusColor(
                        widget.project.status,
                      ).withValues(alpha: 0.1),
                      labelStyle: TextStyle(
                        color: _getStatusColor(widget.project.status),
                      ),
                    )
                  else
                    Chip(
                      label: const Text('Untracked'),
                      backgroundColor: Colors.grey.withValues(alpha: 0.1),
                      labelStyle: const TextStyle(color: Colors.grey),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                widget.project.description,
                style: GoogleFonts.poppins(
                  color: Colors.grey[700],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      'Project Manager',
                      widget.project.projectManager,
                    ),
                  ),
                  Expanded(
                    child: _buildInfoItem(
                      'Team Size',
                      '${widget.project.teamMembers.length} members',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      'Start Date',
                      _formatDate(widget.project.startDate),
                    ),
                  ),
                  Expanded(
                    child: _buildInfoItem(
                      'End Date',
                      widget.project.endDate != null
                          ? _formatDate(widget.project.endDate!)
                          : 'TBD',
                    ),
                  ),
                ],
              ),
              if (widget.project.daysRemaining != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoItem(
                        'Days Remaining',
                        '${widget.project.daysRemaining} days',
                      ),
                    ),
                    Expanded(
                      child: _buildInfoItem(
                        'Health Status',
                        widget.project.healthStatus,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  void _showTeamMembers(BuildContext context) {
    widget.logger.i('👥 ProjectSummaryScreen: Showing team members dialog');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Team Members', style: GoogleFonts.poppins()),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.project.teamMembers.length,
              itemBuilder: (context, index) {
                final member = widget.project.teamMembers[index];
                final isManager = member.name == widget.project.projectManager;

                return ListTile(
                  leading: CircleAvatar(
                    child: Text(member.name.substring(0, 1).toUpperCase()),
                  ),
                  title: Text(member.name, style: GoogleFonts.poppins()),
                  subtitle: Text(
                    '${StringExtension(member.role).capitalize()}${member.category != null ? ' - ${member.category}' : ''}${isManager ? ' (Project Manager)' : ''}',
                    style: GoogleFonts.poppins(),
                  ),
                  trailing: isManager
                      ? const Icon(Icons.star, color: Colors.amber)
                      : null,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close', style: GoogleFonts.poppins()),
            ),
          ],
        );
      },
    );
  }

  Widget _buildContentSection(
    BuildContext context,
    bool isMobile,
    bool isTablet,
    bool isDesktop,
  ) {
    final screenWidth  = MediaQuery.of(context).size.width;
    final sidebarWidth = isMobile ? 0 : (isTablet ? 280 : 300);
    final availableWidth = screenWidth - sidebarWidth - (isMobile ? 24 : 32);
    const double widgetHeight = 400.0;

    widget.logger.d(
      '🏗️ ProjectSummaryScreen: Building content section, isMobile: $isMobile, availableWidth: $availableWidth',
    );

    // ── ActivityFeed, TaskProgressWidget, and WeatherWidget ─────────────────
    final widgets = [
      SizedBox(
        width: availableWidth,
        height: widgetHeight,
        // Task Progress Widget: shows done-ongoing (top) and done-completed (bottom)
        // tasks for THIS project sourced from the TaskProgressMonitor collection.
        // Ongoing tasks are shown first (active), completed tasks at the bottom.
        child: TaskProgressWidget(
          projectId: widget.project.id,
          showAllProjects: false,
          logger: widget.logger,
          // 5 items visible before "View All" – single-project view has more room
          maxInitialDisplay: 5,
        ),
      ),
      SizedBox(
        width: availableWidth,
        height: widgetHeight,
        // Pass the project's saved location – WeatherWidget fetches live data for it
        child: WeatherWidget(
          projectLocation: widget.project.location,
        ),
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
              onPageChanged: (index) {
                setState(() { _currentPage = index; });
              },
              itemCount: widgets.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: widgets[index],
                );
              },
              physics: const NeverScrollableScrollPhysics(),
              pageSnapping: false,
              scrollBehavior: const ScrollBehavior().copyWith(
                scrollbars: false,
                overscroll: false,
              ),
            ),
          ),
          Positioned(
            left: 0,
            child: _currentPage > 0
                ? FloatingActionButton(
                    onPressed: () {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOutCubic,
                      );
                    },
                    mini: true,
                    backgroundColor: const Color(0xFF0A2E5A),
                    child: const Icon(
                      Icons.arrow_left,
                      color: Colors.white,
                      size: 30,
                      weight: 800,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Positioned(
            right: 0,
            child: _currentPage < widgets.length - 1
                ? FloatingActionButton(
                    onPressed: () {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOutCubic,
                      );
                    },
                    mini: true,
                    backgroundColor: const Color(0xFF0A2E5A),
                    child: const Icon(
                      Icons.arrow_right,
                      color: Colors.white,
                      size: 30,
                      weight: 800,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Positioned(
            bottom: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widgets.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == index
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

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'completed':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case 'completed':
        return 'Completed';
      default:
        return 'Untracked';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}