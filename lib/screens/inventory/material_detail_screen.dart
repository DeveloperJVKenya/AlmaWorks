import 'package:almaworks/models/inventory/material_model.dart';
import 'package:almaworks/models/inventory/material_movement_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/add_material_screen.dart';
import 'package:almaworks/screens/inventory/fabrication_orders_screen.dart';
import 'package:almaworks/screens/inventory/inventory_labels.dart';
import 'package:almaworks/screens/inventory/inventory_permissions.dart';
import 'package:almaworks/screens/inventory/inventory_providers.dart';
import 'package:almaworks/screens/inventory/record_material_movement_screen.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/theme/app_colors.dart';
import 'package:almaworks/core/errors/friendly_error.dart';

/// Full traceability view for a single material: current stock level plus
/// the complete, immutable movement history (receipts/issues with
/// condition/verification notes and photos).
class MaterialDetailScreen extends ConsumerWidget {
  final ProjectModel project;
  final Logger logger;
  final String materialId;
  final String userRole;
  final String username;
  final String currentUid;

  const MaterialDetailScreen({
    super.key,
    required this.project,
    required this.logger,
    required this.materialId,
    required this.userRole,
    required this.username,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materialAsync = ref.watch(materialByIdProvider(materialId));

    return BaseLayout(
      title: context.l10n.materialDetails,
      project: project,
      logger: logger,
      selectedMenuItem: 'Inventory',
      onMenuItemSelected: (_) {},
      actions: InventoryPermissions.canManageCatalog(userRole)
          ? [
              materialAsync.maybeWhen(
                data: (material) => material == null
                    ? const SizedBox.shrink()
                    : IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: context.l10n.edit,
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AddMaterialScreen(
                              project: project,
                              logger: logger,
                              createdByUid: currentUid,
                              createdByName: username,
                              existingMaterial: material,
                            ),
                          ),
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
            ]
          : null,
      child: materialAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) {
          logger.e('❌ MaterialDetailScreen: stream error $err');
          return Center(child: Text(friendlyError(err, action: context.l10n.couldNotLoadMaterial), textAlign: TextAlign.center));
        },
        data: (material) {
          if (material == null) {
            return Center(child: Text(context.l10n.materialNotFound));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeaderCard(material),
              const SizedBox(height: 16),
              _buildActionButtons(context, material),
              const SizedBox(height: 20),
              Text(context.l10n.movementHistory, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 8),
              Consumer(
                builder: (context, ref, _) {
                  final historyAsync = ref.watch(materialHistoryProvider(materialId));
                  return historyAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (err, _) {
                      logger.e('❌ MaterialDetailScreen: history stream error $err');
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(friendlyError(err, action: context.l10n.couldNotLoadHistoryShort), style: TextStyle(color: AppColors.inkMuted)),
                      );
                    },
                    data: (history) {
                      if (history.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(context.l10n.noMovementsYet, style: TextStyle(color: AppColors.inkMuted)),
                        );
                      }
                      return Column(
                        children: history.map((m) => _buildHistoryEntry(context, m, material.unit)).toList(),
                      );
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

  Widget _buildHeaderCard(MaterialModel material) {
    final stockColor = material.isOutOfStock
        ? Colors.red
        : material.isLowStock
            ? const Color(0xFFE65100)
            : const Color(0xFF2E7D32);
    final l = l10nNow;
    final stockLabel = material.isOutOfStock ? l.outOfStock : (material.isLowStock ? l.lowStock : l.inStock);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(material.name,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: stockColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: stockColor.withValues(alpha: 0.35)),
                  ),
                  child: Text(stockLabel,
                      style: TextStyle(fontSize: 12, color: stockColor, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${invLabel(material.category)} • ${invLabel(material.source)}', style: TextStyle(color: AppColors.inkMuted)),
            const SizedBox(height: 10),
            Text(l.inStorageQuantity('${material.quantityInStorage}', invLabel(material.unit)),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: stockColor)),
            const SizedBox(height: 4),
            Text(l.conditionAtIntake(invLabel(material.initialCondition)),
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            if (material.description != null) ...[
              const SizedBox(height: 8),
              Text(material.description!, style: TextStyle(fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, MaterialModel material) {
    // Issuing/receiving stock is a canApproveAndIssue action — MainAdmin
    // and System Admin only; plain Admin can still add new materials but no
    // longer records movements.
    final canApproveAndIssue = InventoryPermissions.canApproveAndIssue(userRole);
    final canView = InventoryPermissions.isAuthorized(userRole);
    if (!canView) return const SizedBox.shrink();

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (canApproveAndIssue) ...[
          ElevatedButton.icon(
            onPressed: () => _navigateToMovement(context, MaterialMovementMode.receive, material),
            icon: const Icon(Icons.call_received),
            label: Text(context.l10n.recordReceipt, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            ),
          ),
          ElevatedButton.icon(
            onPressed: material.isOutOfStock
                ? null
                : () => _navigateToMovement(context, MaterialMovementMode.issue, material),
            icon: const Icon(Icons.call_made),
            label: Text(context.l10n.recordIssue, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            ),
          ),
        ],
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
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
          ),
          icon: const Icon(Icons.precision_manufacturing_outlined),
          label: Text(context.l10n.fabricationOrders, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13)),
        ),
      ],
    );
  }

  void _navigateToMovement(BuildContext context, MaterialMovementMode mode, MaterialModel material) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecordMaterialMovementScreen(
          project: project,
          logger: logger,
          material: material,
          mode: mode,
          recordedByUid: currentUid,
          recordedByName: username,
          recordedByRole: userRole,
        ),
      ),
    );
  }

  Widget _buildHistoryEntry(BuildContext context, MaterialMovementModel entry, String unit) {
    final isReceived = entry.isReceived;
    final l = context.l10n;
    final unitLabel = invLabel(unit);
    final color = isReceived ? const Color(0xFF2E7D32) : const Color(0xFF1565C0);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isReceived ? Icons.call_received : Icons.call_made, color: color, size: 18),
                const SizedBox(width: 6),
                Text(
                  isReceived
                      ? l.receivedQuantity('${entry.quantity}', unitLabel)
                      : l.issuedQuantity('${entry.quantity}', unitLabel),
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
                const Spacer(),
                Text(
                  DateFormat('d MMM yyyy, HH:mm').format(entry.eventAt),
                  style: TextStyle(fontSize: 11, color: AppColors.inkMuted),
                ),
              ],
            ),
            if (entry.isIssued && entry.projectName != null) ...[
              const SizedBox(height: 4),
              Text(l.toProject(entry.projectName!), style: const TextStyle(fontSize: 13)),
            ],
            if (entry.isReceived) ...[
              if (entry.conditionOnReceipt != null) ...[
                const SizedBox(height: 4),
                Text(l.conditionLabel(invLabel(entry.conditionOnReceipt)), style: const TextStyle(fontSize: 13)),
              ],
              if (entry.portVerifiedByName != null) ...[
                const SizedBox(height: 4),
                Text(l.verifiedAtPortByName(entry.portVerifiedByName!),
                    style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
              ],
              if (entry.receivedByName != null) ...[
                const SizedBox(height: 4),
                Text(l.receivedIntoStorageByName(entry.receivedByName!),
                    style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
              ],
            ],
            if (entry.notes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(entry.notes, style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
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
            Text(l.recordedBy(entry.recordedByName, roleLabel(entry.recordedByRole)),
                style: TextStyle(fontSize: 10, color: AppColors.inkFaint)),
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
}
