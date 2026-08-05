import 'package:almaworks/models/inventory/asset_assignment_model.dart';
import 'package:almaworks/models/inventory/asset_model.dart';
import 'package:almaworks/models/inventory/checkout_request_model.dart';
import 'package:almaworks/models/inventory/material_model.dart';
import 'package:almaworks/models/inventory/material_movement_model.dart';
import 'package:almaworks/rbacsystem/auth_service.dart';
import 'package:almaworks/services/inventory_service.dart';
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

/// Current signed-in user's role and username. Cached for the app's
/// lifetime (not autoDispose) since BaseLayout/login already keep the
/// underlying Users doc in sync — re-fetching on every Inventory visit adds
/// latency for no benefit within a single session.
final userRoleProvider = FutureProvider<String>((ref) {
  return ref.watch(authServiceProvider).getUserRole();
});

final usernameProvider = FutureProvider<String>((ref) {
  return ref.watch(authServiceProvider).getUsername();
});

final currentUidProvider = Provider<String>((ref) {
  return ref.watch(authServiceProvider).currentUser?.uid ?? '';
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

/// All requests currently awaiting MainAdmin review.
final pendingRequestsProvider = StreamProvider.autoDispose<List<CheckoutRequestModel>>((ref) {
  return ref.watch(inventoryServiceProvider).streamPendingRequests();
});
