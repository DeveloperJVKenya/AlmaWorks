import 'dart:async';

import 'package:almaworks/models/inventory/asset_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:almaworks/services/project_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/confirm_dialog.dart';
import 'package:almaworks/widgets/inventory_form_section.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';

/// Admin-side screen: request to check out an Available asset/tool. Does
/// NOT perform the checkout itself — a MainAdmin must review and approve
/// (capturing condition/photos as the actual handover confirmation) before
/// the asset is checked out. While this request is pending, the asset is
/// locked from any other request or checkout.
class RequestCheckoutScreen extends StatefulWidget {
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
  State<RequestCheckoutScreen> createState() => _RequestCheckoutScreenState();
}

class _RequestCheckoutScreenState extends State<RequestCheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final InventoryService _inventoryService = InventoryService();
  final ProjectService _projectService = ProjectService();

  ProjectModel? _selectedProject;
  bool _isSaving = false;
  List<ProjectModel> _projects = [];
  bool _projectsLoaded = false;
  StreamSubscription<List<ProjectModel>>? _projectsSub;

  @override
  void initState() {
    super.initState();
    // Load the project list once up front (rather than inside the build
    // method via StreamBuilder) so the dropdown is only ever constructed
    // after real data is available — DropdownButtonFormField only honors
    // `initialValue` on its very first build, so building it early with an
    // empty list would leave the pre-selection stuck on nothing forever.
    _projectsSub = _projectService.getAllProjects().listen((projects) {
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _projectsLoaded = true;
        // Default to the project the user was already viewing Inventory
        // from — Inventory itself is company-wide, but most requests are
        // for the project the requester is currently working on, so
        // pre-selecting it saves a redundant pick while still letting
        // them change it. Resolved by id since the stream returns its
        // own ProjectModel instances.
        final matches = projects.where((p) => p.id == widget.project.id);
        _selectedProject = matches.isEmpty ? null : matches.first;
      });
    });
  }

  @override
  void dispose() {
    _projectsSub?.cancel();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Request Checkout',
      message: 'Send a checkout request for "${widget.asset.name}" to MainAdmin for approval?',
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
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Request sent — waiting for MainAdmin approval', style: GoogleFonts.poppins()),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      widget.logger.e('❌ RequestCheckoutScreen: Failed to submit request', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e', style: GoogleFonts.poppins()), backgroundColor: Colors.red),
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
                    icon: widget.asset.itemType == AssetModel.typeTool ? Icons.handyman_outlined : Icons.build_outlined,
                    children: [
                      Text(
                        '${widget.asset.category} • ${widget.asset.itemType}',
                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]),
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
    );
  }
}
