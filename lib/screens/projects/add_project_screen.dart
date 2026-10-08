import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/services/project_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/theme/app_colors.dart';
import 'package:almaworks/core/errors/friendly_error.dart';

class AddProjectScreen extends StatefulWidget {
  final Logger logger;

  const AddProjectScreen({super.key, required this.logger});

  @override
  State<AddProjectScreen> createState() => _AddProjectScreenState();
}

class _AddProjectScreenState extends State<AddProjectScreen> {
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
    _logger.i('🏗️ AddProjectScreen: Initialized');
  }

  @override
  Widget build(BuildContext context) {
    _logger.d('🎨 AddProjectScreen: Building UI');

    return BaseLayout(
      title: context.l10n.addNewProject,
      selectedMenuItem: 'Add Project', // No specific menu item selected
      logger: _logger,
      onMenuItemSelected: _handleMenuNavigation,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            children: [
              Center(
                child: ConstrainedBox(
                  // keeps the form readable on wide screens
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Padding(
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
                    const SizedBox(height: 32),
                    _buildSaveButton(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
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
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.basicInformation,
              style: TextStyle(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: isMobile ? 12 : 16),
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
            SizedBox(height: isMobile ? 12 : 16),
            // Description — optional
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: l.descriptionOptionalCap,
                border: OutlineInputBorder(),
                prefixIcon: const Icon(Icons.description, color: Colors.teal),
              ),
              maxLines: 3,
            ),
            SizedBox(height: isMobile ? 12 : 16),
            // Contract Number — optional
            TextFormField(
              controller: _contractNumberController,
              decoration: InputDecoration(
                labelText: l.contractNumberOptional,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.tag, color: Colors.orange),
              ),
            ),
            SizedBox(height: isMobile ? 12 : 16),
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
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.projectDetails,
              style: TextStyle(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: isMobile ? 12 : 16),
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
            SizedBox(height: isMobile ? 12 : 16),
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
                _logger.d('📝 AddProjectScreen: Status changed to $_selectedStatus');
              },
            ),
            SizedBox(height: isMobile ? 12 : 16),
            // Project Manager — required
            TextFormField(
              controller: _projectManagerController,
              decoration: InputDecoration(
                label: requiredFieldLabel(l.projectManager),
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
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.timeline,
              style: TextStyle(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.bold
              ),
            ),
            SizedBox(height: isMobile ? 12 : 16),
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
            SizedBox(height: isMobile ? 12 : 16),
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
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.teamMembers,
              style: TextStyle(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: isMobile ? 12 : 16),
            // Role dropdown with Define New option
            DropdownButtonFormField<String>(
              initialValue: _selectedRole,
              decoration: InputDecoration(
                label: requiredFieldLabel(l.role),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.work, color: Colors.purple),
              ),
              items: [
                for (final r in const ['subcontractor', 'supplier', 'technician', 'manager'])
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
                _logger.d('📝 AddProjectScreen: Role selected: $_selectedRole');
              },
            ),
            // Custom role text field — visible only when Define New is selected
            if (_isDefiningCustomRole) ...[
              SizedBox(height: isMobile ? 12 : 16),
              TextFormField(
                controller: _customRoleController,
                decoration: InputDecoration(
                  labelText: l.defineRoleName,
                  hintText: l.defineRoleHint,
                  border: const OutlineInputBorder(),
                  prefixIcon:
                      const Icon(Icons.edit_note, color: Colors.deepPurple),
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ],
            SizedBox(height: isMobile ? 12 : 16),
            TextFormField(
              controller: _teamMemberController,
              decoration: InputDecoration(
                labelText: l.teamMemberName,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.person_add, color: Colors.teal),
              ),
              onFieldSubmitted: (_) => _addTeamMember(),
            ),
            SizedBox(height: isMobile ? 12 : 16),
            TextFormField(
              controller: _categoryController,
              decoration: InputDecoration(
                labelText: l.categoryOptional,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.category, color: Colors.orange),
              ),
            ),
            SizedBox(height: isMobile ? 12 : 16),
            ElevatedButton.icon(
              onPressed: _addTeamMember,
              icon: const Icon(Icons.add),
              label: Text(l.add),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
              ),
            ),
            SizedBox(height: isMobile ? 12 : 16),
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
                    label: Text(
                        '${member.name} (${teamRoleLabel(member.role)}${member.category != null ? ' - ${member.category}' : ''})'),
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
                        size: 48, color: AppColors.inkFaint),
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

  Widget _buildSaveButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveProject,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: _isLoading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(context.l10n.creatingProject, style: const TextStyle(fontSize: 16)),
                ],
              )
            : Text(
                context.l10n.createProject,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
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

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _selectStartDate() async {
    _logger.d('📅 AddProjectScreen: Selecting start date');
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null && picked != _startDate) {
      setState(() {
        _startDate = picked;
      });
      _logger.i('✅ AddProjectScreen: Start date selected: $_startDate');
    }
  }

  Future<void> _selectEndDate() async {
    _logger.d('📅 AddProjectScreen: Selecting end date');
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
      _logger.i('✅ AddProjectScreen: End date selected: $_endDate');
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
    _logger.i('👥 AddProjectScreen: Team member added. Total: ${_teamMembers.length}');
  }

  void _removeTeamMember(TeamMember member) {
    setState(() {
      _teamMembers.remove(member);
    });
    _logger.i('👥 AddProjectScreen: Team member removed: ${member.name}');
  }

  void _saveProject() async {
    _logger.i('💾 AddProjectScreen: Save project initiated');

    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });
      try {
        _logger.d('🏗️ AddProjectScreen: Creating project model');

        final newProject = ProjectModel(
          id: '',
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          location: _locationController.text.trim(),
          contractNumber: _contractNumberController.text.trim().isNotEmpty
              ? _contractNumberController.text.trim()
              : null,
          budget: _budgetController.text.isNotEmpty
              ? double.tryParse(_budgetController.text.replaceAll(',', ''))
              : null,
          status: _selectedStatus,
          startDate: _startDate,
          endDate: _endDate,
          projectManager: _projectManagerController.text.trim(),
          teamMembers: _teamMembers,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        _logger.i('📋 AddProjectScreen: Project model created - Name: ${newProject.name}');
        _logger.d('📤 AddProjectScreen: Saving to Firestore...');

        final projectId = await _projectService.addProject(newProject);

        _logger.i('✅ AddProjectScreen: Project saved successfully with ID: $projectId');

        if (mounted) {
          final navigator = Navigator.of(context);
          final message = context.l10n.projectCreated(newProject.name);
          showSuccessSnack(context, message);
          navigator.pop(true);
        }
      } catch (e, stackTrace) {
        _logger.e('❌ AddProjectScreen: Error saving project',
          error: e, stackTrace: stackTrace);

        if (mounted) {
          showErrorSnack(context, e, action: context.l10n.couldNotCreateProject);
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      _logger.w('⚠️ AddProjectScreen: Form validation failed');
    }
  }

  @override
  void dispose() {
    _logger.i('🧹 AddProjectScreen: Disposing controllers');
    _nameController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _contractNumberController.dispose();
    _budgetController.dispose();
    _projectManagerController.dispose();
    _teamMemberController.dispose();
    _categoryController.dispose();
    _customRoleController.dispose();
    super.dispose();
  }
}

/// A form-field label with a red "required" star; follows the theme's text
/// color (so it stays readable in dark mode).
Widget requiredFieldLabel(String text) => Text.rich(
  TextSpan(
    text: '$text ',
    children: const [
      TextSpan(
        text: '*',
        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
      ),
    ],
  ),
);

/// Display name for a stored team-member role ('subcontractor', …); custom
/// roles typed by a user are shown as written.
String teamRoleLabel(String role) {
  final l = l10nNow;
  return switch (role) {
    'subcontractor' => l.teamRoleSubcontractor,
    'supplier' => l.teamRoleSupplier,
    'technician' => l.teamRoleTechnician,
    'manager' => l.teamRoleManager,
    _ => role.isEmpty ? role : role.capitalize(),
  };
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}