import 'dart:io';
import 'dart:typed_data';

import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/confirm_dialog.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';

/// MainAdmin-only screen to register a new company asset.
class AddAssetScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final String createdByUid;
  final String createdByName;

  const AddAssetScreen({
    super.key,
    required this.project,
    required this.logger,
    required this.createdByUid,
    required this.createdByName,
  });

  @override
  State<AddAssetScreen> createState() => _AddAssetScreenState();
}

class _AddAssetScreenState extends State<AddAssetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _serialNumberController = TextEditingController();
  final InventoryService _inventoryService = InventoryService();

  XFile? _selectedPhoto;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _serialNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final String? source = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text('Camera', style: GoogleFonts.poppins()),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text('Gallery', style: GoogleFonts.poppins()),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
    );
    if (file != null && mounted) {
      setState(() => _selectedPhoto = file);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Add Asset',
      message:
          'Register "${_nameController.text.trim()}" (${_categoryController.text.trim()}) '
          'as a new company asset?',
      confirmLabel: 'Add Asset',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isSaving = true);

    try {
      Uint8List? photoBytes;
      String? photoFileName;
      if (_selectedPhoto != null) {
        photoBytes = kIsWeb
            ? await _selectedPhoto!.readAsBytes()
            : await File(_selectedPhoto!.path).readAsBytes();
        photoFileName = _selectedPhoto!.name;
      }

      await _inventoryService.createAsset(
        name: _nameController.text.trim(),
        category: _categoryController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        serialNumber: _serialNumberController.text.trim().isEmpty
            ? null
            : _serialNumberController.text.trim(),
        createdByUid: widget.createdByUid,
        createdByName: widget.createdByName,
        photoBytes: photoBytes,
        photoFileName: photoFileName,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Asset added successfully', style: GoogleFonts.poppins()),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      widget.logger.e('❌ AddAssetScreen: Failed to add asset', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add asset: $e', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseLayout(
      title: 'Add Asset',
      project: widget.project,
      logger: widget.logger,
      selectedMenuItem: 'Inventory',
      onMenuItemSelected: (_) {},
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GestureDetector(
              onTap: _isSaving ? null : _pickPhoto,
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: _selectedPhoto == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_a_photo_outlined, color: Colors.grey[500], size: 32),
                            const SizedBox(height: 6),
                            Text('Add photo (optional)',
                                style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 12)),
                          ],
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: kIsWeb
                            ? Image.network(_selectedPhoto!.path, fit: BoxFit.cover, width: double.infinity)
                            : Image.file(File(_selectedPhoto!.path), fit: BoxFit.cover, width: double.infinity),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Asset Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _categoryController,
              decoration: InputDecoration(
                labelText: 'Category',
                hintText: 'e.g. Power Tool, Heavy Equipment, Hand Tool',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Category is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _serialNumberController,
              decoration: InputDecoration(
                labelText: 'Serial Number (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSaving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2E5A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text('Add Asset', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
