import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/services/project_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

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
  }

  /// MainAdmin/Admin accounts eligible to be linked as this project's PM —
  /// approval rights for task date-extension requests go to whoever is
  /// linked here (or any MainAdmin, regardless of link) plus this drives
  /// who a request actually gets a notification sent to.
  Future<void> _loadPmCandidates() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('Users')
          .where('role', whereIn: ['MainAdmin', 'Admin'])
          .get();
      final candidates = snap.docs
          .map((d) => (uid: d.data()['uid'] as String? ?? '', name: d.id))
          .where((c) => c.uid.isNotEmpty)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
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
      title: 'Edit ${widget.project.name}',
      project: widget.project,
      selectedMenuItem: 'Edit Project', // No specific menu item selected
      logger: _logger,
      onMenuItemSelected: _handleMenuNavigation,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _updateProject,
        backgroundColor: const Color(0xFF0A2E5A),
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
        label: Text(_isLoading ? 'Updating...' : 'Update Project'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$menuItem section coming soon')),
        );
    }
  }

  Widget _buildBasicInformationCard(bool isMobile) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Basic Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Project Name — required
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                label: RichText(
                  text: const TextSpan(
                    text: 'Project Name ',
                    style: TextStyle(color: Colors.black87, fontSize: 16),
                    children: [
                      TextSpan(
                        text: '*',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.business, color: Colors.indigo),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a project name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // Description — optional
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (Optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description, color: Colors.teal),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            // Contract Number — optional
            TextFormField(
              controller: _contractNumberController,
              decoration: const InputDecoration(
                labelText: 'Contract Number (Optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.tag, color: Colors.orange),
              ),
            ),
            const SizedBox(height: 16),
            // Location — required
            TextFormField(
              controller: _locationController,
              decoration: InputDecoration(
                label: RichText(
                  text: const TextSpan(
                    text: 'Location ',
                    style: TextStyle(color: Colors.black87, fontSize: 16),
                    children: [
                      TextSpan(
                        text: '*',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.location_on, color: Colors.red),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a project location';
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
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Project Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _budgetController,
              decoration: const InputDecoration(
                labelText: 'Budget (USD)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money, color: Colors.green),
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
              decoration: const InputDecoration(
                labelText: 'Status (Optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.flag, color: Color(0xFFFFB300)),
              ),
              items: const [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Untracked'),
                ),
                DropdownMenuItem<String?>(
                  value: 'active',
                  child: Text('Active'),
                ),
                DropdownMenuItem<String?>(
                  value: 'completed',
                  child: Text('Completed'),
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
              decoration: const InputDecoration(
                labelText: 'Project Manager *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person, color: Colors.blue),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a project manager';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _selectedPmUid,
              decoration: const InputDecoration(
                labelText: 'Linked PM Account (optional)',
                helperText: 'Enables this person to receive and approve task date-extension requests',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.verified_user_outlined, color: Colors.blue),
              ),
              hint: Text(_pmCandidatesLoading ? 'Loading accounts…' : 'No linked account'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('No linked account')),
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
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Timeline',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[400]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                leading: const Icon(Icons.calendar_today, color: Color(0xFF0A2E5A)),
                title: const Text('Start Date'),
                subtitle: Text(_formatDate(_startDate)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _selectStartDate(),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[400]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                leading: const Icon(Icons.event, color: Color(0xFF0A2E5A)),
                title: const Text('End Date (Optional)'),
                subtitle: Text(_endDate != null ? _formatDate(_endDate!) : 'Not set'),
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
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Team Members',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedRole,
              decoration: const InputDecoration(
                labelText: 'Role *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.work, color: Colors.purple),
              ),
              items: const [
                DropdownMenuItem<String>(
                  value: 'subcontractor',
                  child: Text('Subcontractor'),
                ),
                DropdownMenuItem<String>(
                  value: 'supplier',
                  child: Text('Supplier'),
                ),
                DropdownMenuItem<String>(
                  value: 'technician',
                  child: Text('Technician'),
                ),
                DropdownMenuItem<String>(
                  value: '__define_new__',
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline,
                          size: 18, color: Colors.deepPurple),
                      SizedBox(width: 8),
                      Text(
                        'Define New',
                        style: TextStyle(
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
                decoration: const InputDecoration(
                  labelText: 'Define Role Name *',
                  hintText: 'e.g., Site Foreman, Safety Officer',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.edit_note, color: Colors.deepPurple),
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _teamMemberController,
              decoration: const InputDecoration(
                labelText: 'Team Member Name *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_add, color: Colors.teal),
              ),
              onFieldSubmitted: (_) => _addTeamMember(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _categoryController,
              decoration: const InputDecoration(
                labelText: 'Category (Optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category, color: Colors.orange),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _addTeamMember,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2E5A),
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            if (_teamMembers.isNotEmpty) ...[
              const Text(
                'Team Members:',
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
                    label: Text('${member.name} (${member.role.capitalize()}${member.category != null ? ' - ${member.category}' : ''})'),
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
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  children: [
                    Icon(Icons.people_outline,
                       size: 48,
                       color: Colors.grey[400]
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No team members added yet',
                      style: TextStyle(
                        color: Colors.grey[600],
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
      color: const Color(0xFF0A2E5A),
      child: Text(
        '© 2025 JV Alma C.I.S Site Management System',
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

  void _addTeamMember() {
    if (_selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a role')),
      );
      return;
    }
    // Resolve the actual role string
    String resolvedRole;
    if (_isDefiningCustomRole) {
      final customRole = _customRoleController.text.trim();
      if (customRole.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a custom role name')),
        );
        return;
      }
      resolvedRole = customRole;
    } else {
      resolvedRole = _selectedRole!;
    }
    if (_teamMemberController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a team member name')),
      );
      return;
    }
    final name = _teamMemberController.text.trim();
    final category = _categoryController.text.trim().isNotEmpty ? _categoryController.text.trim() : null;
    if (_teamMembers.any((m) => m.name == name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Team member already exists'),
          backgroundColor: Colors.orange,
        ),
      );
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
          final scaffoldMessenger = ScaffoldMessenger.of(context);
          
          navigator.pop(true);
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('Project "${updatedProject.name}" updated successfully!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } catch (e, stackTrace) {
        _logger.e('❌ EditProjectScreen: Error updating project',
          error: e, stackTrace: stackTrace);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating project: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
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