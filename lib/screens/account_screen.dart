import 'package:almaworks/authentication/login_screen.dart';
import 'package:almaworks/providers/locale_provider.dart';
import 'package:almaworks/providers/theme_provider.dart';
import 'package:almaworks/rbacsystem/auth_service.dart';
import 'package:almaworks/screens/projects/projects_main_screen.dart';
import 'package:almaworks/services/notification_preferences.dart';
import 'package:almaworks/widgets/responsive_layout.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';

// Sidebar here mirrors base_layout.dart's own sidebar — same dark-mode
// support applied there for the same reason: this is a second, separate
// implementation of the same sidebar, so it needs the same theme-aware
// surface/text colors rather than staying permanently light.
const _sidebarSurfaceLight = Colors.white;
const _sidebarSurfaceDark = Color(0xFF1E1E1E);
const _sidebarTextColorLight = Color(0xFF37474F);
const _sidebarTextColorDark = Color(0xFFECEFF1);
const _sidebarDisabledTextColorLight = Color(0xFFB0BEC5);
const _sidebarDisabledTextColorDark = Color(0xFF6B7480);
const _sidebarSelectedTextColorLight = Color(0xFF0A2E5A);
const _sidebarSelectedTextColorDark = Color(0xFF82B1FF);

class AccountScreen extends StatefulWidget {
  final Logger? logger;
  final LocaleProvider localeProvider;
  final ThemeProvider themeProvider;

  const AccountScreen({
    super.key,
    this.logger,
    required this.localeProvider,
    required this.themeProvider,
  });

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AuthService _authService = AuthService();
  late final Logger _logger;

  // ── Profile state ──────────────────────────────────────────────────────────
  bool _isLoadingProfile = true;
  String? _loadError;
  String _userName = '';
  String _userEmail = '';
  String _userRole = '';
  String _userUid = '';

