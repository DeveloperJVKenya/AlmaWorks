import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/projects/add_project_screen.dart' show requiredFieldLabel, teamRoleLabel;
import 'package:almaworks/services/project_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/theme/app_colors.dart';
import 'package:almaworks/core/errors/friendly_error.dart';

class EditProjectScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;

  const EditProjectScreen({
    super.key,
    required this.project,
    required this.logger,
  });

  @override
  State<EditProjectScreen> createState() => _EditProjectScreenState();
}

class _EditProjectScreenState extends State<EditProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _contractNumberController = TextEditingController();
  final _budgetController = TextEditingController();
  final _projectManagerController = TextEditingController();

  String? _selectedStatus;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;

  // Linked Project Manager account (task date-extension approvals target
  // this uid) — separate from _projectManagerController's free-text name.
  String? _selectedPmUid;
  String? _selectedPmName;
  List<({String uid, String name})> _pmCandidates = [];
  bool _pmCandidatesLoading = true;
  final List<TeamMember> _teamMembers = [];
  final TextEditingController _teamMemberController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _customRoleController = TextEditingController();
  String? _selectedRole;
  bool _isDefiningCustomRole = false;

  late final ProjectService _projectService;
  late final Logger _logger;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _logger = widget.logger;
    _projectService = ProjectService();
    _populateFields();
    _loadPmCandidates();
    _logger.i('🏗️ EditProjectScreen: Initialized for project: ${widget.project.name}');
  }

  void _populateFields() {
    _nameController.text = widget.project.name;
    _descriptionController.text = widget.project.description;
    _locationController.text = widget.project.location;
    _contractNumberController.text = widget.project.contractNumber ?? '';
    _budgetController.text = widget.project.budget?.toString() ?? '';
    _projectManagerController.text = widget.project.projectManager;
    _selectedStatus = widget.project.status;
    _startDate = widget.project.startDate;
    _endDate = widget.project.endDate;
    _selectedPmUid = widget.project.projectManagerUid;
    _selectedPmName = widget.project.projectManagerAccountName;
    _teamMembers.addAll(widget.project.teamMembers);

    // Seed the dropdown's item list with the currently-linked PM (from the
    // project doc's own snapshot name) *before* the async query below ever
    // runs. DropdownButtonFormField asserts its initialValue matches
    // exactly one item — on the very first frame, before _loadPmCandidates
    // resolves, _pmCandidates would otherwise be empty while _selectedPmUid
    // already holds a real uid, which throws immediately. Also covers the
    // case where that account's role later changed away from Admin/
    // MainAdmin (so the fresh query below would no longer include them) —
    // without this, opening Edit Project for that project would crash.
    if (_selectedPmUid != null) {
      _pmCandidates = [(uid: _selectedPmUid!, name: _selectedPmName ?? _projectManagerController.text)];
    }
  }

  /// Eligible to be linked as this project's PM — approval rights for
  /// project date-extension requests go to whoever is linked here (or any
  /// MainAdmin, regardless of link), and this also drives who a request
  /// actually gets a notification sent to. Pool is the union of every
  /// MainAdmin/Admin account (unchanged, backward-compatible with projects
  /// linked before the PM-eligibility flag existed) plus anyone explicitly
  /// granted "Project Manager eligible" via the Role Access Requests
  /// screen's Change Role dialog (MainAdmin-only there) — that flag rides
  /// on top of a person's existing role rather than replacing it, so it
  /// can reach people this role-only query wouldn't otherwise include.
  Future<void> _loadPmCandidates() async {
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('Users').where('role', whereIn: ['MainAdmin', 'Admin']).get(),
        FirebaseFirestore.instance.collection('Users').where('isProjectManager', isEqualTo: true).get(),
      ]);
      final seenUids = <String>{};
      final candidates = <({String uid, String name})>[];
      for (final snap in results) {
        for (final d in snap.docs) {
          final uid = d.data()['uid'] as String? ?? '';
          if (uid.isEmpty || !seenUids.add(uid)) continue; // dedupe across the two queries
          candidates.add((uid: uid, name: d.id));
        }
      }
      // Keep the seeded currently-linked PM even if the fresh query didn't
      // return them (role changed, account since removed, etc.) — dropping
      // them here would reintroduce the same crash this seeding exists to
      // prevent, just delayed until the query resolves instead of on the
      // first frame.
      if (_selectedPmUid != null && !candidates.any((c) => c.uid == _selectedPmUid)) {
        candidates.add((uid: _selectedPmUid!, name: _selectedPmName ?? _projectManagerController.text));
      }
      candidates.sort((a, b) => a.name.compareTo(b.name));
      if (mounted) {
        setState(() {
          _pmCandidates = candidates;
          _pmCandidatesLoading = false;
        });
      }
    } catch (e) {
      _logger.e('❌ EditProjectScreen: Failed to load PM candidates', error: e);
      if (mounted) setState(() => _pmCandidatesLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _logger.d('🎨 EditProjectScreen: Building UI');

    return BaseLayout(
      title: context.l10n.editProjectName(widget.project.name),
      project: widget.project,
      selectedMenuItem: 'Edit Project', // No specific menu item selected
      logger: _logger,
      onMenuItemSelected: _handleMenuNavigation,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _updateProject,
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        icon: _isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.save),
        label: Text(_isLoading ? context.l10n.updating : context.l10n.updateProject),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildBasicInformationCard(false),
                    const SizedBox(height: 16),
                    _buildProjectDetailsCard(false),
                    const SizedBox(height: 16),
                    _buildTimelineCard(false),
                    const SizedBox(height: 16),
                    _buildTeamMembersCard(false),
                    const SizedBox(height: 96),
                  ],
                ),
              ),
              _buildFooter(context, false),
            ],
          ),
        ),
      ),
    );
  }

  void _handleMenuNavigation(String menuItem) {
    switch (menuItem) {
      case 'Switch Project':
        Navigator.pushReplacementNamed(context, '/projects');
        break;
      case 'Overview':
        Navigator.pushReplacementNamed(context, '/project-summary');
        break;
      case 'Documents':
        Navigator.pushReplacementNamed(context, '/documents');
        break;
      case 'Drawings':
        Navigator.pushReplacementNamed(context, '/drawings');
        break;
      default:
        showInfoSnack(context, context.l10n.sectionComingSoon(menuItem));
    }
  }

  Widget _buildBasicInformationCard(bool isMobile) {
    final l = context.l10n;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.basicInformation,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Project Name — required
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                label: requiredFieldLabel(l.projectName),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.business, color: Colors.indigo),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l.enterProjectName;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // Description — optional
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: l.descriptionOptionalCap,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.description, color: Colors.teal),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            // Contract Number — optional
            TextFormField(
              controller: _contractNumberController,
              decoration: InputDecoration(
                labelText: l.contractNumberOptional,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.tag, color: Colors.orange),
              ),
            ),
            const SizedBox(height: 16),
            // Location — required
            TextFormField(
              controller: _locationController,
              decoration: InputDecoration(
                label: requiredFieldLabel(l.location),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.location_on, color: Colors.red),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l.enterProjectLocation;
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectDetailsCard(bool isMobile) {
    final l = context.l10n;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.projectDetails,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _budgetController,
              decoration: InputDecoration(
                labelText: l.budgetUsd,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.attach_money, color: Colors.green),
                prefixText: '\$ ',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _selectedStatus,
              decoration: InputDecoration(
                labelText: l.statusOptional,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.flag, color: Color(0xFFFFB300)),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(l.projectStatusUntracked),
                ),
                DropdownMenuItem<String?>(
                  value: 'active',
                  child: Text(l.projectStatusActive),
                ),
                DropdownMenuItem<String?>(
                  value: 'completed',
                  child: Text(l.projectStatusCompleted),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedStatus = value;
                });
                _logger.d('📝 EditProjectScreen: Status changed to $_selectedStatus');
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _projectManagerController,
              decoration: InputDecoration(
                labelText: l.projectManagerRequired,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.person, color: Colors.blue),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l.enterProjectManager;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _selectedPmUid,
              decoration: InputDecoration(
                labelText: l.linkedPmAccount,
                helperText: l.linkedPmHelper,
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.verified_user_outlined, color: Colors.blue),
              ),
              hint: Text(_pmCandidatesLoading ? l.loadingAccounts : l.noLinkedAccount),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(l.noLinkedAccount)),
                ..._pmCandidates.map((c) => DropdownMenuItem<String?>(value: c.uid, child: Text(c.name))),
              ],
              onChanged: _pmCandidatesLoading
                  ? null
                  : (uid) {
                      setState(() {
                        _selectedPmUid = uid;
                        _selectedPmName = uid == null
                            ? null
                            : _pmCandidates.firstWhere((c) => c.uid == uid).name;
                      });
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineCard(bool isMobile) {
    final l = context.l10n;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.timeline,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                leading: Icon(Icons.calendar_today, color: AppColors.brandInk),
                title: Text(l.startDate),
                subtitle: Text(_formatDate(_startDate)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _selectStartDate(),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                leading: Icon(Icons.event, color: AppColors.brandInk),
                title: Text(l.endDateOptional),
                subtitle: Text(_endDate != null ? _formatDate(_endDate!) : l.notSet),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _selectEndDate(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamMembersCard(bool isMobile) {
    final l = context.l10n;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.teamMembers,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedRole,
              decoration: InputDecoration(
                labelText: l.roleRequired,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.work, color: Colors.purple),
              ),
              items: [
                for (final r in const ['subcontractor', 'supplier', 'technician'])
                  DropdownMenuItem<String>(value: r, child: Text(teamRoleLabel(r))),
                DropdownMenuItem<String>(
                  value: '__define_new__',
                  child: Row(
                    children: [
                      const Icon(Icons.add_circle_outline,
                          size: 18, color: Colors.deepPurple),
                      const SizedBox(width: 8),
                      Text(
                        l.defineNew,
                        style: const TextStyle(
                          color: Colors.deepPurple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedRole = value;
                  _isDefiningCustomRole = value == '__define_new__';
                  if (!_isDefiningCustomRole) _customRoleController.clear();
                });
                _logger.d('📝 EditProjectScreen: Role selected: $_selectedRole');
              },
            ),
            // Custom role text field — visible only when Define New is selected
            if (_isDefiningCustomRole) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _customRoleController,
                decoration: InputDecoration(
                  labelText: l.defineRoleName,
                  hintText: l.defineRoleHint,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.edit_note, color: Colors.deepPurple),
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _teamMemberController,
              decoration: InputDecoration(
                labelText: l.teamMemberNameRequired,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.person_add, color: Colors.teal),
              ),
              onFieldSubmitted: (_) => _addTeamMember(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _categoryController,
              decoration: InputDecoration(
                labelText: l.categoryOptional,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.category, color: Colors.orange),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _addTeamMember,
              icon: const Icon(Icons.add),
              label: Text(l.add),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            if (_teamMembers.isNotEmpty) ...[
              Text(
                l.teamMembersColon,
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _teamMembers.map((member) {
                  return Chip(
                    avatar: CircleAvatar(
                      backgroundColor: const Color(0xFF0A2E5A),
                      child: Text(
                        member.name.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    label: Text('${member.name} (${teamRoleLabel(member.role)}${member.category != null ? ' - ${member.category}' : ''})'),
                    onDeleted: () => _removeTeamMember(member),
                    deleteIcon: const Icon(Icons.close, size: 18),
                  );
                }).toList(),
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Icon(Icons.people_outline,
                       size: 48,
                       color: AppColors.inkFaint
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.noTeamMembersYet,
                      style: TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, bool isMobile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: AppColors.navy,
      child: Text(
        context.l10n.copyrightFooter,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _selectStartDate() async {
    _logger.d('📅 EditProjectScreen: Selecting start date');
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null && picked != _startDate) {
      setState(() {
        _startDate = picked;
      });
      _logger.i('✅ EditProjectScreen: Start date selected: $_startDate');
    }
  }

  Future<void> _selectEndDate() async {
    _logger.d('📅 EditProjectScreen: Selecting end date');
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(const Duration(days: 365)),
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
      _logger.i('✅ EditProjectScreen: End date selected: $_endDate');
    }
  }

  /// Keeps the linked PM account (see _selectedPmUid) reflected as a real
  /// entry in _teamMembers, role 'manager' — called right before saving.
  /// Every _teamMembers entry set anywhere else in this screen always has
  /// uid == null (see _addTeamMember/team member picker below, which never
  /// sets it), so "has a uid" is exactly how the one entry this method
  /// manages is told apart from anything the admin added manually — that's
  /// what lets this safely remove-and-re-add its own entry on every save
  /// (covers switching or clearing the linked PM) without ever touching a
  /// manually-added member, even one also named 'manager'.
  void _syncPmTeamMemberEntry() {
    _teamMembers.removeWhere((m) => m.uid != null);
    final pmUid = _selectedPmUid;
    if (pmUid != null) {
      _teamMembers.add(TeamMember(
        name: _selectedPmName ?? _projectManagerController.text.trim(),
        role: 'manager',
        uid: pmUid,
      ));
    }
  }

  void _addTeamMember() {
    if (_selectedRole == null) {
      showWarningSnack(context, context.l10n.selectRole);
      return;
    }
    // Resolve the actual role string
    String resolvedRole;
    if (_isDefiningCustomRole) {
      final customRole = _customRoleController.text.trim();
      if (customRole.isEmpty) {
        showWarningSnack(context, context.l10n.enterCustomRole);
        return;
      }
      resolvedRole = customRole;
    } else {
      resolvedRole = _selectedRole!;
    }
    if (_teamMemberController.text.isEmpty) {
      showWarningSnack(context, context.l10n.enterTeamMemberName);
      return;
    }
    final name = _teamMemberController.text.trim();
    final category = _categoryController.text.trim().isNotEmpty ? _categoryController.text.trim() : null;
    if (_teamMembers.any((m) => m.name == name)) {
      showWarningSnack(context, context.l10n.teamMemberExists);
      return;
    }
    setState(() {
      _teamMembers.add(TeamMember(name: name, role: resolvedRole, category: category));
      _teamMemberController.clear();
      _categoryController.clear();
      _customRoleController.clear();
      _selectedRole = null;
      _isDefiningCustomRole = false;
    });
    _logger.i('👥 EditProjectScreen: Team member added. Total: ${_teamMembers.length}');
  }

  void _removeTeamMember(TeamMember member) {
    setState(() {
      _teamMembers.remove(member);
    });
    _logger.i('👥 EditProjectScreen: Team member removed: ${member.name}');
  }

  void _updateProject() async {
    _logger.i('💾 EditProjectScreen: Update project initiated');

    // The floating Update Project button is always on screen, so it's easy
    // to press it right after typing a team member's name/role and forget
    // the separate "Add" step in the Team Members card. Rather than
    // silently saving without that member, add it now — or, if it can't be
    // added (e.g. no role picked), stop and let _addTeamMember's own
    // snackbar explain why instead of discarding what was typed.
    if (_teamMemberController.text.trim().isNotEmpty) {
      final countBefore = _teamMembers.length;
      _addTeamMember();
      if (_teamMembers.length == countBefore) {
        _logger.w('⚠️ EditProjectScreen: Update blocked — pending team member could not be added');
        return;
      }
    }

    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });
      try {
        _logger.d('🏗️ EditProjectScreen: Creating updated project model');
        _syncPmTeamMemberEntry();

        final updatedProject = ProjectModel(
          id: widget.project.id,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          location: _locationController.text.trim(),
          budget: _budgetController.text.isNotEmpty
              ? double.tryParse(_budgetController.text.replaceAll(',', ''))
              : null,
          status: _selectedStatus,
          startDate: _startDate,
          endDate: _endDate,
          projectManager: _projectManagerController.text.trim(),
          projectManagerUid: _selectedPmUid,
          projectManagerAccountName: _selectedPmName,
          teamMembers: _teamMembers,
          createdAt: widget.project.createdAt,
          updatedAt: DateTime.now(),
        );

        _logger.i('📋 EditProjectScreen: Updated project model created - Name: ${updatedProject.name}');
        _logger.d('📤 EditProjectScreen: Updating in Firestore...');

        await _projectService.updateProject(updatedProject);

        _logger.i('✅ EditProjectScreen: Project updated successfully');

        if (mounted) {
          final navigator = Navigator.of(context);
          showSuccessSnack(context, context.l10n.projectUpdated(updatedProject.name));
          navigator.pop(true);
        }
      } catch (e, stackTrace) {
        _logger.e('❌ EditProjectScreen: Error updating project',
          error: e, stackTrace: stackTrace);

        if (mounted) {
          showErrorSnack(context, e, action: context.l10n.couldNotUpdateProject);
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      _logger.w('⚠️ EditProjectScreen: Form validation failed');
    }
  }

  @override
  void dispose() {
    _logger.i('🧹 EditProjectScreen: Disposing controllers');
    _nameController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _budgetController.dispose();
    _projectManagerController.dispose();
    _teamMemberController.dispose();
    _categoryController.dispose();
    _customRoleController.dispose();
    super.dispose();
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}