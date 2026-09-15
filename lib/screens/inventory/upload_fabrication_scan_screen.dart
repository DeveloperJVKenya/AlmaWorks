import 'dart:io';
import 'dart:typed_data';

import 'package:almaworks/models/inventory/material_fabrication_order_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/inventory_colors.dart';
import 'package:almaworks/screens/inventory/inventory_error_messages.dart';
import 'package:almaworks/screens/inventory/inventory_permissions.dart';
import 'package:almaworks/services/file_pick_helper.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/confirm_dialog.dart';
import 'package:almaworks/widgets/inventory_form_section.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:logger/logger.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The site recipient (Technician or Admin/MainAdmin) scans/uploads the
/// completed paper chain-of-custody form and confirms its values before
/// they become the digital record.
///
/// Capture is document-based, not a single photo: "Scan Document" drives
/// an on-device auto-capture document scanner (edge detection + cropping,
/// no manual shutter framing needed) that supports multiple pages, which
/// are assembled into one PDF client-side; "Upload File" is the
/// alternative for a document already scanned elsewhere (any PDF/image
/// file via the system picker) — the record is never a bare, uncropped
/// photo either way.
///
/// OCR (on-device, google_mlkit_text_recognition) only ever produces a
/// best-effort PRE-FILL for the review fields below, run per captured page
/// image before PDF assembly (not on an already-uploaded PDF file) —
/// accuracy on a handwritten form is inherently limited, so every field
/// stays editable and nothing reaches [InventoryService.submitFabricationFormScan]
/// until the recipient has reviewed/corrected it and tapped Submit. The raw
/// OCR text is still saved alongside the record for later reference/audit.
/// Submitting here never self-verifies — see [InventoryService.submitFabricationFormScan]'s
/// doc comment for the Admin-review / SystemAdmin-verify chain that follows.
class UploadFabricationScanScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final MaterialFabricationOrderModel order;
  final String technicianUid;
  final String technicianName;
  final String recipientRole;

  const UploadFabricationScanScreen({
    super.key,
    required this.project,
    required this.logger,
    required this.order,
    required this.technicianUid,
    required this.technicianName,
    required this.recipientRole,
  });

  @override
  State<UploadFabricationScanScreen> createState() => _UploadFabricationScanScreenState();
}

class _UploadFabricationScanScreenState extends State<UploadFabricationScanScreen> {
  final InventoryService _inventoryService = InventoryService();

  // Multi-page camera scan (cropped page image paths, in capture order) —
  // mutually exclusive with an uploaded document; picking one clears the
  // other, since this screen holds exactly one document per submission.
  List<String> _capturedPagePaths = [];
  // A document uploaded directly (already scanned elsewhere) — any file
  // type the system picker offers; stored as-is, no re-assembly.
  Uint8List? _uploadedFileBytes;
  String? _uploadedFileName;

  bool _isAssembling = false;
  bool _isRunningOcr = false;
  bool _isSaving = false;
  String? _ocrRawText;

  bool get _hasScan => _capturedPagePaths.isNotEmpty || _uploadedFileBytes != null;

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

  /// Drives the on-device document scanner — auto-detects the form's edges
  /// and crops it (no manual photo framing), supports capturing multiple
  /// pages in one session. Never stores a bare, uncropped photo.
  Future<void> _scanDocument() async {
    try {
      final pages = await CunningDocumentScanner.getPictures(noOfPages: 10);
      if (pages == null || pages.isEmpty || !mounted) return;
      setState(() {
        _capturedPagePaths = pages;
        _uploadedFileBytes = null;
        _uploadedFileName = null;
        _ocrRawText = null;
      });
      if (!kIsWeb) await _runOcrOnPages(pages);
    } catch (e) {
      widget.logger.e('❌ UploadFabricationScanScreen: Document scan failed', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the document scanner', style: GoogleFonts.poppins()), backgroundColor: Colors.red),
      );
    }
  }

