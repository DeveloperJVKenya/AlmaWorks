import 'dart:async';
import 'package:almaworks/providers/selected_project_provider.dart';
import 'package:almaworks/rbacsystem/auth_service.dart';
import 'package:almaworks/rbacsystem/client_access_requests_screen.dart';
import 'package:almaworks/rbacsystem/client_request_model.dart';
import 'package:almaworks/rbacsystem/client_request_service.dart';
import 'package:almaworks/rbacsystem/notification_service.dart';
import 'package:almaworks/screens/account_screen.dart';
import 'package:almaworks/screens/projects/projects_main_screen.dart';
import 'package:almaworks/services/project_service.dart';
import 'package:almaworks/widgets/task_progress_widget.dart';
import 'package:almaworks/widgets/dashboard_card.dart';
import 'package:almaworks/widgets/responsive_layout.dart';
import 'package:almaworks/widgets/weather_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:almaworks/screens/settings/settings_screen.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/theme/app_colors.dart';
import 'package:almaworks/core/errors/friendly_error.dart';

class DashboardScreen extends StatefulWidget {
  final Logger logger;
  
  const DashboardScreen({super.key, required this.logger});
  
  Null get projectId => null;

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
  // Live instead of a one-shot get() — see BaseLayout's identical fix for
  // why a role change needs to reach every gated widget without requiring a
  // screen teardown/rebuild.
  StreamSubscription<QuerySnapshot>? _userDocSub;
  String? _notificationListenersSetUpForRole;


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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _logger.e('❌ DashboardScreen: No authenticated user found');
      setState(() => _isLoadingRole = false);
      return;
    }

    _userDocSub?.cancel();
    _userDocSub = FirebaseFirestore.instance
        .collection('Users')
        .where('uid', isEqualTo: user.uid)
        .limit(1)
        .snapshots()
        .listen((querySnapshot) async {
      if (querySnapshot.docs.isNotEmpty) {
        final userData = querySnapshot.docs.first.data();
        final role = userData['role'] as String? ?? 'Client';

        // Client, Technician, and SubContractor are all restricted to
        // their granted project list — Technician sees Admin-equivalent
        // sections once inside one, SubContractor sees Documents-only for
        // their own uploads (see BaseLayout for that split).
        List<String> grantedIds = [];
        if (role == 'Client' || role == 'Technician' || role == 'SubContractor') {
          grantedIds = await _requestService.getClientGrantedProjects(user.uid);
          _logger.i('✅ DashboardScreen: $role granted project IDs: $grantedIds');
        }

        // The notification-listener setup below opens its own long-lived
        // Firestore subscriptions inside NotificationService — only redo it
        // when the role actually changes, not on every incidental emission
        // of this Users-doc stream (e.g. an unrelated field edit), to avoid
        // stacking duplicate listeners.
        if (_notificationListenersSetUpForRole != role) {
          _notificationListenersSetUpForRole = role;

          // Persists this device's FCM token to the signed-in user's Users
          // doc (fcmToken/fcmTokens — see NotificationService._persistFcmToken)
          // so the onAdminNotificationQueued/onUserNotificationQueued Cloud
          // Functions have something to actually send a push to. This was
          // never being called anywhere in the app — _persistFcmToken
          // early-returns if FirebaseAuth.instance.currentUser is null, so
          // calling it at cold app start (before login) wouldn't have worked
          // either; here, right where `user` is already confirmed signed in,
          // is the correct place. Root cause of Inventory checkout/return
          // pushes never reaching devices: the queue docs and Cloud
          // Functions were always correct, but every device's token field
          // was empty, so there was never anything to send to.
          await NotificationService().initialize();

          // ── Admin / MainAdmin / SystemAdmin: attach the AdminNotificationQueue listener ──
          if (role == 'Admin' || role == 'MainAdmin' || role == 'SystemAdmin') {
            await NotificationService().setupAdminNotificationListener(user.uid, role: role);
            _logger.i(
              '🔔 DashboardScreen: Admin notification listener started for $role (uid: ${user.uid})',
            );
          }

          // ── Every role: attach the per-user targeted listener — e.g. a
          // Technician or Admin holding a booked asset needs to be notified
          // directly when someone else books it for an upcoming date,
          // regardless of their own role's broadcast-queue access. ──
          await NotificationService().setupUserNotificationListener(user.uid);
        }

        if (!mounted) return;
        setState(() {
          _userRole = role;
          _grantedProjectIds = grantedIds;
          _isLoadingRole = false;
        });

        _logger.i('✅ DashboardScreen: User role updated: $role, Granted Projects: ${grantedIds.length}');
      } else {
        _logger.w('⚠️ DashboardScreen: User document not found');
        if (!mounted) return;
        setState(() {
          _userRole = 'Client';
          _isLoadingRole = false;
        });
      }
    }, onError: (e) {
      _logger.e('❌ DashboardScreen: Error streaming user role: $e');
      if (!mounted) return;
      setState(() {
        _userRole = 'Client';
        _isLoadingRole = false;
      });
    });
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
        backgroundColor: AppColors.navy,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              Text(
                context.l10n.loadingDashboard,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // Check if the account has access — Technician and SubContractor both
    // go through the exact same request/approval flow as Client (see
    // ClientRequestService) and are just as capable of having every
    // project revoked, so they need the same "no access yet / pending /
    // all revoked" gate, not just Client.
    if (_userRole == 'Client' || _userRole == 'Technician' || _userRole == 'SubContractor') {
      return StreamBuilder<ClientRequest?>(
        stream: _requestService.getClientRequestStatus(
          FirebaseAuth.instance.currentUser!.uid
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              backgroundColor: AppColors.navy,
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
          backgroundColor: AppColors.navy,
          appBar: AppBar(
            title: Text(
              'AlmaWorks',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            backgroundColor: AppColors.navy,
            actions: [
              _settingsButton(context),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AccountScreen(),
                    ),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.only(right: 16.0),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, size: 20, color: AppColors.navy),
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
                        context.l10n.welcomeToAlmaWorks,
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
            color: AppColors.surface,
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
                color: AppColors.brandInk,
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.getStarted,
                style: TextStyle(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brandInk,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.requestAccessIntro,
                style: TextStyle(
                  fontSize: isMobile ? 14 : 16,
                  color: AppColors.inkMuted,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStepItem(
                      1,
                      context.l10n.requestAccessStep1,
                      Icons.touch_app,
                    ),
                    const SizedBox(height: 12),
                    _buildStepItem(
                      2,
                      context.l10n.requestAccessStep2,
                      Icons.admin_panel_settings,
                    ),
                    const SizedBox(height: 12),
                    _buildStepItem(
                      3,
                      context.l10n.requestAccessStep3,
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
              color: AppColors.warningTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: AppColors.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.previousRequestDenied,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.warning,
                        ),
                      ),
                      if (request?.denialReason != null)
                        Text(
                          request!.denialReason!,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.ink,
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
                        throw UserFacingException(l10nNow.profileNotFound);
                      }

                      final error = await _requestService.submitClientRequest(
                        clientUsername: userData['username'],
                        clientEmail: userData['email'],
                        clientUid: userData['uid'],
                      );

                      if (!mounted) return;

                      if (error != null) {
                        showWarningSnack(context, error);
                      } else {
                        showSuccessSnack(context, context.l10n.accessRequestSent);
                      }
                    } catch (e) {
                      _logger.e('❌ DashboardScreen: access request failed', error: e);
                      if (!mounted) return;
                      showErrorSnack(context, e, action: context.l10n.couldNotSendAccessRequest);
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
            label: Text(isSubmitting ? context.l10n.sending : context.l10n.requestAccess),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.navy,
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
        color: AppColors.surface,
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
            context.l10n.requestPending,
            style: TextStyle(
              fontSize: isMobile ? 20 : 24,
              fontWeight: FontWeight.bold,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.requestPendingMessage,
            style: TextStyle(
              fontSize: isMobile ? 14 : 16,
              color: AppColors.inkMuted,
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
          backgroundColor: AppColors.navy,
          child: Text(
            '$step',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        Icon(icon, size: 20, color: AppColors.inkMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: AppColors.ink),
          ),
        ),
      ],
    );
  }

  Widget _settingsButton(BuildContext context) => IconButton(
    icon: const Icon(Icons.settings_rounded, color: Colors.white),
    tooltip: context.l10n.settings,
    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
  );

  // ── Layout builders ─────────────────────────────────────────────────────────

  Widget _buildMobileLayout(SelectedProjectProvider projectProvider) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('AlmaWorks', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: AppColors.navy,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          _settingsButton(context),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AccountScreen()),
            ),
            child: const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 20, color: AppColors.navy),
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
        backgroundColor: AppColors.navy,
        automaticallyImplyLeading: false,
        actions: [
          _settingsButton(context),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AccountScreen()),
            ),
            child: const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 20, color: AppColors.navy),
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
        backgroundColor: AppColors.navy,
        automaticallyImplyLeading: false,
        actions: [
          _settingsButton(context),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AccountScreen()),
            ),
            child: const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 20, color: AppColors.navy),
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
            decoration: const BoxDecoration(color: AppColors.navy),
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
      color: AppColors.surfaceAlt,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: AppColors.navy,
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
    return Material(
      color: Colors.transparent,
      child: ListView(
      padding: padding,
      children: [
        ListTile(
          leading: const Icon(Icons.dashboard),
          title: Text(context.l10n.navDashboard),
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
          title: Text(context.l10n.navProjects),
          selected: _selectedIndex == 1,
          onTap: () {
            _logger.i('📁 DashboardScreen: Projects menu item tapped');
            setState(() { _selectedIndex = 1; _projectsInitialTab = 0; });
            if (Navigator.canPop(context)) Navigator.pop(context);
          },
        ),
        // SystemAdmin now has the same access here as MainAdmin (equal
        // grant/approve/deny/edit-role actions — see
        // ClientAccessRequestsScreen's _grantableRoleOptions/canGrantAdmin),
        // the one exception being that nobody, including SystemAdmin, can
        // ever touch a MainAdmin's own role (enforced independently in
        // that screen regardless of caller).
        if (_userRole == 'MainAdmin' || _userRole == 'Admin' || _userRole == 'SystemAdmin')
          ListTile(
            leading: const Icon(Icons.supervised_user_circle),
            title: Text(context.l10n.navClientAccessRequests),
            selected: _selectedIndex == 2,
            onTap: () {
              _logger.i('👥 DashboardScreen: Client Access Requests tapped');
              setState(() { _selectedIndex = 2; });
              if (Navigator.canPop(context)) Navigator.pop(context);
            },
          ),
      ],
      ),
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
            clientProjectIds:
                (_userRole == 'Client' || _userRole == 'Technician' || _userRole == 'SubContractor')
                    ? _grantedProjectIds
                    : null,
          );
        case 2:
          // SystemAdmin included — see the matching menu-tile guard above.
          if (_userRole == 'MainAdmin' || _userRole == 'Admin' || _userRole == 'SystemAdmin') {
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
      return _buildErrorScreen(context.l10n.couldNotLoadScreen, friendlyError(e));
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
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(error, style: TextStyle(color: AppColors.inkMuted), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _logger.i('🔄 DashboardScreen: Retry button pressed');
                setState(() { _selectedIndex = 0; });
              },
              child: Text(context.l10n.goToDashboard),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _logger.i('🧹 DashboardScreen: Disposing resources');
    // Cancel the AdminNotificationQueue/UserNotificationQueue Firestore
    // listeners so they do not fire after logout or when the widget is
    // removed from the tree. Safe to call regardless of role — the service
    // ignores no-op cancels.
    NotificationService().cancelAdminNotificationListener();
    NotificationService().cancelUserNotificationListener();
    _userDocSub?.cancel();
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
        if (_isRestrictedRole && !widget.grantedProjectIds.contains(doc.id)) continue;

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

  // Client and Technician are both scoped to widget.grantedProjectIds —
  // they only differ in which sections they see once inside a project
  // (handled in BaseLayout), not in the dashboard's own project filtering.
  bool get _isRestrictedRole => widget.userRole == 'Client' || widget.userRole == 'Technician';

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile  = screenWidth < 600;
    final isTablet  = screenWidth >= 600 && screenWidth < 1200;
    final isDesktop = screenWidth >= 1200;

    widget.logger.d('🗂️ UnifiedDashboard: Building dashboard, isClient: $_isRestrictedRole, grantedProjects: ${widget.grantedProjectIds.length}');

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(isMobile ? 12 : 16),
            child: Text(
              _isRestrictedRole ? context.l10n.myProjectsOverview : context.l10n.generalOverview,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.ink),
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
                () => _isRestrictedRole
                    ? widget.projectService.getClientProjectsCount(widget.grantedProjectIds)
                    : widget.projectService.getAllProjectsCount(),
                'total',
              ),
              builder: (context, snapshot) {
                return DashboardCard(
                  title: context.l10n.totalProjects,
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
                () => _isRestrictedRole
                    ? widget.projectService.getClientActiveProjectsCount(widget.grantedProjectIds)
                    : widget.projectService.getProjectCountByStatus('active'),
                'active',
              ),
              builder: (context, snapshot) {
                return DashboardCard(
                  title: context.l10n.activeProjects,
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
                () => _isRestrictedRole
                    ? widget.projectService.getClientCompletedProjectsCount(widget.grantedProjectIds)
                    : widget.projectService.getProjectCountByStatus('completed'),
                'completed',
              ),
              builder: (context, snapshot) {
                return DashboardCard(
                  title: context.l10n.completedProjects,
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

    widget.logger.d('🗳️ Dashboard: Building content section, isClient: $_isRestrictedRole, projectLocations: ${_projectLocations.length}');

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
          projectIds: _isRestrictedRole ? widget.grantedProjectIds : [],
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
                    heroTag: null,
                    tooltip: context.l10n.previous,
                    backgroundColor: AppColors.navy,
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
                    heroTag: null,
                    tooltip: context.l10n.next,
                    backgroundColor: AppColors.navy,
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
                        ? AppColors.brandInk
                        : AppColors.inkFaint.withValues(alpha: 0.5),
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
      color: AppColors.navy,
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