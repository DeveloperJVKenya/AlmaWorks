import 'dart:io';
import 'dart:typed_data';

import 'package:almaworks/models/inventory/asset_model.dart';
import 'package:almaworks/models/inventory/inventory_categories.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/confirm_dialog.dart';
import 'package:almaworks/widgets/inventory_form_section.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';

/// MainAdmin-only screen to register a new company asset or tool, or (when
/// [existingAsset] is supplied) edit one's descriptive fields. The two item
/// types share this exact form/model, distinguished only by [itemType],
/// which drives the title, hints, and quick-pick category chips shown below.
class AddAssetScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final String itemType; // AssetModel.typeAsset | AssetModel.typeTool
  final String createdByUid;
  final String createdByName;

  /// When supplied, the screen behaves as an editor for this asset instead
  /// of a create form — descriptive fields only, never custody state.
  final AssetModel? existingAsset;

  const AddAssetScreen({
    super.key,
    required this.project,
    required this.logger,
    this.itemType = AssetModel.typeAsset,
    required this.createdByUid,
    required this.createdByName,
    this.existingAsset,
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
  final _quantityController = TextEditingController(text: '1');
  final InventoryService _inventoryService = InventoryService();

  XFile? _selectedPhoto;
  bool _isSaving = false;
  String _condition = AssetModel.conditionGood;

  /// Tools only, and only when creating (not editing): how many identical
  /// units to register at once. Each still becomes its own doc with its
  /// own independent custody history — this is purely a convenience for
  /// batch-registering (e.g. "4 hammers") rather than a shared counter, so
  /// per-unit traceability (who has *this specific* hammer) is never lost.
  int get _quantity => int.tryParse(_quantityController.text.trim()) ?? 1;

  bool get _isEditing => widget.existingAsset != null;
  bool get _isTool => widget.itemType == AssetModel.typeTool;
  List<String> get _categoryOptions => _isTool ? InventoryCategories.tool : InventoryCategories.asset;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingAsset;
    if (existing != null) {
      _nameController.text = existing.name;
      _categoryController.text = existing.category;
      _descriptionController.text = existing.description ?? '';
      _serialNumberController.text = existing.serialNumber ?? '';
      _condition = existing.initialCondition;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _serialNumberController.dispose();
    _quantityController.dispose();
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

    final itemLabel = _isTool ? 'tool' : 'asset';
    final actionLabel = _isEditing ? 'Save Changes' : (_isTool ? 'Add Tool' : 'Add Asset');
    final quantity = _isTool && !_isEditing ? _quantity.clamp(1, 500) : 1;
    final confirmed = await showConfirmDialog(
      context,
      title: actionLabel,
      message: _isEditing
          ? 'Save changes to "${_nameController.text.trim()}"?'
          : quantity > 1
              ? 'Register $quantity units of "${_nameController.text.trim()}" '
                  '(${_categoryController.text.trim()}) as new company ${itemLabel}s? '
                  'Each unit is tracked separately, with its own custody history.'
              : 'Register "${_nameController.text.trim()}" (${_categoryController.text.trim()}) '
                  'as a new company $itemLabel?',
      confirmLabel: actionLabel,
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

      if (_isEditing) {
        String? photoUrl;
        if (photoBytes != null && photoFileName != null) {
          // Re-uses createAsset's upload path indirectly isn't possible here
          // (that method also creates a doc), so edits that change the photo
          // upload directly via the same storage path convention.
          photoUrl = await _inventoryService.uploadAssetPhoto(
            assetId: widget.existingAsset!.id,
            photoBytes: photoBytes,
            photoFileName: photoFileName,
          );
        }
        await _inventoryService.updateAsset(
          assetId: widget.existingAsset!.id,
          name: _nameController.text.trim(),
          category: _categoryController.text.trim(),
          description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
          serialNumber: _serialNumberController.text.trim().isEmpty ? null : _serialNumberController.text.trim(),
          photoUrl: photoUrl,
        );
      } else {
        // A shared serial number across multiple units would misrepresent
        // per-unit identity, so it's only carried over when registering a
        // single unit — batches rely on each unit's own doc id instead.
        final serialNumber = quantity > 1
            ? null
            : (_serialNumberController.text.trim().isEmpty ? null : _serialNumberController.text.trim());
        for (var i = 0; i < quantity; i++) {
          await _inventoryService.createAsset(
            itemType: widget.itemType,
            name: _nameController.text.trim(),
            category: _categoryController.text.trim(),
            description: _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
            serialNumber: serialNumber,
            initialCondition: _condition,
            createdByUid: widget.createdByUid,
            createdByName: widget.createdByName,
            photoBytes: photoBytes,
            photoFileName: photoFileName,
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Changes saved'
                : quantity > 1
                    ? '$quantity units added successfully'
                    : '${_isTool ? 'Tool' : 'Asset'} added successfully',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      widget.logger.e('❌ AddAssetScreen: Failed to save ${widget.itemType}', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save $itemLabel: $e', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditing ? 'Edit ${_isTool ? 'Tool' : 'Asset'}' : (_isTool ? 'Add Tool' : 'Add Asset');
    return BaseLayout(
      title: title,
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
                  inventoryFormSection(
                    title: 'Photo',
                    icon: Icons.photo_camera_outlined,
                    children: [
                      Material(
                        color: const Color(0xFFFAFBFC),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: _isSaving ? null : _pickPhoto,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            height: 160,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.grey.withValues(alpha: 0.22)),
                            ),
                            child: _selectedPhoto == null
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundColor: inventoryNavy.withValues(alpha: 0.08),
                                          child: Icon(Icons.add_a_photo_outlined, color: inventoryNavy, size: 22),
                                        ),
                                        const SizedBox(height: 8),
                                        Text('Tap to add a photo (optional)',
                                            style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 12)),
                                      ],
                                    ),
                                  )
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: kIsWeb
                                        ? Image.network(_selectedPhoto!.path, fit: BoxFit.cover, width: double.infinity)
                                        : Image.file(File(_selectedPhoto!.path), fit: BoxFit.cover, width: double.infinity),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  inventoryFormSection(
                    title: 'Details',
                    icon: Icons.info_outline,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: inventoryInputDecoration(
                          label: _isTool ? 'Tool Name' : 'Asset Name',
                          icon: _isTool ? Icons.handyman_outlined : Icons.precision_manufacturing_outlined,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                      ),
                      if (_isTool && !_isEditing) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _quantityController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: inventoryInputDecoration(
                            label: 'Quantity',
                            hint: 'Number of identical units to register',
                            icon: Icons.numbers_outlined,
                          ),
                          validator: (v) {
                            final n = int.tryParse((v ?? '').trim());
                            if (n == null || n < 1) return 'Enter a whole number of 1 or more';
                            return null;
                          },
                        ),
                      ],
                      if (_quantity <= 1) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _serialNumberController,
                          decoration: inventoryInputDecoration(
                            label: 'Serial Number (optional)',
                            icon: Icons.qr_code_2_outlined,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 3,
                        decoration: inventoryInputDecoration(
                          label: 'Description (optional)',
                          icon: Icons.notes_outlined,
                        ),
                      ),
                      if (!_isEditing) ...[
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _condition,
                          isExpanded: true,
                          decoration: inventoryInputDecoration(
                            label: 'Condition at Intake',
                            icon: Icons.fact_check_outlined,
                          ),
                          items: [
                            AssetModel.conditionNew,
                            AssetModel.conditionGood,
                            AssetModel.conditionFair,
                            AssetModel.conditionDamaged,
                          ]
                              .map((c) => DropdownMenuItem(value: c, child: Text(c, style: GoogleFonts.poppins())))
                              .toList(),
                          onChanged: (v) => setState(() => _condition = v ?? _condition),
                        ),
                      ],
                    ],
                  ),
                  inventoryFormSection(
                    title: 'Classification',
                    icon: Icons.category_outlined,
                    children: [
                      TextFormField(
                        controller: _categoryController,
                        decoration: inventoryInputDecoration(
                          label: 'Category',
                          hint: _isTool ? 'e.g. Power Tool, IT Equipment / Electronics' : 'e.g. Heavy Equipment, Vehicle',
                          icon: Icons.category_outlined,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Category is required' : null,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _categoryOptions.where((c) => c != 'Other').map((c) {
                          final selected = _categoryController.text == c;
                          return ChoiceChip(
                            label: Text(c, style: GoogleFonts.poppins(fontSize: 12)),
                            selected: selected,
                            selectedColor: inventoryNavy.withValues(alpha: 0.12),
                            labelStyle: GoogleFonts.poppins(
                              fontSize: 12,
                              color: selected ? inventoryNavy : Colors.grey[700],
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                            side: BorderSide(color: selected ? inventoryNavy : Colors.grey.withValues(alpha: 0.3)),
                            onSelected: (_) => setState(() => _categoryController.text = c),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  inventoryPrimaryButton(
                    label: _isEditing ? 'Save Changes' : (_isTool ? 'Add Tool' : 'Add Asset'),
                    isLoading: _isSaving,
                    onPressed: _submit,
                    icon: _isEditing ? Icons.check : Icons.add,
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
}
