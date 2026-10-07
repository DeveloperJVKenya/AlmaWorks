import 'package:almaworks/models/inventory/material_fabrication_order_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/inventory_colors.dart';
import 'package:almaworks/screens/inventory/fabrication_orders_screen.dart';
import 'package:almaworks/screens/inventory/inventory_providers.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/screens/inventory/inventory_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/theme/app_colors.dart';
import 'package:almaworks/core/errors/friendly_error.dart';

/// MainAdmin/Admin worklist: every fabrication order across all materials
/// still awaiting its scanned paper form back, or flagged with a quantity
/// discrepancy that needs follow-up — the discoverable entry point that
/// used to be missing (previously an admin could only find these by
/// opening materials one at a time via Material Detail → Fabrication
/// Orders). Tapping an order jumps straight to that material's Fabrication
/// Orders live-tracking view — not the generic Material Detail screen —
/// since that's the trail the admin actually came here to follow up on.
class PendingFabricationOrdersScreen extends ConsumerWidget {
  final ProjectModel project;
  final Logger logger;
  final String currentUid;
  final String username;
  final String userRole;

  const PendingFabricationOrdersScreen({
    super.key,
    required this.project,
    required this.logger,
    required this.currentUid,
    required this.username,
    required this.userRole,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(pendingFabricationOrdersProvider);

    return BaseLayout(
      title: context.l10n.fabricationOrders,
      project: project,
      logger: logger,
      selectedMenuItem: 'Inventory',
      onMenuItemSelected: (_) {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.brandTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.precision_manufacturing_outlined, color: AppColors.brandInk),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.l10n.fabricationOrders, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
                      Text(
                        context.l10n.pendingFabricationSubtitle,
                        style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ordersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) {
                logger.e('❌ PendingFabricationOrdersScreen: stream error $err');
                return Center(child: Text(friendlyError(err, action: context.l10n.couldNotLoadOrders), textAlign: TextAlign.center));
              },
              data: (orders) {
                if (orders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(color: AppColors.brandTint, shape: BoxShape.circle),
                          child: Icon(Icons.inbox_outlined, size: 40, color: AppColors.brandInk.withValues(alpha: 0.5)),
                        ),
                        const SizedBox(height: 14),
                        Text(context.l10n.nothingNeedsAttention, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
                        const SizedBox(height: 4),
                        Text(context.l10n.newFabricationOrdersHint, style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                      ],
                    ),
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 720;
                    if (!isWide) {
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: orders.length,
                        itemBuilder: (context, index) => _buildOrderCard(context, ref, orders[index]),
                      );
                    }
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 440,
                        mainAxisExtent: 128,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                      ),
                      itemCount: orders.length,
                      itemBuilder: (context, index) => _buildOrderCard(context, ref, orders[index]),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, WidgetRef ref, MaterialFabricationOrderModel order) {
    final isDiscrepancy = order.isDiscrepancy;
    final color = isDiscrepancy
        ? InventoryColors.damaged
        : order.isScanUploaded
            ? InventoryColors.booked
            : InventoryColors.pendingRequest;
    final icon = isDiscrepancy ? Icons.warning_amber_outlined : Icons.hourglass_top;
    final l = context.l10n;
    final statusLabel = isDiscrepancy
        ? l.invFabDiscrepancy
        : order.isScanUploaded
            ? l.invFabScanUploaded
            : order.isPendingAdminReview
                ? l.invFabPendingAdminReview
                : l.fabStatusWithDriver;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openFabricationOrders(context, ref, order),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${order.materialName} — ${order.quantityIssued} ${invLabel(order.unit)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink)),
                    const SizedBox(height: 4),
                    Text(
                      '${l.issuedByName(order.issuedByName)}${order.projectName != null ? ' • ${order.projectName}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(DateFormat('d MMM yyyy').format(order.issuedAt),
                        style: TextStyle(fontSize: 11, color: AppColors.inkFaint)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                child: Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openFabricationOrders(
    BuildContext context,
    WidgetRef ref,
    MaterialFabricationOrderModel order,
  ) async {
    final material = await ref.read(materialByIdProvider(order.materialId).future);
    if (material == null) {
      if (context.mounted) {
        showWarningSnack(context, context.l10n.materialNoLongerExists);
      }
      return;
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FabricationOrdersScreen(
          project: project,
          logger: logger,
          material: material,
          userRole: userRole,
          username: username,
          currentUid: currentUid,
        ),
      ),
    );
  }
}
