import 'package:almaworks/models/inventory/material_model.dart';
import 'package:almaworks/models/inventory/material_movement_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/add_material_screen.dart';
import 'package:almaworks/screens/inventory/inventory_providers.dart';
import 'package:almaworks/screens/inventory/record_material_movement_screen.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

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
      title: 'Material Details',
      project: project,
      logger: logger,
      selectedMenuItem: 'Inventory',
      onMenuItemSelected: (_) {},
      actions: userRole == 'MainAdmin'
          ? [
              materialAsync.maybeWhen(
                data: (material) => material == null
                    ? const SizedBox.shrink()
                    : IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit',
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
          return Center(child: Text('Error loading material', style: GoogleFonts.poppins()));
        },
        data: (material) {
          if (material == null) {
            return Center(child: Text('Material not found', style: GoogleFonts.poppins()));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeaderCard(material),
              const SizedBox(height: 16),
              _buildActionButtons(context, material),
              const SizedBox(height: 20),
              Text('Movement History', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
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
                        child: Text('Error loading history', style: GoogleFonts.poppins(color: Colors.grey[600])),
                      );
                    },
                    data: (history) {
                      if (history.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text('No movements yet', style: GoogleFonts.poppins(color: Colors.grey[600])),
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
    final stockLabel = material.isOutOfStock ? 'Out of Stock' : (material.isLowStock ? 'Low Stock' : 'In Stock');

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
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: stockColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: stockColor.withValues(alpha: 0.35)),
                  ),
                  child: Text(stockLabel,
                      style: GoogleFonts.poppins(fontSize: 12, color: stockColor, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${material.category} • ${material.source}', style: GoogleFonts.poppins(color: Colors.grey[700])),
            const SizedBox(height: 10),
            Text('${material.quantityInStorage} ${material.unit} in storage',
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: stockColor)),
            const SizedBox(height: 4),
            Text('Condition at intake: ${material.initialCondition}',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
            if (material.description != null) ...[
              const SizedBox(height: 8),
              Text(material.description!, style: GoogleFonts.poppins(fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, MaterialModel material) {
    final canAct = userRole == 'MainAdmin' || userRole == 'Admin';
    if (!canAct) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _navigateToMovement(context, MaterialMovementMode.receive, material),
            icon: const Icon(Icons.call_received),
            label: Text('Record Receipt', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: material.isOutOfStock
                ? null
                : () => _navigateToMovement(context, MaterialMovementMode.issue, material),
            icon: const Icon(Icons.call_made),
            label: Text('Record Issue', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
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
                  '${isReceived ? 'Received' : 'Issued'}: ${entry.quantity} $unit',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: color),
                ),
                const Spacer(),
                Text(
                  DateFormat('d MMM yyyy, HH:mm').format(entry.eventAt),
                  style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
            if (entry.isIssued && entry.projectName != null) ...[
              const SizedBox(height: 4),
              Text('To project: ${entry.projectName}', style: GoogleFonts.poppins(fontSize: 13)),
            ],
            if (entry.isReceived) ...[
              if (entry.conditionOnReceipt != null) ...[
                const SizedBox(height: 4),
                Text('Condition: ${entry.conditionOnReceipt}', style: GoogleFonts.poppins(fontSize: 13)),
              ],
              if (entry.portVerifiedByName != null) ...[
                const SizedBox(height: 4),
                Text('Verified at port by: ${entry.portVerifiedByName}',
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700])),
              ],
              if (entry.receivedByName != null) ...[
                const SizedBox(height: 4),
                Text('Received into storage by: ${entry.receivedByName}',
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700])),
              ],
            ],
            if (entry.notes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(entry.notes, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700])),
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
}
