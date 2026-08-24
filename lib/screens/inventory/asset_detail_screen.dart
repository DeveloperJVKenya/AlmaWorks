import 'dart:io';
import 'dart:typed_data';

import 'package:almaworks/models/inventory/asset_assignment_model.dart';
import 'package:almaworks/models/inventory/asset_booking_model.dart';
import 'package:almaworks/models/inventory/asset_maintenance_window_model.dart';
import 'package:almaworks/models/inventory/asset_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/add_asset_screen.dart';
import 'package:almaworks/screens/inventory/add_maintenance_window_screen.dart';
import 'package:almaworks/screens/inventory/asset_availability_calendar.dart';
import 'package:almaworks/screens/inventory/create_booking_screen.dart';
import 'package:almaworks/screens/inventory/inventory_colors.dart';
import 'package:almaworks/screens/inventory/inventory_error_messages.dart';
import 'package:almaworks/screens/inventory/inventory_providers.dart';
import 'package:almaworks/screens/inventory/record_custody_event_screen.dart';
import 'package:almaworks/screens/inventory/request_checkout_screen.dart';
import 'package:almaworks/screens/inventory/review_checkout_request_screen.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/confirm_dialog.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
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

  /// MainAdmin and Admin share full inventory management + direct booking/
  /// approval powers; only Technician stays on the request→approval flow.
  bool get isManager => userRole == 'MainAdmin' || userRole == 'Admin';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetAsync = ref.watch(assetByIdProvider(assetId));

    return BaseLayout(
      title: 'Asset Details',
      project: project,
      logger: logger,
      selectedMenuItem: 'Inventory',
      onMenuItemSelected: (_) {},
      actions: isManager
          ? [
              assetAsync.maybeWhen(
                data: (asset) => asset == null
                    ? const SizedBox.shrink()
                    : IconButton(
                        icon: const Icon(Icons.build_outlined),
                        tooltip: 'Schedule Maintenance',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AddMaintenanceWindowScreen(
                              project: project,
                              logger: logger,
                              asset: asset,
                              createdByUid: currentUid,
                              createdByName: username,
                            ),
                          ),
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
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
              Consumer(
                builder: (context, ref, _) {
                  final bookingsAsync = ref.watch(assetBookingsProvider(assetId));
                  return bookingsAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Text('Error loading bookings', style: GoogleFonts.poppins(color: Colors.red)),
                    data: (bookings) => _buildActionButton(context, ref, asset, bookings),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text('Availability', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Consumer(
                builder: (context, ref, _) {
                  final bookingsAsync = ref.watch(assetBookingsProvider(assetId));
                  final maintenanceAsync = ref.watch(assetMaintenanceWindowsProvider(assetId));
                  final bookings = bookingsAsync.valueOrNull ?? const <AssetBookingModel>[];
                  final maintenance = maintenanceAsync.valueOrNull ?? const <AssetMaintenanceWindowModel>[];
                  return AssetAvailabilityCalendar(
                    bookings: bookings,
                    maintenanceWindows: maintenance,
                    onCancelBooking: isManager ? (booking) => _cancelBooking(context, ref, booking) : null,
                    onCancelMaintenance:
                        isManager ? (window) => _cancelMaintenance(context, ref, window) : null,
                  );
                },
              ),
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
    final statusColor = InventoryColors.forAsset(asset);
    final statusLabel = asset.hasPendingRequest
        ? 'Request Pending'
        : (asset.status == AssetModel.statusAvailable && asset.hasUpcomingBooking)
            ? 'Booked'
            : asset.status;
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

  Widget _buildActionButton(
    BuildContext context,
    WidgetRef ref,
    AssetModel asset,
    List<AssetBookingModel> bookings,
  ) {
    final canAct = userRole == 'MainAdmin' || userRole == 'Admin' || userRole == 'Technician';
    if (!canAct) return const SizedBox.shrink();

    // A pending request locks the asset — nobody else can request/check it
    // out until a manager resolves it.
    if (asset.hasPendingRequest) {
      if (!isManager) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: InventoryColors.pendingRequest.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: InventoryColors.pendingRequest.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.hourglass_top, color: InventoryColors.pendingRequest, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('A checkout request for this item is awaiting review.',
                    style: GoogleFonts.poppins(fontSize: 12, color: InventoryColors.pendingRequest)),
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
              // A manager (MainAdmin or Admin) can approve any OTHER
              // manager's or Technician's request — MainAdmin approving an
              // Admin's self-request, or a different Admin approving it, both
              // work fine (the self-assignment guard only blocks acting on
              // your OWN request). But if this viewer IS the requester
              // (reachable via the "Request for Myself" fallback above),
              // reviewing/approving it themselves would just be rejected
              // server-side — show a waiting state instead of a dead-end button.
              if (req.requestedByUid == currentUid) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: InventoryColors.pendingRequest.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: InventoryColors.pendingRequest.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_top, color: InventoryColors.pendingRequest, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your request is awaiting review by another Admin/MainAdmin.',
                          style: GoogleFonts.poppins(fontSize: 12, color: InventoryColors.pendingRequest),
                        ),
                      ),
                    ],
                  ),
                );
              }
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
                  backgroundColor: InventoryColors.pendingRequest,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                ),
              );
            },
          );
        },
      );
    }

    // A scheduled booking whose date has arrived — a manager can hand the
    // item over now.
    AssetBookingModel? dueBooking;
    for (final b in bookings) {
      if (b.isScheduled && !b.scheduledStart.isAfter(DateTime.now())) {
        dueBooking = b;
        break;
      }
    }
    if (asset.isAvailable && dueBooking != null && isManager) {
      return ElevatedButton.icon(
        onPressed: () => _navigateToCustodyEvent(
          context,
          mode: CustodyEventMode.collection,
          asset: asset,
          booking: dueBooking!,
        ),
        icon: const Icon(Icons.logout),
        label: Text('Record Collection — ${dueBooking.bookedForName}',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: InventoryColors.checkedOut,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(46),
        ),
      );
    }

    if (asset.isAvailable) {
      if (isManager) {
        final bookButton = ElevatedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateBookingScreen(
                project: project,
                logger: logger,
                asset: asset,
                createdByUid: currentUid,
                createdByName: username,
                createdByRole: userRole,
              ),
            ),
          ),
          icon: const Icon(Icons.event_available),
          label: Text('Book / Check Out', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: InventoryColors.checkedOut,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
          ),
        );
        // An Admin (not MainAdmin) can never book/check an asset out to
        // themself directly — the booking screen's "Book For" picker
        // excludes their own uid. Without this, an Admin who wants the item
        // for themself has no path at all: "Book/Check Out" only lets them
        // pick someone else, and "Request Checkout" is otherwise hidden from
        // every manager. So Admin also gets the same request→approval
        // fallback Technician uses, requiring a *different* Admin/MainAdmin
        // to approve (self-approval is blocked server-side too).
        if (userRole == 'Admin') {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              bookButton,
              const SizedBox(height: 8),
              OutlinedButton.icon(
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
                icon: const Icon(Icons.person_outline),
                label: Text('Request for Myself', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              ),
            ],
          );
        }
        return bookButton;
      }
      // Technician: request only — a manager must approve before it's booked.
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
          backgroundColor: InventoryColors.checkedOut,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(46),
        ),
      );
    }
    AssetBookingModel? activeBookingForCurrentUser;
    if (asset.isCheckedOut && asset.currentHolderId == currentUid) {
      for (final b in bookings) {
        if (b.isActive) {
          activeBookingForCurrentUser = b;
          break;
        }
      }
    }
    // Driver-delivered item still in transit — only the recipient can
    // acknowledge arrival; no condition/photo access, just a receipt
    // confirmation (see InventoryService.acknowledgeDelivery).
    if (activeBookingForCurrentUser != null && activeBookingForCurrentUser.awaitingDeliveryAck) {
      final booking = activeBookingForCurrentUser;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: InventoryColors.booked.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: InventoryColors.booked.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.local_shipping_outlined, color: InventoryColors.booked, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${booking.driverName ?? 'A driver'} is bringing this to you.',
                    style: GoogleFonts.poppins(fontSize: 12, color: InventoryColors.booked),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () => _acknowledgeDelivery(context, booking),
            icon: const Icon(Icons.check_circle_outline),
            label: Text('Acknowledge Receipt', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: InventoryColors.checkedOut,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
            ),
          ),
        ],
      );
    }
    // Being checked out to someone else right now doesn't mean the item's
    // calendar is fully occupied — a future, non-overlapping window can
    // still be booked/requested for later (InventoryService only checks
    // date-range conflicts for a future start, not the asset's current
    // status). This secondary action is offered alongside whatever primary
    // action the viewer's role/relationship to the current holder gives them.
    final bookFutureButton = OutlinedButton.icon(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CreateBookingScreen(
            project: project,
            logger: logger,
            asset: asset,
            createdByUid: currentUid,
            createdByName: username,
            createdByRole: userRole,
          ),
        ),
      ),
      icon: const Icon(Icons.event_available_outlined),
      label: Text('Book a Future Date', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
    );
    final requestFutureForMyselfButton = OutlinedButton.icon(
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
      icon: const Icon(Icons.person_outline),
      label: Text('Request for Myself', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
    );

    if (asset.isCheckedOut && isManager) {
      AssetBookingModel? activeBooking;
      for (final b in bookings) {
        if (b.isActive) {
          activeBooking = b;
          break;
        }
      }
      if (activeBooking == null) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: () => _navigateToCustodyEvent(
              context,
              mode: CustodyEventMode.returnEvent,
              asset: asset,
              booking: activeBooking!,
            ),
            icon: const Icon(Icons.login),
            label: Text('Record Return', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: InventoryColors.available,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
            ),
          ),
          const SizedBox(height: 8),
          bookFutureButton,
          if (userRole == 'Admin') ...[
            const SizedBox(height: 8),
            requestFutureForMyselfButton,
          ],
        ],
      );
    }
    // Non-manager holder: a plain "Return" signal only — notifies
    // MainAdmin/Admin to come perform the actual reception (condition
    // assessment stays their call, never the holder's own self-assessment).
    if (asset.isCheckedOut && !isManager && asset.currentHolderId == currentUid) {
      return ElevatedButton.icon(
        onPressed: () => _sendReturnIntent(context, asset),
        icon: const Icon(Icons.login),
        label: Text('Return', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: InventoryColors.available,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(46),
        ),
      );
    }
    // Technician (or an Admin not currently holding it) viewing an item
    // that's out with someone else — previously a dead end with no action
    // at all. They can still request it for a later, non-conflicting date.
    if (asset.isCheckedOut && !isManager && asset.currentHolderId != currentUid) {
      return requestFutureForMyselfButton;
    }
    return const SizedBox.shrink();
  }

  Future<void> _acknowledgeDelivery(BuildContext context, AssetBookingModel booking) async {
    // Optional: a photo of the signed physical handover form (the driver
    // has no app account, so their pickup ack — and this recipient's own
    // receipt ack — lives on paper; see asset_handover_form_pdf.dart). Not
    // required to confirm receipt, just supporting evidence alongside the
    // real, in-app acknowledgment below.
    //
    // (confirmed, scan) as a record so "Cancel" and "Confirm with no photo"
    // — both of which leave scan null — stay distinguishable via `confirmed`.
    (bool, XFile?) result = (false, null);
    if (context.mounted) {
      result = await showDialog<(bool, XFile?)>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text('Acknowledge Receipt', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
              content: Text(
                'Confirm that "${booking.assetName}" has physically arrived with you. '
                'If you have the signed handover form, you can attach a photo of it too.',
                style: GoogleFonts.poppins(fontSize: 13),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, (false, null)), child: const Text('Cancel')),
                OutlinedButton.icon(
                  onPressed: () async {
                    final file = await ImagePicker().pickImage(source: ImageSource.camera);
                    if (dialogContext.mounted) Navigator.pop(dialogContext, (true, file));
                  },
                  icon: const Icon(Icons.camera_alt_outlined, size: 16),
                  label: const Text('Attach Form Photo'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, (true, null)),
                  child: const Text('Confirm Receipt'),
                ),
              ],
            ),
          ) ??
          (false, null);
    }
    final (confirmed, scan) = result;
    if (!confirmed) return;
    try {
      Uint8List? scanBytes;
      if (scan != null) {
        scanBytes = kIsWeb ? await scan.readAsBytes() : await File(scan.path).readAsBytes();
      }
      await InventoryService().acknowledgeDelivery(
        bookingId: booking.id,
        acknowledgedByUid: currentUid,
        scanBytes: scanBytes,
        scanFileName: scan?.name,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Receipt acknowledged', style: GoogleFonts.poppins()), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      logger.e('❌ AssetDetailScreen: Failed to acknowledge delivery', error: e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyInventoryError(e), style: GoogleFonts.poppins()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _sendReturnIntent(BuildContext context, AssetModel asset) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Return Asset',
      message: 'Notify an Admin/MainAdmin that you\'re returning "${asset.name}"? '
          'They will confirm receipt and record its condition.',
      confirmLabel: 'Notify',
    );
    if (!confirmed) return;
    try {
      await InventoryService().notifyReturnIntent(
        assetId: asset.id,
        assetName: asset.name,
        holderName: username,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Admin/MainAdmin notified — they\'ll confirm receipt', style: GoogleFonts.poppins()),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      logger.e('❌ AssetDetailScreen: Failed to send return intent', error: e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyInventoryError(e), style: GoogleFonts.poppins()), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _navigateToCustodyEvent(
    BuildContext context, {
    required CustodyEventMode mode,
    required AssetModel asset,
    required AssetBookingModel booking,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecordCustodyEventScreen(
          project: project,
          logger: logger,
          asset: asset,
          booking: booking,
          mode: mode,
          recordedByUid: currentUid,
          recordedByName: username,
          recordedByRole: userRole,
        ),
      ),
    );
  }

  Future<void> _cancelBooking(BuildContext context, WidgetRef ref, AssetBookingModel booking) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Cancel Booking',
      message: 'Cancel the booking for ${booking.bookedForName}?',
      confirmLabel: 'Cancel Booking',
    );
    if (!confirmed) return;
    try {
      await InventoryService().cancelBooking(
        bookingId: booking.id,
        assetId: booking.assetId,
        cancelledByUid: currentUid,
        cancelledByName: username,
      );
    } catch (e) {
      logger.e('❌ AssetDetailScreen: Failed to cancel booking', error: e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyInventoryError(e), style: GoogleFonts.poppins()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _cancelMaintenance(BuildContext context, WidgetRef ref, AssetMaintenanceWindowModel window) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Cancel Maintenance',
      message: 'Cancel this maintenance window (${window.reason})?',
      confirmLabel: 'Cancel Window',
    );
    if (!confirmed) return;
    try {
      await InventoryService().cancelMaintenanceWindow(window.id);
    } catch (e) {
      logger.e('❌ AssetDetailScreen: Failed to cancel maintenance window', error: e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyInventoryError(e), style: GoogleFonts.poppins()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildHistoryEntry(BuildContext context, AssetAssignmentModel entry) {
    final isCheckout = entry.isCheckout;
    final color = entry.conditionRating == AssetModel.conditionDamaged
        ? InventoryColors.damaged
        : (isCheckout ? InventoryColors.checkedOut : InventoryColors.available);
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
            if (entry.conditionRating != null) ...[
              const SizedBox(height: 4),
              Text('Condition: ${entry.conditionRating}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: InventoryColors.forCondition(entry.conditionRating),
                  )),
            ],
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

}
