import 'dart:io';
import 'dart:typed_data';

import 'package:almaworks/models/inventory/asset_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:almaworks/services/project_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/confirm_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';

enum CustodyEventMode { checkout, returnEvent }

/// Records a checkout (asset -> person/project) or a return (asset back to
/// storage) for an asset. One screen, mode-driven, to avoid duplicating the
/// photo-picker/condition-notes/confirm-dialog scaffolding twice — the two
/// modes differ only in which fields are editable.
class RecordCustodyEventScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final AssetModel asset;
  final CustodyEventMode mode;
  final String recordedByUid;
  final String recordedByName;
  final String recordedByRole;

  const RecordCustodyEventScreen({
    super.key,
    required this.project,
    required this.logger,
    required this.asset,
    required this.mode,
    required this.recordedByUid,
    required this.recordedByName,
    required this.recordedByRole,
  });

  @override
  State<RecordCustodyEventScreen> createState() => _RecordCustodyEventScreenState();
}

class _RecordCustodyEventScreenState extends State<RecordCustodyEventScreen> {
  final InventoryService _inventoryService = InventoryService();
  final ProjectService _projectService = ProjectService();
  final _conditionController = TextEditingController();

  final List<XFile> _selectedPhotos = [];
  bool _isSaving = false;

  // checkout-only state
  Map<String, dynamic>? _selectedUserDoc; // {'username': ..., 'uid': ...}
  ProjectModel? _selectedProject;

  bool get _isCheckout => widget.mode == CustodyEventMode.checkout;

  @override
  void dispose() {
    _conditionController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage();
    if (files.isEmpty || !mounted) return;
    setState(() => _selectedPhotos.addAll(files));
  }

  Future<void> _submit() async {
    if (_isCheckout && _selectedUserDoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Select who is receiving this asset', style: GoogleFonts.poppins())),
      );
      return;
    }

    final title = _isCheckout ? 'Check Out Asset' : 'Record Return';
    final message = _isCheckout
        ? 'Check out "${widget.asset.name}" to ${_selectedUserDoc!['username']}'
            '${_selectedProject != null ? ' for project ${_selectedProject!.name}' : ''}?'
        : 'Record the return of "${widget.asset.name}" to storage?';

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

      if (_isCheckout) {
        await _inventoryService.createCheckout(
          assetId: widget.asset.id,
          assignedToUserId: _selectedUserDoc!['uid'] as String,
          assignedToName: _selectedUserDoc!['username'] as String,
          projectId: _selectedProject?.id,
          projectName: _selectedProject?.name,
          conditionNotes: _conditionController.text.trim(),
          photoBytesList: photoBytesList,
          photoFileNames: photoFileNames,
          recordedByUid: widget.recordedByUid,
          recordedByName: widget.recordedByName,
          recordedByRole: widget.recordedByRole,
        );
      } else {
        await _inventoryService.createReturn(
          assetId: widget.asset.id,
          previousAssignmentId: widget.asset.currentAssignmentId!,
          conditionNotes: _conditionController.text.trim(),
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
          content: Text(_isCheckout ? 'Asset checked out' : 'Return recorded', style: GoogleFonts.poppins()),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      widget.logger.e('❌ RecordCustodyEventScreen: Failed to submit', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e', style: GoogleFonts.poppins()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseLayout(
      title: _isCheckout ? 'Check Out Asset' : 'Record Return',
      project: widget.project,
      logger: widget.logger,
      selectedMenuItem: 'Inventory',
      onMenuItemSelected: (_) {},
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.asset.name, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          if (_isCheckout) ...[
            _buildUserPicker(),
            const SizedBox(height: 12),
            _buildProjectPicker(),
            const SizedBox(height: 12),
          ] else ...[
            _buildReadOnlyRow('Returning from', widget.asset.currentHolderName ?? 'Unknown'),
            if (widget.asset.currentProjectName != null)
              _buildReadOnlyRow('Project', widget.asset.currentProjectName!),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _conditionController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Condition notes',
              hintText: _isCheckout ? 'Condition at handover' : 'Condition at return',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isSaving ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isCheckout ? const Color(0xFF1565C0) : const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(_isCheckout ? 'Check Out' : 'Record Return',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text('$label: ', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600])),
          Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildUserPicker() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('Users').snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        final items = docs
            .map((d) => {'username': d.id, 'uid': (d.data() as Map<String, dynamic>)['uid'] as String? ?? ''})
            .where((m) => (m['uid'] as String).isNotEmpty)
            .toList();

        return DropdownButtonFormField<Map<String, dynamic>>(
          initialValue: _selectedUserDoc,
          decoration: InputDecoration(
            labelText: 'Assign To',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: items
              .map((m) => DropdownMenuItem(value: m, child: Text(m['username'] as String, style: GoogleFonts.poppins())))
              .toList(),
          onChanged: (value) => setState(() => _selectedUserDoc = value),
        );
      },
    );
  }

  Widget _buildProjectPicker() {
    return StreamBuilder<List<ProjectModel>>(
      stream: _projectService.getAllProjects(),
      builder: (context, snapshot) {
        final projects = snapshot.data ?? const [];
        return DropdownButtonFormField<ProjectModel>(
          initialValue: _selectedProject,
          decoration: InputDecoration(
            labelText: 'Project (optional — leave blank for company storage)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: projects
              .map((p) => DropdownMenuItem(value: p, child: Text(p.name, style: GoogleFonts.poppins())))
              .toList(),
          onChanged: (value) => setState(() => _selectedProject = value),
        );
      },
    );
  }
}
