import 'package:almaworks/models/inventory/material_fabrication_order_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/inventory_colors.dart';
import 'package:almaworks/screens/inventory/fabrication_orders_screen.dart';
import 'package:almaworks/screens/inventory/inventory_providers.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/inventory_form_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

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
      title: 'Fabrication Orders',
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
                    color: inventoryNavy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.precision_manufacturing_outlined, color: inventoryNavy),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fabrication Orders', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
                      Text(
                        'Awaiting a scanned form, or flagged with a discrepancy',
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
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
                return Center(child: Text('Error loading orders', style: GoogleFonts.poppins()));
              },
              data: (orders) {
                if (orders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(color: inventoryNavy.withValues(alpha: 0.06), shape: BoxShape.circle),
                          child: Icon(Icons.inbox_outlined, size: 40, color: inventoryNavy.withValues(alpha: 0.35)),
                        ),
                        const SizedBox(height: 14),
                        Text('Nothing needs attention', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey[800])),
                        const SizedBox(height: 4),
                        Text('New fabrication orders will show up here.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500])),
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
    final statusLabel = isDiscrepancy
        ? 'Discrepancy'
        : order.isScanUploaded
            ? 'Ready for Verification'
            : order.isPendingAdminReview
                ? 'Awaiting Admin Review'
                : 'With Driver — Heading to Fabrication';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openFabricationOrders(context, ref, order),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
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
                    Text('${order.materialName} — ${order.quantityIssued} ${order.unit}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(
                      'Issued by ${order.issuedByName}${order.projectName != null ? ' • ${order.projectName}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 2),
                    Text(DateFormat('d MMM yyyy').format(order.issuedAt),
                        style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[500])),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                child: Text(statusLabel, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('That material no longer exists.', style: GoogleFonts.poppins())),
        );
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
