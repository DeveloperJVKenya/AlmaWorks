import 'package:almaworks/models/inventory/asset_assignment_model.dart';
import 'package:almaworks/models/inventory/asset_booking_model.dart';
import 'package:almaworks/models/inventory/asset_maintenance_window_model.dart';
import 'package:almaworks/models/inventory/asset_model.dart';
import 'package:almaworks/models/inventory/checkout_request_model.dart';
import 'package:almaworks/models/inventory/material_fabrication_order_model.dart';
import 'package:almaworks/models/inventory/material_model.dart';
import 'package:almaworks/models/inventory/material_movement_model.dart';
import 'package:almaworks/rbacsystem/auth_service.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Riverpod providers for the Inventory module.
///
/// Why Riverpod here specifically: the previous StatefulWidget/StreamBuilder
/// version called `InventoryService.streamAllAssets()` directly inside each
/// tab's `build()`. Every keystroke in a search box or filter-dropdown
/// change triggered `setState`, which re-ran `build()`, which called
/// `streamAllAssets()` again — handing StreamBuilder a *brand-new* Stream
/// object each time. StreamBuilder treats that as "subscribe to a different
/// stream," so it tore down and re-created the underlying Firestore listener
/// (and briefly showed a loading spinner) on every single keystroke. Worse,
/// the Assets tab and Tools tab each ran their *own* separate
/// `streamAllAssets()` listener against the exact same collection.
///
/// The providers below are created once, watched (not re-created) by every
/// consumer, and shared across tabs — one live Firestore listener for all
/// assets, reused by both the Assets and Tools tabs; filtering/searching is
/// purely a client-side `.where()` over the already-cached list, with no
/// Firestore round-trip or listener churn.
final inventoryServiceProvider = Provider<InventoryService>((ref) => InventoryService());
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final currentUidProvider = Provider<String>((ref) {
  return ref.watch(authServiceProvider).currentUser?.uid ?? '';
});

/// Single source of the caller's Users doc — role AND username come from
/// the exact same query, kept live. userRoleProvider/usernameProvider and
/// roleMirrorSyncProvider below all derive from this instead of each
/// separately querying `Users` (which is what AuthService.getUserRole() /
/// getUsername() do individually) — that used to mean 2-3 sequential
/// Firestore round trips gating the Inventory screen before it could
/// render its tabs at all.
///
/// A live `.snapshots()` listener rather than a one-shot `.get()` — a role
/// changed directly in Firestore (or a slow mirror sync) now reaches every
/// Inventory widget gated on userRoleProvider without requiring the
/// Inventory screen to be torn down and rebuilt (see BaseLayout's identical
/// fix for the same staleness problem app-wide).
final _currentUserDocProvider = StreamProvider<({String role, String username})>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid.isEmpty) return Stream.value((role: 'Client', username: ''));
  return FirebaseFirestore.instance
      .collection('Users')
      .where('uid', isEqualTo: uid)
      .limit(1)
      .snapshots()
      .map((snapshot) {
    if (snapshot.docs.isEmpty) return (role: 'Client', username: '');
    final data = snapshot.docs.first.data();
    return (role: data['role'] as String? ?? 'Client', username: snapshot.docs.first.id);
  });
});

final userRoleProvider = Provider<AsyncValue<String>>((ref) {
  return ref.watch(_currentUserDocProvider).whenData((doc) => doc.role);
});

final usernameProvider = Provider<AsyncValue<String>>((ref) {
  return ref.watch(_currentUserDocProvider).whenData((doc) => doc.username);
});

