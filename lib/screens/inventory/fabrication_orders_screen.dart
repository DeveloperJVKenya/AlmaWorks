import 'package:almaworks/models/inventory/material_fabrication_order_model.dart';
import 'package:almaworks/models/inventory/material_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/create_fabrication_order_screen.dart';
import 'package:almaworks/screens/inventory/inventory_colors.dart';
import 'package:almaworks/screens/inventory/inventory_labels.dart';
import 'package:almaworks/screens/inventory/inventory_permissions.dart';
import 'package:almaworks/screens/inventory/inventory_providers.dart';
import 'package:almaworks/screens/inventory/upload_fabrication_scan_screen.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/theme/app_colors.dart';
import 'package:almaworks/core/errors/friendly_error.dart';

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
      title: context.l10n.fabricationOrders,
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
              label: Text(context.l10n.newOrder, style: const TextStyle(fontWeight: FontWeight.w600)),
            )
          : null,
      child: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) {
          logger.e('❌ FabricationOrdersScreen: stream error $err');
          return Center(child: Text(friendlyError(err, action: context.l10n.couldNotLoadOrders), textAlign: TextAlign.center));
        },
        data: (orders) {
          if (orders.isEmpty) {
            return Center(
              child: Text(context.l10n.noFabricationOrdersFor(material.name),
                  style: TextStyle(color: AppColors.inkMuted)),
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
    final l = context.l10n;
    final label = order.isDiscrepancy
        ? l.invFabDiscrepancy
        : order.isVerified
            ? l.invFabVerified
            : order.isScanUploaded
                ? l.invFabScanUploaded
                : order.isPendingAdminReview
                    ? l.invFabPendingAdminReview
                    : l.fabStatusWithDriver;
    final unit = invLabel(order.unit);

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
                    child: Text(l.quantityIssued('${order.quantityIssued}', unit),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(l.formId(order.id), style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
              Text(l.issuedByOn(order.issuedByName, DateFormat('d MMM yyyy').format(order.issuedAt)),
                  style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
              if (order.projectName != null)
                Text(l.destination(order.projectName!), style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
              if (order.fabricatorName != null) ...[
                const SizedBox(height: 4),
                Text(l.fabricatorWithCondition(order.fabricatorName!, invLabel(order.fabricatorAckCondition ?? '-')),
                    style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
              ],
              if (order.technicianAckByName != null) ...[
                const SizedBox(height: 4),
                Text(
                  l.receivedByQuantity(order.technicianAckByName!, '${order.technicianAckQuantityReceived}', unit),
                  style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                ),
              ],
              if (order.adminReviewedByName != null) ...[
                const SizedBox(height: 4),
                Text(l.reviewedBy(order.adminReviewedByName!), style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
              ],
              if (order.hasQuantityDiscrepancy && !order.isVerified && !order.isDiscrepancy) ...[
                const SizedBox(height: 4),
                Text(l.quantitiesDontReconcile,
                    style: TextStyle(fontSize: 11, color: InventoryColors.damaged, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 10),
              _buildTraceTimeline(order, l),
              if (canUpload) ...[
                const SizedBox(height: 8),
                Text(l.tapToUploadScan,
                    style: TextStyle(fontSize: 11, color: InventoryColors.checkedOut, fontWeight: FontWeight.w600)),
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
                label: Text(context.l10n.markReviewed, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                style: ElevatedButton.styleFrom(backgroundColor: InventoryColors.checkedOut, foregroundColor: Colors.white),
              ),
            ]
          : [
              ElevatedButton.icon(
                onPressed: () => _verifyOrder(context, order, isDiscrepancy: false),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(context.l10n.verify, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                style: ElevatedButton.styleFrom(backgroundColor: InventoryColors.available, foregroundColor: Colors.white),
              ),
              OutlinedButton.icon(
                onPressed: () => _verifyOrder(context, order, isDiscrepancy: true),
                icon: const Icon(Icons.warning_amber_outlined, size: 18, color: InventoryColors.damaged),
                label: Text(context.l10n.flagDiscrepancy,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: InventoryColors.damaged)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: InventoryColors.damaged)),
              ),
            ],
    );
  }

  Future<void> _reviewOrder(BuildContext context, MaterialFabricationOrderModel order) async {
    final confirmed = await showConfirmDialog(
      context,
      title: context.l10n.markReviewed,
      message: context.l10n.confirmMarkReviewed(order.materialName),
      confirmLabel: context.l10n.markReviewed,
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
        showErrorSnack(context, e, action: context.l10n.couldNotMarkReviewed);
      }
    }
  }

  Future<void> _verifyOrder(BuildContext context, MaterialFabricationOrderModel order, {required bool isDiscrepancy}) async {
    final confirmed = await showConfirmDialog(
      context,
      title: isDiscrepancy ? context.l10n.flagDiscrepancy : context.l10n.verifyOrder,
      message: isDiscrepancy
          ? context.l10n.confirmFlagDiscrepancy(order.materialName)
          : context.l10n.confirmVerifyOrder(order.materialName),
      confirmLabel: isDiscrepancy ? context.l10n.flagDiscrepancy : context.l10n.verify,
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
        showErrorSnack(context, e, action: context.l10n.couldNotVerify);
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
  Widget _buildTraceTimeline(MaterialFabricationOrderModel order, AppLocalizations l) {
    final steps = <(String, DateTime?, bool)>[
      (l.traceHandedToDriver, order.issuedAt, true),
      (
        order.technicianAckByName != null ? l.traceReceivedBackBy(order.technicianAckByName!) : l.traceReceivedBack,
        order.technicianAckAt,
        !order.isIssued,
      ),
      (
        order.isDiscrepancy ? l.traceDiscrepancyFlagged : l.invFabVerified,
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
                  color: steps[i].$3 ? InventoryColors.available : AppColors.inkFaint,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    steps[i].$1,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: steps[i].$3 ? FontWeight.w600 : FontWeight.w400,
                      color: steps[i].$3 ? AppColors.ink : AppColors.inkFaint,
                    ),
                  ),
                ),
                if (steps[i].$3 && steps[i].$2 != null)
                  Text(DateFormat('d MMM, HH:mm').format(steps[i].$2!),
                      style: TextStyle(fontSize: 10, color: AppColors.inkFaint)),
              ],
            ),
          ),
      ],
    );
  }
}
