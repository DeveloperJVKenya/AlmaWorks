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
import 'package:almaworks/screens/inventory/inventory_colors.dart';
import 'package:almaworks/screens/inventory/inventory_error_messages.dart';
import 'package:almaworks/screens/inventory/inventory_permissions.dart';
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

  /// Approve/reject checkout requests, record collections/returns, issue
  /// materials — MainAdmin + System Admin only. Nobody self-approves, so a
  /// MainAdmin/SystemAdmin who currently holds an item never sees these for
  /// their own custody (see the self-holder branch in [_buildActionButton]).
  bool get canApproveAndIssue => InventoryPermissions.canApproveAndIssue(userRole);

  /// Edit an existing asset/tool and schedule/cancel maintenance —
  /// MainAdmin only.
  bool get canManageCatalog => InventoryPermissions.canManageCatalog(userRole);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetAsync = ref.watch(assetByIdProvider(assetId));

    return BaseLayout(
      title: 'Asset Details',
      project: project,
      logger: logger,
      selectedMenuItem: 'Inventory',
      onMenuItemSelected: (_) {},
      actions: canManageCatalog
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
                              userRole: userRole,
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
                    onCancelBooking: canApproveAndIssue ? (booking) => _cancelBooking(context, ref, booking) : null,
                    onCancelMaintenance:
                        canManageCatalog ? (window) => _cancelMaintenance(context, ref, window) : null,
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
                  Expanded(
                    child: Text(
                      asset.currentHolderId == currentUid
                          ? 'In my possession'
                          : 'Held by ${asset.currentHolderName ?? 'Unknown'}',
                      style: GoogleFonts.poppins(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (asset.currentProjectName != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 18, color: Colors.blueGrey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        asset.currentProjectName!,
                        style: GoogleFonts.poppins(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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
    final canAct = InventoryPermissions.canRequestOrReturn(userRole);
    if (!canAct) return const SizedBox.shrink();

    // A pending request locks the asset — nobody else can request/check it
    // out until a MainAdmin/SystemAdmin resolves it.
    if (asset.hasPendingRequest) {
      if (!canApproveAndIssue) {
        return _infoBanner(
          icon: Icons.hourglass_top,
          color: InventoryColors.pendingRequest,
          message: 'A checkout request for this item is awaiting review.',
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
              // Nobody approves their own request — not even MainAdmin. If
              // this viewer IS the requester, reviewing/approving it
              // themselves would just be rejected server-side — show a
              // waiting state instead of a dead-end button.
              if (req.requestedByUid == currentUid) {
                return _infoBanner(
                  icon: Icons.hourglass_top,
                  color: InventoryColors.pendingRequest,
                  message: 'Your request is awaiting review by a different MainAdmin/System Admin.',
                );
              }
              return _actionButton(
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
                icon: Icons.fact_check_outlined,
                label: 'Review Request from ${req.requestedByName}',
                color: InventoryColors.pendingRequest,
              );
            },
          );
        },
      );
    }

    // A scheduled booking whose date has arrived — MainAdmin/SystemAdmin can
    // hand the item over now.
    AssetBookingModel? dueBooking;
    for (final b in bookings) {
      if (b.isScheduled && !b.scheduledStart.isAfter(DateTime.now())) {
        dueBooking = b;
        break;
      }
    }
    if (asset.isAvailable && dueBooking != null && canApproveAndIssue) {
      return _actionButton(
        onPressed: () => _navigateToCustodyEvent(
          context,
          mode: CustodyEventMode.collection,
          asset: asset,
          booking: dueBooking!,
        ),
        icon: Icons.logout,
        label: 'Record Collection — ${dueBooking.bookedForName}',
        color: InventoryColors.checkedOut,
      );
    }

    // Available: everyone — including MainAdmin/SystemAdmin — requests it
    // for themself; there's no direct "book for someone" path anymore. A
    // different MainAdmin/SystemAdmin always processes the request.
    if (asset.isAvailable) {
      return _actionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RequestCheckoutScreen(
              project: project,
              logger: logger,
              asset: asset,
              requestedByUid: currentUid,
              requestedByName: username,
              requestedByRole: userRole,
            ),
          ),
        ),
        icon: Icons.send_outlined,
        label: 'Request Checkout',
        color: InventoryColors.checkedOut,
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
          _infoBanner(
            icon: Icons.local_shipping_outlined,
            color: InventoryColors.booked,
            message: '${booking.driverName ?? 'A driver'} is bringing this to you.',
          ),
          const SizedBox(height: 10),
          _actionButton(
            onPressed: () => _acknowledgeDelivery(context, booking),
            icon: Icons.check_circle_outline,
            label: 'Acknowledge Receipt',
            color: InventoryColors.checkedOut,
          ),
        ],
      );
    }

    // Being checked out to someone else right now doesn't mean the item's
    // calendar is fully occupied — a future, non-overlapping window can
    // still be requested for later (InventoryService only checks date-range
    // conflicts for a future start, not the asset's current status).
    Widget requestFutureButton() => _actionButton(
          outlined: true,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RequestCheckoutScreen(
                project: project,
                logger: logger,
                asset: asset,
                requestedByUid: currentUid,
                requestedByName: username,
                requestedByRole: userRole,
              ),
            ),
          ),
          icon: Icons.event_available_outlined,
          label: 'Request a Future Date',
        );

    // Whoever currently holds the item — Technician, Admin, MainAdmin, or
    // SystemAdmin alike — never records their own return. They only signal
    // intent; a different MainAdmin/SystemAdmin performs the actual return
    // (condition assessment is always someone else's call, never a
    // self-assessment).
    if (asset.isCheckedOut && asset.currentHolderId == currentUid) {
      if (asset.returnRequestedAt != null) {
        return _infoBanner(
          icon: Icons.hourglass_top,
          color: InventoryColors.pendingRequest,
          message: 'Return notified — waiting for a MainAdmin/System Admin to confirm reception.',
        );
      }
      return _actionButton(
        onPressed: () => _sendReturnIntent(context, asset),
        icon: Icons.login,
        label: '${asset.itemType == AssetModel.typeTool ? 'Tool' : 'Asset'} Return',
        color: InventoryColors.available,
      );
    }

    if (asset.isCheckedOut && canApproveAndIssue) {
      AssetBookingModel? activeBooking;
      for (final b in bookings) {
        if (b.isActive) {
          activeBooking = b;
          break;
        }
      }
      final returnRequested = asset.returnRequestedAt != null;
      // Checked out with no matching active booking means this custody
      // event predates (or otherwise bypassed) the booking system — e.g. a
      // direct legacy checkout. There's still a real holder to get the item
      // back from, so fall through to the booking-less return path instead
      // of leaving no action at all.
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (returnRequested)
            _actionButton(
              onPressed: () => _navigateToCustodyEvent(
                context,
                mode: CustodyEventMode.returnEvent,
                asset: asset,
                booking: activeBooking,
              ),
              icon: Icons.login,
              label: 'Record Return',
              color: InventoryColors.available,
            )
          else ...[
            // Faint/disabled-looking until the holder has actually
            // triggered a return from their own side — kept reachable only
            // via the explicit override below, for when the holder is
            // offline or otherwise unreachable.
            Opacity(
              opacity: 0.4,
              child: IgnorePointer(
                child: _actionButton(
                  onPressed: () {},
                  icon: Icons.login,
                  label: 'Record Return',
                  color: InventoryColors.available,
                ),
              ),
            ),
            _actionButton(
              outlined: true,
              onPressed: () => _confirmOverrideReturn(context, asset, activeBooking),
              icon: Icons.admin_panel_settings_outlined,
              label: 'Override & Record Return',
            ),
          ],
          requestFutureButton(),
        ],
      );
    }
    // Technician/Admin (or a MainAdmin/SystemAdmin not currently holding it)
    // viewing an item that's out with someone else — request it for a
    // later, non-conflicting date.
    if (asset.isCheckedOut) {
      return requestFutureButton();
    }
    return const SizedBox.shrink();
  }

  /// Content-sized action button — sizes to its own label/padding instead of
  /// stretching to the available width.
  Widget _actionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    Color? color,
    bool outlined = false,
  }) {
    final child = Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13.5));
    final padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 13);
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: child,
        style: OutlinedButton.styleFrom(padding: padding),
      );
    }
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: child,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: padding,
      ),
    );
  }

  Widget _infoBanner({required IconData icon, required Color color, required String message}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: GoogleFonts.poppins(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
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
      message: 'Notify a MainAdmin/System Admin that you\'re returning "${asset.name}"? '
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
            content: Text('MainAdmin/System Admin notified — they\'ll confirm receipt', style: GoogleFonts.poppins()),
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

  /// Record Return normally stays disabled until the holder themself
  /// triggers a return (see _sendReturnIntent) — this is the explicit,
  /// deliberate override for when they're offline or otherwise unreachable,
  /// so a MainAdmin/System Admin isn't permanently blocked.
  Future<void> _confirmOverrideReturn(BuildContext context, AssetModel asset, AssetBookingModel? booking) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Override Return',
      message: '${asset.currentHolderName ?? 'The current holder'} hasn\'t signalled they\'re returning '
          '"${asset.name}" yet. Only proceed if they\'re unreachable (offline, account issues, etc.) and '
          'you\'ve confirmed the item is physically back.',
      confirmLabel: 'Override & Continue',
    );
    if (!confirmed || !context.mounted) return;
    _navigateToCustodyEvent(context, mode: CustodyEventMode.returnEvent, asset: asset, booking: booking);
  }

  void _navigateToCustodyEvent(
    BuildContext context, {
    required CustodyEventMode mode,
    required AssetModel asset,
    required AssetBookingModel? booking,
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