/// Ensures UserRoles/{uid} exists before Inventory's own Firestore listeners
/// (below) attach — those collections' rules can only resolve the caller's
/// role via a get() on that mirror doc, so subscribing before it's written
/// gets a permission-denied that then sticks (StreamProviders here aren't
/// autoDispose, so a failed listener stays failed for the session). Scoped
/// to just the Inventory screen's content — not awaited from BaseLayout,
/// which would otherwise add this round trip to every screen navigation in
/// the app, not just Inventory's. Not autoDispose: only needs to succeed
/// once per session.
final roleMirrorSyncProvider = FutureProvider<bool>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid.isEmpty) return false;
  final doc = await ref.watch(_currentUserDocProvider.future);
  return ref.watch(authServiceProvider).ensureUserRoleMirror(uid: uid, username: doc.username, role: doc.role);
});

/// Single shared listener for ALL assets+tools — both list tabs watch this
/// same provider and filter client-side by `itemType`, rather than each
/// opening its own Firestore subscription against the same collection.
final allAssetsStreamProvider = StreamProvider<List<AssetModel>>((ref) {
  return ref.watch(inventoryServiceProvider).streamAllAssets();
});

final allMaterialsStreamProvider = StreamProvider<List<MaterialModel>>((ref) {
  return ref.watch(inventoryServiceProvider).streamAllMaterials();
});

/// Family (per-id) providers for detail screens — autoDispose so a listener
/// isn't kept open forever for every asset/material a user has ever opened
/// in the session; it's torn down once the detail screen is left.
final assetByIdProvider = StreamProvider.autoDispose.family<AssetModel?, String>((ref, assetId) {
  return ref.watch(inventoryServiceProvider).streamAsset(assetId);
});

final assetHistoryProvider =
    StreamProvider.autoDispose.family<List<AssetAssignmentModel>, String>((ref, assetId) {
  return ref.watch(inventoryServiceProvider).streamAssetHistory(assetId);
});

final materialByIdProvider = StreamProvider.autoDispose.family<MaterialModel?, String>((ref, materialId) {
  return ref.watch(inventoryServiceProvider).streamMaterial(materialId);
});

final materialHistoryProvider =
    StreamProvider.autoDispose.family<List<MaterialMovementModel>, String>((ref, materialId) {
  return ref.watch(inventoryServiceProvider).streamMaterialHistory(materialId);
});

/// Live status of a single checkout request — used on the asset detail
/// screen to resolve `pendingRequestId` into a reviewable request.
final requestByIdProvider = StreamProvider.autoDispose.family<CheckoutRequestModel?, String>((ref, requestId) {
  return ref.watch(inventoryServiceProvider).streamRequest(requestId);
});

/// All requests currently awaiting MainAdmin/Admin review.
final pendingRequestsProvider = StreamProvider.autoDispose<List<CheckoutRequestModel>>((ref) {
  return ref.watch(inventoryServiceProvider).streamPendingRequests();
});

/// Scheduled + active bookings for an asset — feeds the availability
/// calendar and the "collect today" / "record return" actions.
final assetBookingsProvider =
    StreamProvider.autoDispose.family<List<AssetBookingModel>, String>((ref, assetId) {
  return ref.watch(inventoryServiceProvider).streamAssetBookings(assetId);
});

/// Maintenance blackout windows for an asset.
final assetMaintenanceWindowsProvider =
    StreamProvider.autoDispose.family<List<AssetMaintenanceWindowModel>, String>((ref, assetId) {
  return ref.watch(inventoryServiceProvider).streamAssetMaintenanceWindows(assetId);
});

/// Fabrication orders for a material — the paper-form chain-of-custody
/// trail (Driver -> Fabricator -> Driver -> Technician).
final materialFabricationOrdersProvider =
    StreamProvider.autoDispose.family<List<MaterialFabricationOrderModel>, String>((ref, materialId) {
  return ref.watch(inventoryServiceProvider).streamFabricationOrders(materialId);
});

/// Every fabrication order across all materials still awaiting a scan or
/// flagged with a discrepancy — the admin worklist.
final pendingFabricationOrdersProvider =
    StreamProvider.autoDispose<List<MaterialFabricationOrderModel>>((ref) {
  return ref.watch(inventoryServiceProvider).streamPendingFabricationOrders();
});
