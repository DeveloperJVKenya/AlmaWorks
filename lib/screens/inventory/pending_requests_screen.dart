import 'package:almaworks/models/inventory/checkout_request_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/inventory_providers.dart';
import 'package:almaworks/screens/inventory/review_checkout_request_screen.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/theme/app_colors.dart';
import 'package:almaworks/core/errors/friendly_error.dart';

/// MainAdmin/Admin overview of every checkout request currently awaiting
/// review, across all assets/tools — the discoverable entry point into the
/// per-item "Review Request" flow (also reachable from an individual
/// asset's detail screen).
class PendingRequestsScreen extends ConsumerWidget {
  final ProjectModel project;
  final Logger logger;
  final String currentUid;
  final String username;
  final String userRole;

  const PendingRequestsScreen({
    super.key,
    required this.project,
    required this.logger,
    required this.currentUid,
    required this.username,
    required this.userRole,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(pendingRequestsProvider);

    return BaseLayout(
      title: context.l10n.pendingRequests,
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
                  child: Icon(Icons.pending_actions, color: AppColors.brandInk),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.l10n.pendingRequests, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
                      Text(
                        context.l10n.pendingRequestsSubtitle,
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
            child: requestsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) {
                logger.e('❌ PendingRequestsScreen: stream error $err');
                return Center(child: Text(friendlyError(err, action: context.l10n.couldNotLoadRequests), textAlign: TextAlign.center));
              },
              data: (requests) {
                if (requests.isEmpty) {
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
                        Text(context.l10n.noPendingRequests, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
                        const SizedBox(height: 4),
                        Text(context.l10n.newCheckoutRequestsHint, style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
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
              respondedByRole: userRole,
            ),
          ),
        ),
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
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink)),
                    const SizedBox(height: 4),
                    Text(
                      '${context.l10n.requestedByName(r.requestedByName)}${r.projectName != null ? ' • ${r.projectName}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(DateFormat('d MMM yyyy, HH:mm').format(r.requestedAt),
                        style: TextStyle(fontSize: 11, color: AppColors.inkFaint)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(context.l10n.review, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
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
