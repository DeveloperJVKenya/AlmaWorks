import 'dart:io';
import 'dart:typed_data';

import 'package:almaworks/models/inventory/asset_model.dart';
import 'package:almaworks/models/inventory/inventory_categories.dart';
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
  final _addMoreUnitsController = TextEditingController(text: '0');
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

  /// Tools only, when editing: since quantity isn't a single field to edit
  /// (each unit is its own doc — see _quantity above), "editing the
  /// quantity" of an already-registered tool means registering additional
  /// matching units alongside the one being edited, rather than changing a
  /// number on this specific doc.
  int get _addMoreUnits => int.tryParse(_addMoreUnitsController.text.trim()) ?? 0;

  bool get _isEditing => widget.existingAsset != null;
  bool get _isTool => widget.itemType == AssetModel.typeTool;
  List<String> get _categoryOptions => _isTool ? InventoryCategories.tool : InventoryCategories.asset;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingAsset;
    if (existing != null) {
      _nameController.text = existing.name;
      _categoryController.text = invLabel(existing.category);
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
    _addMoreUnitsController.dispose();
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
    final actionLabel = _isEditing ? l.saveChanges : (_isTool ? l.addTool : l.addAsset);
    final quantity = _isTool && !_isEditing ? _quantity.clamp(1, 500) : 1;
    final addMoreUnits = _isTool && _isEditing ? _addMoreUnits.clamp(0, 500) : 0;
    final name = _nameController.text.trim();
    final categoryText = _categoryController.text.trim();
    final confirmed = await showConfirmDialog(
      context,
      title: actionLabel,
      message: _isEditing
          ? (addMoreUnits > 0 ? l.confirmSaveAndAddUnits(addMoreUnits, name) : l.confirmSaveChangesTo(name))
          : quantity > 1
              ? (_isTool
                  ? l.confirmRegisterToolUnits(quantity, name, categoryText)
                  : l.confirmRegisterAssetUnits(quantity, name, categoryText))
              : (_isTool ? l.confirmRegisterTool(name, categoryText) : l.confirmRegisterAsset(name, categoryText)),
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
          category: _canonicalCategory,
          description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
          serialNumber: _serialNumberController.text.trim().isEmpty ? null : _serialNumberController.text.trim(),
          photoUrl: photoUrl,
        );

        for (var i = 0; i < addMoreUnits; i++) {
          await _inventoryService.createAsset(
            itemType: widget.itemType,
            name: _nameController.text.trim(),
            category: _canonicalCategory,
            description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
            initialCondition: _condition,
            createdByUid: widget.createdByUid,
            createdByName: widget.createdByName,
          );
        }
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
            category: _canonicalCategory,
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
      showSuccessSnack(
        context,
        _isEditing
            ? (addMoreUnits > 0 ? l.changesSavedUnitsAdded(addMoreUnits) : l.changesSaved)
            : quantity > 1
                ? l.unitsAdded(quantity)
                : (_isTool ? l.toolAdded : l.assetAdded),
      );
      Navigator.pop(context);
    } catch (e) {
      widget.logger.e('❌ AddAssetScreen: Failed to save ${widget.itemType}', error: e);
      if (!mounted) return;
      showErrorSnack(context, e, action: l.couldNotSaveItem);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// The stored (English) category when the text is one of the preset
  /// categories shown in the app language; anything typed by hand is kept.
  String get _canonicalCategory {
    final text = _categoryController.text.trim();
    for (final option in _categoryOptions) {
      if (invLabel(option) == text || option == text) return option;
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final title = _isEditing ? (_isTool ? l.editTool : l.editAsset) : (_isTool ? l.addTool : l.addAsset);
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
                        decoration: inventoryInputDecoration(
                          label: _isTool ? l.toolName : l.assetName,
                          icon: _isTool ? Icons.handyman_outlined : Icons.precision_manufacturing_outlined,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? l.nameRequired : null,
                      ),
                      if (_isTool && !_isEditing) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _quantityController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: inventoryInputDecoration(
                            label: l.quantity,
                            hint: l.quantityUnitsHint,
                            icon: Icons.numbers_outlined,
                          ),
                          validator: (v) {
                            final n = int.tryParse((v ?? '').trim());
                            if (n == null || n < 1) return l.wholeNumberOneOrMore;
                            return null;
                          },
                        ),
                      ],
                      if (_isTool && _isEditing) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _addMoreUnitsController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: inventoryInputDecoration(
                            label: l.addMoreUnitsOptional,
                            hint: l.addMoreUnitsHint,
                            icon: Icons.add_box_outlined,
                          ),
                          validator: (v) {
                            final n = int.tryParse((v ?? '0').trim());
                            if (n == null || n < 0) return l.zeroOrMore;
                            return null;
                          },
                        ),
                      ],
                      if (_quantity <= 1) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _serialNumberController,
                          decoration: inventoryInputDecoration(
                            label: l.serialNumberOptional,
                            icon: Icons.qr_code_2_outlined,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 3,
                        decoration: inventoryInputDecoration(
                          label: l.descriptionOptional,
                          icon: Icons.notes_outlined,
                        ),
                      ),
                      if (!_isEditing || _addMoreUnits > 0) ...[
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _condition,
                          isExpanded: true,
                          decoration: inventoryInputDecoration(
                            label: _isEditing ? l.conditionAtIntakeNewUnits : l.conditionAtIntakeLabel,
                            icon: Icons.fact_check_outlined,
                          ),
                          items: [
                            AssetModel.conditionNew,
                            AssetModel.conditionGood,
                            AssetModel.conditionFair,
                            AssetModel.conditionDamaged,
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
                          hint: _isTool ? l.toolCategoryHint : l.assetCategoryHint,
                          icon: Icons.category_outlined,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? l.categoryRequired : null,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _categoryOptions.where((c) => c != 'Other').map((c) {
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
                  const SizedBox(height: 4),
                  inventoryPrimaryButton(
                    label: _isEditing ? l.saveChanges : (_isTool ? l.addTool : l.addAsset),
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
