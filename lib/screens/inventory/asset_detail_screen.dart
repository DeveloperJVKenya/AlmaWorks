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
import 'package:almaworks/screens/inventory/inventory_labels.dart';
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
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/theme/app_colors.dart';
import 'package:almaworks/core/errors/friendly_error.dart';

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
      title: context.l10n.assetDetails,
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
                        tooltip: context.l10n.scheduleMaintenance,
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
                        tooltip: context.l10n.edit,
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
          return Center(child: Text(friendlyError(err, action: context.l10n.couldNotLoadAsset), textAlign: TextAlign.center));
        },
        data: (asset) {
          if (asset == null) {
            return Center(child: Text(context.l10n.assetNotFound));
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
                    error: (err, _) => Text(friendlyError(err, action: context.l10n.couldNotLoadBookings), style: TextStyle(color: AppColors.danger)),
                    data: (bookings) => _buildActionButton(context, ref, asset, bookings),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(context.l10n.availability, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
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
              Text(context.l10n.custodyHistory, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
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
                        child: Text(friendlyError(err, action: context.l10n.couldNotLoadHistoryShort), style: TextStyle(color: AppColors.inkMuted)),
                      );
                    },
                    data: (history) {
                      if (history.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(context.l10n.noCustodyEvents, style: TextStyle(color: AppColors.inkMuted)),
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
    final l = l10nNow;
    final statusLabel = asset.hasPendingRequest
        ? l.requestPendingStatus
        : (asset.status == AssetModel.statusAvailable && asset.hasUpcomingBooking)
            ? l.booked
            : invLabel(asset.status);
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
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(invLabel(asset.category), style: TextStyle(color: AppColors.inkMuted)),
            if (asset.serialNumber != null) ...[
              const SizedBox(height: 4),
              Text(l.serialNumber(asset.serialNumber!), style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            ],
            const SizedBox(height: 4),
            Text(l.conditionAtIntake(invLabel(asset.initialCondition)),
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            if (asset.description != null) ...[
              const SizedBox(height: 8),
              Text(asset.description!, style: TextStyle(fontSize: 13)),
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
                          ? l.inMyPossession
                          : l.heldByName(asset.currentHolderName ?? l.unknown),
                      style: TextStyle(fontSize: 13),
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
                        style: TextStyle(fontSize: 13),
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
          message: context.l10n.requestAwaitingReview,
        );
      }
      return Consumer(
        builder: (context, ref, _) {
          final requestAsync = ref.watch(requestByIdProvider(asset.pendingRequestId!));
          return requestAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Text(friendlyError(err, action: context.l10n.couldNotLoadRequest), style: TextStyle(color: AppColors.danger)),
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
                  message: context.l10n.ownRequestAwaitingReview,
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
                label: context.l10n.reviewRequestFrom(req.requestedByName),
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
        label: context.l10n.recordCollectionFor(dueBooking.bookedForName),
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
        label: context.l10n.requestCheckout,
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
            message: context.l10n.driverBringingToYou(booking.driverName ?? context.l10n.aDriver),
          ),
          const SizedBox(height: 10),
          _actionButton(
            onPressed: () => _acknowledgeDelivery(context, booking),
            icon: Icons.check_circle_outline,
            label: context.l10n.acknowledgeReceipt,
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
          label: context.l10n.requestFutureDate,
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
          message: context.l10n.returnNotified,
        );
      }
      return _actionButton(
        onPressed: () => _sendReturnIntent(context, asset),
        icon: Icons.login,
        label: asset.itemType == AssetModel.typeTool ? context.l10n.toolReturn : context.l10n.assetReturn,
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
              label: context.l10n.recordReturn,
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
                  label: context.l10n.recordReturn,
                  color: InventoryColors.available,
                ),
              ),
            ),
            _actionButton(
              outlined: true,
              onPressed: () => _confirmOverrideReturn(context, asset, activeBooking),
              icon: Icons.admin_panel_settings_outlined,
              label: context.l10n.overrideRecordReturn,
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
    final child = Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5));
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
            child: Text(message, style: TextStyle(fontSize: 12, color: color)),
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
              title: Text(context.l10n.acknowledgeReceipt, style: const TextStyle(fontWeight: FontWeight.w700)),
              content: Text(
                context.l10n.acknowledgeReceiptBody(booking.assetName),
                style: const TextStyle(fontSize: 13),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, (false, null)), child: Text(context.l10n.cancel)),
                OutlinedButton.icon(
                  onPressed: () async {
                    final file = await ImagePicker().pickImage(source: ImageSource.camera);
                    if (dialogContext.mounted) Navigator.pop(dialogContext, (true, file));
                  },
                  icon: const Icon(Icons.camera_alt_outlined, size: 16),
                  label: Text(context.l10n.attachFormPhoto),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, (true, null)),
                  child: Text(context.l10n.confirmReceipt),
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
        showSuccessSnack(context, context.l10n.receiptAcknowledged);
      }
    } catch (e) {
      logger.e('❌ AssetDetailScreen: Failed to acknowledge delivery', error: e);
      if (context.mounted) showErrorSnack(context, e, action: context.l10n.couldNotConfirmReceipt);
    }
  }

  Future<void> _sendReturnIntent(BuildContext context, AssetModel asset) async {
    final confirmed = await showConfirmDialog(
      context,
      title: context.l10n.returnAssetTitle,
      message: context.l10n.returnAssetMessage(asset.name),
      confirmLabel: context.l10n.notify,
    );
    if (!confirmed) return;
    try {
      await InventoryService().notifyReturnIntent(
        assetId: asset.id,
        assetName: asset.name,
        holderName: username,
      );
      if (context.mounted) {
        showSuccessSnack(context, context.l10n.returnNotifiedSnack);
      }
    } catch (e) {
      logger.e('❌ AssetDetailScreen: Failed to send return intent', error: e);
      if (context.mounted) showErrorSnack(context, e, action: context.l10n.couldNotNotifyReturn);
    }
  }

  /// Record Return normally stays disabled until the holder themself
  /// triggers a return (see _sendReturnIntent) — this is the explicit,
  /// deliberate override for when they're offline or otherwise unreachable,
  /// so a MainAdmin/System Admin isn't permanently blocked.
  Future<void> _confirmOverrideReturn(BuildContext context, AssetModel asset, AssetBookingModel? booking) async {
    final confirmed = await showConfirmDialog(
      context,
      title: context.l10n.overrideReturnTitle,
      message: context.l10n.overrideReturnMessage(asset.currentHolderName ?? context.l10n.theCurrentHolder, asset.name),
      confirmLabel: context.l10n.overrideContinue,
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
      title: context.l10n.cancelBooking,
      message: context.l10n.cancelBookingMessage(booking.bookedForName),
      confirmLabel: context.l10n.cancelBooking,
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
      if (context.mounted) showErrorSnack(context, e, action: context.l10n.couldNotCancelBooking);
    }
  }

  Future<void> _cancelMaintenance(BuildContext context, WidgetRef ref, AssetMaintenanceWindowModel window) async {
    final confirmed = await showConfirmDialog(
      context,
      title: context.l10n.cancelMaintenance,
      message: context.l10n.cancelMaintenanceMessage(window.reason),
      confirmLabel: context.l10n.cancelWindow,
    );
    if (!confirmed) return;
    try {
      await InventoryService().cancelMaintenanceWindow(window.id);
    } catch (e) {
      logger.e('❌ AssetDetailScreen: Failed to cancel maintenance window', error: e);
      if (context.mounted) showErrorSnack(context, e, action: context.l10n.couldNotCancelMaintenance);
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
                  isCheckout ? context.l10n.checkedOutEvent : context.l10n.returnedEvent,
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
                const Spacer(),
                Text(
                  DateFormat('d MMM yyyy, HH:mm').format(entry.eventAt),
                  style: TextStyle(fontSize: 11, color: AppColors.inkMuted),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${entry.assignedToName}${entry.projectName != null ? ' • ${entry.projectName}' : ''}',
                style: TextStyle(fontSize: 13)),
            if (entry.conditionRating != null) ...[
              const SizedBox(height: 4),
              Text(context.l10n.conditionLabel(invLabel(entry.conditionRating)),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: InventoryColors.forCondition(entry.conditionRating),
                  )),
            ],
            if (entry.conditionNotes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(entry.conditionNotes, style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
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
            Text(context.l10n.recordedBy(entry.recordedByName, roleLabel(entry.recordedByRole)),
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
