import 'dart:async';

import 'package:almaworks/models/inventory/asset_booking_model.dart';
import 'package:almaworks/models/inventory/asset_maintenance_window_model.dart';
import 'package:almaworks/models/inventory/asset_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/asset_availability_calendar.dart';
import 'package:almaworks/screens/inventory/inventory_error_messages.dart';
import 'package:almaworks/screens/inventory/inventory_providers.dart';
import 'package:almaworks/screens/inventory/relative_date_label.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/confirm_dialog.dart';
import 'package:almaworks/widgets/inventory_form_section.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

/// Everyone — Technician, Admin, MainAdmin, or SystemAdmin alike — requests
/// a booking window for an asset/tool here; nobody books directly for
/// someone else anymore. Does NOT perform the checkout itself: a MainAdmin
/// or System Admin must review and approve (capturing condition/photos as
/// the actual handover confirmation if the window starts today, plus the
/// delivery method) before the asset is checked out. While this request is
/// pending, the asset is locked from any other request.
class RequestCheckoutScreen extends ConsumerStatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final AssetModel asset;
  final String requestedByUid;
  final String requestedByName;

  const RequestCheckoutScreen({
    super.key,
    required this.project,
    required this.logger,
    required this.asset,
    required this.requestedByUid,
    required this.requestedByName,
  });

  @override
  ConsumerState<RequestCheckoutScreen> createState() => _RequestCheckoutScreenState();
}

