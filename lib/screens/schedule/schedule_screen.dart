import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/schedule/general_schedule_screen.dart';
import 'package:almaworks/screens/schedule/dynamic_schedule_screen.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/theme/app_colors.dart';

class ScheduleScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;

  const ScheduleScreen({
    super.key,
    required this.project,
    required this.logger,
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _userRole;
  bool _isLoadingUserData = true;

  @override
  void initState() {
    super.initState();
    // Initialize with 2 tabs by default
    _tabController = TabController(length: 2, vsync: this);
    widget.logger.i(
      '📅 ScheduleScreen: Initialized for project: ${widget.project.name} (ID: ${widget.project.id})',
    );

    // Fetch user role asynchronously
    _fetchUserRole();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final width = MediaQuery.of(context).size.width;
      widget.logger.d(
        '📅 ScheduleScreen: Screen width: $width, isMobile: ${width < 600}',
      );
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        widget.logger.e('❌ ScheduleScreen: No authenticated user found');
        setState(() {
          _userRole = 'Client';
          _isLoadingUserData = false;
        });
        return;
      }

      final querySnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final userData = querySnapshot.docs.first.data();
        final role = userData['role'] as String? ?? 'Client';

        if (mounted) {
          setState(() {
            _userRole = role;
            _isLoadingUserData = false;
          });
        }

        widget.logger.i('✅ ScheduleScreen: User role fetched: $role');
      } else {
        widget.logger.w('⚠️ ScheduleScreen: User document not found');
        if (mounted) {
          setState(() {
            _userRole = 'Client';
            _isLoadingUserData = false;
          });
        }
      }
    } catch (e) {
      widget.logger.e('❌ ScheduleScreen: Error fetching user role: $e');
      if (mounted) {
        setState(() {
          _userRole = 'Client';
          _isLoadingUserData = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    widget.logger.d('📅 ScheduleScreen: Building UI, isMobile: $isMobile');

    // Show loading indicator while fetching user data
    if (_isLoadingUserData) {
      return BaseLayout(
        title: context.l10n.projectSectionTitle(widget.project.name, context.l10n.scheduleTitle),
        project: widget.project,
        logger: widget.logger,
        selectedMenuItem: 'Schedule',
        onMenuItemSelected: (_) {},
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Determine if user is a client
    final bool isClient = _userRole == 'Client';
    final bool isTechnician = _userRole == 'Technician';

    return BaseLayout(
      title: context.l10n.projectSectionTitle(widget.project.name, context.l10n.scheduleTitle),
      project: widget.project,
      logger: widget.logger,
      selectedMenuItem: 'Schedule',
      onMenuItemSelected: (_) {},
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      // Show TabBar only for Admin/MainAdmin users
                      if (!isClient)
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withValues(alpha: 0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TabBar(
                            // swipeable on phones so longer labels (e.g. Italian) never get cut off
                            isScrollable: MediaQuery.sizeOf(context).width < 600,
                            tabAlignment: MediaQuery.sizeOf(context).width < 600 ? TabAlignment.start : TabAlignment.fill,
                            controller: _tabController,
                            labelColor: AppColors.brandInk,
                            unselectedLabelColor: Colors.grey[600],
                            indicatorColor: AppColors.brandInk,
                            indicatorWeight: 3,
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                            unselectedLabelStyle: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                            ),
                            tabs: [
                              Tab(
                                icon: const Icon(Icons.description),
                                text: context.l10n.generalSchedule,
                              ),
                              Tab(
                                icon: const Icon(Icons.dashboard_customize),
                                text: context.l10n.dynamicSchedule,
                              ),
                            ],
                          ),
                        ),
                      SizedBox(
                        height: constraints.maxHeight -
                            (isClient ? 0 : 88) - // TabBar height only for non-clients
                            (isMobile ? 12 : 16) * 2 -
                            48, // Footer height
                        child: isClient
                            ? GeneralScheduleScreen(
                                project: widget.project,
                                logger: widget.logger,
                                isClient: true,
                                isTechnician: isTechnician,
                              )
                            : TabBarView(
                                controller: _tabController,
                                children: [
                                  GeneralScheduleScreen(
                                    project: widget.project,
                                    logger: widget.logger,
                                    isClient: false,
                                    isTechnician: isTechnician,
                                  ),
                                  DynamicScheduleScreen(
                                    project: widget.project,
                                    logger: widget.logger,
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                  _buildFooter(context),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      color: const Color(0xFF0A2E5A),
      child: Text(
        context.l10n.copyrightFooter,
        style: TextStyle(
          color: Colors.white,
          fontSize: isMobile ? 12 : 14,
          fontWeight: FontWeight.w400,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}