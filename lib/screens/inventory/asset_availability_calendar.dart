import 'package:almaworks/models/inventory/asset_booking_model.dart';
import 'package:almaworks/models/inventory/asset_maintenance_window_model.dart';
import 'package:almaworks/screens/inventory/inventory_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/theme/app_colors.dart';

/// Shows an asset's upcoming schedule — booked windows (who/when) and
/// maintenance blackout windows — so a second user can see when it will
/// actually be free before requesting/booking it themself, and so a manager
/// can avoid scheduling a booking over a maintenance period.
class AssetAvailabilityCalendar extends StatelessWidget {
  final List<AssetBookingModel> bookings;
  final List<AssetMaintenanceWindowModel> maintenanceWindows;
  final void Function(AssetMaintenanceWindowModel window)? onCancelMaintenance;
  final void Function(AssetBookingModel booking)? onCancelBooking;

  const AssetAvailabilityCalendar({
    super.key,
    required this.bookings,
    required this.maintenanceWindows,
    this.onCancelMaintenance,
    this.onCancelBooking,
  });

  @override
  Widget build(BuildContext context) {
    final entries = <_Entry>[
      ...bookings.map((b) => _Entry(
            start: b.scheduledStart,
            end: b.scheduledEnd,
            isMaintenance: false,
            booking: b,
          )),
      ...maintenanceWindows.map((m) => _Entry(
            start: m.startDate,
            end: m.endDate,
            isMaintenance: true,
            maintenance: m,
          )),
    ]..sort((a, b) => a.start.compareTo(b.start));

    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: InventoryColors.available.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: InventoryColors.available.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_available, color: InventoryColors.available, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(context.l10n.noUpcomingBookings,
                  style: TextStyle(fontSize: 12, color: InventoryColors.available)),
            ),
          ],
        ),
      );
    }

    final fmt = DateFormat('d MMM yyyy');
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.map((e) {
        final color = e.isMaintenance
            ? InventoryColors.maintenanceScheduled
            : (e.booking!.isActive ? InventoryColors.checkedOut : InventoryColors.booked);
        final title = e.isMaintenance
            ? l.maintenanceReason(e.maintenance!.reason)
            : (e.booking!.isActive ? l.checkedOutTo(e.booking!.bookedForName) : l.bookedFor(e.booking!.bookedForName));
        final canCancel = e.isMaintenance
            ? onCancelMaintenance != null
            : (onCancelBooking != null && !e.booking!.isActive);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                    const SizedBox(height: 2),
                    Text('${fmt.format(e.start)} — ${fmt.format(e.end)}',
                        style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
                  ],
                ),
              ),
              if (canCancel)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: e.isMaintenance ? l.cancelMaintenance : l.cancelBooking,
                  color: AppColors.inkMuted,
                  onPressed: () => e.isMaintenance
                      ? onCancelMaintenance!(e.maintenance!)
                      : onCancelBooking!(e.booking!),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _Entry {
  final DateTime start;
  final DateTime end;
  final bool isMaintenance;
  final AssetBookingModel? booking;
  final AssetMaintenanceWindowModel? maintenance;

  _Entry({required this.start, required this.end, required this.isMaintenance, this.booking, this.maintenance});
}
