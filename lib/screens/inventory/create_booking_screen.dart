import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:almaworks/models/inventory/asset_booking_model.dart';
import 'package:almaworks/models/inventory/asset_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/asset_handover_form_pdf.dart';
import 'package:almaworks/screens/inventory/inventory_error_messages.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/confirm_dialog.dart';
import 'package:almaworks/widgets/inventory_form_section.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

/// MainAdmin/Admin: book an asset/tool for a date range. If the window
/// starts today, the physical handover is captured immediately (condition +
/// photos, asset flips to Checked Out); otherwise this only reserves the
/// window — a manager records the actual collection later, on the day.
///
/// An Admin can never book an asset out to themself (MainAdmin is exempt) —
/// enforced both here (the assignee picker excludes the current admin
/// unless they're MainAdmin) and, authoritatively, by InventoryService/
/// Firestore rules.
class CreateBookingScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final AssetModel asset;
  final String createdByUid;
  final String createdByName;
  final String createdByRole;

  const CreateBookingScreen({
    super.key,
    required this.project,
    required this.logger,
    required this.asset,
    required this.createdByUid,
    required this.createdByName,
    required this.createdByRole,
  });

  @override
  State<CreateBookingScreen> createState() => _CreateBookingScreenState();
}

class _CreateBookingScreenState extends State<CreateBookingScreen> {
  final InventoryService _inventoryService = InventoryService();
  final _conditionController = TextEditingController();

  final List<XFile> _selectedPhotos = [];
  final _driverNameController = TextEditingController();
  bool _isSaving = false;
  String _deliveryMethod = AssetBookingModel.deliveryDirect;

  List<Map<String, dynamic>> _users = [];
  bool _usersLoaded = false;
  String? _usersError;
  String? _selectedUserUid;
  StreamSubscription<QuerySnapshot>? _usersSub;

