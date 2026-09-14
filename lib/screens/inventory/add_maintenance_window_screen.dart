import 'package:almaworks/models/inventory/asset_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/inventory_error_messages.dart';
import 'package:almaworks/screens/inventory/inventory_permissions.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/confirm_dialog.dart';
import 'package:almaworks/widgets/inventory_form_section.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

/// MainAdmin/Admin: block out a date range during which this asset/tool
/// can't be booked (e.g. scheduled servicing) — rejected if it overlaps an
/// existing scheduled/active booking.
class AddMaintenanceWindowScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final AssetModel asset;
  final String createdByUid;
  final String createdByName;
  final String userRole;

  const AddMaintenanceWindowScreen({
    super.key,
    required this.project,
    required this.logger,
    required this.asset,
    required this.createdByUid,
    required this.createdByName,
    required this.userRole,
  });

  @override
  State<AddMaintenanceWindowScreen> createState() => _AddMaintenanceWindowScreenState();
}

class _AddMaintenanceWindowScreenState extends State<AddMaintenanceWindowScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final InventoryService _inventoryService = InventoryService();

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 1));
  bool _isSaving = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: isStart ? DateTime.now().subtract(const Duration(days: 1)) : _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (!_endDate.isAfter(_startDate)) {
          _endDate = _startDate.add(const Duration(days: 1));
        }
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Schedule Maintenance',
      message: 'Block "${widget.asset.name}" from booking between '
          '${DateFormat('d MMM').format(_startDate)} and ${DateFormat('d MMM yyyy').format(_endDate)}?',
      confirmLabel: 'Schedule',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await _inventoryService.createMaintenanceWindow(
        assetId: widget.asset.id,
        assetName: widget.asset.name,
        startDate: _startDate,
        endDate: _endDate,
        reason: _reasonController.text.trim(),
        createdByUid: widget.createdByUid,
        createdByName: widget.createdByName,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maintenance window scheduled', style: GoogleFonts.poppins()), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    } catch (e) {
      widget.logger.e('❌ AddMaintenanceWindowScreen: Failed to submit', error: e);
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
    if (!InventoryPermissions.canManageCatalog(widget.userRole)) {
      return BaseLayout(
        title: 'Schedule Maintenance',
        project: widget.project,
        logger: widget.logger,
        selectedMenuItem: 'Inventory',
        onMenuItemSelected: (_) {},
        child: Center(
          child: Text(
            'You do not have permission to schedule maintenance.',
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[700]),
          ),
        ),
      );
    }
    return BaseLayout(
      title: 'Schedule Maintenance',
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
                      title: widget.asset.name,
                      icon: Icons.build_outlined,
                      children: [
                        Text('${widget.asset.category} • ${widget.asset.itemType}',
                            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600])),
                      ],
                    ),
                    inventoryFormSection(
                      title: 'Blackout Window',
                      icon: Icons.date_range_outlined,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _pickDate(isStart: true),
                                icon: const Icon(Icons.event_outlined, size: 18),
                                label: Text('From ${DateFormat('d MMM yyyy').format(_startDate)}',
                                    style: GoogleFonts.poppins(fontSize: 12.5)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _pickDate(isStart: false),
                                icon: const Icon(Icons.event_outlined, size: 18),
                                label: Text('To ${DateFormat('d MMM yyyy').format(_endDate)}',
                                    style: GoogleFonts.poppins(fontSize: 12.5)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _reasonController,
                          maxLines: 2,
                          decoration: inventoryInputDecoration(
                            label: 'Reason',
                            hint: 'e.g. Scheduled servicing',
                            icon: Icons.edit_note_outlined,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Reason is required' : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    inventoryPrimaryButton(
                      label: 'Schedule',
                      isLoading: _isSaving,
                      onPressed: _submit,
                      icon: Icons.build_outlined,
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
