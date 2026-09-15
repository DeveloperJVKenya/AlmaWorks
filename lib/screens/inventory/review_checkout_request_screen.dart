import 'dart:io';
import 'dart:typed_data';

import 'package:almaworks/models/inventory/asset_booking_model.dart';
import 'package:almaworks/models/inventory/checkout_request_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/inventory_error_messages.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/confirm_dialog.dart';
import 'package:almaworks/widgets/inventory_form_section.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';

/// MainAdmin/SystemAdmin screen: review a pending checkout request.
/// Approving captures condition notes + photos as the actual handover
/// confirmation (this action IS the checkout — it writes the immutable
/// custody ledger entry), plus the delivery method (direct handoff or via
/// driver) — the only place that choice is made now that "Book For" no
/// longer exists. Rejecting unlocks the asset back to Available with no
/// ledger entry created.
class ReviewCheckoutRequestScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final CheckoutRequestModel request;
  final String respondedByUid;
  final String respondedByName;
  final String respondedByRole;

  const ReviewCheckoutRequestScreen({
    super.key,
    required this.project,
    required this.logger,
    required this.request,
    required this.respondedByUid,
    required this.respondedByName,
    required this.respondedByRole,
  });

  @override
  State<ReviewCheckoutRequestScreen> createState() => _ReviewCheckoutRequestScreenState();
}

class _ReviewCheckoutRequestScreenState extends State<ReviewCheckoutRequestScreen> {
  final InventoryService _inventoryService = InventoryService();
  final _conditionController = TextEditingController();
  final _driverNameController = TextEditingController();
  final List<XFile> _selectedPhotos = [];
  bool _isSaving = false;
  String _deliveryMethod = AssetBookingModel.deliveryDirect;

  @override
  void dispose() {
    _conditionController.dispose();
    _driverNameController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage();
    if (files.isEmpty || !mounted) return;
    setState(() => _selectedPhotos.addAll(files));
  }

  Future<void> _approve() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Approve & Check Out',
      message: 'Approve ${widget.request.requestedByName}\'s request for "${widget.request.assetName}"? '
          'This checks the item out to them immediately.',
      confirmLabel: 'Approve',
    );
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

      await _inventoryService.approveCheckoutRequest(
        request: widget.request,
        conditionNotes: _conditionController.text.trim(),
        photoBytesList: photoBytesList,
        photoFileNames: photoFileNames,
        respondedByUid: widget.respondedByUid,
        respondedByName: widget.respondedByName,
        respondedByRole: widget.respondedByRole,
        deliveryMethod: _deliveryMethod,
        driverName: _deliveryMethod == AssetBookingModel.deliveryDriver
            ? _driverNameController.text.trim()
            : null,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Approved — item checked out', style: GoogleFonts.poppins()), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    } catch (e) {
      widget.logger.e('❌ ReviewCheckoutRequestScreen: Approve failed', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyInventoryError(e), style: GoogleFonts.poppins()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _reject() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Reject Request', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: TextField(
          controller: reasonController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Reason (optional)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: GoogleFonts.poppins())),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: Text('Reject', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await _inventoryService.rejectCheckoutRequest(
        requestId: widget.request.id,
        assetId: widget.request.assetId,
        respondedByUid: widget.respondedByUid,
        respondedByName: widget.respondedByName,
        rejectionReason: reasonController.text.trim().isEmpty ? null : reasonController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request rejected', style: GoogleFonts.poppins()), backgroundColor: Colors.blueGrey),
      );
      Navigator.pop(context);
    } catch (e) {
      widget.logger.e('❌ ReviewCheckoutRequestScreen: Reject failed', error: e);
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
    final r = widget.request;
    return BaseLayout(
      title: 'Review Request',
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
                  title: r.assetName,
                  icon: Icons.inbox_outlined,
                  children: [
                    _infoRow('Requested by', r.requestedByName),
                    if (r.projectName != null) _infoRow('Project', r.projectName!),
                    _infoRow('Reason', r.reason),
                  ],
                ),
                inventoryFormSection(
                  title: 'Approve — Condition at Handover',
                  icon: Icons.fact_check_outlined,
                  children: [
                    Text(
                      'Filling this in and tapping Approve checks the item out to '
                      '${r.requestedByName} immediately.',
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _conditionController,
                      maxLines: 3,
                      decoration: inventoryInputDecoration(label: 'Condition notes', icon: Icons.fact_check_outlined),
                    ),
                    const SizedBox(height: 16),
                    Text('Delivery', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey[700])),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: AssetBookingModel.deliveryDirect,
                          label: Text('Direct handoff', style: GoogleFonts.poppins(fontSize: 12.5)),
                          icon: const Icon(Icons.handshake_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: AssetBookingModel.deliveryDriver,
                          label: Text('Via Driver/Transporter', style: GoogleFonts.poppins(fontSize: 12.5)),
                          icon: const Icon(Icons.local_shipping_outlined, size: 16),
                        ),
                      ],
                      selected: {_deliveryMethod},
                      onSelectionChanged: (s) => setState(() => _deliveryMethod = s.first),
                    ),
                    if (_deliveryMethod == AssetBookingModel.deliveryDriver) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _driverNameController,
                        decoration: inventoryInputDecoration(label: 'Driver name', icon: Icons.person_outline),
                      ),
                    ],
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
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isSaving ? null : _reject,
                      icon: const Icon(Icons.close, color: Colors.red),
                      label: Text('Reject', style: GoogleFonts.poppins(color: Colors.red, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _approve,
                      icon: _isSaving
                          ? const SizedBox(
                              height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check),
                      label: Text('Approve', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                    ),
                  ],
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

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
          ),
          Expanded(child: Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
