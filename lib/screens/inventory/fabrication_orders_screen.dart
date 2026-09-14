import 'package:almaworks/models/inventory/material_fabrication_order_model.dart';
import 'package:almaworks/models/inventory/material_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/create_fabrication_order_screen.dart';
import 'package:almaworks/screens/inventory/inventory_colors.dart';
import 'package:almaworks/screens/inventory/inventory_permissions.dart';
import 'package:almaworks/screens/inventory/inventory_providers.dart';
import 'package:almaworks/screens/inventory/upload_fabrication_scan_screen.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

/// The fabrication-order trail for a single material: MainAdmin/SystemAdmin
/// can issue new orders; a Technician can upload the completed scanned form
/// for an order still awaiting one. Tools never appear here — fabrication
/// only ever applies to Materials, and only when chosen at issue time.
class FabricationOrdersScreen extends ConsumerWidget {
  final ProjectModel project;
  final Logger logger;
  final MaterialModel material;
  final String userRole;
  final String username;
  final String currentUid;

  const FabricationOrdersScreen({
    super.key,
    required this.project,
    required this.logger,
    required this.material,
    required this.userRole,
    required this.username,
    required this.currentUid,
  });

  bool get _canApproveAndIssue => InventoryPermissions.canApproveAndIssue(userRole);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(materialFabricationOrdersProvider(material.id));

    return BaseLayout(
      title: 'Fabrication Orders',
      project: project,
      logger: logger,
      selectedMenuItem: 'Inventory',
      onMenuItemSelected: (_) {},
      floatingActionButton: _canApproveAndIssue
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CreateFabricationOrderScreen(
                    project: project,
                    logger: logger,
                    material: material,
                    createdByUid: currentUid,
                    createdByName: username,
                  ),
                ),
              ),
              icon: const Icon(Icons.add),
              label: Text('New Order', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            )
          : null,
      child: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) {
          logger.e('❌ FabricationOrdersScreen: stream error $err');
          return Center(child: Text('Error loading orders', style: GoogleFonts.poppins()));
        },
        data: (orders) {
          if (orders.isEmpty) {
            return Center(
              child: Text('No fabrication orders yet for "${material.name}"',
                  style: GoogleFonts.poppins(color: Colors.grey[600])),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            itemBuilder: (context, i) => _buildOrderCard(context, orders[i]),
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, MaterialFabricationOrderModel order) {
    final color = order.isDiscrepancy
        ? InventoryColors.damaged
        : order.isVerified
            ? InventoryColors.available
            : order.isScanUploaded
                ? InventoryColors.booked
                : InventoryColors.pendingRequest;
    final label = order.isDiscrepancy
        ? 'Discrepancy'
        : order.isVerified
            ? 'Verified'
            : order.isScanUploaded
                ? 'Scan Uploaded'
                : 'With Driver — Heading to Fabrication';

    // Only the Technician performs the scan-upload — never MainAdmin/
    // SystemAdmin (who issue orders) and never plain Admin either.
    final canUpload = InventoryPermissions.canUploadFabricationScan(userRole) && order.isIssued;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: canUpload
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UploadFabricationScanScreen(
                      project: project,
                      logger: logger,
                      order: order,
                      technicianUid: currentUid,
                      technicianName: username,
                    ),
                  ),
                )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${order.quantityIssued} ${order.unit} issued',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: Text(label, style: GoogleFonts.poppins(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Form ID: ${order.id}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[600])),
              Text('Issued by ${order.issuedByName} on ${DateFormat('d MMM yyyy').format(order.issuedAt)}',
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700])),
              if (order.projectName != null)
                Text('Destination: ${order.projectName}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700])),
              if (order.fabricatorName != null) ...[
                const SizedBox(height: 4),
                Text('Fabricator: ${order.fabricatorName} (${order.fabricatorAckCondition ?? '-'})',
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700])),
              ],
              if (order.technicianAckByName != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Received by ${order.technicianAckByName}: ${order.technicianAckQuantityReceived} ${order.unit}',
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
              const SizedBox(height: 10),
              _buildTraceTimeline(order),
              if (canUpload) ...[
                const SizedBox(height: 8),
                Text('Tap to upload the completed scanned form',
                    style: GoogleFonts.poppins(fontSize: 11, color: InventoryColors.checkedOut, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Shows exactly where this order sits in the paper-based
  /// Admin -> Driver -> Fabricator -> Driver -> Technician chain, since the
  /// underlying status model only has two real states before verification
  /// (issued/scanUploaded) — this makes that whole "issued" span legible as
  /// "materials are currently with the driver, heading to fabrication" for
  /// the Technician, rather than an opaque "Awaiting Scan".
  Widget _buildTraceTimeline(MaterialFabricationOrderModel order) {
    final steps = <(String, DateTime?, bool)>[
      ('Issued — handed to driver', order.issuedAt, true),
      ('Scan uploaded by Technician', order.technicianAckAt, order.isScanUploaded || order.isVerified || order.isDiscrepancy),
      (
        order.isDiscrepancy ? 'Discrepancy flagged' : 'Verified',
        order.verifiedAt,
        order.isVerified || order.isDiscrepancy,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  steps[i].$3 ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 14,
                  color: steps[i].$3 ? InventoryColors.available : Colors.grey[400],
                ),
                const SizedBox(width: 6),
                Text(
                  steps[i].$1,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: steps[i].$3 ? FontWeight.w600 : FontWeight.w400,
                    color: steps[i].$3 ? Colors.grey[800] : Colors.grey[400],
                  ),
                ),
                if (steps[i].$3 && steps[i].$2 != null) ...[
                  const Spacer(),
                  Text(DateFormat('d MMM, HH:mm').format(steps[i].$2!),
                      style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey[500])),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
