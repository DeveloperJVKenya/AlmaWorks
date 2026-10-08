import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/schedule/msproject_gantt_screen.dart';
import 'package:almaworks/screens/schedule/purchasing_plan_screen.dart';
import 'package:almaworks/screens/schedule/schedule_monitor_screen.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:almaworks/core/l10n/l10n.dart';

class DynamicScheduleScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;

  const DynamicScheduleScreen({
    super.key,
    required this.project,
    required this.logger,
  });

  @override
  State<DynamicScheduleScreen> createState() => _DynamicScheduleScreenState();
}

class _DynamicScheduleScreenState extends State<DynamicScheduleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    widget.logger.i(
      '📅 DynamicScheduleScreen: Initialized for project: ${widget.project.name} (ID: ${widget.project.id})',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final width = MediaQuery.of(context).size.width;
      widget.logger.d(
        '📅 DynamicScheduleScreen: Screen width: $width, isMobile: ${width < 600}',
      );
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    widget.logger.d('📅 DynamicScheduleScreen: Building UI, isMobile: $isMobile');

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF0A2E5A),
              unselectedLabelColor: Colors.grey[600],
              indicatorColor: const Color(0xFF0A2E5A),
              labelStyle: TextStyle(
                fontWeight: FontWeight.w600,
              ),
              tabs: [
                Tab(text: context.l10n.ganttChart),
                Tab(text: context.l10n.scheduleMonitor),
                Tab(text: context.l10n.purchasingPlanResources),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                MSProjectGanttScreen(
                  project: widget.project,
                  logger: widget.logger,
                ),
                ScheduleMonitorScreen(
                  project: widget.project,
                  logger: widget.logger,
                  projectId: widget.project.id,
                  projectName: widget.project.name,
                ),
                PurchasingPlanScreen(
                  project: widget.project,
                  logger: widget.logger,
                  projectId: widget.project.id,
                  projectName: widget.project.name,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}