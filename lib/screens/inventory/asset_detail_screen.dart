import 'package:almaworks/models/inventory/asset_assignment_model.dart';
import 'package:almaworks/models/inventory/asset_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/record_custody_event_screen.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

/// Full traceability view for a single asset: current status/holder plus
/// the complete, immutable custody history (checkout/return events with
/// condition notes and photos).
class AssetDetailScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final String assetId;
  final String userRole;
  final String username;
  final String currentUid;

  const AssetDetailScreen({
    super.key,
    required this.project,
    required this.logger,
    required this.assetId,
    required this.userRole,
    required this.username,
    required this.currentUid,
  });

  @override
  State<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends State<AssetDetailScreen> {
  final InventoryService _inventoryService = InventoryService();

  @override
  Widget build(BuildContext context) {
    return BaseLayout(
      title: 'Asset Details',
      project: widget.project,
      logger: widget.logger,
      selectedMenuItem: 'Inventory',
      onMenuItemSelected: (_) {},
      child: StreamBuilder<AssetModel?>(
        stream: _inventoryService.streamAsset(widget.assetId),
        builder: (context, assetSnapshot) {
          if (assetSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final asset = assetSnapshot.data;
          if (asset == null) {
            return Center(child: Text('Asset not found', style: GoogleFonts.poppins()));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeaderCard(asset),
              const SizedBox(height: 16),
              _buildActionButton(asset),
              const SizedBox(height: 20),
              Text('Custody History', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              StreamBuilder<List<AssetAssignmentModel>>(
                stream: _inventoryService.streamAssetHistory(widget.assetId),
                builder: (context, historySnapshot) {
                  if (historySnapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final history = historySnapshot.data ?? const [];
                  if (history.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('No custody events yet', style: GoogleFonts.poppins(color: Colors.grey[600])),
                    );
                  }
                  return Column(
                    children: history.map(_buildHistoryEntry).toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard(AssetModel asset) {
    final statusColor = _statusColor(asset.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(asset.name,
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                  ),
                  child: Text(asset.status,
                      style: GoogleFonts.poppins(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(asset.category, style: GoogleFonts.poppins(color: Colors.grey[700])),
            if (asset.serialNumber != null) ...[
              const SizedBox(height: 4),
              Text('S/N: ${asset.serialNumber}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
            ],
            if (asset.description != null) ...[
              const SizedBox(height: 8),
              Text(asset.description!, style: GoogleFonts.poppins(fontSize: 13)),
            ],
            if (asset.isCheckedOut) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 18, color: Colors.blueGrey),
                  const SizedBox(width: 6),
                  Text('Held by ${asset.currentHolderName ?? 'Unknown'}', style: GoogleFonts.poppins(fontSize: 13)),
                ],
              ),
              if (asset.currentProjectName != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 18, color: Colors.blueGrey),
                    const SizedBox(width: 6),
                    Text(asset.currentProjectName!, style: GoogleFonts.poppins(fontSize: 13)),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(AssetModel asset) {
    final canAct = widget.userRole == 'MainAdmin' || widget.userRole == 'Admin';
    if (!canAct) return const SizedBox.shrink();

    if (asset.isAvailable) {
      return ElevatedButton.icon(
        onPressed: () => _navigateToCustodyEvent(mode: CustodyEventMode.checkout, asset: asset),
        icon: const Icon(Icons.logout),
        label: Text('Check Out', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(46),
        ),
      );
    }
    if (asset.isCheckedOut) {
      return ElevatedButton.icon(
        onPressed: () => _navigateToCustodyEvent(mode: CustodyEventMode.returnEvent, asset: asset),
        icon: const Icon(Icons.login),
        label: Text('Record Return', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(46),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  void _navigateToCustodyEvent({required CustodyEventMode mode, required AssetModel asset}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecordCustodyEventScreen(
          project: widget.project,
          logger: widget.logger,
          asset: asset,
          mode: mode,
          recordedByUid: widget.currentUid,
          recordedByName: widget.username,
          recordedByRole: widget.userRole,
        ),
      ),
    );
  }

  Widget _buildHistoryEntry(AssetAssignmentModel entry) {
    final isCheckout = entry.isCheckout;
    final color = isCheckout ? const Color(0xFF1565C0) : const Color(0xFF2E7D32);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isCheckout ? Icons.logout : Icons.login, color: color, size: 18),
                const SizedBox(width: 6),
                Text(
                  isCheckout ? 'Checked Out' : 'Returned',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: color),
                ),
                const Spacer(),
                Text(
                  DateFormat('d MMM yyyy, HH:mm').format(entry.eventAt),
                  style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${entry.assignedToName}${entry.projectName != null ? ' • ${entry.projectName}' : ''}',
                style: GoogleFonts.poppins(fontSize: 13)),
            if (entry.conditionNotes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(entry.conditionNotes, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700])),
            ],
            if (entry.photoUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: entry.photoUrls.length,
                  separatorBuilder: (context, _) => const SizedBox(width: 6),
                  itemBuilder: (context, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: GestureDetector(
                      onTap: () => _showFullPhoto(entry.photoUrls[i]),
                      child: Image.network(entry.photoUrls[i], width: 72, height: 72, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text('Recorded by ${entry.recordedByName} (${entry.recordedByRole})',
                style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  void _showFullPhoto(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(child: Image.network(url)),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case AssetModel.statusAvailable:
        return const Color(0xFF2E7D32);
      case AssetModel.statusCheckedOut:
        return const Color(0xFF1565C0);
      case AssetModel.statusUnderMaintenance:
        return const Color(0xFFE65100);
      case AssetModel.statusRetired:
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
}