  List<ProjectModel> _projects = [];
  bool _projectsLoaded = false;
  String? _projectsError;
  String? _selectedProjectId;
  StreamSubscription<QuerySnapshot>? _projectsSub;

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 1));

  bool get _isMainAdmin => widget.createdByRole == 'MainAdmin';
  bool get _startsToday => !_startDate.isAfter(DateTime.now());
  bool get _isTool => widget.asset.itemType == AssetModel.typeTool;
  String get _itemLabel => _isTool ? 'Tool' : 'Asset';

  @override
  void initState() {
    super.initState();
    _subscribeUsers();
    _subscribeProjects();
  }

  // Split into their own methods (rather than inline in initState) so the
  // "Retry" action on a stream error can just re-run the same subscription
  // instead of needing a full screen reload — see item 5 fix: previously
  // these StreamSubscriptions had no onError handler at all, so any
  // transient hiccup (auth token not yet ready at mount, a brief network
  // blip) silently left `_usersLoaded`/`_projectsLoaded` false forever, with
  // the "Handover" card's spinner spinning with no way out.
  void _subscribeUsers() {
    _usersSub?.cancel();
    setState(() => _usersError = null);
    _usersSub = FirebaseFirestore.instance.collection('Users').snapshots().listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          _users = snapshot.docs
              .map((d) => {'username': d.id, 'uid': (d.data())['uid'] as String? ?? ''})
              .where((m) => (m['uid'] as String).isNotEmpty)
              // An Admin may never book an asset out to themself — MainAdmin is exempt.
              .where((m) => _isMainAdmin || m['uid'] != widget.createdByUid)
              .toList();
          _usersLoaded = true;
          _usersError = null;
        });
      },
      onError: (e) {
        widget.logger.e('❌ CreateBookingScreen: Users stream error', error: e);
        if (!mounted) return;
        setState(() {
          _usersLoaded = true;
          _usersError = 'Could not load users: $e';
        });
      },
    );
  }

  // Deliberately NOT ProjectService.getAllProjects(): that method caches one
  // shared broadcast StreamController per process and hands every caller
  // the SAME hot stream. Broadcast streams never replay their most recent
  // value to a late subscriber — only whichever screen happened to be
  // listening at the moment Firestore last pushed a snapshot got it. Any
  // other screen (like this one) that subscribes afterward gets nothing
  // until Firestore emits a brand-new snapshot, which for a rarely-changing
  // `Projects` collection can mean an indefinitely stuck spinner. Querying
  // Firestore directly here — the same way _subscribeUsers() above already
  // does for `Users` — sidesteps that shared-stream caching entirely.
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
        });
      },
      onError: (e) {
        widget.logger.e('❌ CreateBookingScreen: Projects stream error', error: e);
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
    _usersSub?.cancel();
    _projectsSub?.cancel();
    _conditionController.dispose();
    _driverNameController.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _selectedUserDoc {
    if (_selectedUserUid == null) return null;
    final matches = _users.where((m) => m['uid'] == _selectedUserUid);
    return matches.isEmpty ? null : matches.first;
  }

  ProjectModel? get _selectedProject {
    if (_selectedProjectId == null) return null;
    final matches = _projects.where((p) => p.id == _selectedProjectId);
    return matches.isEmpty ? null : matches.first;
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

  Future<void> _pickPhotos() async {
    final files = await ImagePicker().pickMultiImage();
    if (files.isEmpty || !mounted) return;
    setState(() => _selectedPhotos.addAll(files));
  }

  Future<void> _submit() async {
    if (_selectedUserDoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Select who this booking is for', style: GoogleFonts.poppins())),
      );
      return;
    }

    final title = _startsToday ? 'Check Out Now' : 'Book $_itemLabel';
    final message = _startsToday
        ? 'Check out "${widget.asset.name}" to ${_selectedUserDoc!['username']} now'
            '${_selectedProject != null ? ' for project ${_selectedProject!.name}' : ''}?'
        : 'Book "${widget.asset.name}" for ${_selectedUserDoc!['username']} from '
            '${DateFormat('d MMM').format(_startDate)} to ${DateFormat('d MMM yyyy').format(_endDate)}?';

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

      final booking = await _inventoryService.createBooking(
        assetId: widget.asset.id,
        assetName: widget.asset.name,
        itemType: widget.asset.itemType,
        bookedForUid: _selectedUserDoc!['uid'] as String,
        bookedForName: _selectedUserDoc!['username'] as String,
        projectId: _selectedProject?.id,
        projectName: _selectedProject?.name,
        scheduledStart: _startDate,
        scheduledEnd: _endDate,
        conditionNotes: _conditionController.text.trim(),
        photoBytesList: photoBytesList,
        photoFileNames: photoFileNames,
        deliveryMethod: _deliveryMethod,
        driverName: _deliveryMethod == AssetBookingModel.deliveryDriver
            ? _driverNameController.text.trim()
            : null,
        createdByUid: widget.createdByUid,
        createdByName: widget.createdByName,
        createdByRole: widget.createdByRole,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_startsToday ? '$_itemLabel checked out' : 'Booking created', style: GoogleFonts.poppins()),
          backgroundColor: Colors.green,
        ),
      );

      // Driver has no app account — the pickup/receipt acknowledgment is
      // captured on a printed form instead. Offer it right away, while the
      // admin still has the item in hand to give to the driver.
      if (_deliveryMethod == AssetBookingModel.deliveryDriver && mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Handover Form', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            content: Text(
              'Download the printable handover form for the driver to sign at pickup, '
              'and for ${_selectedUserDoc!['username']} to sign at receipt.',
              style: GoogleFonts.poppins(fontSize: 13),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Skip')),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await generateAndSaveHandoverForm(context: context, logger: widget.logger, booking: booking);
                },
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Download Form'),
              ),
            ],
          ),
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      widget.logger.e('❌ CreateBookingScreen: Failed to submit', error: e);
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
      title: 'Book $_itemLabel',
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
                    title: 'Booking Window',
                    icon: Icons.date_range_outlined,
                    subtitle: _startsToday
                        ? 'Starts today — this hands the item over immediately'
                        : 'Future window — the item stays Available until collected on the day',
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
                    ],
                  ),
                  inventoryFormSection(
                    title: 'Handover',
                    icon: Icons.logout,
                    children: [
                      _buildUserPicker(),
                      const SizedBox(height: 12),
                      _buildProjectPicker(),
                      const SizedBox(height: 16),
                      Text('Delivery method', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey[700])),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: AssetBookingModel.deliveryDirect,
                            label: Text('Direct handoff'),
                            icon: Icon(Icons.handshake_outlined, size: 16),
                          ),
                          ButtonSegment(
                            value: AssetBookingModel.deliveryDriver,
                            label: Text('Via Driver/Transporter'),
                            icon: Icon(Icons.local_shipping_outlined, size: 16),
                          ),
                        ],
                        selected: {_deliveryMethod},
                        onSelectionChanged: (s) => setState(() => _deliveryMethod = s.first),
                      ),
                      if (_deliveryMethod == AssetBookingModel.deliveryDriver) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _driverNameController,
                          decoration: inventoryInputDecoration(
                            label: 'Driver / Transporter name',
                            hint: 'e.g. James, company driver',
                            icon: Icons.badge_outlined,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'The recipient will need to tap "Acknowledge Receipt" once it arrives on site.',
                          style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey[600]),
                        ),
                      ],
                    ],
                  ),
                  inventoryFormSection(
                    title: 'Condition & Photos',
                    icon: Icons.fact_check_outlined,
                    subtitle: _startsToday ? null : 'Captured when the item is actually collected',
                    children: [
                      TextField(
                        controller: _conditionController,
                        maxLines: 3,
                        enabled: _startsToday,
                        decoration: inventoryInputDecoration(
                          label: 'Condition notes',
                          hint: 'Condition at handover',
                          icon: Icons.fact_check_outlined,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: (_isSaving || !_startsToday) ? null : _pickPhotos,
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
                    label: _startsToday ? 'Check Out' : 'Book $_itemLabel',
                    isLoading: _isSaving,
                    onPressed: _submit,
                    icon: _startsToday ? Icons.logout : Icons.event_available,
                    color: const Color(0xFF1565C0),
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

  Widget _buildUserPicker() {
    if (!_usersLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_usersError != null) {
      return _buildLoadError(_usersError!, _subscribeUsers);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedUserUid,
          isExpanded: true,
          decoration: inventoryInputDecoration(label: 'Book For', icon: Icons.person_outline),
          items: _users
              .map((m) => DropdownMenuItem(
                    value: m['uid'] as String,
                    child: Text(m['username'] as String, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins()),
                  ))
              .toList(),
          onChanged: (value) => setState(() => _selectedUserUid = value),
        ),
        // MainAdmin is the only role exempt from the self-checkout guard —
        // give it a one-tap shortcut instead of hunting for their own name
        // in a long user list.
        if (_isMainAdmin) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _selectedUserUid = widget.createdByUid),
              icon: const Icon(Icons.person_pin_circle_outlined, size: 16),
              label: Text('Book for myself', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProjectPicker() {
    if (!_projectsLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_projectsError != null) {
      return _buildLoadError(_projectsError!, _subscribeProjects);
    }
    return DropdownButtonFormField<String>(
      initialValue: _selectedProjectId,
      isExpanded: true,
      decoration: inventoryInputDecoration(
        label: 'Project (optional — leave blank for company storage)',
        icon: Icons.folder_outlined,
      ),
      items: _projects
          .map((p) => DropdownMenuItem(
                value: p.id,
                child: Text(p.name, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins()),
              ))
          .toList(),
      onChanged: (value) => setState(() => _selectedProjectId = value),
    );
  }

  Widget _buildLoadError(String message, VoidCallback onRetry) {
    return Container(
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
          Expanded(child: Text(message, style: GoogleFonts.poppins(fontSize: 12, color: Colors.red[800]))),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
