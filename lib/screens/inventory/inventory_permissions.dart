/// Single source of truth for Inventory role checks — replaces the ad hoc
/// `role == 'MainAdmin' || role == 'SystemAdmin'` literals that used to be
/// duplicated (with slightly different, drift-prone role sets) across
/// inventory_screen.dart, asset_detail_screen.dart, material_detail_screen.dart,
/// fabrication_orders_screen.dart and the various leaf action screens.
///
/// Client is never included in any of these — Client access to Inventory is
/// blocked at the nav entry (base_layout.dart) and again at the screen level
/// (inventory_screen.dart's isAuthorized check) before any of these are even
/// reached.
class InventoryPermissions {
  InventoryPermissions._();

  static const _mainAdmin = 'MainAdmin';
  static const _admin = 'Admin';
  static const _systemAdmin = 'SystemAdmin';
  static const _technician = 'Technician';

  /// Screen-level gate for the whole Inventory section.
  static bool isAuthorized(String role) =>
      role == _mainAdmin || role == _admin || role == _systemAdmin || role == _technician;

  /// MainAdmin/Admin/SystemAdmin can register new assets/tools/materials.
  static bool canAddCatalogItems(String role) => role == _mainAdmin || role == _admin || role == _systemAdmin;

  /// Approving requests, issuing/receiving stock, reviewing pending
  /// fabrication orders — MainAdmin/SystemAdmin only.
  static bool canApproveAndIssue(String role) => role == _mainAdmin || role == _systemAdmin;

  /// Editing an existing asset/tool/material, or scheduling a maintenance
  /// blackout window — MainAdmin and SystemAdmin.
  static bool canManageCatalog(String role) => role == _mainAdmin || role == _systemAdmin;

  /// Requesting a checkout/booking or returning/collecting one already held
  /// — every authorized Inventory role including Technician.
  static bool canRequestOrReturn(String role) => isAuthorized(role);

  /// Scanning + re-uploading the completed fabrication delivery form — the
  /// site recipient, which may be a Technician or an Admin/MainAdmin.
  static bool canUploadFabricationScan(String role) =>
      role == _technician || role == _admin || role == _mainAdmin;

  /// Reviewing a Technician-submitted fabrication scan before it reaches
  /// SystemAdmin verification — Admin/MainAdmin only.
  static bool canReviewFabricationScan(String role) => role == _admin || role == _mainAdmin;

  /// Final verify/flag-discrepancy decision on a fabrication order —
  /// SystemAdmin/MainAdmin only.
  static bool canVerifyFabricationOrder(String role) => role == _systemAdmin || role == _mainAdmin;

  static bool isTechnician(String role) => role == _technician;
  static bool isClient(String role) => role == 'Client';
}
