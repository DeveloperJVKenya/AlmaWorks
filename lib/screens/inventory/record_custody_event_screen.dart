import 'dart:io';
import 'dart:typed_data';

import 'package:almaworks/models/inventory/asset_booking_model.dart';
import 'package:almaworks/models/inventory/asset_model.dart';
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
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';

enum CustodyEventMode { collection, returnEvent }

/// Records the physical handover of a *scheduled* booking (mode: collection
/// — the booking's date has arrived, hand the item over now) or the return
/// of a checked-out item (mode: returnEvent — item comes back to storage).
/// One screen, mode-driven, to avoid duplicating the photo-picker/condition-
/// notes/confirm-dialog scaffolding twice.
///
/// The return path additionally captures a structured [AssetModel]
/// condition rating (not just free-text notes) — this is what makes
/// mishandling traceable back to whoever held it in reporting, rather than
/// only living in prose.
///
/// [booking] is required for collection (a handover always starts from a
/// scheduled booking) but nullable for returnEvent: an asset checked out
/// via the pre-booking direct-checkout path (or any other route that leaves
/// a custody ledger entry with no paired booking — see
/// [AssetAssignmentModel.bookingId]) has no [AssetBookingModel] to close.
/// When null, holder/project details come from [asset]'s own custody
/// pointer fields instead, and submission calls
/// [InventoryService.recordLegacyReturn] rather than
/// [InventoryService.recordBookingReturn].
class RecordCustodyEventScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final AssetModel asset;
  final AssetBookingModel? booking;
  final CustodyEventMode mode;
  final String recordedByUid;
  final String recordedByName;
  final String recordedByRole;

  const RecordCustodyEventScreen({
    super.key,
    required this.project,
    required this.logger,
    required this.asset,
    required this.booking,
    required this.mode,
    required this.recordedByUid,
    required this.recordedByName,
    required this.recordedByRole,
  }) : assert(
          booking != null || mode == CustodyEventMode.returnEvent,
          'booking is required for CustodyEventMode.collection',
        );

  @override
  State<RecordCustodyEventScreen> createState() => _RecordCustodyEventScreenState();
}

class _RecordCustodyEventScreenState extends State<RecordCustodyEventScreen> {
  final InventoryService _inventoryService = InventoryService();
  final _conditionController = TextEditingController();

  final List<XFile> _selectedPhotos = [];
  bool _isSaving = false;
  String _conditionRating = AssetModel.conditionGood;

  bool get _isCollection => widget.mode == CustodyEventMode.collection;

  @override
  void dispose() {
    _conditionController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final files = await ImagePicker().pickMultiImage();
    if (files.isEmpty || !mounted) return;
    setState(() => _selectedPhotos.addAll(files));
  }

  Future<void> _submit() async {
    final title = _isCollection ? 'Record Collection' : 'Record Return';
    final returningFrom = widget.booking?.bookedForName ?? widget.asset.currentHolderName ?? 'storage';
    final message = _isCollection
        ? 'Confirm "${widget.asset.name}" is being handed over to ${widget.booking!.bookedForName} now?'
        : 'Record the return of "${widget.asset.name}" from $returningFrom?';

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

      if (_isCollection) {
        await _inventoryService.recordCollection(
          booking: widget.booking!,
          conditionNotes: _conditionController.text.trim(),
          photoBytesList: photoBytesList,
          photoFileNames: photoFileNames,
          recordedByUid: widget.recordedByUid,
          recordedByName: widget.recordedByName,
          recordedByRole: widget.recordedByRole,
        );
      } else if (widget.booking != null) {
        await _inventoryService.recordBookingReturn(
          booking: widget.booking!,
          conditionNotes: _conditionController.text.trim(),
          conditionRating: _conditionRating,
          photoBytesList: photoBytesList,
          photoFileNames: photoFileNames,
          recordedByUid: widget.recordedByUid,
          recordedByName: widget.recordedByName,
          recordedByRole: widget.recordedByRole,
        );
      } else {
        await _inventoryService.recordLegacyReturn(
          asset: widget.asset,
          conditionNotes: _conditionController.text.trim(),
          conditionRating: _conditionRating,
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
          content: Text(_isCollection ? 'Collection recorded' : 'Return recorded', style: GoogleFonts.poppins()),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      widget.logger.e('❌ RecordCustodyEventScreen: Failed to submit', error: e);
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
      title: _isCollection ? 'Record Collection' : 'Record Return',
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
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(widget.asset.name,
                        style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  inventoryFormSection(
                    title: _isCollection ? 'Handover' : 'Return',
                    icon: _isCollection ? Icons.logout : Icons.login,
                    children: [
                      _buildReadOnlyRow(
                        _isCollection ? 'Handing over to' : 'Returning from',
                        widget.booking?.bookedForName ?? widget.asset.currentHolderName ?? 'Unknown',
                      ),
                      if ((widget.booking?.projectName ?? widget.asset.currentProjectName) != null)
                        _buildReadOnlyRow(
                          'Project',
                          widget.booking?.projectName ?? widget.asset.currentProjectName!,
                        ),
                    ],
                  ),
                  inventoryFormSection(
                    title: 'Condition & Photos',
                    icon: Icons.fact_check_outlined,
                    children: [
                      if (!_isCollection) ...[
                        Text('Condition rating', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey[700])),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            AssetModel.conditionNew,
                            AssetModel.conditionGood,
                            AssetModel.conditionFair,
                            AssetModel.conditionDamaged,
                          ].map((rating) {
                            final selected = _conditionRating == rating;
                            final color = InventoryColors.forCondition(rating);
                            return ChoiceChip(
                              label: Text(rating, style: GoogleFonts.poppins(fontSize: 12)),
                              selected: selected,
                              onSelected: (_) => setState(() => _conditionRating = rating),
                              selectedColor: color.withValues(alpha: 0.18),
                              labelStyle: TextStyle(color: selected ? color : Colors.grey[700]),
                              side: BorderSide(color: selected ? color : Colors.grey.withValues(alpha: 0.3)),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextField(
                        controller: _conditionController,
                        maxLines: 3,
                        decoration: inventoryInputDecoration(
                          label: 'Condition notes',
                          hint: _isCollection ? 'Condition at handover' : 'Condition at return',
                          icon: Icons.fact_check_outlined,
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
                    label: _isCollection ? 'Confirm Collection' : 'Record Return',
                    isLoading: _isSaving,
                    onPressed: _submit,
                    icon: _isCollection ? Icons.logout : Icons.login,
                    color: _isCollection ? InventoryColors.checkedOut : InventoryColors.available,
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
}
