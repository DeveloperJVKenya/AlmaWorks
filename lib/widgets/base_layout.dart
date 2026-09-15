import 'dart:async';

import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/rbacsystem/auth_service.dart';
import 'package:almaworks/rbacsystem/client_request_service.dart';
import 'package:almaworks/screens/communication/communication_screen.dart';
import 'package:almaworks/screens/financial_screen.dart';
import 'package:almaworks/screens/photo_gallery_screen.dart';
import 'package:almaworks/screens/photos_screen.dart';
import 'package:almaworks/screens/projects/projects_main_screen.dart';
import 'package:almaworks/screens/documents_screen.dart';
import 'package:almaworks/screens/drawings_screen.dart';
import 'package:almaworks/screens/inventory/inventory_screen.dart';
import 'package:almaworks/screens/notifications_screen.dart';
import 'package:almaworks/screens/quality_and_safety_screen.dart';
import 'package:almaworks/screens/reports/reports_screen.dart';
import 'package:almaworks/screens/safety_training/safety_training_screen.dart';
import 'package:almaworks/screens/schedule/schedule_screen.dart';
import 'package:almaworks/screens/schedule/task_progress_monitor_screen.dart'; // ← ADDED
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// The sidebar now switches its own surface/text colors with the app theme
// instead of staying permanently white — it used to hardcode `color:
// Colors.white` (see _buildSidebar) while menu item labels left their color
// unset, so titles silently inherited the *ambient* theme's default text
// color: near-black under light (fine, coincidentally correct), near-white
// under dark — on a sidebar that was still hardcoded white, i.e. invisible
// white-on-white text. Rather than keep the sidebar permanently light (a
// workaround, not what a "dark mode" toggle should mean), both the surface
// and every text/icon color below now branch on Theme.of(context).brightness.
const _sidebarSurfaceLight = Colors.white;
const _sidebarSurfaceDark = Color(0xFF1E1E1E);

// Bolder + brighter than a plain light-blue would be washed out against
// _sidebarSurfaceDark, per feedback that dark-mode sidebar text needed more
// visual weight generally, not just to be technically visible.
const _sidebarSelectedTextColorLight = Color(0xFF0A2E5A);
const _sidebarSelectedTextColorDark = Color(0xFF82B1FF);
const _sidebarTextColorLight = Color(0xFF37474F);
const _sidebarTextColorDark = Color(0xFFECEFF1);

/// Route name tagged on ProjectSummaryScreen's push (see
/// projects_main_screen.dart) so BaseLayout's sidebar can pop back to it
/// specifically from any section, instead of the old pushReplacement that
/// silently discarded it from the stack — see _goToProjectSummary/
/// _goToSection below.
const projectSummaryRouteName = '/projectSummary';

class BaseLayout extends StatefulWidget {
  final Widget child;
  final String title;
  final ProjectModel? project;
  final Logger logger;
  final String selectedMenuItem;
  final Function(String) onMenuItemSelected;
  final Widget? floatingActionButton;
  final List<Widget>? actions;

  const BaseLayout({
    super.key,
    required this.child,
    required this.title,
    this.project,
    required this.logger,
    required this.selectedMenuItem,
    required this.onMenuItemSelected,
    this.floatingActionButton,
    this.actions,
  });

  @override
  State<BaseLayout> createState() => _BaseLayoutState();
}

