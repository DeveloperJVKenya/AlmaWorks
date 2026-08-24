import 'dart:io';
import 'dart:typed_data';

import 'package:almaworks/models/inventory/material_fabrication_order_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/inventory_colors.dart';
import 'package:almaworks/screens/inventory/inventory_error_messages.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/confirm_dialog.dart';
import 'package:almaworks/widgets/inventory_form_section.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';

/// Technician: scan/upload the completed paper chain-of-custody form and
/// confirm its values before they become the digital record.
///
/// OCR (on-device, google_mlkit_text_recognition) only ever produces a
/// best-effort PRE-FILL for the review fields below — accuracy on a
/// handwritten form is inherently limited, so every field stays editable
/// and nothing reaches [InventoryService.submitFabricationFormScan] until
/// the Technician has reviewed/corrected it and tapped Submit. The raw OCR
/// text is still saved alongside the record for later reference/audit.
class UploadFabricationScanScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final MaterialFabricationOrderModel order;
  final String technicianUid;
  final String technicianName;

  const UploadFabricationScanScreen({
    super.key,
    required this.project,
    required this.logger,
    required this.order,
    required this.technicianUid,
    required this.technicianName,
  });

  @override
  State<UploadFabricationScanScreen> createState() => _UploadFabricationScanScreenState();
}

class _UploadFabricationScanScreenState extends State<UploadFabricationScanScreen> {
  final InventoryService _inventoryService = InventoryService();

  XFile? _scanFile;
  Uint8List? _scanBytes;
  bool _isRunningOcr = false;
  bool _isSaving = false;
  String? _ocrRawText;

  final _driverPickupController = TextEditingController();
  final _fabricatorNameController = TextEditingController();
  final _fabricatorReceivedController = TextEditingController();
  final _fabricatorDamageNotesController = TextEditingController();
  final _fabricatorOutputController = TextEditingController();
  final _driverFromFabricatorController = TextEditingController();
  final _technicianReceivedController = TextEditingController();
  String _fabricatorCondition = MaterialFabricationOrderModel.conditionGood;

  @override
  void initState() {
    super.initState();
    _fabricatorNameController.text = widget.order.expectedFabricatorName ?? '';
  }

  @override
  void dispose() {
    _driverPickupController.dispose();
    _fabricatorNameController.dispose();
    _fabricatorReceivedController.dispose();
    _fabricatorDamageNotesController.dispose();
    _fabricatorOutputController.dispose();
    _driverFromFabricatorController.dispose();
    _technicianReceivedController.dispose();
    super.dispose();
  }

  Future<void> _pickScan({required bool fromCamera}) async {
    final picker = ImagePicker();
    final file = fromCamera ? await picker.pickImage(source: ImageSource.camera) : await picker.pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;

    final bytes = kIsWeb ? await file.readAsBytes() : await File(file.path).readAsBytes();
    setState(() {
      _scanFile = file;
      _scanBytes = bytes;
    });

    if (!kIsWeb) await _runOcr(file.path);
  }

  /// Best-effort on-device text recognition — pre-fill only. Not run on
  /// web (google_mlkit_text_recognition needs a native platform channel);
  /// web users just fill the review form manually.
  Future<void> _runOcr(String imagePath) async {
    setState(() => _isRunningOcr = true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final result = await recognizer.processImage(inputImage);
      if (!mounted) return;
      setState(() => _ocrRawText = result.text);
      _prefillFromOcr(result.text);
    } catch (e) {
      widget.logger.e('❌ UploadFabricationScanScreen: OCR failed', error: e);
    } finally {
      await recognizer.close();
      if (mounted) setState(() => _isRunningOcr = false);
    }
  }

  /// Very rough "number near a keyword" pre-fill — the Technician is
  /// expected to verify every value against the physical form before
  /// submitting, this just saves re-typing when it happens to work.
  void _prefillFromOcr(String text) {
    final lines = text.split('\n');
    double? numberNear(List<String> keywords) {
      for (final line in lines) {
        final lower = line.toLowerCase();
        if (keywords.any((k) => lower.contains(k))) {
          final match = RegExp(r'\d+(\.\d+)?').firstMatch(line);
          if (match != null) return double.tryParse(match.group(0)!);
        }
      }
      return null;
    }

    final driverPickup = numberNear(['quantity taken', 'pickup']);
    final fabReceived = numberNear(['quantity received']);
    final fabOutput = numberNear(['fabricated quantity', 'output']);
    final driverFromFab = numberNear(['collected']);
    final techReceived = numberNear(['quantity received']);

    setState(() {
      if (driverPickup != null) _driverPickupController.text = driverPickup.toString();
      if (fabReceived != null) _fabricatorReceivedController.text = fabReceived.toString();
      if (fabOutput != null) _fabricatorOutputController.text = fabOutput.toString();
      if (driverFromFab != null) _driverFromFabricatorController.text = driverFromFab.toString();
      if (techReceived != null) _technicianReceivedController.text = techReceived.toString();
      if (text.toLowerCase().contains('damaged')) _fabricatorCondition = MaterialFabricationOrderModel.conditionDamaged;
    });
  }

  bool get _formComplete =>
      _scanBytes != null &&
      double.tryParse(_driverPickupController.text.trim()) != null &&
      _fabricatorNameController.text.trim().isNotEmpty &&
      double.tryParse(_fabricatorReceivedController.text.trim()) != null &&
      double.tryParse(_fabricatorOutputController.text.trim()) != null &&
      double.tryParse(_driverFromFabricatorController.text.trim()) != null &&
      double.tryParse(_technicianReceivedController.text.trim()) != null;

