import 'package:almaworks/core/l10n/l10n.dart';

/// Display name for a fixed Inventory value stored in Firestore — asset
/// statuses, conditions, item types, categories, sourcing, and the
/// lower-case booking/request/fabrication statuses. The stored values
/// themselves never change (queries and rules depend on them); only what's
/// shown follows the app language. Unknown values (e.g. a category typed in
/// by hand) are shown as stored.
String invLabel(String? value) {
  if (value == null) return '';
  final l = l10nNow;
  return switch (value) {
    // Asset status
    'Available' => l.invStatusAvailable,
    'Checked Out' => l.invStatusCheckedOut,
    'Under Maintenance' => l.invStatusUnderMaintenance,
    'Retired' => l.invStatusRetired,
    // Conditions
    'New' => l.invConditionNew,
    'Good' => l.invConditionGood,
    'Fair' => l.invConditionFair,
    'Damaged' => l.invConditionDamaged,
    'Partially Damaged' => l.invConditionPartiallyDamaged,
    // Item types
    'Asset' => l.invTypeAsset,
    'Tool' => l.invTypeTool,
    // Material sourcing
    'Local' => l.invSourceLocal,
    'International' => l.invSourceInternational,
    // Categories
    'Heavy Equipment' => l.invCatHeavyEquipment,
    'Vehicle' => l.invCatVehicle,
    'IT Equipment / Electronics' => l.invCatItEquipment,
    'Office Equipment' => l.invCatOfficeEquipment,
    'Furniture' => l.invCatFurniture,
    'Safety Equipment' => l.invCatSafetyEquipment,
    'Power Tool' => l.invCatPowerTool,
    'Hand Tool' => l.invCatHandTool,
    'Measuring Tool' => l.invCatMeasuringTool,
    'Safety Tool' => l.invCatSafetyTool,
    'Cement & Aggregates' => l.invCatCement,
    'Steel & Metal' => l.invCatSteel,
    'Electrical' => l.invCatElectrical,
    'Plumbing' => l.invCatPlumbing,
    'Timber' => l.invCatTimber,
    'Finishes' => l.invCatFinishes,
    'Other' => l.invCatOther,
    // Booking / request / fabrication statuses (stored lower-case)
    'scheduled' => l.invBookingScheduled,
    'active' => l.invBookingActive,
    'completed' => l.invBookingCompleted,
    'cancelled' => l.invBookingCancelled,
    'pending' => l.invRequestPending,
    'approved' => l.invRequestApproved,
    'rejected' => l.invRequestRejected,
    'issued' => l.invFabIssued,
    'pendingAdminReview' => l.invFabPendingAdminReview,
    'scanUploaded' => l.invFabScanUploaded,
    'verified' => l.invFabVerified,
    'discrepancy' => l.invFabDiscrepancy,
    'received' => l.invMovementReceived,
    'direct' => l.invDeliveryDirect,
    'driver' => l.invDeliveryDriver,
    // Material units
    'bags' => l.unitBags,
    'pieces' => l.unitPieces,
    'tonnes' => l.unitTonnes,
    'litres' => l.unitLitres,
    'rolls' => l.unitRolls,
    _ => value,
  };
}
