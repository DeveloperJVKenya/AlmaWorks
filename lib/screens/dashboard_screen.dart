import 'dart:async';
import 'package:almaworks/providers/selected_project_provider.dart';
import 'package:almaworks/rbacsystem/auth_service.dart';
import 'package:almaworks/rbacsystem/client_access_requests_screen.dart';
import 'package:almaworks/rbacsystem/client_request_model.dart';
import 'package:almaworks/rbacsystem/client_request_service.dart';
import 'package:almaworks/screens/account_screen.dart';
import 'package:almaworks/screens/projects/projects_main_screen.dart';
import 'package:almaworks/services/project_service.dart';
//import 'package:almaworks/widgets/activity_feed.dart';
import 'package:almaworks/widgets/task_progress_widget.dart';
import 'package:almaworks/widgets/dashboard_card.dart';
import 'package:almaworks/widgets/responsive_layout.dart';
import 'package:almaworks/widgets/weather_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:almaworks/main.dart' show localeProvider;

class DashboardScreen extends StatefulWidget {
  final Logger logger;
  
  const DashboardScreen({super.key, required this.logger});
  
  get projectId => null;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  int _projectsInitialTab = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final ProjectService _projectService;
  late final Logger _logger;
  late final ClientRequestService _requestService;
  String _userRole = '';
  bool _isLoadingRole = true;
  List<String> _grantedProjectIds = [];
  

  @override
  void initState() {
    super.initState();
    _logger = widget.logger;
    _projectService = ProjectService();
    _requestService = ClientRequestService();
    _logger.i('🗂️ DashboardScreen: Initialized with logger and project service');
    _fetchUserRoleAndAccess();
  }

  Future<void> _fetchUserRoleAndAccess() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _logger.e('❌ DashboardScreen: No authenticated user found');
        setState(() => _isLoadingRole = false);
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
        
        // If client, fetch granted project IDs
        List<String> grantedIds = [];
        if (role == 'Client') {
          grantedIds = await _requestService.getClientGrantedProjects(user.uid);
          _logger.i('✅ DashboardScreen: Client granted project IDs: $grantedIds');
        }
        
        setState(() {
          _userRole = role;
          _grantedProjectIds = grantedIds;
          _isLoadingRole = false;
        });
        