class _BaseLayoutState extends State<BaseLayout> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _userRole;
  List<String>? _clientProjectIds;
  bool _isLoadingUserData = true;
  final ClientRequestService _requestService = ClientRequestService();
  final AuthService _authService = AuthService();

  // Bell icon badge — merges UserNotificationQueue (by uid),
  // AdminNotificationQueue (by role), and ScheduleNotifications (by uid),
  // the same three sources NotificationsScreen itself reads (see
  // notifications_screen.dart). Lives here (not per-screen) so the badge is
  // correct everywhere, since BaseLayout wraps every screen in the app.
  int _unreadUserCount = 0;
  int _unreadAdminCount = 0;
  int _unreadScheduleCount = 0;
  StreamSubscription<QuerySnapshot>? _unreadUserSub;
  StreamSubscription<QuerySnapshot>? _unreadAdminSub;
  StreamSubscription<QuerySnapshot>? _unreadScheduleSub;

  // Live instead of a one-shot get() — a role changed directly in Firestore
  // (or a slow mirror sync) now reflects here, and in every role-gated
  // widget downstream, without requiring the screen to be torn down and
  // rebuilt. Previously this was a single get() in _fetchUserRoleAndAccess,
  // which is exactly why a role change could leave stale permissions
  // ("hanging" gates) visible for the rest of the session.
  StreamSubscription<QuerySnapshot>? _userDocSub;

  int get _unreadNotificationCount => _unreadUserCount + _unreadAdminCount + _unreadScheduleCount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchUserRoleAndAccess();
      // Project Summary is the anchor every section's back button now
      // returns to (see _goToSection/_goToProjectSummary below) — opening
      // the drawer here on mobile means arriving back at it (by back
      // button or by tapping Overview) always surfaces the section menu
      // immediately, mirroring the persistent side panel larger screens
      // already show for free.
      if (mounted && widget.selectedMenuItem == 'Overview' && MediaQuery.of(context).size.width < 600) {
        _scaffoldKey.currentState?.openDrawer();
      }
    });
  }

  void _subscribeNotificationBadge(String uid, String role) {
    _unreadUserSub?.cancel();
    _unreadAdminSub?.cancel();
    _unreadScheduleSub?.cancel();
    _unreadUserSub = FirebaseFirestore.instance
        .collection('UserNotificationQueue')
        .where('targetUid', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() => _unreadUserCount = snap.docs.where((d) => (d.data()['isRead'] as bool?) != true).length);
    }, onError: (e) => widget.logger.e('❌ BaseLayout: user notification badge stream error', error: e));

    _unreadAdminSub = FirebaseFirestore.instance
        .collection('AdminNotificationQueue')
        .where('targetRoles', arrayContains: role)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() => _unreadAdminCount = snap.docs.where((d) => (d.data()['isRead'] as bool?) != true).length);
    }, onError: (e) => widget.logger.e('❌ BaseLayout: admin notification badge stream error', error: e));

    _unreadScheduleSub = FirebaseFirestore.instance
        .collection('ScheduleNotifications')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() => _unreadScheduleCount = snap.docs.where((d) => (d.data()['isRead'] as bool?) != true).length);
    }, onError: (e) => widget.logger.e('❌ BaseLayout: schedule notification badge stream error', error: e));
  }

  Future<void> _fetchUserRoleAndAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      widget.logger.e('❌ BaseLayout: No authenticated user found');
      if (mounted) {
        setState(() {
          _isLoadingUserData = false;
        });
      }
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
        final username = querySnapshot.docs.first.id;
        final role = userData['role'] as String? ?? 'Client';

        // Keep UserRoles/{uid} in sync on every emission, not just at
        // login — persisted sessions skip login_screen.dart entirely on app
        // restart (see main.dart's isLoggedIn fast-path), so this is the
        // only place guaranteed to run for an already-signed-in user. This
        // is what lets a pre-existing account (or one whose role was just
        // changed directly in Users) stop being gated out of role-restricted
        // features like Inventory without needing to log out and back in.
        //
        // Fire-and-forget again (not awaited): awaiting this here previously
        // meant every single navigation in the ENTIRE app — not just
        // Inventory — paid for a full extra Firestore round trip (this
        // write's own rules cross-check does a get() before the set())
        // behind BaseLayout's full-screen loading gate below, which is what
        // made every "Add" button feel like it hung. The race this exists
        // to prevent only matters for Inventory's own Firestore listeners,
        // so that wait now lives in inventory_providers.dart's
        // roleMirrorSyncProvider instead, scoped to just the Inventory
        // screen's content area — everywhere else stays instant.
        unawaited(_authService.ensureUserRoleMirror(uid: user.uid, username: username, role: role));

        // Technician is granted through the exact same request/approval
        // flow as Client (see ClientAccessRequestsScreen's role selector)
        // and is restricted to the same granted-project list — the two
        // roles only differ in which sections they see once inside a
        // project, not in how project access itself is scoped.
        List<String> grantedIds = [];
        if (role == 'Client' || role == 'Technician') {
          grantedIds =
              await _requestService.getClientGrantedProjects(user.uid);
          widget.logger
              .i('✅ BaseLayout: $role granted project IDs: $grantedIds');
        }

        if (mounted) {
          setState(() {
            _userRole = role;
            _clientProjectIds = (role == 'Client' || role == 'Technician') ? grantedIds : null;
            _isLoadingUserData = false;
          });
        }
        _subscribeNotificationBadge(user.uid, role);

        widget.logger.i(
            '✅ BaseLayout: User role updated: $role, Granted Projects: ${grantedIds.length}');
      } else {
        widget.logger.w('⚠️ BaseLayout: User document not found');
        if (mounted) {
          setState(() {
            _userRole = 'Client';
            _isLoadingUserData = false;
          });
        }
      }
    }, onError: (e) {
      widget.logger.e('❌ BaseLayout: Error streaming user role: $e');
      if (mounted) {
        setState(() {
          _userRole = 'Client';
          _isLoadingUserData = false;
        });
      }
    });
  }

  void _goToProjectSummary(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.settings.name == projectSummaryRouteName || route.isFirst);
  }

  /// Section switch (Documents, Drawings, Schedule, ...): pop back to
  /// Project Summary first (discarding whatever section was open, same as
  /// the old pushReplacement did) then push the new section on top of it —
  /// unlike pushReplacement, this never discards Project Summary itself, so
  /// the system back button from any section always returns there instead
  /// of skipping past the whole project.
  void _goToSection(BuildContext context, Widget Function() builder) {
    _goToProjectSummary(context);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => builder()));
  }

  @override
  void dispose() {
    _unreadUserSub?.cancel();
    _unreadAdminSub?.cancel();
    _unreadScheduleSub?.cancel();
    _userDocSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 1200;

    if (_isLoadingUserData) {
      return Scaffold(
        key: _scaffoldKey,
        appBar: _buildAppBar(context),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: _buildAppBar(context),
      drawer: isMobile ? _buildDrawer(context) : null,
      body: Row(
        children: [
          if (!isMobile) _buildSidebar(context, isTablet),
          Expanded(child: widget.child),
        ],
      ),
      floatingActionButton: widget.floatingActionButton,
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: Text(
        widget.title,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      centerTitle: true,
      backgroundColor: const Color(0xFF0A2E5A),
      foregroundColor: Colors.white,
      actions: [
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => NotificationsScreen(logger: widget.logger)),
              ),
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Notifications',
            ),
            if (_unreadNotificationCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    _unreadNotificationCount > 99 ? '99+' : '$_unreadNotificationCount',
                    style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
        // Technician gets nothing in the appbar besides the notification
        // bell above, app-wide (not just Inventory) — every section routes
        // through this one shared appbar builder, so this single branch is
        // enough to guarantee it regardless of what any given screen passes
        // as `actions`.
        if (_userRole != 'Technician' && widget.actions != null) ...widget.actions!,
      ],
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: _buildSidebarContent(context),
    );
  }

  Widget _buildSidebar(BuildContext context, bool isTablet) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: isTablet ? 280 : 300,
      decoration: BoxDecoration(
        color: isDark ? _sidebarSurfaceDark : _sidebarSurfaceLight,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
            blurRadius: 4,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: _buildSidebarContent(context),
    );
  }

  Widget _buildSidebarContent(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final bool isClient = _userRole == 'Client';
    // Technician sees the same section set Admin does (everything except
    // Financials — Inventory stays visible since Technicians can read +
    // request checkouts there), but — like Client — is restricted to only
    // their granted projects. Since every `_buildProtectedMenuItem` call
    // below already shows to "everyone" by default and only Client gets an
    // explicit exclusion (Financials being the one exception), Technician
    // automatically inherits Admin's section visibility with zero further
    // changes there; the two places that DO need to know about Technician
    // are the granted-project restriction (isRestrictedRole below) and the
    // Financials exclusion.
    final bool isTechnician = _userRole == 'Technician';
    // Sub-contractor: Documents-only (their own uploads, on their granted
    // project(s)) per requirement — everything else in the sidebar below
    // is hidden for them, and they share the same granted-project
    // restriction Client/Technician already have.
    final bool isSubContractor = _userRole == 'SubContractor';
    final bool isRestrictedRole = isClient || isTechnician || isSubContractor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ColoredBox(
      color: isDark ? _sidebarSurfaceDark : _sidebarSurfaceLight,
      child: Column(
        children: [
        Container(
          height: 120,
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFF0A2E5A),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  widget.project?.name ?? 'AlmaWorks',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  isClient ? 'My Project Dashboard' : 'Project Dashboard',
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          // Material(color: transparent) gives ListTile's selectedTileColor/
          // ink-splash an explicit canvas-type Material ancestor — without
          // it, Flutter can't guarantee the tile's background/splash paints
          // visibly and logs "ListTile background color or ink splashes may
          // be invisible" on every build (harmless visually here, but noisy).
          child: Material(
            color: Colors.transparent,
            child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // ── Switch Project ────────────────────────────────────────────
              ListTile(
                leading: const Icon(Icons.swap_horiz, color: Colors.blueGrey),
                title: Text(
                  isRestrictedRole ? 'My Projects' : 'Switch Project',
                  style: GoogleFonts.poppins(
                    color: widget.selectedMenuItem == 'Switch Project'
                        ? (isDark ? _sidebarSelectedTextColorDark : _sidebarSelectedTextColorLight)
                        : (isDark ? _sidebarTextColorDark : _sidebarTextColorLight),
                    fontWeight: widget.selectedMenuItem == 'Switch Project' ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                selected: widget.selectedMenuItem == 'Switch Project',
                selectedTileColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.blueGrey[50],
                onTap: () {
                  widget.logger.i(
                      '🧭 BaseLayout: Switch Project selected, role: $_userRole');
                  if (isMobile) Navigator.pop(context);

                  // Leaving the project entirely — discard the whole
                  // "inside a project" stack (Project Summary and any
                  // section on top of it) down to the app's root screen,
                  // then push a fresh Projects list on top of THAT (not
                  // pushReplacement — replacing the root route itself would
                  // leave nothing for back-navigation to land on).
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ProjectsMainScreen(
                        logger: widget.logger,
                        clientProjectIds:
                            isRestrictedRole ? _clientProjectIds : null,
                      ),
                    ),
                  );
                },
              ),

              // ── Overview (not Sub-contractor — Documents-only for now) ──────
              if (!isSubContractor)
              ListTile(
                leading: const Icon(Icons.dashboard, color: Colors.indigo),
                title: Text(
                  'Overview',
                  style: GoogleFonts.poppins(
                    color: widget.selectedMenuItem == 'Overview'
                        ? (isDark ? _sidebarSelectedTextColorDark : _sidebarSelectedTextColorLight)
                        : (isDark ? _sidebarTextColorDark : _sidebarTextColorLight),
                    fontWeight: widget.selectedMenuItem == 'Overview' ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                selected: widget.selectedMenuItem == 'Overview',
                selectedTileColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.blueGrey[50],
                onTap: () {
                  widget.logger.i('🧭 BaseLayout: Overview selected');
                  if (isMobile) Navigator.pop(context);
                  if (widget.project != null) {
                    if (isRestrictedRole &&
                        _clientProjectIds != null &&
                        !_clientProjectIds!.contains(widget.project!.id)) {
                      widget.logger.w(
                          '⚠️ BaseLayout: $_userRole attempted to access unauthorized project');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'You do not have access to this project',
                            style: GoogleFonts.poppins(),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    _goToProjectSummary(context);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'No project selected',
                          style: GoogleFonts.poppins(),
                        ),
                      ),
                    );
                  }
                },
              ),

              // ── Documents ─────────────────────────────────────────────────
              _buildProtectedMenuItem(
                context: context,
                icon: Icons.description,
                iconColor: Colors.blue,
                title: 'Documents',
                selectedItem: 'Documents',
                isMobile: isMobile,
                isClient: isRestrictedRole,
                onNavigate: () => DocumentsScreen(
                  project: widget.project!,
                  logger: widget.logger,
                ),
              ),

              // Sub-contractor per requirement: Documents (their own
              // uploads only — see DocumentsScreen) is the only section
              // they get right now; every other section below (including
              // Communication, which is otherwise available to literally
              // every other role) is deliberately withheld until their
              // real permission set is defined.
              if (!isSubContractor) ...[
              // ── Drawings ──────────────────────────────────────────────────
              _buildProtectedMenuItem(
                context: context,
                icon: Icons.architecture,
                iconColor: Colors.teal,
                title: 'Drawings',
                selectedItem: 'Drawings',
                isMobile: isMobile,
                isClient: isRestrictedRole,
                onNavigate: () => DrawingsScreen(
                  project: widget.project!,
                  logger: widget.logger,
                ),
              ),

              // ── Schedule ──────────────────────────────────────────────────
              _buildProtectedMenuItem(
                context: context,
                icon: Icons.schedule,
                iconColor: Colors.orange,
                title: 'Schedule',
                selectedItem: 'Schedule',
                isMobile: isMobile,
                isClient: isRestrictedRole,
                onNavigate: () => ScheduleScreen(
                  project: widget.project!,
                  logger: widget.logger,
                ),
              ),

              // ── Quality & Safety ──────────────────────────────────────────
              _buildProtectedMenuItem(
                context: context,
                icon: Icons.shield_sharp,
                iconColor: Colors.green,
                title: 'Quality & Safety',
                selectedItem: 'Quality & Safety',
                isMobile: isMobile,
                isClient: isRestrictedRole,
                onNavigate: () => QualityAndSafetyScreen(
                  project: widget.project!,
                  logger: widget.logger,
                ),
              ),

              // ── Safety Training (gamified worker safety awareness) ────────
              // Same visibility as Task Progress/Photo Gallery below —
              // Admin/MainAdmin/SystemAdmin/Technician (on-site workers),
              // excluded for Client the same way those are.
              if (!isClient)
                _buildProtectedMenuItem(
                  context: context,
                  icon: Icons.health_and_safety,
                  iconColor: Colors.redAccent,
                  title: 'Safety Training',
                  selectedItem: 'Safety Training',
                  isMobile: isMobile,
                  isClient: isRestrictedRole,
                  onNavigate: () => SafetyTrainingScreen(
                    project: widget.project!,
                    logger: widget.logger,
                  ),
                ),

              // ── Reports ───────────────────────────────────────────────────
              // Admins see all tabs + can create/upload.
              // Clients see Weekly & Monthly saved reports in read-only mode.
              _buildProtectedMenuItem(
                context: context,
                icon: Icons.insert_chart,
                iconColor: Colors.deepPurple,
                title: 'Reports',
                selectedItem: 'Reports',
                isMobile: isMobile,
                isClient: isRestrictedRole,
                onNavigate: () => ReportsScreen(
                  project: widget.project!,
                  logger: widget.logger,
                  isClient: isClient,
                  isTechnician: _userRole == 'Technician',
                ),
              ),

              // ── Task Progress Monitor (Admin / MainAdmin only) ─────────────
              if (!isClient)
                _buildProtectedMenuItem(
                  context: context,
                  icon: Icons.track_changes_rounded,
                  iconColor: Colors.cyan,
                  title: 'Task Progress',
                  selectedItem: 'Task Progress',
                  isMobile: isMobile,
                  isClient: isRestrictedRole,
                  onNavigate: () => TaskProgressMonitorScreen(
                    project: widget.project!,
                    logger: widget.logger,
                  ),
                ),

              // ── Photo Gallery (Admin / MainAdmin only) ────────────────────
              if (!isClient)
                _buildProtectedMenuItem(
                  context: context,
                  icon: Icons.photo_library,
                  iconColor: Colors.pink,
                  title: 'Photo Gallery',
                  selectedItem: 'Photo Gallery',
                  isMobile: isMobile,
                  isClient: isRestrictedRole,
                  onNavigate: () => PhotoGalleryScreen(
                    project: widget.project!,
                    logger: widget.logger,
                  ),
                ),

              // ── Photos (Client only) ──────────────────────────────────────
              if (isClient)
                _buildProtectedMenuItem(
                  context: context,
                  icon: Icons.photo_album,
                  iconColor: Colors.pink,
                  title: 'Photos',
                  selectedItem: 'Photos',
                  isMobile: isMobile,
                  isClient: isRestrictedRole,
                  onNavigate: () => PhotosScreen(
                    project: widget.project!,
                    logger: widget.logger,
                  ),
                ),

              // ── Financials (Admin / MainAdmin only — explicitly excludes
              // Technician too, unlike every other Admin-visible section
              // above, since Technicians shouldn't see budget/payment data) ──
              if (!isRestrictedRole)
                _buildProtectedMenuItem(
                  context: context,
                  icon: Icons.account_balance,
                  iconColor: Color(0xFF2E7D32),
                  title: 'Financials',
                  selectedItem: 'Financials',
                  isMobile: isMobile,
                  isClient: isRestrictedRole,
                  onNavigate: () => FinancialScreen(
                    project: widget.project!,
                    logger: widget.logger,
                  ),
                ),

              // ── Inventory (Admin / MainAdmin only) ────────────────────────
              // Company-wide asset register + custody ledger. Not scoped to
              // widget.project's data — project is passed through only so
              // BaseLayout can render its header/project-switcher chrome
              // consistently with every other destination screen.
              if (!isClient)
                _buildProtectedMenuItem(
                  context: context,
                  icon: Icons.inventory_2,
                  iconColor: Colors.brown,
                  title: 'Inventory',
                  selectedItem: 'Inventory',
                  isMobile: isMobile,
                  // Not isRestrictedRole here — Technician keeps Inventory
                  // access (read + request checkouts), only Client is
                  // excluded, matching the `if (!isClient)` visibility
                  // condition above this call.
                  isClient: isClient,
                  onNavigate: () => InventoryScreen(
                    project: widget.project!,
                    logger: widget.logger,
                  ),
                ),

              // ── Communication (all OTHER roles) ─────────────────────────────
              // Communication is available to every role except
              // Sub-contractor (see the enclosing if block above) —
              // Clients need to message their Admins and vice versa.
              // The CommunicationService enforces project-scoped filtering,
              // so no additional role guard is needed here.
              _buildProtectedMenuItem(
                context: context,
                icon: Icons.mail_outline_rounded,
                iconColor: Colors.blueAccent,
                title: 'Communication',
                selectedItem: 'Communication',
                isMobile: isMobile,
                isClient: isRestrictedRole,
                onNavigate: () => CommunicationScreen(
                  project: widget.project!,
                  logger: widget.logger,
                ),
              ),
              ], // end if (!isSubContractor)
            ],
            ),
          ),
        ),
      ],
      ),
    );
  }

  Widget _buildProtectedMenuItem({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String selectedItem,
    required bool isMobile,
    required bool isClient,
    required Widget Function() onNavigate,
  }) {
    final selected = widget.selectedMenuItem == selectedItem;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedTextColor = isDark ? _sidebarSelectedTextColorDark : _sidebarSelectedTextColorLight;
    final unselectedTextColor = isDark ? _sidebarTextColorDark : _sidebarTextColorLight;
    // A left accent bar on the active item — a clearer, more modern "you
    // are here" affordance than relying on background tint alone. A
    // Container border (not ListTile's `shape`, which draws uniformly
    // around all four edges) so only the left edge is marked.
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: selected ? selectedTextColor : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(
          title,
          style: GoogleFonts.poppins(
            color: selected ? selectedTextColor : unselectedTextColor,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        selected: selected,
        selectedTileColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.blueGrey[50],
        onTap: () {
        widget.logger.i('🧭 BaseLayout: $title selected');
        if (isMobile) Navigator.pop(context);

        if (widget.project != null) {
          if (isClient &&
              _clientProjectIds != null &&
              !_clientProjectIds!.contains(widget.project!.id)) {
            widget.logger.w(
                '⚠️ BaseLayout: $_userRole attempted to access unauthorized project: $title');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'You do not have access to this project',
                  style: GoogleFonts.poppins(),
                ),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }

          _goToSection(context, onNavigate);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No project selected',
                style: GoogleFonts.poppins(),
              ),
            ),
          );
        }
        },
      ),
    );
  }
}