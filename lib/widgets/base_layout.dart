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
import 'package:almaworks/notifications/notification_bell.dart';
import 'package:almaworks/screens/quality_and_safety_screen.dart';
import 'package:almaworks/screens/reports/reports_screen.dart';
import 'package:almaworks/screens/safety_training/safety_training_screen.dart';
import 'package:almaworks/screens/schedule/schedule_screen.dart';
import 'package:almaworks/screens/schedule/task_progress_monitor_screen.dart';
import 'package:almaworks/screens/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:almaworks/widgets/responsive_layout.dart';
import 'package:logger/logger.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/theme/app_colors.dart';
import 'package:almaworks/core/errors/friendly_error.dart';

// Sidebar colors follow the light/dark/high-contrast choice in Settings
// (see AppColors): surface, text and the selected item all switch together.

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

  // Live instead of a one-shot get() — a role changed directly in Firestore
  // (or a slow mirror sync) now reflects here, and in every role-gated
  // widget downstream, without requiring the screen to be torn down and
  // rebuilt. Previously this was a single get() in _fetchUserRoleAndAccess,
  // which is exactly why a role change could leave stale permissions
  // ("hanging" gates) visible for the rest of the session.
  StreamSubscription<QuerySnapshot>? _userDocSub;

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
      if (mounted && widget.selectedMenuItem == 'Overview' && MediaQuery.of(context).size.width < kSidebarBreakpoint) {
        _scaffoldKey.currentState?.openDrawer();
      }
    });
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
    _userDocSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Below kSidebarBreakpoint the section menu is a drawer; a permanent
    // sidebar there would leave the screen itself too little room.
    final isMobile = screenWidth < kSidebarBreakpoint;
    final isTablet = screenWidth >= kSidebarBreakpoint && screenWidth < 1200;

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
          Expanded(child: ContentWidthScope(child: widget.child)),
        ],
      ),
      floatingActionButton: widget.floatingActionButton,
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: Text(
        widget.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      centerTitle: true,
      backgroundColor: AppColors.isDark ? null : AppColors.navy,
      foregroundColor: Colors.white,
      actions: [
        // Unread count comes from the same provider the notification
        // center lists (notifications/notification_providers.dart), so the
        // badge and the list can never disagree.
        NotificationBell(logger: widget.logger),
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
    return Container(
      width: isTablet ? 260 : 300,
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
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
    // true while the menu is the drawer (taps close it)
    final isMobile = screenWidth < kSidebarBreakpoint;
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
    final l = context.l10n;
    final selectedTextColor = AppColors.brandInk;
    final textColor = AppColors.ink;

    return ColoredBox(
      color: AppColors.surface,
      child: Column(
        children: [
        Container(
          height: 120,
          width: double.infinity,
          decoration: const BoxDecoration(
            color: AppColors.navy,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  widget.project?.name ?? 'AlmaWorks',
                  style: TextStyle(
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
                  isClient ? l.myProjectDashboard : l.projectDashboard,
                  style: TextStyle(
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
                leading: Icon(Icons.swap_horiz, color: AppColors.inkMuted),
                title: Text(
                  isRestrictedRole ? l.navMyProjects : l.navSwitchProject,
                  style: TextStyle(
                    color: widget.selectedMenuItem == 'Switch Project' ? selectedTextColor : textColor,
                    fontWeight: widget.selectedMenuItem == 'Switch Project' ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                selected: widget.selectedMenuItem == 'Switch Project',
                selectedTileColor: AppColors.brandTint,
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
                  l.navOverview,
                  style: TextStyle(
                    color: widget.selectedMenuItem == 'Overview' ? selectedTextColor : textColor,
                    fontWeight: widget.selectedMenuItem == 'Overview' ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                selected: widget.selectedMenuItem == 'Overview',
                selectedTileColor: AppColors.brandTint,
                onTap: () {
                  widget.logger.i('🧭 BaseLayout: Overview selected');
                  if (isMobile) Navigator.pop(context);
                  if (widget.project != null) {
                    if (isRestrictedRole &&
                        _clientProjectIds != null &&
                        !_clientProjectIds!.contains(widget.project!.id)) {
                      widget.logger.w(
                          '⚠️ BaseLayout: $_userRole attempted to access unauthorized project');
                      showErrorMessage(context, l.noAccessToProject);
                      return;
                    }

                    _goToProjectSummary(context);
                  } else {
                    showInfoSnack(context, l.noProjectSelected);
                  }
                },
              ),

              // ── Documents ─────────────────────────────────────────────────
              _buildProtectedMenuItem(
                context: context,
                icon: Icons.description,
                iconColor: Colors.blue,
                title: l.navDocuments,
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
                title: l.navDrawings,
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
                title: l.navSchedule,
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
                title: l.navQualitySafety,
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
                  title: l.navSafetyTraining,
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
                title: l.navReports,
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
                  title: l.navTaskProgress,
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
                  title: l.navPhotoGallery,
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
                  title: l.navPhotos,
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
                  title: l.navFinancials,
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
                  title: l.navInventory,
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
                title: l.navCommunication,
                selectedItem: 'Communication',
                isMobile: isMobile,
                isClient: isRestrictedRole,
                onNavigate: () => CommunicationScreen(
                  project: widget.project!,
                  logger: widget.logger,
                ),
              ),
              ], // end if (!isSubContractor)

              // ── Settings (every role) ─────────────────────────────────────
              Divider(color: AppColors.divider),
              ListTile(
                leading: Icon(Icons.settings_rounded, color: AppColors.inkMuted),
                title: Text(l.settings, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                onTap: () {
                  if (isMobile) Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
                },
              ),
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
    final selectedTextColor = AppColors.brandInk;
    final unselectedTextColor = AppColors.ink;
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
          style: TextStyle(
            color: selected ? selectedTextColor : unselectedTextColor,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        selected: selected,
        selectedTileColor: AppColors.brandTint,
        onTap: () {
        widget.logger.i('🧭 BaseLayout: $title selected');
        if (isMobile) Navigator.pop(context);

        if (widget.project != null) {
          if (isClient &&
              _clientProjectIds != null &&
              !_clientProjectIds!.contains(widget.project!.id)) {
            widget.logger.w(
                '⚠️ BaseLayout: $_userRole attempted to access unauthorized project: $title');
            showErrorMessage(context, context.l10n.noAccessToProject);
            return;
          }

          _goToSection(context, onNavigate);
        } else {
          showInfoSnack(context, context.l10n.noProjectSelected);
        }
        },
      ),
    );
  }
}

