import 'package:almaworks/authentication/login_screen.dart';
import 'package:almaworks/core/errors/friendly_error.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/settings/settings_providers.dart';
import 'package:almaworks/core/theme/app_colors.dart';
import 'package:almaworks/rbacsystem/auth_service.dart';
import 'package:almaworks/screens/projects/projects_main_screen.dart';
import 'package:almaworks/screens/settings/settings_screen.dart';
import 'package:almaworks/widgets/modern/modern_ui.dart';
import 'package:almaworks/widgets/responsive_layout.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

class AccountScreen extends ConsumerStatefulWidget {
  final Logger? logger;

  const AccountScreen({super.key, this.logger});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AuthService _authService = AuthService();
  late final Logger _logger;

  // ── Profile state ──────────────────────────────────────────────────────────
  bool _isLoadingProfile = true;
  Object? _loadError;
  String _userName = '';
  String _userEmail = '';
  String _userRole = '';
  String _userUid = '';

  // ── Edit mode ──────────────────────────────────────────────────────────────
  bool _isEditingProfile = false;
  bool _isSavingProfile = false;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _logger = widget.logger ?? Logger();
    _logger.i('👤 AccountScreen: initState called');
    _loadUserProfile();
  }

  // ── Data Loading ───────────────────────────────────────────────────────────

  Future<void> _loadUserProfile() async {
    _logger.i('👤 AccountScreen: _loadUserProfile() started');
    setState(() {
      _isLoadingProfile = true;
      _loadError = null;
    });

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        _logger.e('👤 AccountScreen: FirebaseAuth.currentUser is null — user not signed in');
        throw UserFacingException(l10nNow.errSignInAgain);
      }

      _userUid = currentUser.uid;
      final querySnapshot = await _firestore.collection('Users').where('uid', isEqualTo: _userUid).limit(1).get();

      if (querySnapshot.docs.isEmpty) {
        _logger.e('👤 AccountScreen: No user document found for uid=$_userUid');
        throw UserFacingException(l10nNow.profileNotFound);
      }

      final doc = querySnapshot.docs.first;
      final data = doc.data();
      _logger.i('👤 AccountScreen: Profile document id = ${doc.id}');

      // Empty string = "not on record"; shown with a translated
      // placeholder at build time so it follows the language setting.
      final resolvedName = data['Username'] as String? ?? data['username'] as String? ?? data['name'] as String? ?? '';
      final resolvedEmail = data['Email'] as String? ?? data['email'] as String? ?? currentUser.email ?? '';
      final resolvedRole = data['role'] as String? ?? data['Role'] as String? ?? '';

      setState(() {
        _userName = resolvedName;
        _userEmail = resolvedEmail;
        _userRole = resolvedRole;
        _isLoadingProfile = false;
      });

      _nameController.text = _userName;
      _emailController.text = _userEmail;
      _logger.i('👤 AccountScreen: Profile loaded successfully');
    } catch (e, stack) {
      _logger.e('❌ AccountScreen: _loadUserProfile() failed', error: e, stackTrace: stack);
      setState(() {
        _isLoadingProfile = false;
        _loadError = e;
      });
    }
  }

  // ── Save Profile ───────────────────────────────────────────────────────────

  Future<void> _saveProfile() async {
    _logger.i('💾 AccountScreen: _saveProfile() called');
    final l = context.l10n;

    if (_nameController.text.trim().isEmpty) {
      showErrorMessage(context, l.nameCannotBeEmpty);
      return;
    }

    setState(() => _isSavingProfile = true);

    try {
      final querySnapshot = await _firestore.collection('Users').where('uid', isEqualTo: _userUid).limit(1).get();

      if (querySnapshot.docs.isNotEmpty) {
        await querySnapshot.docs.first.reference.update({
          'Username': _nameController.text.trim(),
          'Email': _emailController.text.trim(),
        });
        _logger.i('💾 AccountScreen: Firestore update succeeded');
      } else {
        _logger.w('💾 AccountScreen: No document found to update — uid=$_userUid');
      }

      setState(() {
        _userName = _nameController.text.trim();
        _userEmail = _emailController.text.trim();
        _isEditingProfile = false;
        _isSavingProfile = false;
      });

      if (mounted) showSuccessSnack(context, l.profileUpdated);
    } catch (e, stack) {
      _logger.e('❌ AccountScreen: _saveProfile() failed', error: e, stackTrace: stack);
      setState(() => _isSavingProfile = false);
      if (mounted) showErrorSnack(context, e, action: l.couldNotSaveProfile);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600 && screenWidth < 1200;

    return ResponsiveLayout(
      mobile: _buildMobileLayout(),
      tablet: _buildTabletLayout(isTablet),
      desktop: _buildDesktopLayout(),
    );
  }

  Widget _buildMobileLayout() => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: _buildAppBar(),
    drawer: _buildDrawer(),
    body: Column(
      children: [
        Expanded(child: _buildAccountContent(true)),
        _buildFooter(true),
      ],
    ),
  );

  Widget _buildTabletLayout(bool isTablet) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: _buildAppBar(),
    body: Row(
      children: [
        _buildSidebar(isTablet),
        Expanded(
          child: Column(
            children: [
              Expanded(child: _buildAccountContent(false)),
              _buildFooter(false),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildDesktopLayout() => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: _buildAppBar(),
    body: Row(
      children: [
        _buildSidebar(false),
        Expanded(
          child: Column(
            children: [
              Expanded(child: _buildAccountContent(false)),
              _buildFooter(false),
            ],
          ),
        ),
      ],
    ),
  );

  // ── AppBar ─────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    final l = context.l10n;
    return AppBar(
      title: Text(l.myAccount, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      centerTitle: true,
      actions: [
        if (!_isLoadingProfile && _loadError == null) ...[
          if (_isSavingProfile)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: Icon(_isEditingProfile ? Icons.check_rounded : Icons.edit),
              tooltip: _isEditingProfile ? l.saveChanges : l.editProfile,
              onPressed: () {
                if (_isEditingProfile) {
                  _saveProfile();
                } else {
                  setState(() => _isEditingProfile = true);
                }
              },
            ),
          if (_isEditingProfile)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l.cancel,
              onPressed: () {
                setState(() {
                  _isEditingProfile = false;
                  _nameController.text = _userName;
                  _emailController.text = _userEmail;
                });
              },
            ),
        ],
        IconButton(icon: const Icon(Icons.refresh), tooltip: l.refreshProfile, onPressed: _loadUserProfile),
        IconButton(
          icon: const Icon(Icons.settings_rounded),
          tooltip: l.settings,
          onPressed: () => _openSettings(null),
        ),
      ],
    );
  }

  void _openSettings(SettingsSection? section) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(initialSection: section)));
  }

  // ── Sidebar (mirrors BaseLayout sidebar structure) ─────────────────────────

  /// Mobile drawer wraps the same sidebar content used on tablet/desktop.
  Widget _buildDrawer() => Drawer(child: _buildSidebarContent());

  Widget _buildSidebar(bool isTablet) {
    return Container(
      width: isTablet ? 280 : 300,
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 4, offset: const Offset(2, 0))],
      ),
      child: _buildSidebarContent(),
    );
  }

  /// Sidebar content that matches BaseLayout exactly:
  /// header → Switch Project → Overview → per-project sections (greyed out
  /// since no project is selected from this screen) → Account (selected).
  Widget _buildSidebarContent() {
    final l = context.l10n;
    final bool isClient = _userRole == 'Client';
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final textColor = AppColors.ink;
    final disabledTextColor = AppColors.inkFaint;
    final selectedTextColor = AppColors.brandInk;

    return ColoredBox(
      color: AppColors.surface,
      child: Column(
        children: [
          // ── Header ─────────────────────────────────────────────────────────
          Container(
            height: 120,
            width: double.infinity,
            color: AppColors.navy,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    'AlmaWorks',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    isClient ? l.myProjectDashboard : l.projectDashboard,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          // ── Nav items ──────────────────────────────────────────────────────
          Expanded(
            // See base_layout.dart's identical wrap for why this Material is
            // needed — avoids the "ListTile background color or ink splashes
            // may be invisible" warning from the selectedTileColor below.
            child: Material(
              color: Colors.transparent,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: Icon(Icons.swap_horiz, color: AppColors.inkMuted),
                    title: Text(
                      isClient ? l.navMyProjects : l.navSwitchProject,
                      style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      if (isMobile) Navigator.pop(context);
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProjectsMainScreen(logger: _logger, clientProjectIds: isClient ? [] : null),
                        ),
                      );
                    },
                  ),

                  // Overview — no project selected from this screen, shown greyed
                  ListTile(
                    leading: Icon(Icons.dashboard, color: disabledTextColor),
                    title: Text(l.navOverview, style: TextStyle(color: disabledTextColor)),
                    enabled: false,
                  ),

                  // Project sections — all disabled (no active project context here)
                  for (final item in [
                    (Icons.description, l.navDocuments),
                    (Icons.architecture, l.navDrawings),
                    (Icons.schedule, l.navSchedule),
                    (Icons.shield_sharp, l.navQualitySafety),
                    if (!isClient) (Icons.insert_chart, l.navReports),
                    if (!isClient) (Icons.photo_library, l.navPhotoGallery),
                    if (isClient) (Icons.photo_album, l.navPhotos),
                    (Icons.account_balance, l.navFinancials),
                  ])
                    ListTile(
                      leading: Icon(item.$1, color: disabledTextColor),
                      title: Text(item.$2, style: TextStyle(color: disabledTextColor)),
                      enabled: false,
                    ),

                  Divider(color: AppColors.divider),

                  // Account — currently selected
                  Container(
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: selectedTextColor, width: 3)),
                    ),
                    child: ListTile(
                      leading: Icon(Icons.person, color: selectedTextColor),
                      title: Text(
                        l.navAccount,
                        style: TextStyle(color: selectedTextColor, fontWeight: FontWeight.w700),
                      ),
                      selected: true,
                      selectedTileColor: AppColors.brandTint,
                      onTap: () {},
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.settings_rounded, color: AppColors.inkMuted),
                    title: Text(l.settings, style: TextStyle(color: textColor)),
                    onTap: () {
                      if (isMobile) Navigator.pop(context);
                      _openSettings(null);
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

  // ── Main Content ───────────────────────────────────────────────────────────

  Widget _buildAccountContent(bool isMobile) {
    final l = context.l10n;
    if (_isLoadingProfile) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.brandInk),
            const SizedBox(height: 16),
            Text(l.loadingProfile, style: TextStyle(color: AppColors.inkMuted)),
          ],
        ),
      );
    }

    if (_loadError != null) {
      return EmptyState(
        icon: Icons.person_off_rounded,
        title: l.couldNotLoadProfile,
        message: friendlyError(_loadError!),
        action: PrimaryButton(label: l.retry, icon: Icons.refresh, onPressed: _loadUserProfile),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      child: ResponsiveCenter(
        maxWidth: 820,
        child: Column(
          children: [
            _buildProfileSection(isMobile),
            const SizedBox(height: 20),
            _buildSettingsSection(isMobile),
          ],
        ),
      ),
    );
  }

  // ── Profile Section ────────────────────────────────────────────────────────

  Widget _buildProfileSection(bool isMobile) {
    final l = context.l10n;
    final initials = _userName.isNotEmpty
        ? _userName.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join()
        : '?';

    return AppCard(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: isMobile ? 44 : 56,
                backgroundColor: AppColors.navy,
                child: Text(
                  initials,
                  style: TextStyle(fontSize: isMobile ? 26 : 32, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              if (_userRole.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.surface, width: 1.5),
                  ),
                  child: Text(
                    roleLabel(_userRole, l),
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (_isEditingProfile) ...[
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(labelText: l.fullName, prefixIcon: const Icon(Icons.person_outline)),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              decoration: InputDecoration(labelText: l.emailAddress, prefixIcon: const Icon(Icons.email_outlined)),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 6),
            Text(l.emailChangeNote, style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
          ] else ...[
            Text(
              _userName.isEmpty ? l.unknownUser : _userName,
              style: TextStyle(fontSize: isMobile ? 20 : 24, fontWeight: FontWeight.bold, color: AppColors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(20)),
              child: Text(
                roleLabel(_userRole, l),
                style: TextStyle(color: AppColors.brandInk, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            const SizedBox(height: 20),
            Divider(color: AppColors.divider),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.email_outlined, l.email, _userEmail.isEmpty ? l.noEmailOnRecord : _userEmail),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.inkMuted),
        const SizedBox(width: 10),
        Text(
          '$label:',
          style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.inkMuted, fontSize: 13),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value, style: TextStyle(fontSize: 14, color: AppColors.ink), overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  // ── Settings Section ───────────────────────────────────────────────────────
  //
  // A summary of the current choices; each row opens the full Settings
  // screen at its section.

  Widget _buildSettingsSection(bool isMobile) {
    final l = context.l10n;
    final themeMode = ref.watch(themeModeProvider);
    final font = ref.watch(appFontProvider);
    final scale = ref.watch(textScaleProvider);
    final language = ref.watch(languageProvider);
    final themeName = switch (themeMode) {
      ThemeMode.system => l.themeSystem,
      ThemeMode.light => l.themeLight,
      ThemeMode.dark => l.themeDark,
    };
    final accessibilityExtras = [
      if (ref.watch(boldTextProvider)) l.boldText,
      if (ref.watch(highContrastProvider)) l.highContrast,
      if (ref.watch(reduceMotionProvider)) l.reduceMotion,
    ];

    return AppCard(
      padding: EdgeInsets.all(isMobile ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              children: [
                Expanded(child: Text(l.settings, style: appText(isMobile ? 16 : 18, weight: FontWeight.w700))),
                TextButton.icon(
                  onPressed: () => _openSettings(null),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(l.openSettings),
                ),
              ],
            ),
          ),
          _SettingsSummaryRow(
            icon: Icons.palette_rounded,
            color: AppPalette.violet,
            title: l.appearance,
            value: '$themeName · ${font.label}',
            onTap: () => _openSettings(SettingsSection.appearance),
          ),
          _SettingsSummaryRow(
            icon: Icons.accessibility_new_rounded,
            color: AppPalette.teal,
            title: l.accessibility,
            value: [l.textSizePercent((scale * 100).round()), ...accessibilityExtras].join(' · '),
            onTap: () => _openSettings(SettingsSection.accessibility),
          ),
          _SettingsSummaryRow(
            icon: Icons.translate_rounded,
            color: AppPalette.brightBlue,
            title: l.language,
            value: '${language.flag}  ${language.nativeName}',
            onTap: () => _openSettings(SettingsSection.language),
          ),
          _SettingsSummaryRow(
            icon: Icons.notifications_active_rounded,
            color: AppPalette.orange,
            title: l.deviceNotifications,
            value: ref.watch(deviceNotificationsProvider) ? l.on : l.off,
            onTap: () => _openSettings(SettingsSection.notifications),
          ),
          Divider(height: 20, color: AppColors.divider),
          _SettingsSummaryRow(
            icon: Icons.logout_rounded,
            color: AppColors.danger,
            title: l.logout,
            titleColor: AppColors.danger,
            onTap: _showLogoutDialog,
          ),
        ],
      ),
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────────

  Widget _buildFooter(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      color: AppColors.navy,
      child: Text(
        context.l10n.copyrightFooter,
        style: TextStyle(color: Colors.white, fontSize: isMobile ? 12 : 14, fontWeight: FontWeight.w400),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _showLogoutDialog() {
    final l = context.l10n;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.logout, color: AppColors.danger),
            const SizedBox(width: 8),
            Text(l.logout),
          ],
        ),
        content: Text(l.logoutConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              navigator.pop(); // close the confirmation dialog
              _logger.i('🚪 AccountScreen: Logging out');
              try {
                // AuthService.logout() clears the persisted "isLoggedIn" flag
                // AND signs out of Firebase Auth — mirrors WelcomeScreen's
                // logout button.
                await _authService.logout();
              } catch (e) {
                _logger.e('❌ AccountScreen: logout() failed', error: e);
              }
              if (!mounted) return;
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            child: Text(l.logout),
          ),
        ],
      ),
    );
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}

class _SettingsSummaryRow extends StatelessWidget {
  const _SettingsSummaryRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
    this.value,
    this.titleColor,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? value;
  final Color? titleColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            IconBadge(icon: icon, color: color, size: 38),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: appText(14, weight: FontWeight.w600, color: titleColor)),
                  if (value != null)
                    Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appText(12.5, color: AppColors.inkMuted),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: titleColor ?? AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}