  Future<void> _submit() async {
    if (!_formComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fill in every field and attach the scan before submitting', style: GoogleFonts.poppins())),
      );
      return;
    }

    final confirmed = await showConfirmDialog(
      context,
      title: 'Submit Verified Form',
      message: 'Confirm these values match the completed paper form for "${widget.order.materialName}"? '
          'This becomes the permanent digital record.',
      confirmLabel: 'Submit',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await _inventoryService.submitFabricationFormScan(
        order: widget.order,
        scanBytes: _scanBytes!,
        scanFileName: _scanFile!.name,
        ocrRawText: _ocrRawText,
        driverAckQuantityAtPickup: double.parse(_driverPickupController.text.trim()),
        fabricatorName: _fabricatorNameController.text.trim(),
        fabricatorAckQuantityReceived: double.parse(_fabricatorReceivedController.text.trim()),
        fabricatorAckCondition: _fabricatorCondition,
        fabricatorDamageNotes: _fabricatorDamageNotesController.text.trim().isEmpty
            ? null
            : _fabricatorDamageNotesController.text.trim(),
        fabricatorAckQuantityOutput: double.parse(_fabricatorOutputController.text.trim()),
        driverAckQuantityFromFabricator: double.parse(_driverFromFabricatorController.text.trim()),
        technicianAckQuantityReceived: double.parse(_technicianReceivedController.text.trim()),
        technicianAckByUid: widget.technicianUid,
        technicianAckByName: widget.technicianName,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Form submitted', style: GoogleFonts.poppins()), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    } catch (e) {
      widget.logger.e('❌ UploadFabricationScanScreen: Failed to submit', error: e);
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
    return BaseLayout(
      title: 'Upload Completed Form',
      project: widget.project,
      logger: widget.logger,
      selectedMenuItem: 'Inventory',
      onMenuItemSelected: (_) {},
      child: Container(
        color: inventoryPageBackground,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            inventoryFormMaxWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  inventoryFormSection(
                    title: widget.order.materialName,
                    icon: Icons.description_outlined,
                    subtitle: 'Form ID: ${widget.order.id} • Issued ${widget.order.quantityIssued} ${widget.order.unit}',
                    children: const [],
                  ),
                  inventoryFormSection(
                    title: 'Scan',
                    icon: Icons.document_scanner_outlined,
                    subtitle: 'Capture or select a clear photo of the completed form',
                    children: [
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isSaving ? null : () => _pickScan(fromCamera: true),
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: Text('Camera', style: GoogleFonts.poppins()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isSaving ? null : () => _pickScan(fromCamera: false),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: Text('Gallery', style: GoogleFonts.poppins()),
                          ),
                        ),
                      ]),
                      if (_isRunningOcr) ...[
                        const SizedBox(height: 12),
                        Row(children: [
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Text('Reading form (pre-fill only — verify everything below)...',
                              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                        ]),
                      ],
                      if (_scanBytes != null) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: kIsWeb
                              ? Image.network(_scanFile!.path, height: 160, fit: BoxFit.cover)
                              : Image.file(File(_scanFile!.path), height: 160, fit: BoxFit.cover),
                        ),
                      ],
                    ],
                  ),
                  inventoryFormSection(
                    title: 'Verify Values',
                    icon: Icons.fact_check_outlined,
                    subtitle: 'Every value below must match the physical form — correct anything OCR got wrong',
                    children: [
                      _numField(_driverPickupController, 'Driver pickup quantity (from office)'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _fabricatorNameController,
                        decoration: inventoryInputDecoration(label: 'Fabricator name', icon: Icons.factory_outlined),
                      ),
                      const SizedBox(height: 12),
                      _numField(_fabricatorReceivedController, 'Fabricator: quantity received'),
                      const SizedBox(height: 12),
                      Text('Fabricator condition', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey[700])),
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, children: [
                        MaterialFabricationOrderModel.conditionGood,
                        MaterialFabricationOrderModel.conditionDamaged,
                      ].map((c) {
                        final selected = _fabricatorCondition == c;
                        final color = c == MaterialFabricationOrderModel.conditionDamaged
                            ? InventoryColors.damaged
                            : InventoryColors.available;
                        return ChoiceChip(
                          label: Text(c, style: GoogleFonts.poppins(fontSize: 12)),
                          selected: selected,
                          onSelected: (_) => setState(() => _fabricatorCondition = c),
                          selectedColor: color.withValues(alpha: 0.18),
                          labelStyle: TextStyle(color: selected ? color : Colors.grey[700]),
                        );
                      }).toList()),
                      if (_fabricatorCondition == MaterialFabricationOrderModel.conditionDamaged) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _fabricatorDamageNotesController,
                          maxLines: 2,
                          decoration: inventoryInputDecoration(label: 'Damage description', icon: Icons.report_problem_outlined),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _numField(_fabricatorOutputController, 'Fabricator: fabricated output quantity'),
                      const SizedBox(height: 12),
                      _numField(_driverFromFabricatorController, 'Driver: quantity collected from fabricator'),
                      const SizedBox(height: 12),
                      _numField(_technicianReceivedController, 'Your (Technician) received quantity'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  inventoryPrimaryButton(
                    label: 'Submit',
                    isLoading: _isSaving,
                    onPressed: _submit,
                    icon: Icons.upload_outlined,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: inventoryInputDecoration(label: '$label (${widget.order.unit})', icon: Icons.numbers_outlined),
    );
  }
}