class _RequestCheckoutScreenState extends ConsumerState<RequestCheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final InventoryService _inventoryService = InventoryService();

  ProjectModel? _selectedProject;
  bool _isSaving = false;
  List<ProjectModel> _projects = [];
  bool _projectsLoaded = false;
  String? _projectsError;
  StreamSubscription<QuerySnapshot>? _projectsSub;

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    _subscribeProjects();
  }

  // Load the project list once up front (rather than inside the build
  // method via StreamBuilder) so the dropdown is only ever constructed
  // after real data is available — DropdownButtonFormField only honors
  // `initialValue` on its very first build, so building it early with an
  // empty list would leave the pre-selection stuck on nothing forever.
  // Split out from initState (rather than inline) so the error state's
  // "Retry" action can just re-run this instead of needing a full screen
  // reload — previously this stream had no onError handler at all, so any
  // transient hiccup left `_projectsLoaded` false forever with the picker's
  // spinner spinning with no way out.
  //
  // Deliberately NOT ProjectService.getAllProjects(): that method caches one
  // shared broadcast StreamController per process, and broadcast streams
  // never replay their most recent value to a late subscriber — only
  // whichever screen happened to be listening at the moment Firestore last
  // pushed a snapshot got it. Any other screen that subscribes afterward
  // gets nothing until Firestore emits a brand-new snapshot, which for a
  // rarely-changing `Projects` collection can mean an indefinitely stuck
  // spinner. Querying Firestore directly here sidesteps that entirely.
  void _subscribeProjects() {
    _projectsSub?.cancel();
    setState(() => _projectsError = null);
    _projectsSub = FirebaseFirestore.instance.collection('Projects').snapshots().listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          _projects = snapshot.docs.map(ProjectModel.fromFirestore).toList();
          _projectsLoaded = true;
          _projectsError = null;
          // Default to the project the user was already viewing Inventory
          // from — Inventory itself is company-wide, but most requests are
          // for the project the requester is currently working on, so
          // pre-selecting it saves a redundant pick while still letting
          // them change it.
          final matches = _projects.where((p) => p.id == widget.project.id);
          _selectedProject = matches.isEmpty ? null : matches.first;
        });
      },
      onError: (e) {
        widget.logger.e('❌ RequestCheckoutScreen: Projects stream error', error: e);
        if (!mounted) return;
        setState(() {
          _projectsLoaded = true;
          _projectsError = 'Could not load projects: $e';
        });
      },
    );
  }

  @override
  void dispose() {
    _projectsSub?.cancel();
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

  bool _rangesOverlap(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
    return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
  }

  /// Client-side preview only — highlights a selection that collides with an
  /// existing booking or maintenance window so the requester sees it before
  /// submitting, rather than only finding out after a rejection.
  /// `InventoryService.createCheckoutRequest`'s server-side `_assertNoOverlap`
  /// remains the actual source of truth.
  String? _findConflict(List<AssetBookingModel> bookings, List<AssetMaintenanceWindowModel> maintenance) {
    for (final b in bookings) {
      if (!b.blocksCalendar) continue;
      if (_rangesOverlap(_startDate, _endDate, b.scheduledStart, b.scheduledEnd)) {
        return 'This overlaps an existing booking for ${b.bookedForName} '
            '(${DateFormat('d MMM').format(b.scheduledStart)} - ${DateFormat('d MMM yyyy').format(b.scheduledEnd)}).';
      }
    }
    for (final m in maintenance) {
      if (_rangesOverlap(_startDate, _endDate, m.startDate, m.endDate)) {
        return 'This overlaps scheduled maintenance '
            '(${DateFormat('d MMM').format(m.startDate)} - ${DateFormat('d MMM yyyy').format(m.endDate)}).';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Request Checkout',
      message: 'Send a checkout request for "${widget.asset.name}" '
          '(${DateFormat('d MMM').format(_startDate)} - ${DateFormat('d MMM yyyy').format(_endDate)}) '
          'to a MainAdmin/System Admin for approval?',
      confirmLabel: 'Send Request',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await _inventoryService.createCheckoutRequest(
        assetId: widget.asset.id,
        assetName: widget.asset.name,
        itemType: widget.asset.itemType,
        requestedByUid: widget.requestedByUid,
        requestedByName: widget.requestedByName,
        projectId: _selectedProject?.id,
        projectName: _selectedProject?.name,
        reason: _reasonController.text.trim(),
        requestedStart: _startDate,
        requestedEnd: _endDate,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Request sent — waiting for MainAdmin/System Admin approval', style: GoogleFonts.poppins()),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      widget.logger.e('❌ RequestCheckoutScreen: Failed to submit request', error: e);
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
      title: 'Request Checkout',
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
                    icon: widget.asset.itemType == AssetModel.typeTool
                        ? Icons.handyman_outlined
                        : Icons.precision_manufacturing_outlined,
                    children: [
                      Text(
                        '${widget.asset.category} • ${widget.asset.itemType}',
                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  inventoryFormSection(
                    title: 'Booking Window',
                    icon: Icons.date_range_outlined,
                    subtitle: 'When you need it and when you\'ll return it',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickDate(isStart: true),
                              icon: const Icon(Icons.event_outlined, size: 18),
                              label: Text('From ${relativeDayLabelWithDate(_startDate)}',
                                  style: GoogleFonts.poppins(fontSize: 12.5)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickDate(isStart: false),
                              icon: const Icon(Icons.event_outlined, size: 18),
                              label: Text('To ${relativeDayLabelWithDate(_endDate)}',
                                  style: GoogleFonts.poppins(fontSize: 12.5)),
                            ),
                          ),
                        ],
                      ),
                      Consumer(
                        builder: (context, ref, _) {
                          final bookingsAsync = ref.watch(assetBookingsProvider(widget.asset.id));
                          final maintenanceAsync = ref.watch(assetMaintenanceWindowsProvider(widget.asset.id));
                          final bookings = bookingsAsync.valueOrNull ?? const <AssetBookingModel>[];
                          final maintenance = maintenanceAsync.valueOrNull ?? const <AssetMaintenanceWindowModel>[];

                          final conflict = _findConflict(bookings, maintenance);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (conflict != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(conflict,
                                            style: GoogleFonts.poppins(fontSize: 12, color: Colors.red[800])),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (bookings.isNotEmpty || maintenance.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text('Already on the calendar',
                                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                                const SizedBox(height: 8),
                                AssetAvailabilityCalendar(
                                  bookings: bookings,
                                  maintenanceWindows: maintenance,
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                  inventoryFormSection(
                    title: 'Request Details',
                    icon: Icons.fact_check_outlined,
                    children: [
                      TextFormField(
                        controller: _reasonController,
                        maxLines: 3,
                        decoration: inventoryInputDecoration(
                          label: 'Reason for checkout',
                          hint: 'e.g. Needed for site work at ...',
                          icon: Icons.edit_note_outlined,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Reason is required' : null,
                      ),
                      const SizedBox(height: 14),
                      if (!_projectsLoaded)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else if (_projectsError != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_projectsError!,
                                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.red[800])),
                              ),
                              TextButton(onPressed: _subscribeProjects, child: const Text('Retry')),
                            ],
                          ),
                        )
                      else
                        DropdownButtonFormField<ProjectModel>(
                          initialValue: _selectedProject,
                          isExpanded: true,
                          decoration: inventoryInputDecoration(label: 'Project (optional)', icon: Icons.folder_outlined),
                          items: _projects
                              .map((p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(p.name, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins()),
                                  ))
                              .toList(),
                          onChanged: (value) => setState(() => _selectedProject = value),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  inventoryPrimaryButton(
                    label: 'Send Request',
                    isLoading: _isSaving,
                    onPressed: _submit,
                    icon: Icons.send,
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
