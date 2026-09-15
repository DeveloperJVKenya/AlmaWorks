import 'package:almaworks/models/inventory/material_fabrication_order_model.dart';
import 'package:almaworks/models/inventory/material_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/create_fabrication_order_screen.dart';
import 'package:almaworks/screens/inventory/inventory_colors.dart';
import 'package:almaworks/screens/inventory/inventory_permissions.dart';
import 'package:almaworks/screens/inventory/inventory_providers.dart';
import 'package:almaworks/screens/inventory/upload_fabrication_scan_screen.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

/// The fabrication-order trail for a single material: MainAdmin/SystemAdmin
/// can issue new orders; the site recipient (Technician or Admin/MainAdmin)
/// uploads the completed scanned form for an order still awaiting one, an
/// Admin/MainAdmin reviews it if a Technician submitted, and finally a
/// SystemAdmin/MainAdmin verifies or flags a discrepancy. Tools never
/// appear here — fabrication only ever applies to Materials, and only when
/// chosen at issue time.
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
                    createdByRole: userRole,
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
            itemBuilder: (context, i) => _buildOrderCard(context, ref, orders[i]),
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, WidgetRef ref, MaterialFabricationOrderModel order) {
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
                ? 'Ready for Verification'
                : order.isPendingAdminReview
                    ? 'Awaiting Admin Review'
                    : 'With Driver — Heading to Fabrication';

    final canUpload = InventoryPermissions.canUploadFabricationScan(userRole) && order.isIssued;
    final canReview = InventoryPermissions.canReviewFabricationScan(userRole) && order.isPendingAdminReview;
    final canVerify = InventoryPermissions.canVerifyFabricationOrder(userRole) && order.isScanUploaded;

    // SystemAdmin/MainAdmin can see an order still awaiting Admin review,
    // but shouldn't be able to act on it (open/verify) until that review is
    // done — visible, not actionable.
    final isFaintForViewer = InventoryPermissions.canVerifyFabricationOrder(userRole) &&
        !InventoryPermissions.canReviewFabricationScan(userRole) &&
        order.isPendingAdminReview;

    Widget card = Card(
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
                      recipientRole: userRole,
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
              if (order.adminReviewedByName != null) ...[
                const SizedBox(height: 4),
                Text('Reviewed by ${order.adminReviewedByName}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700])),
              ],
              if (order.hasQuantityDiscrepancy && !order.isVerified && !order.isDiscrepancy) ...[
                const SizedBox(height: 4),
                Text('⚠ Quantities don\'t fully reconcile — review before verifying',
                    style: GoogleFonts.poppins(fontSize: 11, color: InventoryColors.damaged, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 10),
              _buildTraceTimeline(order),
              if (canUpload) ...[
                const SizedBox(height: 8),
                Text('Tap to upload the completed scanned form',
                    style: GoogleFonts.poppins(fontSize: 11, color: InventoryColors.checkedOut, fontWeight: FontWeight.w600)),
              ],
              if (canReview) ...[
                const SizedBox(height: 10),
                _actionButtons(context, ref, order, review: true),
              ],
              if (canVerify) ...[
                const SizedBox(height: 10),
                _actionButtons(context, ref, order, review: false),
              ],
            ],
          ),
        ),
      ),
    );

    if (isFaintForViewer) {
      return Opacity(opacity: 0.45, child: IgnorePointer(child: card));
    }
    return card;
  }

  Widget _actionButtons(BuildContext context, WidgetRef ref, MaterialFabricationOrderModel order, {required bool review}) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: review
          ? [
              ElevatedButton.icon(
                onPressed: () => _reviewOrder(context, order),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: Text('Mark Reviewed', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12.5)),
                style: ElevatedButton.styleFrom(backgroundColor: InventoryColors.checkedOut, foregroundColor: Colors.white),
              ),
            ]
          : [
              ElevatedButton.icon(
                onPressed: () => _verifyOrder(context, order, isDiscrepancy: false),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text('Verify', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12.5)),
                style: ElevatedButton.styleFrom(backgroundColor: InventoryColors.available, foregroundColor: Colors.white),
              ),
              OutlinedButton.icon(
                onPressed: () => _verifyOrder(context, order, isDiscrepancy: true),
                icon: const Icon(Icons.warning_amber_outlined, size: 18, color: InventoryColors.damaged),
                label: Text('Flag Discrepancy',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12.5, color: InventoryColors.damaged)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: InventoryColors.damaged)),
              ),
            ],
    );
  }

  Future<void> _reviewOrder(BuildContext context, MaterialFabricationOrderModel order) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Mark Reviewed',
      message: 'Confirm you\'ve checked the scanned form for "${order.materialName}"? '
          'It will then be ready for SystemAdmin verification.',
      confirmLabel: 'Mark Reviewed',
    );
    if (!confirmed) return;
    try {
      await InventoryService().adminReviewFabricationScan(
        orderId: order.id,
        reviewerUid: currentUid,
        reviewerName: username,
        reviewerRole: userRole,
      );
    } catch (e) {
      logger.e('❌ FabricationOrdersScreen: Failed to review order', error: e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to mark reviewed: $e', style: GoogleFonts.poppins()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _verifyOrder(BuildContext context, MaterialFabricationOrderModel order, {required bool isDiscrepancy}) async {
    final confirmed = await showConfirmDialog(
      context,
      title: isDiscrepancy ? 'Flag Discrepancy' : 'Verify Order',
      message: isDiscrepancy
          ? 'Flag "${order.materialName}" as a quantity discrepancy for follow-up?'
          : 'Confirm "${order.materialName}" is verified and reconciled?',
      confirmLabel: isDiscrepancy ? 'Flag Discrepancy' : 'Verify',
    );
    if (!confirmed) return;
    try {
      await InventoryService().verifyFabricationOrder(
        orderId: order.id,
        verifiedByUid: currentUid,
        verifiedByName: username,
        verifierRole: userRole,
        isDiscrepancy: isDiscrepancy,
      );
    } catch (e) {
      logger.e('❌ FabricationOrdersScreen: Failed to verify order', error: e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to verify: $e', style: GoogleFonts.poppins()), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// The live tracking view — deliberately only two real checkpoints, each
  /// backed by an actual movement-history entry (see
  /// InventoryService.createFabricationOrder/submitFabricationFormScan):
  /// handed to the driver, and received back from the site recipient.
  /// Nothing in between (with fabricator, in transit, etc.) is tracked —
  /// by design, not an omission. The final verification outcome is shown
  /// as a third node since it's the order's end state, not an extra
  /// movement checkpoint.
  Widget _buildTraceTimeline(MaterialFabricationOrderModel order) {
    final steps = <(String, DateTime?, bool)>[
      ('Handed to driver (movement recorded)', order.issuedAt, true),
      (
        'Received back — scan uploaded${order.technicianAckByName != null ? ' by ${order.technicianAckByName}' : ''} (movement recorded)',
        order.technicianAckAt,
        !order.isIssued,
      ),
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
                Expanded(
                  child: Text(
                    steps[i].$1,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: steps[i].$3 ? FontWeight.w600 : FontWeight.w400,
                      color: steps[i].$3 ? Colors.grey[800] : Colors.grey[400],
                    ),
                  ),
                ),
                if (steps[i].$3 && steps[i].$2 != null)
                  Text(DateFormat('d MMM, HH:mm').format(steps[i].$2!),
                      style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey[500])),
              ],
            ),
          ),
      ],
    );
  }
}
