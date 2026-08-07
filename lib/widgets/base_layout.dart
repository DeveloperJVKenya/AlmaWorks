import 'dart:async';

import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/rbacsystem/auth_service.dart';
import 'package:almaworks/rbacsystem/client_request_service.dart';
import 'package:almaworks/screens/communication/communication_screen.dart';
import 'package:almaworks/screens/financial_screen.dart';
import 'package:almaworks/screens/photo_gallery_screen.dart';
import 'package:almaworks/screens/photos_screen.dart';
import 'package:almaworks/screens/projects/projects_main_screen.dart';
import 'package:almaworks/screens/projects/project_summary_screen.dart';
import 'package:almaworks/screens/documents_screen.dart';
import 'package:almaworks/screens/drawings_screen.dart';
import 'package:almaworks/screens/inventory/inventory_screen.dart';
import 'package:almaworks/screens/quality_and_safety_screen.dart';
import 'package:almaworks/screens/reports/reports_screen.dart';
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
  String? _userRole;
  List<String>? _clientProjectIds;
  bool _isLoadingUserData = true;
  final ClientRequestService _requestService = ClientRequestService();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchUserRoleAndAccess();
    });
  }

  Future<void> _fetchUserRoleAndAccess() async {
    try {
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

      final querySnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final userData = querySnapshot.docs.first.data();
        final username = querySnapshot.docs.first.id;
        final role = userData['role'] as String? ?? 'Client';

        // Keep UserRoles/{uid} in sync on every screen load, not just at
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

        List<String> grantedIds = [];
        if (role == 'Client') {
          grantedIds =
              await _requestService.getClientGrantedProjects(user.uid);
          widget.logger
              .i('✅ BaseLayout: Client granted project IDs: $grantedIds');
        }

        if (mounted) {
          setState(() {
            _userRole = role;
            _clientProjectIds = role == 'Client' ? grantedIds : null;
            _isLoadingUserData = false;
          });
        }

        widget.logger.i(
            '✅ BaseLayout: User role fetched: $role, Granted Projects: ${grantedIds.length}');
      } else {
        widget.logger.w('⚠️ BaseLayout: User document not found');
        if (mounted) {
          setState(() {
            _userRole = 'Client';
            _isLoadingUserData = false;
          });
        }
      }
    } catch (e) {
      widget.logger.e('❌ BaseLayout: Error fetching user role: $e');
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 1200;

    if (_isLoadingUserData) {
      return Scaffold(
        appBar: _buildAppBar(context),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
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
      actions: widget.actions,
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
                  isClient ? 'My Projects' : 'Switch Project',
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
                      '🧭 BaseLayout: Switch Project selected, isClient: $isClient');
                  if (isMobile) Navigator.pop(context);

                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProjectsMainScreen(
                        logger: widget.logger,
                        clientProjectIds:
                            isClient ? _clientProjectIds : null,
                      ),
                    ),
                  );
                },
              ),

              // ── Overview ──────────────────────────────────────────────────
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
                    if (isClient &&
                        _clientProjectIds != null &&
                        !_clientProjectIds!.contains(widget.project!.id)) {
                      widget.logger.w(
                          '⚠️ BaseLayout: Client attempted to access unauthorized project');
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

                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProjectSummaryScreen(
                          project: widget.project!,
                          logger: widget.logger,
                        ),
                      ),
                    );
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
                isClient: isClient,
                onNavigate: () => DocumentsScreen(
                  project: widget.project!,
                  logger: widget.logger,
                ),
              ),

              // ── Drawings ──────────────────────────────────────────────────
              _buildProtectedMenuItem(
                context: context,
                icon: Icons.architecture,
                iconColor: Colors.teal,
                title: 'Drawings',
                selectedItem: 'Drawings',
                isMobile: isMobile,
                isClient: isClient,
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
                isClient: isClient,
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
                isClient: isClient,
                onNavigate: () => QualityAndSafetyScreen(
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
                isClient: isClient,
                onNavigate: () => ReportsScreen(
                  project: widget.project!,
                  logger: widget.logger,
                  isClient: isClient,
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
                  isClient: isClient,
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
                  isClient: isClient,
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
                  isClient: isClient,
                  onNavigate: () => PhotosScreen(
                    project: widget.project!,
                    logger: widget.logger,
                  ),
                ),

              // ── Financials (Admin / MainAdmin only) ───────────────────────
              if (!isClient)
                _buildProtectedMenuItem(
                  context: context,
                  icon: Icons.account_balance,
                  iconColor: Color(0xFF2E7D32),
                  title: 'Financials',
                  selectedItem: 'Financials',
                  isMobile: isMobile,
                  isClient: isClient,
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
                  isClient: isClient,
                  onNavigate: () => InventoryScreen(
                    project: widget.project!,
                    logger: widget.logger,
                  ),
                ),

              // ── Communication (all roles) ─────────────────────────────────
              // Communication is intentionally available to ALL roles —
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
                isClient: isClient,
                onNavigate: () => CommunicationScreen(
                  project: widget.project!,
                  logger: widget.logger,
                ),
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
                '⚠️ BaseLayout: Client attempted to access unauthorized project: $title');
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

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => onNavigate(),
            ),
          );
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