  /// Alternative to scanning — attach a document already scanned/prepared
  /// elsewhere (PDF or image) via the system file picker.
  Future<void> _pickExistingFile() async {
    PickedUploadFile? picked;
    try {
      picked = await pickFileForUpload(allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
    } on FileBytesUnavailableException catch (e) {
      widget.logger.e('❌ UploadFabricationScanScreen: File pick failed', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString(), style: GoogleFonts.poppins()), backgroundColor: Colors.red),
      );
      return;
    }
    if (picked == null || !mounted) return;
    setState(() {
      _uploadedFileBytes = picked!.bytes;
      _uploadedFileName = picked.name;
      _capturedPagePaths = [];
      _ocrRawText = null;
    });
  }

  /// Best-effort on-device text recognition — pre-fill only, run against
  /// each captured page in turn and concatenated. Not run on web
  /// (google_mlkit_text_recognition needs a native platform channel) or
  /// against a directly-uploaded file (OCR needs an image, not a PDF) —
  /// web users / uploaded-file submissions just fill the review form
  /// manually.
  Future<void> _runOcrOnPages(List<String> pagePaths) async {
    setState(() => _isRunningOcr = true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final buffer = StringBuffer();
      for (final path in pagePaths) {
        final inputImage = InputImage.fromFilePath(path);
        final result = await recognizer.processImage(inputImage);
        buffer.writeln(result.text);
      }
      if (!mounted) return;
      final text = buffer.toString();
      setState(() => _ocrRawText = text);
      _prefillFromOcr(text);
    } catch (e) {
      widget.logger.e('❌ UploadFabricationScanScreen: OCR failed', error: e);
    } finally {
      await recognizer.close();
      if (mounted) setState(() => _isRunningOcr = false);
    }
  }

  /// Assembles the captured page images into a single PDF (one page per
  /// image) — the record stored for a camera scan is always a document,
  /// never a raw photo. A directly-uploaded file is used as-is.
  Future<(Uint8List bytes, String fileName)?> _buildScanPayload() async {
    if (_uploadedFileBytes != null && _uploadedFileName != null) {
      return (_uploadedFileBytes!, _uploadedFileName!);
    }
    if (_capturedPagePaths.isEmpty) return null;

    setState(() => _isAssembling = true);
    try {
      final doc = pw.Document();
      for (final path in _capturedPagePaths) {
        final bytes = await File(path).readAsBytes();
        final image = pw.MemoryImage(bytes);
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (context) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
          ),
        );
      }
      final pdfBytes = await doc.save();
      final fileName = 'fabrication_scan_${widget.order.id}.pdf';
      return (pdfBytes, fileName);
    } finally {
      if (mounted) setState(() => _isAssembling = false);
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
      _hasScan &&
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
      final payload = await _buildScanPayload();
      if (payload == null) {
        throw Exception('Attach a scanned document or upload a file before submitting');
      }
      await _inventoryService.submitFabricationFormScan(
        order: widget.order,
        scanBytes: payload.$1,
        scanFileName: payload.$2,
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
        recipientRole: widget.recipientRole,
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
    if (!InventoryPermissions.canUploadFabricationScan(widget.recipientRole)) {
      return BaseLayout(
        title: 'Upload Completed Form',
        project: widget.project,
        logger: widget.logger,
        selectedMenuItem: 'Inventory',
        onMenuItemSelected: (_) {},
        child: Center(
          child: Text(
            'You do not have permission to submit a fabrication scan.',
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[700]),
          ),
        ),
      );
    }
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
                    subtitle: 'Scan the completed form (multi-page supported) or upload an existing document',
                    children: [
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: (_isSaving || _isAssembling) ? null : _scanDocument,
                            icon: const Icon(Icons.document_scanner_outlined),
                            label: Text('Scan Document', style: GoogleFonts.poppins()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: (_isSaving || _isAssembling) ? null : _pickExistingFile,
                            icon: const Icon(Icons.upload_file_outlined),
                            label: Text('Upload File', style: GoogleFonts.poppins()),
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
                      if (_capturedPagePaths.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('${_capturedPagePaths.length} page(s) captured',
                            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 120,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _capturedPagePaths.length,
                            separatorBuilder: (context, _) => const SizedBox(width: 8),
                            itemBuilder: (context, i) => ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(File(_capturedPagePaths[i]), width: 90, height: 120, fit: BoxFit.cover),
                            ),
                          ),
                        ),
                      ],
                      if (_uploadedFileBytes != null && _uploadedFileName != null) ...[
                        const SizedBox(height: 12),
                        Row(children: [
                          const Icon(Icons.insert_drive_file_outlined, color: InventoryColors.checkedOut),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_uploadedFileName!,
                                style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]),
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
                    isLoading: _isSaving || _isAssembling,
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
