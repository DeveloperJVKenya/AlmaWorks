import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:almaworks/models/inventory/material_model.dart';
import 'package:almaworks/models/inventory/material_movement_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/inventory_error_messages.dart';
import 'package:almaworks/screens/inventory/inventory_permissions.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/confirm_dialog.dart';
import 'package:almaworks/widgets/inventory_form_section.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';

enum MaterialMovementMode { receive, issue }

/// Records a receipt (stock coming into storage — local purchase or
/// international shipment) or an issue (stock going out to a project/site)
/// for a material. Mode-driven, mirroring RecordCustodyEventScreen's shape,
/// since the underlying flow (quantity + condition notes + photos + confirm)
/// is the same; only the field set per mode differs.
class RecordMaterialMovementScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final MaterialModel material;
  final MaterialMovementMode mode;
  final String recordedByUid;
  final String recordedByName;
  final String recordedByRole;

  const RecordMaterialMovementScreen({
    super.key,
    required this.project,
    required this.logger,
    required this.material,
    required this.mode,
    required this.recordedByUid,
    required this.recordedByName,
    required this.recordedByRole,
  });

  @override
  State<RecordMaterialMovementScreen> createState() => _RecordMaterialMovementScreenState();
}

class _RecordMaterialMovementScreenState extends State<RecordMaterialMovementScreen> {
  final InventoryService _inventoryService = InventoryService();
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();
  final _portVerifiedByController = TextEditingController();
  final _receivedByController = TextEditingController();

  final List<XFile> _selectedPhotos = [];
  bool _isSaving = false;

  // receive-only
  String _condition = MaterialMovementModel.conditionGood;

  // issue-only. Selection is tracked by primitive project id (String), not
  // the ProjectModel object itself — DropdownButtonFormField matches its
  // current value against `items` by `==`, and ProjectModel doesn't
  // override `==` (reference equality only). Since a StreamBuilder inside
  // build() recreates a brand-new list of ProjectModel instances on every
  // emission, a previously-selected instance would stop matching anything
  // in the new list, throwing "There should be exactly one item with
  // [DropdownButton]'s value" — same failure mode fixed in
  // RecordCustodyEventScreen and RequestCheckoutScreen. Loaded once up
  // front for the same reason: DropdownButtonFormField only honors
  // `initialValue` on its very first build.
  List<ProjectModel> _projects = [];
  bool _projectsLoaded = false;
  String? _projectsError;
  String? _selectedProjectId;
  StreamSubscription<QuerySnapshot>? _projectsSub;

  ProjectModel? get _selectedProject {
    if (_selectedProjectId == null) return null;
    final matches = _projects.where((p) => p.id == _selectedProjectId);
    return matches.isEmpty ? null : matches.first;
  }

  bool get _isReceive => widget.mode == MaterialMovementMode.receive;

