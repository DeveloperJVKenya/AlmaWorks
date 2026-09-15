import 'dart:async';

import 'package:almaworks/models/inventory/material_fabrication_order_model.dart';
import 'package:almaworks/models/inventory/material_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/fabrication_form_pdf.dart';
import 'package:almaworks/screens/inventory/inventory_error_messages.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/confirm_dialog.dart';
import 'package:almaworks/widgets/inventory_form_section.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';

/// MainAdmin/Admin: issue a quantity of a material for fabrication —
/// decided per issue, not a fixed material property. Creates the order,
/// decrements storage, then offers an immediate "Download Form" so the
/// printed chain-of-custody form (Driver -> Fabricator -> Driver ->
/// Technician, none but the Technician with an app account) can travel
/// with the goods.
class CreateFabricationOrderScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final MaterialModel material;
  final String createdByUid;
  final String createdByName;
  final String createdByRole;

  const CreateFabricationOrderScreen({
    super.key,
    required this.project,
    required this.logger,
    required this.material,
    required this.createdByUid,
    required this.createdByName,
    required this.createdByRole,
  });

  @override
  State<CreateFabricationOrderScreen> createState() => _CreateFabricationOrderScreenState();
}

class _CreateFabricationOrderScreenState extends State<CreateFabricationOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _fabricatorController = TextEditingController();
  final InventoryService _inventoryService = InventoryService();

  List<ProjectModel> _projects = [];
  bool _projectsLoaded = false;
  String? _projectsError;
  ProjectModel? _selectedProject;
  StreamSubscription<QuerySnapshot>? _projectsSub;

  bool _isSaving = false;
  MaterialFabricationOrderModel? _createdOrder;

  @override
  void initState() {
    super.initState();
    _subscribeProjects();
  }

  // Deliberately NOT ProjectService.getAllProjects(): that method caches one
  // shared broadcast StreamController per process, and broadcast streams
  // never replay their most recent value to a late subscriber — a screen
  // that subscribes after another screen already consumed the latest
  // snapshot gets nothing until Firestore emits a brand-new one, which for
  // the rarely-changing `Projects` collection can mean an indefinitely
  // stuck spinner. Querying Firestore directly avoids that entirely.
  void _subscribeProjects() {
    _projectsSub?.cancel();
    setState(() => _projectsError = null);
    _projectsSub = FirebaseFirestore.instance.collection('Projects').snapshots().listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          _projects = snapshot.docs.map(ProjectModel.fromFirestore).toList();
          _projectsLoaded = true;
          _projectsError = null;
          final matches = _projects.where((p) => p.id == widget.project.id);
          _selectedProject = matches.isEmpty ? null : matches.first;
        });
      },
      onError: (e) {
        widget.logger.e('❌ CreateFabricationOrderScreen: Projects stream error', error: e);
        if (!mounted) return;
        setState(() {
          _projectsLoaded = true;
          _projectsError = 'Could not load projects: $e';
        });
      },
    );
  }

  @override
  void dispose() {
    _projectsSub?.cancel();
    _quantityController.dispose();
    _fabricatorController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final quantity = double.tryParse(_quantityController.text.trim());
    if (quantity == null || quantity <= 0) return;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Issue for Fabrication',
      message: 'Issue $quantity ${widget.material.unit} of "${widget.material.name}" for fabrication?',
      confirmLabel: 'Issue',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final order = await _inventoryService.createFabricationOrder(
        materialId: widget.material.id,
        materialName: widget.material.name,
        unit: widget.material.unit,
        quantity: quantity,
        projectId: _selectedProject?.id,
        projectName: _selectedProject?.name,
        expectedFabricatorName:
            _fabricatorController.text.trim().isEmpty ? null : _fabricatorController.text.trim(),
        issuedByUid: widget.createdByUid,
        issuedByName: widget.createdByName,
        issuedByRole: widget.createdByRole,
      );
      if (!mounted) return;
      setState(() => _createdOrder = order);
    } catch (e) {
      widget.logger.e('❌ CreateFabricationOrderScreen: Failed to submit', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyInventoryError(e), style: GoogleFonts.poppins()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _downloadForm() async {
    if (_createdOrder == null) return;
    await generateAndSaveFabricationForm(context: context, logger: widget.logger, order: _createdOrder!);
  }

  @override
  Widget build(BuildContext context) {
    return BaseLayout(
      title: 'Issue for Fabrication',
      project: widget.project,
      logger: widget.logger,
      selectedMenuItem: 'Inventory',
      onMenuItemSelected: (_) {},
      child: Container(
        color: inventoryPageBackground,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              inventoryFormMaxWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_createdOrder == null) ..._buildForm() else ..._buildSuccess(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildForm() {
    return [
      inventoryFormSection(
        title: widget.material.name,
        icon: Icons.precision_manufacturing_outlined,
        subtitle: '${widget.material.quantityInStorage} ${widget.material.unit} currently in storage',
        children: [
          TextFormField(
            controller: _quantityController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: inventoryInputDecoration(
              label: 'Quantity to issue (${widget.material.unit})',
              icon: Icons.numbers_outlined,
            ),
            validator: (v) {
              final q = double.tryParse((v ?? '').trim());
              if (q == null || q <= 0) return 'Enter a valid quantity';
              if (q > widget.material.quantityInStorage) return 'Only ${widget.material.quantityInStorage} available';
              return null;
            },
          ),
          const SizedBox(height: 14),
          if (!_projectsLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_projectsError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_projectsError!, style: GoogleFonts.poppins(fontSize: 12, color: Colors.red[800])),
                  ),
                  TextButton(onPressed: _subscribeProjects, child: const Text('Retry')),
                ],
              ),
            )
          else
            DropdownButtonFormField<ProjectModel>(
              initialValue: _selectedProject,
              isExpanded: true,
              decoration: inventoryInputDecoration(label: 'Destination site', icon: Icons.location_on_outlined),
              items: _projects
                  .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(p.name, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins()),
                      ))
                  .toList(),
              onChanged: (value) => setState(() => _selectedProject = value),
            ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _fabricatorController,
            decoration: inventoryInputDecoration(
              label: 'Expected fabricator (optional)',
              hint: 'Best guess — corrected against the scan later',
              icon: Icons.factory_outlined,
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      inventoryPrimaryButton(
        label: 'Issue',
        isLoading: _isSaving,
        onPressed: _submit,
        icon: Icons.local_shipping_outlined,
      ),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _buildSuccess() {
    return [
      inventoryFormSection(
        title: 'Order Created',
        icon: Icons.check_circle_outline,
        subtitle: 'Form ID: ${_createdOrder!.id}',
        children: [
          Text(
            'Download and print the chain-of-custody form, then hand it to the Driver/Transporter along with '
            '"${widget.material.name}". The completed form gets scanned back into the app once it reaches the Technician.',
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[700]),
          ),
        ],
      ),
      const SizedBox(height: 4),
      inventoryPrimaryButton(
        label: 'Download Form',
        isLoading: false,
        onPressed: _downloadForm,
        icon: Icons.picture_as_pdf_outlined,
      ),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Done', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(height: 24),
    ];
  }
}
