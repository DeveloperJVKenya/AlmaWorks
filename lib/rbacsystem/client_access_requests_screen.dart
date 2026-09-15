import 'package:almaworks/rbacsystem/auth_service.dart';
import 'package:almaworks/rbacsystem/client_request_model.dart';
import 'package:almaworks/rbacsystem/client_request_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class ClientAccessRequestsScreen extends StatefulWidget {
  final Logger logger;

  const ClientAccessRequestsScreen({super.key, required this.logger});

  @override
  State<ClientAccessRequestsScreen> createState() =>
      _ClientAccessRequestsScreenState();
}

class _ClientAccessRequestsScreenState
    extends State<ClientAccessRequestsScreen>
    with SingleTickerProviderStateMixin {
  final ClientRequestService _requestService = ClientRequestService();
  final AuthService _authService = AuthService();
  late TabController _tabController;
  // Gates the 'Admin'/'System Admin' options in the role-edit dialog —
  // MainAdmin and SystemAdmin have equal grant power here (the one
  // exception, a MainAdmin's own role being untouchable, is enforced
  // separately below regardless of caller); a plain Admin can still switch
  // someone between Client and Technician only.
  String _currentUserRole = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCurrentUserRole();
  }

  Future<void> _loadCurrentUserRole() async {
    final role = await _authService.getUserRole();
    if (mounted) setState(() => _currentUserRole = role);
  }

  /// Which roles the current approver may grant — Admin's scope is
  /// deliberately narrower than MainAdmin's (Technician/Sub-contractor
  /// only). Shared by every grant/re-approve/edit-role dialog below so the
  /// three don't drift out of sync with each other.
  List<({String value, String label, String subtitle})> _grantableRoleOptions() {
    const client = (
      value: 'Client',
      label: 'Client',
      subtitle: 'Read-only access to granted projects',
    );
    const technician = (
      value: 'Technician',
      label: 'Technician',
      subtitle: 'Full working access to granted projects (like Admin, minus Financials)',
    );
    const subContractor = (
      value: 'SubContractor',
      label: 'Sub-contractor',
      subtitle: 'Documents only, for their own uploads, on granted projects (more permissions defined later)',
    );
    const admin = (
      value: 'Admin',
      label: 'Admin',
      subtitle: 'Full system access, not limited to granted projects',
    );
    const systemAdmin = (
      value: 'SystemAdmin',
      label: 'System Admin',
      subtitle: 'Full Admin access, plus the only role (with MainAdmin) that can '
          'approve checkout requests, record returns, and issue materials',
    );

    if (_currentUserRole == 'MainAdmin' || _currentUserRole == 'SystemAdmin') {
      return [client, technician, subContractor, admin, systemAdmin];
    }
    // Admin is the only other role that can reach this screen at all
    // (see dashboard_screen.dart's menu gate) — scoped to exactly
    // Technician/Sub-contractor, never Client (self-evident default,
    // nothing to "grant"), Admin, or SystemAdmin.
    return [technician, subContractor];
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Scaffold
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Client Access Requests',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF0A2E5A),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Pending Requests', icon: Icon(Icons.pending_actions)),
            Tab(text: 'Request History', icon: Icon(Icons.history)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPendingRequestsTab(),
          _buildRequestHistoryTab(),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Pending tab
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildPendingRequestsTab() {
    return StreamBuilder<List<ClientRequest>>(
      stream: _requestService.getPendingRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0A2E5A)),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error loading requests',
                    style: GoogleFonts.poppins(fontSize: 18)),
                const SizedBox(height: 8),
                Text(
                  snapshot.error.toString(),
                  style: GoogleFonts.poppins(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final requests = snapshot.data ?? [];

        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox, size: 100, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'No Pending Requests',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Client access requests will appear here',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) =>
              _buildPendingRequestCard(requests[index]),
        );
      },
    );
  }

  Widget _buildPendingRequestCard(ClientRequest request) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF0A2E5A),
                  child: Text(
                    request.clientUsername[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.clientUsername,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        request.clientEmail,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Pending',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[900],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  'Requested: ${DateFormat('MMM dd, yyyy HH:mm').format(request.requestDate)}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showApprovalDialog(request),
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showDenialDialog(request),
                    icon: const Icon(Icons.cancel, size: 18),
                    label: const Text('Deny'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // History tab
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildRequestHistoryTab() {
    return StreamBuilder<List<ClientRequest>>(
      stream: _requestService.getAllRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0A2E5A)),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading history',
              style: GoogleFonts.poppins(),
            ),
          );
        }

        final requests = (snapshot.data ?? [])
            .where((r) => r.status != 'pending')
            .toList();

        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 100, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'No Request History',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) =>
              _buildHistoryRequestCard(requests[index]),
        );
      },
    );
  }

  Widget _buildHistoryRequestCard(ClientRequest request) {
    final isApproved = request.status == 'approved';
    final statusColor = isApproved ? Colors.green : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor:
                      const Color(0xFF0A2E5A).withValues(alpha: 0.15),
                  child: Text(
                    request.clientUsername[0].toUpperCase(),
                    style: const TextStyle(color: Color(0xFF0A2E5A)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.clientUsername,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        request.clientEmail,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isApproved ? 'Approved' : 'Denied',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // ── Action menu ───────────────────────────────────────────
                _buildHistoryActionMenu(request, isApproved),
              ],
            ),

            const SizedBox(height: 12),

            // ── Metadata rows ──────────────────────────────────────────────
            _buildInfoRow(
              Icons.calendar_today,
              'Requested: ${DateFormat('MMM dd, yyyy').format(request.requestDate)}',
            ),
            if (request.approvalDate != null)
              _buildInfoRow(
                Icons.event_available,
                'Processed: ${DateFormat('MMM dd, yyyy').format(request.approvalDate!)}',
              ),
            if (request.approvedBy != null)
              _buildInfoRow(
                Icons.person,
                'By: ${request.approvedBy}',
              ),
            if (isApproved)
              _buildInfoRow(
                Icons.badge_outlined,
                'Role: ${request.grantedRole}',
              ),
            if (isApproved && request.grantedProjects.isNotEmpty)
              _buildInfoRow(
                Icons.folder_open,
                '${request.grantedProjects.length} project(s) granted',
              ),
            if (!isApproved && request.denialReason != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 16, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Reason: ${request.denialReason}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.red[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Quick-action buttons ───────────────────────────────────────
            const SizedBox(height: 12),
            if (isApproved)
              _buildApprovedQuickActions(request)
            else
              _buildDeniedQuickActions(request),
          ],
        ),
      ),
    );
  }

  /// Three-dot overflow menu on every history card.
  Widget _buildHistoryActionMenu(ClientRequest request, bool isApproved) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (value) {
        switch (value) {
          case 'add_projects':
            _showAddProjectsDialog(request);
            break;
          case 'revoke_projects':
            _showRevokeProjectsDialog(request);
            break;
          case 'edit_role':
            _showEditRoleDialog(request);
            break;
          case 're_approve':
            _showReApproveDialog(request);
            break;
          case 're_deny':
            _showReDenyDialog(request);
            break;
        }
      },
      itemBuilder: (_) => isApproved
          ? [
              PopupMenuItem(
                value: 'add_projects',
                child: _popupItem(
                  Icons.add_circle_outline,
                  'Add More Projects',
                  Colors.green,
                ),
              ),
              PopupMenuItem(
                value: 'revoke_projects',
                child: _popupItem(
                  Icons.remove_circle_outline,
                  'Revoke Project Access',
                  Colors.orange,
                ),
              ),
              PopupMenuItem(
                value: 'edit_role',
                child: _popupItem(
                  Icons.manage_accounts_outlined,
                  'Change Role',
                  Colors.blue,
                ),
              ),
            ]
          : [
              PopupMenuItem(
                value: 're_approve',
                child: _popupItem(
                  Icons.check_circle_outline,
                  'Approve Now',
                  Colors.green,
                ),
              ),
              PopupMenuItem(
                value: 're_deny',
                child: _popupItem(
                  Icons.edit_note,
                  'Update Denial Reason',
                  Colors.red,
                ),
              ),
            ],
    );
  }

  Widget _popupItem(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label, style: GoogleFonts.poppins(fontSize: 13)),
      ],
    );
  }

  /// Compact buttons shown inline for approved cards.
  Widget _buildApprovedQuickActions(ClientRequest request) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showAddProjectsDialog(request),
            icon: const Icon(Icons.add, size: 16),
            label: Text('Add Projects',
                style: GoogleFonts.poppins(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green[700],
              side: BorderSide(color: Colors.green[300]!),
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showRevokeProjectsDialog(request),
            icon: const Icon(Icons.remove, size: 16),
            label: Text('Revoke Access',
                style: GoogleFonts.poppins(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange[700],
              side: BorderSide(color: Colors.orange[300]!),
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  /// Compact buttons shown inline for denied cards.
  Widget _buildDeniedQuickActions(ClientRequest request) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showReApproveDialog(request),
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: Text('Approve Now',
                style: GoogleFonts.poppins(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green[700],
              side: BorderSide(color: Colors.green[300]!),
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showReDenyDialog(request),
            icon: const Icon(Icons.edit_note, size: 16),
            label: Text('Update Reason',
                style: GoogleFonts.poppins(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red[700],
              side: BorderSide(color: Colors.red[300]!),
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Pending request dialogs (unchanged logic, unchanged UI)
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _showApprovalDialog(ClientRequest request) async {
    final selectedProjects = <String>[];
    final roleOptions = _grantableRoleOptions();
    // Every requester goes through this exact same request regardless of
    // which role they'll end up with; this is the only place that
    // decision actually gets made. Default to whatever's first in this
    // approver's own scope (Client for MainAdmin, Technician for Admin —
    // see _grantableRoleOptions) rather than hardcoding 'Client', since
    // Admin's scope doesn't include Client at all.
    String grantedRole = roleOptions.first.value;
    final projects = await _fetchAvailableProjects();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Approve Access Request',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Grant access to ${request.clientUsername} as:',
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
                const SizedBox(height: 4),
                RadioGroup<String>(
                  groupValue: grantedRole,
                  onChanged: (v) => setDialogState(() => grantedRole = v ?? grantedRole),
                  child: Column(
                    children: roleOptions
                        .map((r) => RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(r.label, style: GoogleFonts.poppins(fontSize: 14)),
                              subtitle: Text(r.subtitle,
                                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                              value: r.value,
                              activeColor: const Color(0xFF0A2E5A),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Select projects to grant access to:',
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
                const SizedBox(height: 16),
                if (projects.isEmpty)
                  Text('No projects available',
                      style: GoogleFonts.poppins(
                          color: Colors.grey[600], fontSize: 14))
                else
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: projects.length,
                      itemBuilder: (context, index) {
                        final project = projects[index];
                        final projectId = project['id'] as String;
                        final projectName = project['name'] as String;
                        return CheckboxListTile(
                          title: Text(projectName,
                              style: GoogleFonts.poppins(fontSize: 14)),
                          value: selectedProjects.contains(projectId),
                          activeColor: const Color(0xFF0A2E5A),
                          onChanged: (bool? value) {
                            setDialogState(() {
                              if (value == true) {
                                selectedProjects.add(projectId);
                              } else {
                                selectedProjects.remove(projectId);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: selectedProjects.isEmpty
                  ? null
                  : () => _approveRequest(request, selectedProjects, grantedRole),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A2E5A)),
              child: Text('Approve',
                  style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDenialDialog(ClientRequest request) async {
    final reasonController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Deny Access Request',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Are you sure you want to deny access for ${request.clientUsername}?',
              style: GoogleFonts.poppins(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'Reason (optional)',
                labelStyle: GoogleFonts.poppins(),
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () =>
                _denyRequest(request, reasonController.text),
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Deny',
                style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // History — Approved request dialogs
  // ──────────────────────────────────────────────────────────────────────────

  /// Dialog: add more projects to an already-approved request.
  Future<void> _showAddProjectsDialog(ClientRequest request) async {
    final selectedProjects = <String>[];
    final allProjects = await _fetchAvailableProjects();

    // Filter out already-granted ones.
    final available = allProjects
        .where((p) => !request.grantedProjects.contains(p['id']))
        .toList();

    if (!mounted) return;

    if (available.isEmpty) {
      _showSnack(
          'All available projects have already been granted.', Colors.blue);
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.add_circle_outline,
                  color: Colors.green, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Add Projects — ${request.clientUsername}',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select additional projects to grant:',
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: available.length,
                    itemBuilder: (context, i) {
                      final p = available[i];
                      return CheckboxListTile(
                        dense: true,
                        title: Text(p['name'] as String,
                            style: GoogleFonts.poppins(fontSize: 13)),
                        value: selectedProjects.contains(p['id']),
                        activeColor: Colors.green,
                        onChanged: (v) => setDialogState(() {
                          if (v == true) {
                            selectedProjects.add(p['id'] as String);
                          } else {
                            selectedProjects.remove(p['id']);
                          }
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              onPressed: selectedProjects.isEmpty
                  ? null
                  : () => _addProjects(request, selectedProjects),
              icon: const Icon(Icons.add, size: 16),
              label: Text('Add',
                  style: GoogleFonts.poppins(color: Colors.white)),
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
          ],
        ),
      ),
    );
  }

  /// Dialog: revoke specific projects from an already-approved request.
  Future<void> _showRevokeProjectsDialog(ClientRequest request) async {
    if (request.grantedProjects.isEmpty) {
      _showSnack('No granted projects to revoke.', Colors.blue);
      return;
    }

    // Resolve project names for display.
    final projectDetails =
        await _fetchProjectDetails(request.grantedProjects);

    if (!mounted) return;

    final selectedToRevoke = <String>[];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.remove_circle_outline,
                  color: Colors.orange, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Revoke Access — ${request.clientUsername}',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select projects to revoke access from:',
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 16, color: Colors.orange[700]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Revoking all projects will mark this request as denied.',
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: Colors.orange[800]),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: projectDetails.length,
                    itemBuilder: (context, i) {
                      final p = projectDetails[i];
                      return CheckboxListTile(
                        dense: true,
                        title: Text(p['name'] as String,
                            style: GoogleFonts.poppins(fontSize: 13)),
                        value:
                            selectedToRevoke.contains(p['id']),
                        activeColor: Colors.orange[700],
                        onChanged: (v) => setDialogState(() {
                          if (v == true) {
                            selectedToRevoke.add(p['id'] as String);
                          } else {
                            selectedToRevoke.remove(p['id']);
                          }
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              onPressed: selectedToRevoke.isEmpty
                  ? null
                  : () => _revokeProjects(request, selectedToRevoke),
              icon: const Icon(Icons.remove, size: 16),
              label: Text('Revoke',
                  style: GoogleFonts.poppins(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[700]),
            ),
          ],
        ),
      ),
    );
  }

  /// Dialog: change the role granted to an already-approved account —
  /// Client/Technician, plus Admin when the caller is a MainAdmin — without
  /// having to revoke and re-approve the request.
  Future<void> _showEditRoleDialog(ClientRequest request) async {
    // MainAdmin immunity: nobody — not even another MainAdmin — edits a
    // MainAdmin's role from here. Matches the same guard in
    // ClientRequestService.updateGrantedRole and firestore.rules' Users
    // update clause; this is just the earliest, friendliest place to stop
    // it, before a doomed write round-trip.
    if (request.grantedRole == 'MainAdmin') {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('MainAdmin is protected', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Text(
            '${request.clientUsername} is a MainAdmin — their role, project access, and permissions can\'t be '
            'changed or revoked from this screen, by design.',
            style: GoogleFonts.poppins(fontSize: 13),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('OK', style: GoogleFonts.poppins())),
          ],
        ),
      );
      return;
    }

    final roleOptions = _grantableRoleOptions();
    final canGrantAdmin = _currentUserRole == 'MainAdmin' || _currentUserRole == 'SystemAdmin';
    String selectedRole = roleOptions.any((r) => r.value == request.grantedRole)
        ? request.grantedRole
        : roleOptions.first.value;

    // PM eligibility is a separate, additive flag on the Users doc (not a
    // role swap — see TeamMember/ProjectModel.projectManagerUid) — fetch
    // its current value fresh since ClientRequest doesn't carry it.
    bool isProjectManager = false;
    if (canGrantAdmin) {
      try {
        final userQuery = await FirebaseFirestore.instance
            .collection('Users')
            .where('uid', isEqualTo: request.clientUid)
            .limit(1)
            .get();
        if (userQuery.docs.isNotEmpty) {
          isProjectManager = userQuery.docs.first.data()['isProjectManager'] as bool? ?? false;
        }
      } catch (e) {
        widget.logger.e('❌ ClientAccessRequestsScreen: failed to load PM flag', error: e);
      }
    }
    final initialIsProjectManager = isProjectManager;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.manage_accounts_outlined,
                  color: Colors.blue, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Change Role — ${request.clientUsername}',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current role: ${request.grantedRole}',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: selectedRole,
                  onChanged: (v) =>
                      setDialogState(() => selectedRole = v ?? selectedRole),
                  child: Column(
                    children: roleOptions
                        .map((r) => RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(r.label, style: GoogleFonts.poppins(fontSize: 14)),
                              subtitle: Text(r.subtitle,
                                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                              value: r.value,
                              activeColor: const Color(0xFF0A2E5A),
                            ))
                        .toList(),
                  ),
                ),
                if (canGrantAdmin) ...[
                  const Divider(height: 20),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text('Project Manager eligible',
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        'Makes them pickable as a project\'s Linked PM Account (Edit Project), independent '
                        'of the role above — doesn\'t change their base permissions.',
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                    value: isProjectManager,
                    activeColor: const Color(0xFF0A2E5A),
                    onChanged: (v) => setDialogState(() => isProjectManager = v ?? false),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: (selectedRole == request.grantedRole && isProjectManager == initialIsProjectManager)
                  ? null
                  : () => _updateRole(
                        request,
                        selectedRole,
                        isProjectManager: canGrantAdmin ? isProjectManager : null,
                      ),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A2E5A)),
              child: Text('Save',
                  style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // History — Denied request dialogs
  // ──────────────────────────────────────────────────────────────────────────

  /// Dialog: approve a previously denied request.
  Future<void> _showReApproveDialog(ClientRequest request) async {
    final selectedProjects = <String>[];
    final roleOptions = _grantableRoleOptions();
    String grantedRole = roleOptions.first.value;
    final projects = await _fetchAvailableProjects();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: Colors.green, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Approve Request — ${request.clientUsername}',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Previous denial reason context
                if (request.denialReason != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.history,
                            size: 14, color: Colors.red),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Previously denied: ${request.denialReason}',
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.red[800]),
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  'Grant access as:',
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
                RadioGroup<String>(
                  groupValue: grantedRole,
                  onChanged: (v) => setDialogState(() => grantedRole = v ?? grantedRole),
                  child: Column(
                    children: roleOptions
                        .map((r) => RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(r.label, style: GoogleFonts.poppins(fontSize: 13)),
                              value: r.value,
                              activeColor: Colors.green,
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Select projects to grant:',
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
                const SizedBox(height: 12),
                if (projects.isEmpty)
                  Text('No projects available',
                      style: GoogleFonts.poppins(
                          color: Colors.grey[600], fontSize: 13))
                else
                  Container(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: projects.length,
                      itemBuilder: (context, i) {
                        final p = projects[i];
                        return CheckboxListTile(
                          dense: true,
                          title: Text(p['name'] as String,
                              style:
                                  GoogleFonts.poppins(fontSize: 13)),
                          value: selectedProjects.contains(p['id']),
                          activeColor: Colors.green,
                          onChanged: (v) => setDialogState(() {
                            if (v == true) {
                              selectedProjects.add(p['id'] as String);
                            } else {
                              selectedProjects.remove(p['id']);
                            }
                          }),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              onPressed: selectedProjects.isEmpty
                  ? null
                  : () => _reApproveRequest(request, selectedProjects, grantedRole),
              icon: const Icon(Icons.check, size: 16),
              label: Text('Approve',
                  style: GoogleFonts.poppins(color: Colors.white)),
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
          ],
        ),
      ),
    );
  }

  /// Dialog: update denial reason / re-deny.
  Future<void> _showReDenyDialog(ClientRequest request) async {
    final reasonController =
        TextEditingController(text: request.denialReason ?? '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.edit_note, color: Colors.red, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Update Denial — ${request.clientUsername}',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Update the denial reason or confirm denial with a new message:',
              style: GoogleFonts.poppins(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'Denial reason (optional)',
                labelStyle: GoogleFonts.poppins(fontSize: 13),
                border: const OutlineInputBorder(),
                hintText: 'Enter a reason for the denial...',
                hintStyle:
                    GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
              ),
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () =>
                _reDenyRequest(request, reasonController.text),
            icon: const Icon(Icons.save, size: 16),
            label: Text('Save & Re-deny',
                style: GoogleFonts.poppins(color: Colors.white)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Actions — existing
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _approveRequest(
      ClientRequest request, List<String> projectIds, String grantedRole) async {
    Navigator.pop(context);

    final userData = await _authService.getUserData();
    if (userData == null) return;

    final error = await _requestService.approveClientRequest(
      requestId: request.requestId,
      projectIds: projectIds,
      approvedByUsername: userData['username'],
      approvedByUid: userData['uid'],
      grantedRole: grantedRole,
    );

    if (!mounted) return;
    if (error != null) {
      _showSnack(error, Colors.red);
    } else {
      _showSnack('Access granted to ${request.clientUsername}', Colors.green);
    }
  }

  Future<void> _denyRequest(ClientRequest request, String reason) async {
    Navigator.pop(context);

    final userData = await _authService.getUserData();
    if (userData == null) return;

    final error = await _requestService.denyClientRequest(
      requestId: request.requestId,
      deniedByUsername: userData['username'],
      deniedByUid: userData['uid'],
      reason: reason.isNotEmpty ? reason : null,
    );

    if (!mounted) return;
    if (error != null) {
      _showSnack(error, Colors.red);
    } else {
      _showSnack(
          'Request denied for ${request.clientUsername}', Colors.orange);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Actions — new (history editing)
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _addProjects(
      ClientRequest request, List<String> newProjectIds) async {
    Navigator.pop(context);

    final userData = await _authService.getUserData();
    if (userData == null) return;

    final error = await _requestService.addProjectsToApprovedRequest(
      requestId: request.requestId,
      clientUid: request.clientUid,
      clientUsername: request.clientUsername,
      newProjectIds: newProjectIds,
      adminUsername: userData['username'],
      adminUid: userData['uid'],
    );

    if (!mounted) return;
    if (error != null) {
      _showSnack(error, Colors.red);
    } else {
      _showSnack(
          'Projects added for ${request.clientUsername}', Colors.green);
    }
  }

  Future<void> _revokeProjects(
      ClientRequest request, List<String> projectIdsToRevoke) async {
    Navigator.pop(context);

    final userData = await _authService.getUserData();
    if (userData == null) return;

    final error = await _requestService.revokeProjectsFromApprovedRequest(
      requestId: request.requestId,
      clientUid: request.clientUid,
      clientUsername: request.clientUsername,
      projectIdsToRevoke: projectIdsToRevoke,
      adminUsername: userData['username'],
      adminUid: userData['uid'],
    );

    if (!mounted) return;
    if (error != null) {
      _showSnack(error, Colors.red);
    } else {
      _showSnack(
          'Access revoked for ${request.clientUsername}', Colors.orange);
    }
  }

  Future<void> _updateRole(ClientRequest request, String newRole, {bool? isProjectManager}) async {
    Navigator.pop(context);

    final userData = await _authService.getUserData();
    if (userData == null) return;

    final error = await _requestService.updateGrantedRole(
      requestId: request.requestId,
      clientUid: request.clientUid,
      newRole: newRole,
      adminUsername: userData['username'],
      adminUid: userData['uid'],
      isProjectManager: isProjectManager,
    );

    if (!mounted) return;
    if (error != null) {
      _showSnack(error, Colors.red);
    } else {
      _showSnack(
          '${request.clientUsername}\'s role changed to $newRole', Colors.green);
    }
  }

  Future<void> _reApproveRequest(
      ClientRequest request, List<String> projectIds, String grantedRole) async {
    Navigator.pop(context);

    final userData = await _authService.getUserData();
    if (userData == null) return;

    final error = await _requestService.reApproveRequest(
      requestId: request.requestId,
      projectIds: projectIds,
      adminUsername: userData['username'],
      adminUid: userData['uid'],
      grantedRole: grantedRole,
    );

    if (!mounted) return;
    if (error != null) {
      _showSnack(error, Colors.red);
    } else {
      _showSnack(
          '${request.clientUsername}\'s request has been approved',
          Colors.green);
    }
  }

  Future<void> _reDenyRequest(
      ClientRequest request, String newReason) async {
    Navigator.pop(context);

    final userData = await _authService.getUserData();
    if (userData == null) return;

    final error = await _requestService.reDenyRequest(
      requestId: request.requestId,
      adminUsername: userData['username'],
      adminUid: userData['uid'],
      newReason: newReason.isNotEmpty ? newReason : null,
    );

    if (!mounted) return;
    if (error != null) {
      _showSnack(error, Colors.red);
    } else {
      _showSnack('Denial updated for ${request.clientUsername}', Colors.orange);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────────────

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: color,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchAvailableProjects() async {
    try {
      widget.logger.i('📋 Fetching available projects');
      final snapshot =
          await FirebaseFirestore.instance.collection('Projects').get();
      widget.logger
          .i('✅ Found ${snapshot.docs.length} projects');
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {'id': doc.id, 'name': data['name'] ?? 'Unnamed Project'};
      }).toList();
    } catch (e) {
      widget.logger.e('❌ Error fetching projects: $e');
      return [];
    }
  }

  /// Fetches project name/id details for a given list of project IDs.
  /// Used to display the names of already-granted projects in the revoke dialog.
  Future<List<Map<String, dynamic>>> _fetchProjectDetails(
      List<String> projectIds) async {
    try {
      final results = <Map<String, dynamic>>[];
      for (final id in projectIds) {
        final doc = await FirebaseFirestore.instance
            .collection('Projects')
            .doc(id)
            .get();
        results.add({
          'id': id,
          'name': doc.exists
              ? (doc.data()?['name'] ?? 'Unknown Project')
              : 'Unknown Project',
        });
      }
      return results;
    } catch (e) {
      widget.logger.e('❌ Error fetching project details: $e');
      return projectIds.map((id) => {'id': id, 'name': id}).toList();
    }
  }
}