import 'dart:io';
import 'dart:typed_data';

import 'package:almaworks/models/inventory/inventory_categories.dart';
import 'package:almaworks/models/inventory/material_model.dart';
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

/// MainAdmin-only screen to register a new material, or (when
/// [existingMaterial] is supplied) edit one's descriptive fields.
class AddMaterialScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final String createdByUid;
  final String createdByName;
  final MaterialModel? existingMaterial;

  const AddMaterialScreen({
    super.key,
    required this.project,
    required this.logger,
    required this.createdByUid,
    required this.createdByName,
    this.existingMaterial,
  });

  @override
  State<AddMaterialScreen> createState() => _AddMaterialScreenState();
}

class _AddMaterialScreenState extends State<AddMaterialScreen> {
  static const _units = ['bags', 'pieces', 'kg', 'tonnes', 'm', 'm²', 'm³', 'litres', 'rolls'];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _initialQuantityController = TextEditingController(text: '0');
  final _reorderLevelController = TextEditingController(text: '0');
  final InventoryService _inventoryService = InventoryService();

  String _unit = _units.first;
  String _source = MaterialModel.sourceLocal;
  String _condition = MaterialModel.conditionGood;
  XFile? _selectedPhoto;
  bool _isSaving = false;

  bool get _isEditing => widget.existingMaterial != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingMaterial;
    if (existing != null) {
      _nameController.text = existing.name;
      _categoryController.text = existing.category;
      _descriptionController.text = existing.description ?? '';
      _reorderLevelController.text = existing.reorderLevel.toString();
      _unit = existing.unit;
      _source = existing.source;
      _condition = existing.initialCondition;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _initialQuantityController.dispose();
    _reorderLevelController.dispose();
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

    final actionLabel = _isEditing ? 'Save Changes' : 'Add Material';
    final confirmed = await showConfirmDialog(
      context,
      title: actionLabel,
      message: _isEditing
          ? 'Save changes to "${_nameController.text.trim()}"?'
          : 'Register "${_nameController.text.trim()}" (${_categoryController.text.trim()}) '
              'as a new material in the stock register?',
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
          photoUrl = await _inventoryService.uploadMaterialPhoto(
            materialId: widget.existingMaterial!.id,
            photoBytes: photoBytes,
            photoFileName: photoFileName,
          );
        }
        await _inventoryService.updateMaterial(
          materialId: widget.existingMaterial!.id,
          name: _nameController.text.trim(),
          category: _categoryController.text.trim(),
          unit: _unit,
          source: _source,
          description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
          reorderLevel: double.tryParse(_reorderLevelController.text.trim()),
          photoUrl: photoUrl,
        );
      } else {
        await _inventoryService.createMaterial(
          name: _nameController.text.trim(),
          category: _categoryController.text.trim(),
          unit: _unit,
          source: _source,
          description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
          initialQuantity: double.tryParse(_initialQuantityController.text.trim()) ?? 0,
          reorderLevel: double.tryParse(_reorderLevelController.text.trim()) ?? 0,
          initialCondition: _condition,
          createdByUid: widget.createdByUid,
          createdByName: widget.createdByName,
          photoBytes: photoBytes,
          photoFileName: photoFileName,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Changes saved' : 'Material added successfully', style: GoogleFonts.poppins()),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      widget.logger.e('❌ AddMaterialScreen: Failed to save material', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save material: $e', style: GoogleFonts.poppins()),
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
      title: _isEditing ? 'Edit Material' : 'Add Material',
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
                        decoration: inventoryInputDecoration(label: 'Material Name', icon: Icons.inventory_2_outlined),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 3,
                        decoration: inventoryInputDecoration(label: 'Description (optional)', icon: Icons.notes_outlined),
                      ),
                      if (!_isEditing) ...[
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _condition,
                          isExpanded: true,
                          decoration: inventoryInputDecoration(label: 'Condition at Intake', icon: Icons.fact_check_outlined),
                          items: [
                            MaterialModel.conditionNew,
                            MaterialModel.conditionGood,
                            MaterialModel.conditionFair,
                            MaterialModel.conditionDamaged,
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
                          hint: 'e.g. Cement & Aggregates, Steel & Metal',
                          icon: Icons.category_outlined,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Category is required' : null,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: InventoryCategories.material.where((c) => c != 'Other').map((c) {
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
                  inventoryFormSection(
                    title: 'Stock',
                    icon: Icons.inventory_2_outlined,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _unit,
                              isExpanded: true,
                              decoration: inventoryInputDecoration(label: 'Unit', icon: Icons.straighten_outlined),
                              items: _units
                                  .map((u) => DropdownMenuItem(value: u, child: Text(u, style: GoogleFonts.poppins())))
                                  .toList(),
                              onChanged: (v) => setState(() => _unit = v ?? _unit),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _source,
                              isExpanded: true,
                              decoration: inventoryInputDecoration(label: 'Source', icon: Icons.public_outlined),
                              items: [MaterialModel.sourceLocal, MaterialModel.sourceInternational]
                                  .map((s) => DropdownMenuItem(value: s, child: Text(s, style: GoogleFonts.poppins())))
                                  .toList(),
                              onChanged: (v) => setState(() => _source = v ?? _source),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (!_isEditing) ...[
                            Expanded(
                              child: TextFormField(
                                controller: _initialQuantityController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: inventoryInputDecoration(label: 'Initial Quantity', icon: Icons.numbers_outlined),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: TextFormField(
                              controller: _reorderLevelController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: inventoryInputDecoration(
                                label: 'Reorder Level',
                                hint: 'Low-stock threshold',
                                icon: Icons.warning_amber_outlined,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_isEditing) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Quantity in storage (${widget.existingMaterial!.quantityInStorage} '
                          '${widget.existingMaterial!.unit}) can only be changed by recording a '
                          'receipt or issue — not by editing.',
                          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  inventoryPrimaryButton(
                    label: _isEditing ? 'Save Changes' : 'Add Material',
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