        _logger.i('✅ DashboardScreen: User role fetched: $role, Granted Projects: ${grantedIds.length}');
      } else {
        _logger.w('⚠️ DashboardScreen: User document not found');
        setState(() {
          _userRole = 'Client';
          _isLoadingRole = false;
        });
      }
    } catch (e) {
      _logger.e('❌ DashboardScreen: Error fetching user role: $e');
      setState(() {
        _userRole = 'Client';
        _isLoadingRole = false;
      });
    }
  }

  void navigateToProjects({int initialTab = 0}) {
    _logger.i('🧭 DashboardScreen: Navigating to projects with initial tab: $initialTab');
    
    setState(() {
      _selectedIndex = 1;
      _projectsInitialTab = initialTab;
    });
    
    _logger.d('✅ DashboardScreen: Successfully navigated to projects section with tab: $initialTab');
  }

  @override
  Widget build(BuildContext context) {
    _logger.d('🎨 DashboardScreen: Building with selectedIndex: $_selectedIndex');
    
    if (_isLoadingRole) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A2E5A),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              Text(
                'Loading Dashboard...',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // Check if client has access
    if (_userRole == 'Client') {
      return StreamBuilder<ClientRequest?>(
        stream: _requestService.getClientRequestStatus(
          FirebaseAuth.instance.currentUser!.uid
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              backgroundColor: const Color(0xFF0A2E5A),
              body: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            );
          }

          final request = snapshot.data;
          final hasAccess = request?.status == 'approved' && 
                           (request?.grantedProjects.isNotEmpty ?? false);

          if (!hasAccess) {
            return _buildAccessRequestScreen(request);
          }

          // Client has access, show normal dashboard with filtering
          return _buildMainDashboard();
        },
      );
    }
    
    // Admin/MainAdmin - show normal dashboard
    return _buildMainDashboard();
  }

  Widget _buildMainDashboard() {
    return ChangeNotifierProvider(
      create: (context) {
        _logger.d('🗂️ DashboardScreen: Creating SelectedProjectProvider');
        return SelectedProjectProvider();
      },
      child: Consumer<SelectedProjectProvider>(
        builder: (context, projectProvider, child) {
          _logger.d('🔄 DashboardScreen: Consumer rebuilding, hasSelectedProject: ${projectProvider.hasSelectedProject}');
          
          return ResponsiveLayout(
            mobile: _buildMobileLayout(projectProvider),
            tablet: _buildTabletLayout(projectProvider),
            desktop: _buildDesktopLayout(projectProvider),
          );
        },
      ),
    );
  }

  Widget _buildAccessRequestScreen(ClientRequest? request) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final authService = AuthService();
    bool isSubmitting = false;

    return StatefulBuilder(
      builder: (context, setModalState) {
        return Scaffold(
          backgroundColor: const Color(0xFF0A2E5A),
          appBar: AppBar(
            title: Text(
              'AlmaWorks',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            backgroundColor: const Color(0xFF0A2E5A),
            actions: [
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AccountScreen(localeProvider: localeProvider),
                    ),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.only(right: 16.0),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, size: 20, color: Color(0xFF0A2E5A)),
                  ),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 20.0 : 40.0),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.vpn_key,
                        size: isMobile ? 80 : 100,
                        color: Colors.white.withValues(alpha:0.9),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Welcome to AlmaWorks',
                        style: TextStyle(
                          fontSize: isMobile ? 24 : 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      if (request == null || request.status == 'denied')
                        _buildRequestAccessContent(
                          request, 
                          isMobile, 
                          isSubmitting, 
                          authService,
                          setModalState,
                        )
                      else if (request.status == 'pending')
                        _buildPendingRequestContent(isMobile),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRequestAccessContent(
    ClientRequest? request,
    bool isMobile,
    bool isSubmitting,
    AuthService authService,
    StateSetter setModalState,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha:0.1),
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(
                Icons.info_outline,
                size: 48,
                color: const Color(0xFF0A2E5A),
              ),
              const SizedBox(height: 16),
              Text(
                'Get Started',
                style: TextStyle(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0A2E5A),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'To access construction projects and collaborate with your team, you\'ll need to request access from our administrators.',
                style: TextStyle(
                  fontSize: isMobile ? 14 : 16,
                  color: Colors.grey[700],
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStepItem(
                      1,
                      'Click the button below to send your request',
                      Icons.touch_app,
                    ),
                    const SizedBox(height: 12),
                    _buildStepItem(
                      2,
                      'An administrator will review your request',
                      Icons.admin_panel_settings,
                    ),
                    const SizedBox(height: 12),
                    _buildStepItem(
                      3,
                      'You\'ll be notified once access is granted',
                      Icons.notifications_active,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (request?.status == 'denied')
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.orange[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange[300]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.orange[900]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Previous request was not approved',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[900],
                        ),
                      ),
                      if (request?.denialReason != null)
                        Text(
                          request!.denialReason!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange[800],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: isSubmitting
                ? null
                : () async {
                    setModalState(() => isSubmitting = true);

                    try {
                      final userData = await authService.getUserData();
                      if (userData == null) {
                        throw Exception('User data not found');
                      }

                      final error = await _requestService.submitClientRequest(
                        clientUsername: userData['username'],
                        clientEmail: userData['email'],
                        clientUid: userData['uid'],
                      );

                      if (!mounted) return;

                      if (error != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(error),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Access request sent successfully!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    } finally {
                      if (mounted) {
                        setModalState(() => isSubmitting = false);
                      }
                    }
                  },
            icon: isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.send),
            label: Text(isSubmitting ? 'Sending...' : 'Request Access'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0A2E5A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingRequestContent(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.pending_actions, size: 48, color: Colors.orange),
          const SizedBox(height: 16),
          Text(
            'Request Pending',
            style: TextStyle(
              fontSize: isMobile ? 20 : 24,
              fontWeight: FontWeight.bold,
              color: Colors.orange[700],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your access request is being reviewed by our administrators. You\'ll receive access once approved.',
            style: TextStyle(
              fontSize: isMobile ? 14 : 16,
              color: Colors.grey[700],
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem(int step, String text, IconData icon) {
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: const Color(0xFF0A2E5A),
          child: Text(
            '$step',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
        ),
      ],
    );
  }

  // ── Layout builders (unchanged) ─────────────────────────────────────────────

  Widget _buildMobileLayout(SelectedProjectProvider projectProvider) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('AlmaWorks', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF0A2E5A),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => AccountScreen(localeProvider: localeProvider)),
            ),
            child: const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 20, color: Color(0xFF0A2E5A)),
              ),
            ),
          ),
        ],
      ),
      drawer: _buildDrawer(projectProvider),
      body: _getSelectedScreen(projectProvider),
    );
  }

  Widget _buildTabletLayout(SelectedProjectProvider projectProvider) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AlmaWorks', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF0A2E5A),
        automaticallyImplyLeading: false,
        actions: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => AccountScreen(localeProvider: localeProvider)),
            ),
            child: const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 20, color: Color(0xFF0A2E5A)),
              ),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          SizedBox(width: 280, child: _buildSideNav(projectProvider)),
          const VerticalDivider(width: 1),
          Expanded(child: _getSelectedScreen(projectProvider)),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(SelectedProjectProvider projectProvider) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AlmaWorks', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF0A2E5A),
        automaticallyImplyLeading: false,
        actions: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => AccountScreen(localeProvider: localeProvider)),
            ),
            child: const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 20, color: Color(0xFF0A2E5A)),
              ),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          SizedBox(width: 300, child: _buildSideNav(projectProvider)),
          const VerticalDivider(width: 1),
          Expanded(child: _getSelectedScreen(projectProvider)),
        ],
      ),
    );
  }

  Widget _buildDrawer(SelectedProjectProvider projectProvider) {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF0A2E5A)),
            child: const Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                'AlmaWorks',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Expanded(
            child: _buildNavItems(projectProvider, padding: EdgeInsets.zero),
          ),
        ],
      ),
    );
  }

  Widget _buildSideNav(SelectedProjectProvider projectProvider) {
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: const Color(0xFF0A2E5A),
            child: const Text(
              'AlmaWorks',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: _buildNavItems(projectProvider)),
        ],
      ),
    );
  }

  Widget _buildNavItems(SelectedProjectProvider projectProvider, {EdgeInsets? padding}) {
    return ListView(
      padding: padding,
      children: [
        ListTile(
          leading: const Icon(Icons.dashboard),
          title: const Text('Dashboard'),
          selected: _selectedIndex == 0,
          onTap: () {
            _logger.i('🏠 DashboardScreen: Dashboard menu item tapped');
            setState(() { _selectedIndex = 0; });
            projectProvider.clearSelection();
            if (Navigator.canPop(context)) Navigator.pop(context);
          },
        ),
        ListTile(
          leading: const Icon(Icons.folder),
          title: const Text('Projects'),
          selected: _selectedIndex == 1,
          onTap: () {
            _logger.i('📁 DashboardScreen: Projects menu item tapped');
            setState(() { _selectedIndex = 1; _projectsInitialTab = 0; });
            if (Navigator.canPop(context)) Navigator.pop(context);
          },
        ),
        if (_userRole == 'MainAdmin' || _userRole == 'Admin')
          ListTile(
            leading: const Icon(Icons.supervised_user_circle),
            title: const Text('Client Access Requests'),
            selected: _selectedIndex == 2,
            onTap: () {
              _logger.i('👥 DashboardScreen: Client Access Requests tapped');
              setState(() { _selectedIndex = 2; });
              if (Navigator.canPop(context)) Navigator.pop(context);
            },
          ),
      ],
    );
  }

  Widget _getSelectedScreen(SelectedProjectProvider projectProvider) {
    _logger.d('🎯 DashboardScreen: Getting screen for index $_selectedIndex');
    
    try {
      switch (_selectedIndex) {
        case 0:
          return UnifiedDashboard(
            projectService: _projectService,
            logger: _logger,
            onNavigateToProjects: navigateToProjects,
            userRole: _userRole,
            grantedProjectIds: _grantedProjectIds,
          );
        case 1:
          _logger.d('✅ DashboardScreen: Returning ProjectsMainScreen');
          return ProjectsMainScreen(
            logger: _logger,
            initialTabIndex: _projectsInitialTab,
            clientProjectIds: _userRole == 'Client' ? _grantedProjectIds : null,
          );
        case 2:
          if (_userRole == 'MainAdmin' || _userRole == 'Admin') {
            _logger.d('✅ DashboardScreen: Returning ClientAccessRequestsScreen');
            return ClientAccessRequestsScreen(logger: _logger);
          } else {
            return UnifiedDashboard(
              projectService: _projectService,
              logger: _logger,
              onNavigateToProjects: navigateToProjects,
              userRole: _userRole,
              grantedProjectIds: _grantedProjectIds,
            );
          }
        default:
          return UnifiedDashboard(
            projectService: _projectService,
            logger: _logger,
            onNavigateToProjects: navigateToProjects,
            userRole: _userRole,
            grantedProjectIds: _grantedProjectIds,
          );
      }
    } catch (e, stackTrace) {
      _logger.e('❌ DashboardScreen: Error getting selected screen',
          error: e, stackTrace: stackTrace);
      return _buildErrorScreen('Error loading screen', e.toString());
    }
  }

  Widget _buildErrorScreen(String title, String error) {
    _logger.w('⚠️ DashboardScreen: Building error screen: $title');
    
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(error, style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _logger.i('🔄 DashboardScreen: Retry button pressed');
                setState(() { _selectedIndex = 0; });
              },
              child: const Text('Go to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _logger.i('🧹 DashboardScreen: Disposing resources');
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UnifiedDashboard  –  shown for all roles with role-based filtering
// ─────────────────────────────────────────────────────────────────────────────
class UnifiedDashboard extends StatefulWidget {
  final ProjectService projectService;
  final Logger logger;
  final Function({int initialTab}) onNavigateToProjects;
  final String userRole;
  final List<String> grantedProjectIds;

  const UnifiedDashboard({
    super.key,
    required this.projectService,
    required this.logger,
    required this.onNavigateToProjects,
    required this.userRole,
    required this.grantedProjectIds,
  });

  @override
  State<UnifiedDashboard> createState() => _UnifiedDashboardState();
}

class _UnifiedDashboardState extends State<UnifiedDashboard> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // ── Project locations for WeatherWidget ─────────────────────────────────────
  List<String> _projectLocations = [];
  StreamSubscription<QuerySnapshot>? _locationsSub;

  @override
  void initState() {
    super.initState();
    _subscribeToProjectLocations();
  }

  /// Streams project documents from Firestore and extracts the 'location' field.
  /// Clients only see locations for their granted projects.
  void _subscribeToProjectLocations() {
    final query = FirebaseFirestore.instance.collection('Projects');

    _locationsSub = query.snapshots().listen((snapshot) {
      final locations = <String>[];
      for (final doc in snapshot.docs) {
        // For clients, only include granted project locations
        if (_isClient && !widget.grantedProjectIds.contains(doc.id)) continue;

        final data = doc.data();
        final loc  = data['location'] as String?;
        if (loc != null && loc.trim().isNotEmpty) {
          locations.add(loc.trim());
        }
      }
      if (mounted) {
        setState(() => _projectLocations = locations.toSet().toList());
      }
    }, onError: (e) {
      widget.logger.e('❌ UnifiedDashboard: Error streaming project locations: $e');
    });
  }

  @override
  void dispose() {
    _locationsSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  bool get _isClient => widget.userRole == 'Client';

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile  = screenWidth < 600;
    final isTablet  = screenWidth >= 600 && screenWidth < 1200;
    final isDesktop = screenWidth >= 1200;

    widget.logger.d('🗂️ UnifiedDashboard: Building dashboard, isClient: $_isClient, grantedProjects: ${widget.grantedProjectIds.length}');

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(isMobile ? 12 : 16),
            child: Text(
              _isClient ? 'My Projects Overview' : 'General Overview',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          _buildMetricsGrid(context),
          const SizedBox(height: 16),
          _buildContentSection(context, isMobile, isTablet, isDesktop),
          const SizedBox(height: 16),
          _buildFooter(context, isMobile),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    widget.logger.d('📊 UnifiedDashboard: Building metrics grid');

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
      child: Row(
        children: [
          Expanded(
            child: FutureBuilder<int>(
              future: _safeGetProjectCount(
                () => _isClient
                    ? widget.projectService.getClientProjectsCount(widget.grantedProjectIds)
                    : widget.projectService.getAllProjectsCount(),
                'total',
              ),
              builder: (context, snapshot) {
                return DashboardCard(
                  title: 'Total Projects',
                  value: snapshot.hasData ? '${snapshot.data}' : (snapshot.hasError ? '0' : '...'),
                  icon: Icons.folder,
                  color: Colors.blue,
                  onTap: () {
                    widget.logger.i('👆 Dashboard: Total projects card tapped');
                    widget.onNavigateToProjects(initialTab: 0);
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FutureBuilder<int>(
              future: _safeGetProjectCount(
                () => _isClient
                    ? widget.projectService.getClientActiveProjectsCount(widget.grantedProjectIds)
                    : widget.projectService.getProjectCountByStatus('active'),
                'active',
              ),
              builder: (context, snapshot) {
                return DashboardCard(
                  title: 'Active Projects',
                  value: snapshot.hasData ? '${snapshot.data}' : (snapshot.hasError ? '0' : '...'),
                  icon: Icons.work,
                  color: Colors.green,
                  onTap: () {
                    widget.logger.i('👆 Dashboard: Active projects card tapped');
                    widget.onNavigateToProjects(initialTab: 1);
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FutureBuilder<int>(
              future: _safeGetProjectCount(
                () => _isClient
                    ? widget.projectService.getClientCompletedProjectsCount(widget.grantedProjectIds)
                    : widget.projectService.getProjectCountByStatus('completed'),
                'completed',
              ),
              builder: (context, snapshot) {
                return DashboardCard(
                  title: 'Completed Projects',
                  value: snapshot.hasData ? '${snapshot.data}' : (snapshot.hasError ? '0' : '...'),
                  icon: Icons.check_circle,
                  color: Colors.orange,
                  onTap: () {
                    widget.logger.i('👆 Dashboard: Completed projects card tapped');
                    widget.onNavigateToProjects(initialTab: 2);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<int> _safeGetProjectCount(Future<int> Function() getCount, String type) async {
    try {
      widget.logger.d('🔢 Dashboard: Getting $type project count');
      final count = await getCount();
      widget.logger.i('✅ Dashboard: $type project count retrieved: $count');
      return count;
    } catch (e) {
      widget.logger.e('❌ Dashboard: Error getting $type project count: $e');
      return 0;
    }
  }

  Widget _buildContentSection(BuildContext context, bool isMobile, bool isTablet, bool isDesktop) {
    final screenWidth  = MediaQuery.of(context).size.width;
    final sidebarWidth = isMobile ? 0 : (isTablet ? 280 : 300);
    final availableWidth = screenWidth - sidebarWidth - (isMobile ? 24 : 32);
    const double widgetHeight = 400.0;

    widget.logger.d('🗳️ Dashboard: Building content section, isClient: $_isClient, projectLocations: ${_projectLocations.length}');

    // ── ActivityFeed, TaskProgressWidget, and WeatherWidget ─────────────────
    final widgets = [
      SizedBox(
        width: availableWidth,
        height: widgetHeight,
        // Task Progress Widget: shows done-ongoing (top) and done-completed (bottom)
        // tasks sourced from the TaskProgressMonitor collection, across all projects
        // the current user is permitted to see.
        child: TaskProgressWidget(
          showAllProjects: true,
          projectIds: _isClient ? widget.grantedProjectIds : [],
          logger: widget.logger,
          // 4 items visible before "View All" – fits comfortably in the 400px card
          maxInitialDisplay: 4,
          // Show per-project phase percentages grouped above the task list.
          // Each project's phases are listed under a folder-icon project header.
          showPhaseBreakdown: true,
        ),
      ),
      SizedBox(
        width: availableWidth,
        height: widgetHeight,
        // Pass all project locations so WeatherWidget fetches each site's weather
        child: WeatherWidget(
          projectLocations: _projectLocations,
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
              physics: const BouncingScrollPhysics(),
              pageSnapping: true,
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
                    child: const Icon(Icons.arrow_left, color: Colors.white, size: 30),
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
                    child: const Icon(Icons.arrow_right, color: Colors.white, size: 30),
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

  Widget _buildFooter(BuildContext context, bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      color: const Color(0xFF0A2E5A),
      child: Text(
        '© 2026 JV Alma C.I.S Site Management System',
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