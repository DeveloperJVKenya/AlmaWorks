import 'package:almaworks/models/inventory/checkout_request_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/inventory_providers.dart';
import 'package:almaworks/screens/inventory/review_checkout_request_screen.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/inventory_form_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

/// MainAdmin-only overview of every checkout request currently awaiting
/// review, across all assets/tools — the discoverable entry point into the
/// per-item "Review Request" flow (also reachable from an individual
/// asset's detail screen).
class PendingRequestsScreen extends ConsumerWidget {
  final ProjectModel project;
  final Logger logger;
  final String currentUid;
  final String username;

  const PendingRequestsScreen({
    super.key,
    required this.project,
    required this.logger,
    required this.currentUid,
    required this.username,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(pendingRequestsProvider);

    return BaseLayout(
      title: 'Pending Requests',
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
                  child: const Icon(Icons.pending_actions, color: inventoryNavy),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pending Requests', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
                      Text(
                        'Awaiting your approval before checkout',
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
            child: requestsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) {
                logger.e('❌ PendingRequestsScreen: stream error $err');
                return Center(child: Text('Error loading requests', style: GoogleFonts.poppins()));
              },
              data: (requests) {
                if (requests.isEmpty) {
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
                        Text('No pending requests', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey[800])),
                        const SizedBox(height: 4),
                        Text('New checkout requests will show up here.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500])),
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
                        itemCount: requests.length,
                        itemBuilder: (context, index) => _buildRequestCard(context, requests[index]),
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
                      itemCount: requests.length,
                      itemBuilder: (context, index) => _buildRequestCard(context, requests[index]),
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

  Widget _buildRequestCard(BuildContext context, CheckoutRequestModel r) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ReviewCheckoutRequestScreen(
              project: project,
              logger: logger,
              request: r,
              respondedByUid: currentUid,
              respondedByName: username,
              respondedByRole: 'MainAdmin',
            ),
          ),
        ),
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
                decoration: BoxDecoration(
                  color: const Color(0xFFE65100).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.hourglass_top, color: Color(0xFFE65100)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.assetName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(
                      'Requested by ${r.requestedByName}${r.projectName != null ? ' • ${r.projectName}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 2),
                    Text(DateFormat('d MMM yyyy, HH:mm').format(r.requestedAt),
                        style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[500])),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: inventoryNavy,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Review', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right, size: 16, color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
