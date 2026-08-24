import 'package:almaworks/models/inventory/asset_model.dart';
import 'package:flutter/material.dart';

/// Shared, higher-contrast color palette for the Inventory module —
/// replaces the ad hoc `_statusColor()` duplicated per screen and the local
/// `_navy` constant that used to live in inventory_screen.dart. Shades are
/// deliberately deeper/more saturated than plain Material defaults for
/// legibility on light chip backgrounds, while staying distinguishable at a
/// glance across every status a card/badge can show.
class InventoryColors {
  InventoryColors._();

  /// Section header / app-bar accent — replaces the old local `_navy`.
  static const navy = Color(0xFF0A2748);

  static const available = Color(0xFF1B7A3D);
  static const checkedOut = Color(0xFF0D47A1);
  static const underMaintenance = Color(0xFFC65100);
  static const retired = Color(0xFF616161);

  /// A future-dated booking exists but the asset is still physically
  /// Available right now — distinct hue from Checked Out so it's never
  /// mistaken for "currently held".
  static const booked = Color(0xFF6A1B9A);

  /// A maintenance blackout window is scheduled (future), while the asset
  /// remains usable today.
  static const maintenanceScheduled = Color(0xFFAD1457);

  static const damaged = Color(0xFFB71C1C);
  static const pendingRequest = Color(0xFFC65100);

  /// Resolves the primary status color for an [AssetModel], factoring in
  /// the new "has an upcoming booking" / pending-request states that a bare
  /// `status` string doesn't capture.
  static Color forAsset(AssetModel asset) {
    if (asset.hasPendingRequest) return pendingRequest;
    if (asset.status == AssetModel.statusAvailable && asset.hasUpcomingBooking) return booked;
    return forStatus(asset.status);
  }

  static Color forStatus(String status) {
    switch (status) {
      case AssetModel.statusAvailable:
        return available;
      case AssetModel.statusCheckedOut:
        return checkedOut;
      case AssetModel.statusUnderMaintenance:
        return underMaintenance;
      case AssetModel.statusRetired:
        return retired;
      default:
        return retired;
    }
  }

  static Color forCondition(String? condition) {
    switch (condition) {
      case AssetModel.conditionNew:
        return const Color(0xFF1B7A3D);
      case AssetModel.conditionGood:
        return const Color(0xFF2E7D32);
      case AssetModel.conditionFair:
        return const Color(0xFFC65100);
      case AssetModel.conditionDamaged:
        return damaged;
      default:
        return Colors.grey;
    }
  }
}
