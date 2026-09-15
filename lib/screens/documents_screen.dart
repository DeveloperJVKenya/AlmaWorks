import 'dart:async';

import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/models/document_audit_model.dart';
import 'package:almaworks/screens/projects/edit_project_screen.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; 
import 'package:open_file/open_file.dart';
import 'package:almaworks/helpers/download_helper.dart';

class DocumentsScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  
  const DocumentsScreen({
    super.key,
    required this.project,
    required this.logger,
  });

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> with TickerProviderStateMixin {
  late TabController _mainTabController;
  late TabController _clientSubTabController;
  late TabController _subContractorSubTabController;
  late TabController _supplierSubTabController;
  bool _isLoading = false;
  late ProjectModel _currentProject;
  String? _selectedSubcontractor;
  String? _selectedSupplier;
  String? _userRole;
  bool _isLoadingUserData = true;
  String _actorUid = '';
  String _actorName = '';

  // When the project's team has members whose role is neither
  // 'subcontractor' nor 'supplier' (e.g. 'technician', or a free-text
  // custom role defined via edit_project_screen.dart's "Define New" option),
  // the Supplier tab exposes a dropdown to switch to one of those roles
  // instead. Null means the tab is showing Supplier (the default).
  String? _selectedOtherRole;
  String? _selectedOtherRoleMember;

  final List<String> _mainTabs = ['Client', 'Sub-Contractor', 'Supplier'];
  final List<String> _subSections = ['Contract', 'Communication'];

  // Only Admin/SystemAdmin/MainAdmin may upload or delete documents;
  // Client AND Technician are view-only everywhere, including download.
  bool get _canManageDocuments =>
      _userRole == 'Admin' ||
      _userRole == 'SystemAdmin' ||
      _userRole == 'MainAdmin';

  bool get _isTechnician => _userRole == 'Technician';

  // Distinct team-member roles other than subcontractor/supplier, in
  // first-seen order, case-insensitively de-duplicated.
  List<String> get _otherRoles {
    final seen = <String>{};
    final result = <String>[];
    for (final m in _currentProject.teamMembers) {
      final role = m.role.trim();
      if (role.isEmpty) continue;
      final lower = role.toLowerCase();
      if (lower == 'subcontractor' || lower == 'supplier') continue;
      if (seen.add(lower)) result.add(role);
    }
    return result;
  }

  // Client tab has an extra "Access Requests" sub-tab that Sub-Contractor
  // and Supplier tabs do not expose.
  final List<String> _clientSubSections = [
    'Contract',
    'Communication',
    'Access Requests',
  ];

  @override
  void initState() {
    super.initState();
    _currentProject = widget.project;
    
    // Initialize tab controllers immediately with default values
    _mainTabController = TabController(length: _mainTabs.length, vsync: this);
    // Client gets 3 sub-tabs; sub-contractor and supplier keep 2.
    _clientSubTabController = TabController(length: _clientSubSections.length, vsync: this);
    _subContractorSubTabController = TabController(length: _subSections.length, vsync: this);
    _supplierSubTabController = TabController(length: _subSections.length, vsync: this);
    
    widget.logger.i('📂 DocumentsScreen: Initialized for project: ${_currentProject.name}');
    
    // Fetch user role asynchronously
    _fetchUserRole();
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    _clientSubTabController.dispose();
    _subContractorSubTabController.dispose();
    _supplierSubTabController.dispose();
    super.dispose();
  }

  /// Matches this signed-in Sub-contractor account to one of the project's
  /// Sub-Contractor team-member entries by name — same convention as the
  /// Project Manager auto-link (task_progress_monitor_screen.dart): the
  /// Users doc's own id/display name (_actorName) is exactly the string
  /// that would have been typed into the team-member's name field. Returns
  /// null (no confident match) rather than guessing, same reasoning as the
  /// PM auto-link — a SubContractor account that hasn't been added as a
  /// team member yet, or whose name doesn't exactly match, sees the empty
  /// state instead of either nothing or (worse) someone else's documents.
  String? _resolveOwnSubcontractorName() {
    final match = _currentProject.teamMembers.where(
      (m) => m.role.trim().toLowerCase() == 'subcontractor' &&
          m.name.trim().toLowerCase() == _actorName.trim().toLowerCase(),
    );
    return match.isEmpty ? null : match.first.name;
  }

  void _navigateToEditProject() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditProjectScreen(
          project: _currentProject,
          logger: widget.logger,
        ),
      ),
    ).then((_) async {
      final doc = await FirebaseFirestore.instance.collection('Projects').doc(_currentProject.id).get();
      if (doc.exists) {
        setState(() {
          _currentProject = ProjectModel.fromFirestore(doc);
          _selectedSubcontractor = null;
          _selectedSupplier = null;
          _selectedOtherRole = null;
          _selectedOtherRoleMember = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    widget.logger.d('🎨 DocumentsScreen: Building UI');

    // Show loading indicator while fetching user data
    if (_isLoadingUserData) {
      return BaseLayout(
        title: '${_currentProject.name} - Documents',
        project: _currentProject,
        logger: widget.logger,
        selectedMenuItem: 'Documents',
        onMenuItemSelected: (_) {},
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Determine if user is a client
    final bool isClient = _userRole == 'Client';
    // Sub-contractor accounts see only their own Sub-Contractor-tab
    // documents — matched to a team-member entry by name (same
    // name-matching convention used elsewhere, e.g. the Project Manager
    // auto-link in task_progress_monitor_screen.dart), the same way a
    // Client account is implicitly scoped to the "Client" tab already.
    // isClient's related conditions below (tab bar / single-section swap)
    // are deliberately reused for this rather than introduced as a
    // parallel set of checks, since the two cases are structurally
    // identical — just pointed at a different tab + memberName filter.
    final bool isSubContractorAccount = _userRole == 'SubContractor';
    final String? ownSubcontractorName = isSubContractorAccount ? _resolveOwnSubcontractorName() : null;
    final bool showSingleSection = isClient || isSubContractorAccount;

    return BaseLayout(
      title: '${_currentProject.name} - Documents',
      project: _currentProject,
      logger: widget.logger,
      selectedMenuItem: 'Documents',
      onMenuItemSelected: (_) {},
      actions: [
        if (_canManageDocuments)
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Document activity history',
            onPressed: _showAuditHistory,
          ),
      ],
      floatingActionButton: !_canManageDocuments
          ? null
          : FloatingActionButton(
              onPressed: _isLoading ? null : () {
                String role;
                TabController subController;
                String? memberName;

                // Admin/Technician/SystemAdmin/MainAdmin can access all tabs.
                role = _mainTabs[_mainTabController.index];
                switch (role) {
                  case 'Client':
                    subController = _clientSubTabController;
                    memberName = null;
                    break;
                  case 'Sub-Contractor':
                    subController = _subContractorSubTabController;
                    memberName = _selectedSubcontractor;
                    break;
                  case 'Supplier':
                    subController = _supplierSubTabController;
                    if (_selectedOtherRole != null) {
                      role = _selectedOtherRole!;
                      memberName = _selectedOtherRoleMember;
                    } else {
                      memberName = _selectedSupplier;
                    }
                    break;
                  default:
                    return;
                }

                if (role != 'Client' && memberName == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Please select a $role first', style: GoogleFonts.poppins()),
                    ),
                  );
                  return;
                }
                // Resolve which sections list to index into so that the
                // third Client sub-tab ('Access Requests') maps correctly.
                final List<String> activeSections =
                    (role == 'Client') ? _clientSubSections : _subSections;
                String section = activeSections[subController.index];
                _addDocument(role, section, teamMemberName: memberName);
              },
              backgroundColor: const Color(0xFF0A2E5A),
              foregroundColor: Colors.white,
              child: const Icon(Icons.file_upload),
            ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      // Show TabBar only for Admin-tier / Technician users —
                      // Client and Sub-contractor accounts are both
                      // implicitly scoped to one section, no tab picker.
                      if (!showSingleSection)
                        TabBar(
                          controller: _mainTabController,
                          tabs: [
                            const Tab(text: 'Client'),
                            const Tab(text: 'Sub-Contractor'),
                            Tab(child: _buildSupplierTabLabel()),
                          ],
                          labelColor: const Color(0xFF0A2E5A),
                          unselectedLabelColor: Colors.grey,
                          labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                        ),
                      SizedBox(
                        height: constraints.maxHeight - (showSingleSection ? 0 : 48) - 48,
                        child: isClient
                            ? _buildRoleSection('Client', _clientSubTabController, memberName: null, sections: _clientSubSections)
                            : isSubContractorAccount
                                ? (ownSubcontractorName == null
                                    // No Sub-Contractor team-member entry
                                    // matches this account's name yet — no
                                    // "go edit the project" shortcut here
                                    // (unlike the Admin-tier empty state),
                                    // since a Sub-contractor account can't
                                    // and shouldn't reach Edit Project.
                                    ? Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(32.0),
                                          child: Text(
                                            'No documents yet — ask your project admin to add you as a '
                                            'Sub-Contractor team member first.',
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.poppins(color: Colors.grey[600]),
                                          ),
                                        ),
                                      )
                                    : _buildRoleSection('Sub-Contractor', _subContractorSubTabController,
                                        memberName: ownSubcontractorName, sections: _subSections))
                                : TabBarView(
                                controller: _mainTabController,
                                children: [
                                  _buildRoleSection('Client', _clientSubTabController, memberName: null, sections: _clientSubSections),
                                  _buildSubcontractorContent(),
                                  _buildSupplierContent(),
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

  Widget _buildRoleSection(
    String role,
    TabController subTabController, {
    String? memberName,
    // Callers can supply their own sections list (e.g. Client's 3-tab list).
    // Falls back to the shared 2-tab list for Sub-Contractor and Supplier.
    List<String>? sections,
  }) {
    final List<String> tabSections = sections ?? _subSections;
    return LayoutBuilder(
      builder: (context, constraints) {
        // On narrow screens the sub-tab bar becomes horizontally scrollable so
        // that all tabs stay accessible without overflowing.
        final bool narrowScreen = constraints.maxWidth < 400;
        return Column(
          children: [
            TabBar(
              controller: subTabController,
              // isScrollable prevents RenderFlex overflow on slim devices.
              isScrollable: true,
              // Center the tabs on wide screens; left-align on narrow ones so
              // the first tab isn't hidden behind the screen edge.
              tabAlignment: narrowScreen
                  ? TabAlignment.start
                  : TabAlignment.center,
              tabs: tabSections
                  .map((section) => Tab(text: section))
                  .toList(),
              labelColor: const Color(0xFF0A2E5A),
              unselectedLabelColor: Colors.grey,
              labelStyle:
                  GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
            Expanded(
              child: TabBarView(
                controller: subTabController,
                children: tabSections
                    .map((section) => _buildDocumentList(
                          role,
                          section,
                          memberName: memberName,
                        ))
                    .toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSubcontractorContent() {
    final subs = _currentProject.teamMembers.where((m) => m.role == 'subcontractor').toList();
    if (subs.isEmpty) {
      return Center(
        child: _buildEmptyMemberSection('Subcontractors', _navigateToEditProject),
      );
    }
    if (_selectedSubcontractor == null) {
      return _buildMembersList(subs, (name) => setState(() => _selectedSubcontractor = name));
    } else {
      return _buildSelectedMemberSection(
        'Sub-Contractor',
        _subContractorSubTabController,
        _selectedSubcontractor!,
        () => setState(() => _selectedSubcontractor = null),
      );
    }
  }

  // The last main tab's label: plain "Supplier" text when the project has no
  // team members in any role other than subcontractor/supplier, otherwise a
  // dropdown that lets the user switch this tab between Supplier and any of
  // those other roles.
  // Sentinel for the "Supplier" menu entry — PopupMenuButton treats a
  // selection that resolves to `null` as the menu being dismissed with no
  // selection (it calls onCanceled instead of onSelected in that case), so
  // Supplier can never use a literal `null` value or picking it back after
  // switching away would silently do nothing.
  static const _supplierSentinel = '__supplier__';

  Widget _buildSupplierTabLabel() {
    final otherRoles = _otherRoles;
    final label = _selectedOtherRole == null ? 'Supplier' : _selectedOtherRole!.capitalize();
    if (otherRoles.isEmpty) {
      return Text(label);
    }
    return PopupMenuButton<String>(
      tooltip: 'Switch role',
      onSelected: (value) {
        setState(() {
          _selectedOtherRole = value == _supplierSentinel ? null : value;
          _selectedOtherRoleMember = null;
        });
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(value: _supplierSentinel, child: Text('Supplier')),
        ...otherRoles.map(
          (role) => PopupMenuItem<String>(value: role, child: Text(role.capitalize())),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
    );
  }

  Widget _buildSupplierContent() {
    if (_selectedOtherRole != null) {
      return _buildOtherRoleContent(_selectedOtherRole!);
    }
    final suppliers = _currentProject.teamMembers.where((m) => m.role == 'supplier').toList();
    if (suppliers.isEmpty) {
      return Center(
        child: _buildEmptyMemberSection('Suppliers', _navigateToEditProject),
      );
    }
    if (_selectedSupplier == null) {
      return _buildMembersList(suppliers, (name) => setState(() => _selectedSupplier = name));
    } else {
      return _buildSelectedMemberSection(
        'Supplier',
        _supplierSubTabController,
        _selectedSupplier!,
        () => setState(() => _selectedSupplier = null),
      );
    }
  }

  // Mirrors _buildSupplierContent's member-picker flow, scoped to whichever
  // "other" role was chosen from the Supplier tab's dropdown. Only the
  // Contract and Communication sub-tabs are offered for these roles — no
  // "Access Requests" sub-tab, that stays Client-only.
  Widget _buildOtherRoleContent(String role) {
    final members = _currentProject.teamMembers
        .where((m) => m.role.toLowerCase() == role.toLowerCase())
        .toList();
    if (members.isEmpty) {
      return Center(
        child: _buildEmptyMemberSection(role.capitalize(), _navigateToEditProject),
      );
    }
    if (_selectedOtherRoleMember == null) {
      return _buildMembersList(members, (name) => setState(() => _selectedOtherRoleMember = name));
    } else {
      return _buildSelectedMemberSection(
        role,
        _supplierSubTabController,
        _selectedOtherRoleMember!,
        () => setState(() => _selectedOtherRoleMember = null),
      );
    }
  }

  Widget _buildMembersList(List<TeamMember> members, Function(String) onSelected) {
    return ListView.separated(
      itemCount: members.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final member = members[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF0A2E5A),
            child: Text(
              member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(member.name, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${member.role.capitalize()}${member.category != null ? ' - ${member.category}' : ''}',
            style: GoogleFonts.poppins(color: Colors.grey[600]),
          ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () => onSelected(member.name),
        );
      },
    );
  }

  Widget _buildSelectedMemberSection(String role, TabController subController, String memberName, VoidCallback onBack) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[100],
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
              ),
              Expanded(
                child: Text(
                  'Documents for $memberName',
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildRoleSection(role, subController, memberName: memberName),
        ),
      ],
    );
  }

  Widget _buildEmptyMemberSection(String title, VoidCallback onEdit) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No $title added to this project yet',
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Add team members via the Edit Project section.',
            style: GoogleFonts.poppins(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit),
            label: Text('Go to Edit Project'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0A2E5A),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentList(String role, String section, {String? memberName}) {
    Query query = FirebaseFirestore.instance
        .collection('ProjectDocuments')
        .where('projectId', isEqualTo: _currentProject.id)
        .where('role', isEqualTo: role)
        .where('section', isEqualTo: section)
        .orderBy('uploadedAt', descending: true);
    if (memberName != null) {
      query = query.where('teamMemberName', isEqualTo: memberName);
    }
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          widget.logger.e('Firestore error: ${snapshot.error}');
          return Center(
            child: Text(
              'Error loading documents',
              style: GoogleFonts.poppins(color: Colors.red[600]),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        return ListView(
          children: [
            if (docs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Text(
                    'No documents in this section',
                    style: GoogleFonts.poppins(color: Colors.grey[600]),
                  ),
                ),
              )
            else
              ...docs.map((doc) {
                final docData = doc.data() as Map<String, dynamic>;
                final docId = doc.id;
                final title = docData['title'] as String;
                final fileName = docData['fileName'] as String;
                final url = docData['url'] as String;
                final type = docData['type'] as String;
                return ListTile(
                  leading: Icon(_getDocumentIcon(type), color: _getFileIconColor(type)),
                  title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    '$fileName - Uploaded: ${_formatDate(docData['uploadedAt'] as Timestamp)}',
                    style: GoogleFonts.poppins(color: Colors.grey[600]),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'view') {
                        _viewDocument(url, type, title);
                      } else if (value == 'download') {
                        _downloadDocument(url, fileName);
                      } else if (value == 'delete') {
                        _deleteDocument(
                          docId,
                          url,
                          role: role,
                          section: section,
                          memberName: memberName ?? '',
                          title: title,
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'view',
                        child: Row(
                          children: [
                            Icon(Icons.visibility, color: Colors.blue[600]),
                            const SizedBox(width: 8),
                            Text('View', style: GoogleFonts.poppins()),
                          ],
                        ),
                      ),
                      if (!_isTechnician)
                        PopupMenuItem(
                          value: 'download',
                          child: Row(
                            children: [
                              Icon(Icons.download, color: Colors.green[600]),
                              const SizedBox(width: 8),
                              Text('Download', style: GoogleFonts.poppins()),
                            ],
                          ),
                        ),
                      if (_canManageDocuments)
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red[600]),
                              const SizedBox(width: 8),
                              Text('Delete', style: GoogleFonts.poppins()),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Future<void> _logAuditEntry({
    required String action,
    required String role,
    required String section,
    required String memberName,
    required String documentId,
    required String documentTitle,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('DocumentAuditLog').add(
            DocumentAuditEntry(
              id: '',
              projectId: _currentProject.id,
              mainTab: role,
              section: section,
              teamMemberName: memberName,
              documentId: documentId,
              documentTitle: documentTitle,
              action: action,
              actorUid: _actorUid,
              actorName: _actorName,
              actorRole: _userRole ?? '',
              createdAt: DateTime.now(),
            ).toFirestore(),
          );
    } catch (e) {
      widget.logger.e('❌ DocumentsScreen: Failed to write audit entry', error: e);
    }
  }

  Future<void> _showAuditHistory() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.history, color: Color(0xFF0A2E5A)),
            const SizedBox(width: 10),
            Text('Document Activity', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ],
        ),
        content: SizedBox(
          width: 420,
          height: 480,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('DocumentAuditLog')
                .where('projectId', isEqualTo: _currentProject.id)
                .orderBy('createdAt', descending: true)
                .limit(100)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error loading activity', style: GoogleFonts.poppins(color: Colors.red[600])),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final entries = snapshot.data!.docs
                  .map((d) => DocumentAuditEntry.fromFirestore(d))
                  .toList();
              if (entries.isEmpty) {
                return Center(
                  child: Text('No activity recorded yet', style: GoogleFonts.poppins(color: Colors.grey[600])),
                );
              }
              return ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final e = entries[index];
                  final scope = e.teamMemberName.isNotEmpty
                      ? '${e.mainTab.capitalize()} · ${e.teamMemberName} · ${e.section}'
                      : '${e.mainTab.capitalize()} · ${e.section}';
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      e.isUpload ? Icons.upload_file : Icons.delete_outline,
                      color: e.isUpload ? Colors.green[600] : Colors.red[600],
                    ),
                    title: Text(
                      '${e.actorName} (${e.actorRole}) ${e.isUpload ? 'uploaded' : 'deleted'} "${e.documentTitle}"',
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      '$scope\n${_formatDateTime(e.createdAt)}',
                      style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[600]),
                    ),
                    isThreeLine: true,
                  );
                },
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
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '${date.day}/${date.month}/${date.year} $h:$m';
  }

  Future<void> _fetchUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        widget.logger.e('❌ DocumentsScreen: No authenticated user found');
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
        final username = querySnapshot.docs.first.id;

        if (mounted) {
          setState(() {
            _userRole = role;
            _actorUid = user.uid;
            _actorName = username;
            _isLoadingUserData = false;
          });
        }

        widget.logger.i('✅ DocumentsScreen: User role fetched: $role');
      } else {
        widget.logger.w('⚠️ DocumentsScreen: User document not found');
        if (mounted) {
          setState(() {
            _userRole = 'Client';
            _isLoadingUserData = false;
          });
        }
      }
    } catch (e) {
      widget.logger.e('❌ DocumentsScreen: Error fetching user role: $e');
      if (mounted) {
        setState(() {
          _userRole = 'Client';
          _isLoadingUserData = false;
        });
      }
    }
  }

  // Updated _addDocument method (fixed List<int> to Uint8List)
  Future<void> _addDocument(String role, String section, {String? teamMemberName}) async {
    widget.logger.i('📤 DocumentsScreen: Starting document upload for $role - $section${teamMemberName != null ? ' ($teamMemberName)' : ''}');

    try {
      setState(() => _isLoading = true);

      // withData: true ensures PlatformFile.bytes is populated on web.
      // Without this flag the bytes field is null on web and causes a
      // "Null check operator used on a null value" crash.
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'doc', 'pptx', 'ppt', 'txt'],
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        widget.logger.d('📤 DocumentsScreen: File selection cancelled');
        return;
      }

      final pickedFile = result.files.first;
      final fileName = pickedFile.name;
      final extension = fileName.split('.').last.toLowerCase();
      widget.logger.d('📤 DocumentsScreen: Picked file: $fileName');

      final title = await _getDocumentTitle(fileName.split('.').first);
      if (title == null) {
        widget.logger.d('📤 DocumentsScreen: Title input cancelled');
        return;
      }

      Uint8List fileBytes;
      if (kIsWeb) {
        // bytes is guaranteed non-null when withData: true is set above,
        // but we guard defensively so a future regression gives a clear error.
        if (pickedFile.bytes == null) {
          widget.logger.e('❌ DocumentsScreen: File bytes are null on web — withData may not have worked');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Could not read file data. Please try again.',
                  style: GoogleFonts.poppins(),
                ),
              ),
            );
          }
          return;
        }
        fileBytes = pickedFile.bytes!;
      } else {
        if (pickedFile.path == null) {
          widget.logger.e('❌ DocumentsScreen: File path is null on native');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Could not access file path. Please try again.',
                  style: GoogleFonts.poppins(),
                ),
              ),
            );
          }
          return;
        }
        fileBytes = await File(pickedFile.path!).readAsBytes();
      }

      UploadTask? uploadTask;

      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('${_currentProject.id}/Documents/${timestamp}_$fileName');

        final metadata = SettableMetadata(
          contentType: _getContentType(extension),
          customMetadata: {
            'projectId': _currentProject.id,
            'role': role,
            'section': section,
            'title': title,
            'teamMemberName': teamMemberName ?? '',
            'platform': kIsWeb ? 'web' : Platform.operatingSystem,
          },
        );

        // Create the task BEFORE opening the dialog so the StreamBuilder
        // inside the dialog can subscribe to snapshotEvents immediately.
        uploadTask = storageRef.putData(fileBytes, metadata);

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => _UploadProgressDialog(
              uploadTask: uploadTask!,
              fileName: fileName,
              onCancel: () async {
                await uploadTask?.cancel();
                widget.logger.d('📤 DocumentsScreen: Upload cancelled by user');
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
            ),
          );
        }

        await uploadTask;
        final url = await storageRef.getDownloadURL();
        widget.logger.d('📤 DocumentsScreen: Upload complete, URL obtained');

        final docRef = await FirebaseFirestore.instance
            .collection('ProjectDocuments')
            .add({
          'projectId': _currentProject.id,
          'title': title,
          'fileName': fileName,
          'url': url,
          'type': extension,
          'role': role,
          'section': section,
          'teamMemberName': teamMemberName ?? '',
          'uploadedAt': Timestamp.now(),
        });

        unawaited(_logAuditEntry(
          action: DocumentAuditEntry.actionUpload,
          role: role,
          section: section,
          memberName: teamMemberName ?? '',
          documentId: docRef.id,
          documentTitle: title,
        ));

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Document "$title" added successfully!', style: GoogleFonts.poppins()),
            ),
          );
          widget.logger.i('✅ DocumentsScreen: Document uploaded successfully: $fileName with title $title');
        }
      } on FirebaseException catch (e) {
        if (e.code == 'canceled') {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Upload cancelled', style: GoogleFonts.poppins()),
              ),
            );
          }
        } else {
          widget.logger.e('❌ DocumentsScreen: Error adding document', error: e);
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error adding document: ${e.message}', style: GoogleFonts.poppins()),
              ),
            );
          }
        }
      } catch (e) {
        widget.logger.e('❌ DocumentsScreen: Error adding document', error: e);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error adding document: ${e.toString()}', style: GoogleFonts.poppins()),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      widget.logger.e('❌ DocumentsScreen: Unexpected error in _addDocument', error: e);
    } finally {
      // Runs on every exit path — success, error, or an early return from
      // a cancelled picker/title dialog or a null bytes/path guard.
      // Previously the reset only lived in the inner try's finally, so
      // cancelling the file picker or title dialog left _isLoading stuck
      // at true, permanently disabling (dimming) the upload FAB.
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  IconData _getDocumentIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'docx':
      case 'doc':
        return Icons.description;
      case 'pptx':
      case 'ppt':
        return Icons.slideshow;
      case 'txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileIconColor(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Colors.red[600]!;
      case 'docx':
      case 'doc':
        return Colors.blueGrey[600]!;
      case 'pptx':
      case 'ppt':
        return Colors.orange[600]!;
      case 'txt':
        return Colors.grey[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  Future<String?> _getDocumentTitle(String prefilledName) async {
    String? title = prefilledName;
    final controller = TextEditingController(text: prefilledName);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Enter Document Title', style: GoogleFonts.poppins()),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Title (e.g., RFI, Close Out doc)',
              border: const OutlineInputBorder(),
              labelStyle: GoogleFonts.poppins(),
            ),
            style: GoogleFonts.poppins(),
            onChanged: (val) => title = val.trim(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            TextButton(
              onPressed: () {
                if (title != null && title!.isNotEmpty) {
                  Navigator.pop(ctx, true);
                } else {
                  if (!mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Please enter a title', style: GoogleFonts.poppins())),
                  );
                }
              },
              child: Text('OK', style: GoogleFonts.poppins()),
            ),
          ],
        );
      },
    );
    return result == true ? title : null;
  }

  String _getContentType(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'doc':
        return 'application/msword';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  String _getViewerUrl(String url, String type) {
    final encodedUrl = Uri.encodeComponent(url);
    if (type.toLowerCase() == 'pdf') {
      return url;
    } else {
      return 'https://view.officeapps.live.com/op/view.aspx?src=$encodedUrl';
    }
  }

  Future<void> _viewDocument(String url, String type, String name) async {
    widget.logger.i('👀 DocumentsScreen: Viewing document: $name ($type)');
    final connectivityResult = await Connectivity().checkConnectivity();
    final isOnline = connectivityResult.any((r) => r != ConnectivityResult.none);

    try {
      final cacheManager = DefaultCacheManager();
      FileInfo? cachedFile;
      if (isOnline) {
        cachedFile = await cacheManager.downloadFile(url);
      } else {
        cachedFile = await cacheManager.getFileFromCache(url);
      }

      if (cachedFile != null) {
        final localPath = cachedFile.file.path;
        if (type.toLowerCase() == 'txt') {
          // For TXT, read and show in dialog (works offline)
          final content = await File(localPath).readAsString();
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(name, style: GoogleFonts.poppins()),
                content: SingleChildScrollView(
                  child: SelectableText(content, style: GoogleFonts.poppins()),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Close', style: GoogleFonts.poppins()),
                  ),
                ],
              ),
            );
          }
        } else if (kIsWeb) {
          // On web, always use launchUrl (can't open local files directly)
          final viewerUrl = _getViewerUrl(url, type);
          final uri = Uri.parse(viewerUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            if (mounted) {
              widget.logger.e('Could not launch $viewerUrl');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Could not open document viewer', style: GoogleFonts.poppins()),
                ),
              );
            }
          }
        } else {
          // On native, open local file with system viewer (prompts if multiple apps)
          final result = await OpenFile.open(localPath);
          if (result.type != ResultType.done && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not open file: ${result.message}', style: GoogleFonts.poppins()),
                action: SnackBarAction(
                  label: 'Download instead',
                  onPressed: () => _downloadDocument(url, name),
                ),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No internet and no cache available', style: GoogleFonts.poppins()),
            ),
          );
        }
      }
    } catch (e) {
      widget.logger.e('Error viewing document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error viewing document: $e', style: GoogleFonts.poppins()),
          ),
        );
      }
    }
  }

  Future<void> _downloadDocument(String url, String name) async {
    widget.logger.i('⬇️ Downloading: $name');
    try {
      // Fetch file bytes from URL
      final response = await Dio().get(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final Uint8List bytes = response.data;

      // Use platform-specific download helper
      final result = await platformDownloadFile(bytes, name);

      if (!mounted) return;

      if (result != null) {
        // Success: result is either a path (mobile) or message (web)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kIsWeb 
                ? result  // Web: "Download started. Check your browser downloads."
                : 'Downloaded successfully!\nLocation: $result',  // Mobile: Full path
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Open',
              textColor: Colors.white,
              onPressed: () async {
                if (!kIsWeb) {
                  await OpenFile.open(result);
                }
              },
            ),
          ),
        );
      } else {
        // User cancelled (shouldn't happen with new implementation)
        widget.logger.d('Download cancelled by user');
      }
    } catch (e) {
      widget.logger.e('❌ Error downloading', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains('permission')
                ? 'Storage permission denied. Please enable it in Settings.'
                : 'Error downloading: $e',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: e.toString().contains('permission')
              ? SnackBarAction(
                  label: 'Settings',
                  textColor: Colors.white,
                  onPressed: () => openAppSettings(),
                )
              : null,
          ),
        );
      }
    }
  }

  Future<void> _deleteDocument(
    String docId,
    String url, {
    required String role,
    required String section,
    required String memberName,
    required String title,
  }) async {
    widget.logger.i('🗑️ DocumentsScreen: Deleting document: $docId');
    try {
      widget.logger.d('🗑️ DocumentsScreen: Deleting from storage');
      final ref = FirebaseStorage.instance.refFromURL(url);
      await ref.delete();
      widget.logger.d('🗑️ DocumentsScreen: Deleting from Firestore');
      await FirebaseFirestore.instance
          .collection('ProjectDocuments')
          .doc(docId)
          .delete();

      unawaited(_logAuditEntry(
        action: DocumentAuditEntry.actionDelete,
        role: role,
        section: section,
        memberName: memberName,
        documentId: docId,
        documentTitle: title,
      ));

      if (mounted) {
        widget.logger.i('✅ DocumentsScreen: Document deleted successfully');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Document deleted successfully', style: GoogleFonts.poppins()),
          ),
        );
      }
    } catch (e) {
      widget.logger.e('❌ DocumentsScreen: Error deleting document', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting: $e', style: GoogleFonts.poppins()),
          ),
        );
      }
    }
  }

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year}';
  }
}

