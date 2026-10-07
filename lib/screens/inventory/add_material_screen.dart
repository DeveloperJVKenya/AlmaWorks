import 'dart:io';
import 'dart:typed_data';

import 'package:almaworks/models/inventory/inventory_categories.dart';
import 'package:almaworks/models/inventory/material_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/inventory_labels.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/confirm_dialog.dart';
import 'package:almaworks/widgets/inventory_form_section.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/theme/app_colors.dart';
import 'package:almaworks/core/errors/friendly_error.dart';

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
      _categoryController.text = invLabel(existing.category);
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
              title: Text(context.l10n.camera),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(context.l10n.gallery),
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

    final l = context.l10n;
    final actionLabel = _isEditing ? l.saveChanges : l.addMaterial;
    final confirmed = await showConfirmDialog(
      context,
      title: actionLabel,
      message: _isEditing
          ? l.confirmSaveChangesTo(_nameController.text.trim())
          : l.confirmRegisterMaterial(_nameController.text.trim(), _categoryController.text.trim()),
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
          category: _canonicalCategory,
          unit: _unit,
          source: _source,
          description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
          reorderLevel: double.tryParse(_reorderLevelController.text.trim()),
          photoUrl: photoUrl,
        );
      } else {
        await _inventoryService.createMaterial(
          name: _nameController.text.trim(),
          category: _canonicalCategory,
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
      showSuccessSnack(context, _isEditing ? l.changesSaved : l.materialAdded);
      Navigator.pop(context);
    } catch (e) {
      widget.logger.e('❌ AddMaterialScreen: Failed to save material', error: e);
      if (!mounted) return;
      showErrorSnack(context, e, action: l.couldNotSaveMaterial);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// The stored (English) category for a preset shown in the app language.
  String get _canonicalCategory {
    final text = _categoryController.text.trim();
    for (final option in InventoryCategories.material) {
      if (invLabel(option) == text || option == text) return option;
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return BaseLayout(
      title: _isEditing ? l.editMaterial : l.addMaterial,
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
                    title: l.photo,
                    icon: Icons.photo_camera_outlined,
                    children: [
                      Material(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: _isSaving ? null : _pickPhoto,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            height: 160,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: _selectedPhoto == null
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundColor: AppColors.brandTint,
                                          child: Icon(Icons.add_a_photo_outlined, color: AppColors.brandInk, size: 22),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(l.tapToAddPhoto,
                                            style: TextStyle(color: AppColors.inkMuted, fontSize: 12)),
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
                    title: l.details,
                    icon: Icons.info_outline,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: inventoryInputDecoration(label: l.materialName, icon: Icons.inventory_2_outlined),
                        validator: (v) => (v == null || v.trim().isEmpty) ? l.nameRequired : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 3,
                        decoration: inventoryInputDecoration(label: l.descriptionOptional, icon: Icons.notes_outlined),
                      ),
                      if (!_isEditing) ...[
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _condition,
                          isExpanded: true,
                          decoration: inventoryInputDecoration(label: l.conditionAtIntakeLabel, icon: Icons.fact_check_outlined),
                          items: [
                            MaterialModel.conditionNew,
                            MaterialModel.conditionGood,
                            MaterialModel.conditionFair,
                            MaterialModel.conditionDamaged,
                          ]
                              .map((c) => DropdownMenuItem(value: c, child: Text(invLabel(c))))
                              .toList(),
                          onChanged: (v) => setState(() => _condition = v ?? _condition),
                        ),
                      ],
                    ],
                  ),
                  inventoryFormSection(
                    title: l.classification,
                    icon: Icons.category_outlined,
                    children: [
                      TextFormField(
                        controller: _categoryController,
                        decoration: inventoryInputDecoration(
                          label: l.category,
                          hint: l.materialCategoryHint,
                          icon: Icons.category_outlined,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? l.categoryRequired : null,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: InventoryCategories.material.where((c) => c != 'Other').map((c) {
                          final selected = _categoryController.text == invLabel(c);
                          return ChoiceChip(
                            label: Text(invLabel(c), style: const TextStyle(fontSize: 12)),
                            selected: selected,
                            selectedColor: AppColors.brandTint,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: selected ? AppColors.brandInk : AppColors.inkMuted,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                            side: BorderSide(color: selected ? AppColors.brandInk : AppColors.border),
                            onSelected: (_) => setState(() => _categoryController.text = invLabel(c)),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                  inventoryFormSection(
                    title: l.stock,
                    icon: Icons.inventory_2_outlined,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _unit,
                              isExpanded: true,
                              decoration: inventoryInputDecoration(label: l.unit, icon: Icons.straighten_outlined),
                              items: _units
                                  .map((u) => DropdownMenuItem(value: u, child: Text(invLabel(u))))
                                  .toList(),
                              onChanged: (v) => setState(() => _unit = v ?? _unit),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _source,
                              isExpanded: true,
                              decoration: inventoryInputDecoration(label: l.source, icon: Icons.public_outlined),
                              items: [MaterialModel.sourceLocal, MaterialModel.sourceInternational]
                                  .map((s) => DropdownMenuItem(value: s, child: Text(invLabel(s))))
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
                                decoration: inventoryInputDecoration(label: l.initialQuantity, icon: Icons.numbers_outlined),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: TextFormField(
                              controller: _reorderLevelController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: inventoryInputDecoration(
                                label: l.reorderLevel,
                                hint: l.reorderLevelHint,
                                icon: Icons.warning_amber_outlined,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_isEditing) ...[
                        const SizedBox(height: 8),
                        Text(
                          l.quantityEditNote(
                            '${widget.existingMaterial!.quantityInStorage}',
                            invLabel(widget.existingMaterial!.unit),
                          ),
                          style: TextStyle(fontSize: 11, color: AppColors.inkMuted),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  inventoryPrimaryButton(
                    label: _isEditing ? l.saveChanges : l.addMaterial,
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