  // ── Settings ───────────────────────────────────────────────────────────────
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;

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
    _logger.d('👤 AccountScreen: localeProvider instance = ${widget.localeProvider.hashCode}, '
        'current language = ${widget.localeProvider.language}, '
        'locale = ${widget.localeProvider.locale}');
    _loadUserProfile();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final notificationsEnabled = await NotificationPreferences.isEnabled();
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = notificationsEnabled;
      _darkModeEnabled = widget.themeProvider.isDarkMode;
    });
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
        throw Exception('No authenticated user found. Please log in again.');
      }

      _userUid = currentUser.uid;
      _logger.i('👤 AccountScreen: currentUser.uid = $_userUid');
      _logger.d('👤 AccountScreen: currentUser.email = ${currentUser.email}');

      _logger.d('👤 AccountScreen: Querying Firestore — Users where uid == $_userUid');
      final querySnapshot = await _firestore
          .collection('Users')
          .where('uid', isEqualTo: _userUid)
          .limit(1)
          .get();

      _logger.d('👤 AccountScreen: Firestore query returned ${querySnapshot.docs.length} doc(s)');

      if (querySnapshot.docs.isEmpty) {
        _logger.e('👤 AccountScreen: No user document found for uid=$_userUid');
        throw Exception('User profile not found. Please contact your administrator.');
      }

      final doc = querySnapshot.docs.first;
      final data = doc.data();
      _logger.i('👤 AccountScreen: Profile document id = ${doc.id}');
      _logger.d('👤 AccountScreen: Raw Firestore fields = ${data.keys.toList()}');

      final resolvedName = data['Username'] as String? ??
          data['username'] as String? ??
          data['name'] as String? ??
          'Unknown User';
      final resolvedEmail = data['Email'] as String? ??
          data['email'] as String? ??
          currentUser.email ??
          'No email on record';
      final resolvedRole = data['role'] as String? ??
          data['Role'] as String? ??
          'Member';

      _logger.d('👤 AccountScreen: Resolved — name="$resolvedName" email="$resolvedEmail" role="$resolvedRole"');

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
      _logger.e('❌ AccountScreen: _loadUserProfile() failed — $e');
      _logger.d('❌ AccountScreen: Stack trace:\n$stack');
      setState(() {
        _isLoadingProfile = false;
        _loadError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── Save Profile ───────────────────────────────────────────────────────────

  Future<void> _saveProfile() async {
    _logger.i('💾 AccountScreen: _saveProfile() called');

    if (_nameController.text.trim().isEmpty) {
      _logger.w('💾 AccountScreen: Save aborted — name field is empty');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSavingProfile = true);
    _logger.d('💾 AccountScreen: Querying Firestore to find document for uid=$_userUid');

    try {
      final querySnapshot = await _firestore
          .collection('Users')
          .where('uid', isEqualTo: _userUid)
          .limit(1)
          .get();

      _logger.d('💾 AccountScreen: Found ${querySnapshot.docs.length} doc(s) to update');

      if (querySnapshot.docs.isNotEmpty) {
        final docId = querySnapshot.docs.first.id;
        _logger.d('💾 AccountScreen: Updating document "$docId" with new name/email');
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

      _logger.i('💾 AccountScreen: Profile save complete — name="$_userName" email="$_userEmail"');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e, stack) {
      _logger.e('❌ AccountScreen: _saveProfile() failed — $e');
      _logger.d('❌ AccountScreen: Stack trace:\n$stack');
      setState(() => _isSavingProfile = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
        );
      }
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
        appBar: _buildAppBar(),
        drawer: _buildDrawer(),
        body: Column(children: [
          Expanded(child: _buildAccountContent(true)),
          _buildFooter(true),
        ]),
      );

  Widget _buildTabletLayout(bool isTablet) => Scaffold(
        appBar: _buildAppBar(),
        body: Row(children: [
          _buildSidebar(isTablet),
          Expanded(
            child: Column(children: [
              Expanded(child: _buildAccountContent(false)),
              _buildFooter(false),
            ]),
          ),
        ]),
      );

  Widget _buildDesktopLayout() => Scaffold(
        appBar: _buildAppBar(),
        body: Row(children: [
          _buildSidebar(false),
          Expanded(
            child: Column(children: [
              Expanded(child: _buildAccountContent(false)),
              _buildFooter(false),
            ]),
          ),
        ]),
      );

  // ── AppBar ─────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text('My Account',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white)),
      centerTitle: true,
      backgroundColor: const Color(0xFF0A2E5A),
      foregroundColor: Colors.white,
      actions: [
        if (!_isLoadingProfile && _loadError == null) ...[
          if (_isSavingProfile)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            )
          else
            IconButton(
              icon: Icon(_isEditingProfile ? Icons.check_rounded : Icons.edit),
              tooltip: _isEditingProfile ? 'Save changes' : 'Edit profile',
              onPressed: () {
                if (_isEditingProfile) {
                  _saveProfile();
                } else {
                  _logger.d('👤 AccountScreen: Edit mode enabled');
                  setState(() => _isEditingProfile = true);
                }
              },
            ),
          if (_isEditingProfile)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
              onPressed: () {
                _logger.d('👤 AccountScreen: Edit mode cancelled');
                setState(() {
                  _isEditingProfile = false;
                  _nameController.text = _userName;
                  _emailController.text = _userEmail;
                });
              },
            ),
        ],
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh profile',
          onPressed: () {
            _logger.i('👤 AccountScreen: Manual refresh triggered');
            _loadUserProfile();
          },
        ),
      ],
    );
  }

  // ── Sidebar (mirrors BaseLayout sidebar structure) ─────────────────────────

  /// Mobile drawer wraps the same sidebar content used on tablet/desktop.
  Widget _buildDrawer() => Drawer(child: _buildSidebarContent());

  Widget _buildSidebar(bool isTablet) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: isTablet ? 280 : 300,
      decoration: BoxDecoration(
        color: isDark ? _sidebarSurfaceDark : _sidebarSurfaceLight,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
              blurRadius: 4,
              offset: const Offset(2, 0)),
        ],
      ),
      child: _buildSidebarContent(),
    );
  }

  /// Sidebar content that matches BaseLayout exactly:
  /// header → Switch Project → Overview → per-project sections (greyed out
  /// since no project is selected from this screen) → Account (selected).
  Widget _buildSidebarContent() {
    final bool isClient = _userRole == 'Client';
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? _sidebarTextColorDark : _sidebarTextColorLight;
    final disabledTextColor = isDark ? _sidebarDisabledTextColorDark : _sidebarDisabledTextColorLight;
    final selectedTextColor = isDark ? _sidebarSelectedTextColorDark : _sidebarSelectedTextColorLight;

    return ColoredBox(
      color: isDark ? _sidebarSurfaceDark : _sidebarSurfaceLight,
      child: Column(
        children: [
        // ── Header ─────────────────────────────────────────────────────────
        Container(
          height: 120,
          width: double.infinity,
          decoration: const BoxDecoration(color: Color(0xFF0A2E5A)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'AlmaWorks',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  isClient ? 'My Project Dashboard' : 'Project Dashboard',
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
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
              // Switch Project / My Projects
              ListTile(
                leading: const Icon(Icons.swap_horiz, color: Colors.blueGrey),
                title: Text(
                  isClient ? 'My Projects' : 'Switch Project',
                  style: GoogleFonts.poppins(color: textColor, fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  _logger.i('🧭 AccountScreen sidebar: Switch Project tapped');
                  if (isMobile) Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProjectsMainScreen(
                        logger: _logger,
                        clientProjectIds: isClient ? [] : null,
                      ),
                    ),
                  );
                },
              ),

              // Overview — no project selected from this screen, shown greyed
              ListTile(
                leading: Icon(Icons.dashboard, color: Colors.indigo.withValues(alpha: 0.4)),
                title: Text('Overview', style: GoogleFonts.poppins(color: disabledTextColor)),
                enabled: false,
                onTap: null,
              ),

              // Project sections — all disabled (no active project context here)
              for (final item in [
                (Icons.description, 'Documents'),
                (Icons.architecture, 'Drawings'),
                (Icons.schedule, 'Schedule'),
                (Icons.shield_sharp, 'Quality & Safety'),
                if (!isClient) (Icons.insert_chart, 'Reports'),
                if (!isClient) (Icons.photo_library, 'Photo Gallery'),
                if (isClient) (Icons.photo_album, 'Photos'),
                (Icons.account_balance, 'Financials'),
              ])
                ListTile(
                  leading: Icon(item.$1, color: disabledTextColor),
                  title: Text(item.$2, style: GoogleFonts.poppins(color: disabledTextColor)),
                  enabled: false,
                ),

              const Divider(),

              // Account — currently selected
              Container(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: selectedTextColor, width: 3)),
                ),
                child: ListTile(
                  leading: Icon(Icons.person, color: selectedTextColor),
                  title: Text(
                    'Account',
                    style: GoogleFonts.poppins(color: selectedTextColor, fontWeight: FontWeight.w700),
                  ),
                  selected: true,
                  selectedTileColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.blueGrey[50],
                  onTap: () {},
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

  // ── Main Content ───────────────────────────────────────────────────────────

  Widget _buildAccountContent(bool isMobile) {
    if (_isLoadingProfile) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF0A2E5A)),
            SizedBox(height: 16),
            Text('Loading your profile…', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 56),
              const SizedBox(height: 16),
              Text(_loadError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 15)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                onPressed: () {
                  _logger.i('👤 AccountScreen: Retry profile load tapped');
                  _loadUserProfile();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A2E5A),
                    foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      child: Column(
        children: [
          _buildProfileSection(isMobile),
          const SizedBox(height: 20),
          _buildSettingsSection(isMobile),
        ],
      ),
    );
  }

  // ── Profile Section ────────────────────────────────────────────────────────

  Widget _buildProfileSection(bool isMobile) {
    final initials = _userName.isNotEmpty
        ? _userName
            .trim()
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .map((w) => w[0].toUpperCase())
            .take(2)
            .join()
        : '?';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: isMobile ? 44 : 56,
                  backgroundColor: const Color(0xFF0A2E5A),
                  child: Text(
                    initials,
                    style: TextStyle(
                        fontSize: isMobile ? 26 : 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ),
                if (_userRole.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      _userRole,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (_isEditingProfile) ...[
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder()),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder()),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 4),
              Text(
                'Note: Changing your email here updates your profile record only.',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ] else ...[
              Text(
                _userName,
                style: TextStyle(
                    fontSize: isMobile ? 20 : 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A2E5A).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _userRole,
                  style: const TextStyle(
                      color: Color(0xFF0A2E5A),
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              _buildInfoRow(Icons.email_outlined, 'Email', _userEmail),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 10),
        Text('$label:',
            style: TextStyle(
                fontWeight: FontWeight.w500, color: Colors.grey[600], fontSize: 13)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  // ── Settings Section ───────────────────────────────────────────────────────

  Widget _buildSettingsSection(bool isMobile) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings, color: Color(0xFF0A2E5A)),
                const SizedBox(width: 8),
                Text('Settings',
                    style: TextStyle(
                        fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            _buildSettingsTile(
              Icons.notifications_outlined,
              'Notifications',
              Switch(
                value: _notificationsEnabled,
                onChanged: (v) async {
                  _logger.d('🔔 AccountScreen: Notifications toggled → $v');
                  setState(() => _notificationsEnabled = v);
                  await NotificationPreferences.setEnabled(v);
                },
                activeThumbColor: const Color(0xFF0A2E5A),
              ),
            ),
            _buildSettingsTile(
              Icons.dark_mode_outlined,
              'Dark Mode',
              Switch(
                value: _darkModeEnabled,
                onChanged: (v) async {
                  _logger.d('🌙 AccountScreen: Dark mode toggled → $v');
                  setState(() => _darkModeEnabled = v);
                  await widget.themeProvider.setDarkMode(v);
                },
                activeThumbColor: const Color(0xFF0A2E5A),
              ),
            ),
            _buildLanguageTile(),
            const Divider(height: 24),
            _buildSettingsTile(
              Icons.security_outlined,
              'Privacy & Security',
              const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _showComingSoon('Privacy & Security'),
            ),
            _buildSettingsTile(
              Icons.help_outline,
              'Help & Support',
              const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _showComingSoon('Help & Support'),
            ),
            const Divider(height: 24),
            _buildSettingsTile(
              Icons.logout,
              'Logout',
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.red),
              onTap: _showLogoutDialog,
              textColor: Colors.red,
              iconColor: Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  // ── Language Tile & Picker ─────────────────────────────────────────────────

  Widget _buildLanguageTile() {
    final provider = widget.localeProvider;
    _logger.d('🌐 AccountScreen: _buildLanguageTile() — '
        'provider.language=${provider.language} locale=${provider.locale}');

    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final currentLang = provider.language;
        final flag = kLanguageFlags[currentLang]!;
        final label = kLanguageLabels[currentLang]!;

        _logger.d('🌐 AccountScreen: ListenableBuilder rebuilt — '
            'language=$currentLang flag=$flag label=$label');

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.language_outlined, color: Colors.grey[700]),
          title: Text('Language', style: GoogleFonts.poppins()),
          trailing: GestureDetector(
            onTap: () {
              _logger.i('🌐 AccountScreen: Language tile tapped — opening picker');
              _showLanguagePicker(provider);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(
                    color: const Color(0xFF0A2E5A).withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xFF0A2E5A).withValues(alpha: 0.05),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(flag, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, color: Color(0xFF0A2E5A))),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more, size: 16, color: Color(0xFF0A2E5A)),
                ],
              ),
            ),
          ),
          onTap: () {
            _logger.i('🌐 AccountScreen: Language row tapped — opening picker');
            _showLanguagePicker(provider);
          },
        );
      },
    );
  }

  void _showLanguagePicker(LocaleProvider provider) {
    _logger.i('🌐 AccountScreen: _showLanguagePicker() called');
    _logger.d('🌐 AccountScreen: provider.language before open = ${provider.language}');
    _logger.d('🌐 AccountScreen: provider.locale before open = ${provider.locale}');
    _logger.d('🌐 AccountScreen: Available languages = ${AppLanguage.values}');

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) {
        _logger.d('🌐 AccountScreen: Bottom sheet builder called');
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Select Language',
                      style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const Divider(height: 1),
                ...AppLanguage.values.map((lang) {
                  _logger.d('🌐 AccountScreen: Building language option — $lang '
                      '(${kLanguageLabels[lang]})');
                  return ListenableBuilder(
                    listenable: provider,
                    builder: (context, _) {
                      final isSelected = provider.language == lang;
                      _logger.d('🌐 AccountScreen: ListenableBuilder for $lang — '
                          'isSelected=$isSelected, provider.language=${provider.language}');
                      return ListTile(
                        leading: Text(kLanguageFlags[lang]!,
                            style: const TextStyle(fontSize: 28)),
                        title: Text(
                          kLanguageLabels[lang]!,
                          style: GoogleFonts.poppins(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected ? const Color(0xFF0A2E5A) : null),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle,
                                color: Color(0xFF0A2E5A))
                            : null,
                        onTap: () {
                          _logger.i('🌐 AccountScreen: Language selected — $lang '
                              '(${kLanguageLabels[lang]})');
                          _logger.d('🌐 AccountScreen: Previous language = '
                              '${provider.language}, locale = ${provider.locale}');

                          try {
                            provider.setLanguage(lang);
                            _logger.i('🌐 AccountScreen: provider.setLanguage($lang) called successfully');
                            _logger.d('🌐 AccountScreen: provider.language after set = '
                                '${provider.language}, locale = ${provider.locale}');
                          } catch (e, stack) {
                            _logger.e('❌ AccountScreen: provider.setLanguage($lang) threw — $e');
                            _logger.d('❌ AccountScreen: Stack trace:\n$stack');
                          }

                          _logger.d('🌐 AccountScreen: Closing bottom sheet');
                          Navigator.pop(sheetContext);

                          _logger.d('🌐 AccountScreen: Showing snackbar confirmation');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Language changed to ${kLanguageLabels[lang]}'),
                              duration: const Duration(seconds: 2),
                            ),
                          );

                          _logger.i('🌐 AccountScreen: Language switch flow complete — '
                              'new language=${provider.language}, locale=${provider.locale}');
                        },
                      );
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      _logger.d('🌐 AccountScreen: Bottom sheet dismissed — '
          'final language=${provider.language}, locale=${provider.locale}');
    });
  }

  Widget _buildSettingsTile(
    IconData icon,
    String title,
    Widget trailing, {
    VoidCallback? onTap,
    Color? textColor,
    Color? iconColor,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: iconColor ?? Colors.grey[700]),
      title: Text(title, style: GoogleFonts.poppins(color: textColor)),
      trailing: trailing,
      onTap: onTap,
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────────

  Widget _buildFooter(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      color: const Color(0xFF0A2E5A),
      child: Text(
        '© 2026 JV Alma C.I.S Site Management System',
        style: TextStyle(
            color: Colors.white,
            fontSize: isMobile ? 12 : 14,
            fontWeight: FontWeight.w400),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _showComingSoon(String feature) {
    _logger.d('👤 AccountScreen: "$feature" tapped — coming soon');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature coming soon')),
    );
  }

  void _showLogoutDialog() {
    _logger.i('🚪 AccountScreen: Logout dialog opened');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.red),
            SizedBox(width: 8),
            Text('Logout'),
          ],
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () {
              _logger.d('🚪 AccountScreen: Logout cancelled');
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              navigator.pop(); // close the confirmation dialog
              _logger.i('🚪 AccountScreen: Logging out');
              try {
                // AuthService.logout() clears the persisted "isLoggedIn" flag
                // AND signs out of Firebase Auth. Calling _auth.signOut()
                // alone (the previous behavior) left the persisted flag
                // stale, and nothing navigated the user away from this
                // screen afterward — they'd appear "logged out" under the
                // hood while still looking at their (now-broken) account
                // page. Mirrors WelcomeScreen's logout button.
                await _authService.logout();
                _logger.i('🚪 AccountScreen: logout() succeeded');
              } catch (e) {
                _logger.e('❌ AccountScreen: logout() failed — $e');
              }
              if (!mounted) return;
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _logger.i('🧹 AccountScreen: dispose() called');
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}