// ---------------------------------------------------------------------------
// Dedicated upload-progress dialog
// ---------------------------------------------------------------------------
// Uses its own StatefulWidget so it owns the stream subscription and calls
// its own setState — completely independent of the parent screen's state.
// This is the only reliable pattern for live progress inside showDialog.
// ---------------------------------------------------------------------------

class _UploadProgressDialog extends StatefulWidget {
  final UploadTask uploadTask;
  final String fileName;
  final VoidCallback onCancel;

  const _UploadProgressDialog({
    required this.uploadTask,
    required this.fileName,
    required this.onCancel,
  });

  @override
  State<_UploadProgressDialog> createState() => _UploadProgressDialogState();
}

class _UploadProgressDialogState extends State<_UploadProgressDialog> {
  double _progress = 0.0;
  String _bytesLabel = '';
  String _statusLabel = 'Preparing…';
  StreamSubscription<TaskSnapshot>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.uploadTask.snapshotEvents.listen(
      (TaskSnapshot snap) {
        if (!mounted) return;
        final transferred = snap.bytesTransferred;
        final total = snap.totalBytes;
        setState(() {
          _progress = total > 0 ? transferred / total : 0.0;
          final tMB = (transferred / 1048576).toStringAsFixed(1);
          final totalMB = (total / 1048576).toStringAsFixed(1);
          _bytesLabel = '$tMB MB / $totalMB MB';
          _statusLabel = _progress >= 1.0 ? 'Finalising…' : 'Uploading…';
        });
      },
      onError: (_) {/* parent handles errors */},
      cancelOnError: true,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_progress * 100).toStringAsFixed(0);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined, color: Color(0xFF0A2E5A), size: 22),
          const SizedBox(width: 10),
          Text(
            'Uploading Document',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),

            // ── Circular ring with % in the centre ───────────────────────
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    value: _progress,
                    strokeWidth: 9,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0A2E5A)),
                  ),
                ),
                Text(
                  '$pct%',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0A2E5A),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 22),

            // ── Rounded linear bar ────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0A2E5A)),
              ),
            ),

            const SizedBox(height: 12),

            // ── Status label + bytes transferred ─────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _statusLabel,
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                ),
                if (_bytesLabel.isNotEmpty)
                  Text(
                    _bytesLabel,
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                  ),
              ],
            ),

            const SizedBox(height: 6),

            // ── File name ─────────────────────────────────────────────────
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.fileName,
                style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade400),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.red[600])),
        ),
      ],
    );
  }
}