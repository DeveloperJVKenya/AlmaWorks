import 'package:almaworks/models/inventory/asset_assignment_model.dart';
import 'package:almaworks/models/inventory/asset_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/add_asset_screen.dart';
import 'package:almaworks/screens/inventory/inventory_providers.dart';
import 'package:almaworks/screens/inventory/record_custody_event_screen.dart';
import 'package:almaworks/screens/inventory/request_checkout_screen.dart';
import 'package:almaworks/screens/inventory/review_checkout_request_screen.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

/// Full traceability view for a single asset: current status/holder plus
/// the complete, immutable custody history (checkout/return events with
/// condition notes and photos).
class AssetDetailScreen extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final assetAsync = ref.watch(assetByIdProvider(assetId));

    return BaseLayout(
      title: 'Asset Details',
      project: project,
      logger: logger,
      selectedMenuItem: 'Inventory',
      onMenuItemSelected: (_) {},
      actions: userRole == 'MainAdmin'
          ? [
              assetAsync.maybeWhen(
                data: (asset) => asset == null
                    ? const SizedBox.shrink()
                    : IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AddAssetScreen(
                              project: project,
                              logger: logger,
                              itemType: asset.itemType,
                              createdByUid: currentUid,
                              createdByName: username,
                              existingAsset: asset,
                            ),
                          ),
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
            ]
          : null,
      child: assetAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) {
          logger.e('❌ AssetDetailScreen: stream error $err');
          return Center(child: Text('Error loading asset', style: GoogleFonts.poppins()));
        },
        data: (asset) {
          if (asset == null) {
            return Center(child: Text('Asset not found', style: GoogleFonts.poppins()));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeaderCard(asset),
              const SizedBox(height: 16),
              _buildActionButton(context, asset),
              const SizedBox(height: 20),
              Text('Custody History', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Consumer(
                builder: (context, ref, _) {
                  final historyAsync = ref.watch(assetHistoryProvider(assetId));
                  return historyAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (err, _) {
                      logger.e('❌ AssetDetailScreen: history stream error $err');
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text('Error loading history', style: GoogleFonts.poppins(color: Colors.grey[600])),
                      );
                    },
                    data: (history) {
                      if (history.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text('No custody events yet', style: GoogleFonts.poppins(color: Colors.grey[600])),
                        );
                      }
                      return Column(children: history.map((e) => _buildHistoryEntry(context, e)).toList());
                    },
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
    final statusColor = asset.hasPendingRequest ? const Color(0xFFE65100) : _statusColor(asset.status);
    final statusLabel = asset.hasPendingRequest ? 'Request Pending' : asset.status;
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
                  child: Text(statusLabel,
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
            const SizedBox(height: 4),
            Text('Condition at intake: ${asset.initialCondition}',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
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

  Widget _buildActionButton(BuildContext context, AssetModel asset) {
    final canAct = userRole == 'MainAdmin' || userRole == 'Admin' || userRole == 'Technician';
    if (!canAct) return const SizedBox.shrink();

    // A pending request locks the asset — nobody else can request/check it
    // out until MainAdmin resolves it.
    if (asset.hasPendingRequest) {
      if (userRole != 'MainAdmin') {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFE65100).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE65100).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.hourglass_top, color: Color(0xFFE65100), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('A checkout request for this item is awaiting MainAdmin review.',
                    style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFFE65100))),
              ),
            ],
          ),
        );
      }
      return Consumer(
        builder: (context, ref, _) {
          final requestAsync = ref.watch(requestByIdProvider(asset.pendingRequestId!));
          return requestAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Text('Error loading request', style: GoogleFonts.poppins(color: Colors.red)),
            data: (req) {
              if (req == null) return const SizedBox.shrink();
              return ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ReviewCheckoutRequestScreen(
                      project: project,
                      logger: logger,
                      request: req,
                      respondedByUid: currentUid,
                      respondedByName: username,
                      respondedByRole: userRole,
                    ),
                  ),
                ),
                icon: const Icon(Icons.fact_check_outlined),
                label: Text('Review Request from ${req.requestedByName}',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65100),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                ),
              );
            },
          );
        },
      );
    }

    if (asset.isAvailable) {
      if (userRole == 'MainAdmin') {
        return ElevatedButton.icon(
          onPressed: () => _navigateToCustodyEvent(context, mode: CustodyEventMode.checkout, asset: asset),
          icon: const Icon(Icons.logout),
          label: Text('Check Out', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1565C0),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
          ),
        );
      }
      // Admin: request only — MainAdmin must approve before it's checked out.
      return ElevatedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RequestCheckoutScreen(
              project: project,
              logger: logger,
              asset: asset,
              requestedByUid: currentUid,
              requestedByName: username,
            ),
          ),
        ),
        icon: const Icon(Icons.send_outlined),
        label: Text('Request Checkout', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(46),
        ),
      );
    }
    if (asset.isCheckedOut) {
      return ElevatedButton.icon(
        onPressed: () => _navigateToCustodyEvent(context, mode: CustodyEventMode.returnEvent, asset: asset),
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

  void _navigateToCustodyEvent(BuildContext context, {required CustodyEventMode mode, required AssetModel asset}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecordCustodyEventScreen(
          project: project,
          logger: logger,
          asset: asset,
          mode: mode,
          recordedByUid: currentUid,
          recordedByName: username,
          recordedByRole: userRole,
        ),
      ),
    );
  }

  Widget _buildHistoryEntry(BuildContext context, AssetAssignmentModel entry) {
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
                      onTap: () => _showFullPhoto(context, entry.photoUrls[i]),
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

  void _showFullPhoto(BuildContext context, String url) {
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