  @override
  void initState() {
    super.initState();
    if (!_isReceive) _subscribeProjects();
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
        });
      },
      onError: (e) {
        widget.logger.e('❌ RecordMaterialMovementScreen: Projects stream error', error: e);
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
    _notesController.dispose();
    _portVerifiedByController.dispose();
    _receivedByController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage();
    if (files.isEmpty || !mounted) return;
    setState(() => _selectedPhotos.addAll(files));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final quantity = double.tryParse(_quantityController.text.trim());
    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enter a valid quantity', style: GoogleFonts.poppins())),
      );
      return;
    }

    if (!_isReceive && quantity > widget.material.quantityInStorage) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Only ${widget.material.quantityInStorage} ${widget.material.unit} remaining in storage',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
      return;
    }

    final title = _isReceive ? 'Record Receipt' : 'Record Issue';
    final message = _isReceive
        ? 'Record receipt of $quantity ${widget.material.unit} of "${widget.material.name}" into storage?'
        : 'Issue $quantity ${widget.material.unit} of "${widget.material.name}"'
            '${_selectedProject != null ? ' to project ${_selectedProject!.name}' : ''}?';

    final confirmed = await showConfirmDialog(context, title: title, message: message, confirmLabel: title);
    if (!confirmed || !mounted) return;

    setState(() => _isSaving = true);

    try {
      final photoBytesList = <Uint8List>[];
      final photoFileNames = <String>[];
      for (final file in _selectedPhotos) {
        final bytes = kIsWeb ? await file.readAsBytes() : await File(file.path).readAsBytes();
        photoBytesList.add(bytes);
        photoFileNames.add(file.name);
      }

      if (_isReceive) {
        await _inventoryService.recordMaterialReceipt(
          materialId: widget.material.id,
          quantity: quantity,
          conditionOnReceipt: _condition,
          portVerifiedByName: widget.material.source == MaterialModel.sourceInternational &&
                  _portVerifiedByController.text.trim().isNotEmpty
              ? _portVerifiedByController.text.trim()
              : null,
          receivedByName:
              _receivedByController.text.trim().isEmpty ? null : _receivedByController.text.trim(),
          notes: _notesController.text.trim(),
          photoBytesList: photoBytesList,
          photoFileNames: photoFileNames,
          recordedByUid: widget.recordedByUid,
          recordedByName: widget.recordedByName,
          recordedByRole: widget.recordedByRole,
        );
      } else {
        await _inventoryService.recordMaterialIssue(
          materialId: widget.material.id,
          quantity: quantity,
          projectId: _selectedProject?.id,
          projectName: _selectedProject?.name,
          notes: _notesController.text.trim(),
          photoBytesList: photoBytesList,
          photoFileNames: photoFileNames,
          recordedByUid: widget.recordedByUid,
          recordedByName: widget.recordedByName,
          recordedByRole: widget.recordedByRole,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isReceive ? 'Receipt recorded' : 'Issue recorded', style: GoogleFonts.poppins()),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      widget.logger.e('❌ RecordMaterialMovementScreen: Failed to submit', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyInventoryError(e), style: GoogleFonts.poppins()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!InventoryPermissions.canApproveAndIssue(widget.recordedByRole)) {
      return BaseLayout(
        title: _isReceive ? 'Record Receipt' : 'Record Issue',
        project: widget.project,
        logger: widget.logger,
        selectedMenuItem: 'Inventory',
        onMenuItemSelected: (_) {},
        child: Center(
          child: Text(
            'You do not have permission to record material movements.',
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[700]),
          ),
        ),
      );
    }
    return BaseLayout(
      title: _isReceive ? 'Record Receipt' : 'Record Issue',
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
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.material.name, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700)),
                        Text('${widget.material.quantityInStorage} ${widget.material.unit} currently in storage',
                            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  inventoryFormSection(
                    title: _isReceive ? 'Receipt' : 'Issue',
                    icon: _isReceive ? Icons.call_received : Icons.call_made,
                    children: [
                      TextFormField(
                        controller: _quantityController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: inventoryInputDecoration(
                          label: 'Quantity (${widget.material.unit})',
                          icon: Icons.numbers_outlined,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Quantity is required' : null,
                      ),
                      const SizedBox(height: 14),
                      if (_isReceive) ...[
                        DropdownButtonFormField<String>(
                          initialValue: _condition,
                          isExpanded: true,
                          decoration: inventoryInputDecoration(label: 'Condition on Receipt', icon: Icons.fact_check_outlined),
                          items: [
                            MaterialMovementModel.conditionGood,
                            MaterialMovementModel.conditionPartial,
                            MaterialMovementModel.conditionDamaged,
                          ]
                              .map((c) => DropdownMenuItem(value: c, child: Text(c, style: GoogleFonts.poppins())))
                              .toList(),
                          onChanged: (v) => setState(() => _condition = v ?? _condition),
                        ),
                        const SizedBox(height: 14),
                        if (widget.material.source == MaterialModel.sourceInternational) ...[
                          TextFormField(
                            controller: _portVerifiedByController,
                            decoration: inventoryInputDecoration(
                              label: 'Verified at Port of Arrival By',
                              hint: 'Name of person who verified this shipment',
                              icon: Icons.anchor_outlined,
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          controller: _receivedByController,
                          decoration: inventoryInputDecoration(
                            label: 'Received Into Storage By',
                            hint: 'Name of person who signed for it',
                            icon: Icons.badge_outlined,
                          ),
                        ),
                      ] else
                        _buildProjectPicker(),
                    ],
                  ),
                  inventoryFormSection(
                    title: 'Notes & Photos',
                    icon: Icons.fact_check_outlined,
                    children: [
                      TextField(
                        controller: _notesController,
                        maxLines: 3,
                        decoration: inventoryInputDecoration(
                          label: 'Notes',
                          hint: _isReceive ? 'Condition/state details on receipt' : 'Reason / additional notes',
                          icon: Icons.notes_outlined,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _isSaving ? null : _pickPhotos,
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: Text('Add Photos', style: GoogleFonts.poppins()),
                      ),
                      if (_selectedPhotos.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 80,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _selectedPhotos.length,
                            separatorBuilder: (context, _) => const SizedBox(width: 8),
                            itemBuilder: (context, i) {
                              final file = _selectedPhotos[i];
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: kIsWeb
                                        ? Image.network(file.path, width: 80, height: 80, fit: BoxFit.cover)
                                        : Image.file(File(file.path), width: 80, height: 80, fit: BoxFit.cover),
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: () => setState(() => _selectedPhotos.removeAt(i)),
                                      child: const CircleAvatar(
                                        radius: 10,
                                        backgroundColor: Colors.black54,
                                        child: Icon(Icons.close, size: 12, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  inventoryPrimaryButton(
                    label: _isReceive ? 'Record Receipt' : 'Record Issue',
                    isLoading: _isSaving,
                    onPressed: _submit,
                    icon: _isReceive ? Icons.call_received : Icons.call_made,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectPicker() {
    if (!_projectsLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_projectsError != null) {
      return Container(
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
            Expanded(child: Text(_projectsError!, style: GoogleFonts.poppins(fontSize: 12, color: Colors.red[800]))),
            TextButton(onPressed: _subscribeProjects, child: const Text('Retry')),
          ],
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: _selectedProjectId,
      isExpanded: true,
      decoration: inventoryInputDecoration(label: 'Destination Project', icon: Icons.folder_outlined),
      items: _projects
          .map((p) => DropdownMenuItem(
                value: p.id,
                child: Text(p.name, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins()),
              ))
          .toList(),
      onChanged: (value) => setState(() => _selectedProjectId = value),
    );
  }
}
