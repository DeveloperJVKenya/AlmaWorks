import 'dart:typed_data';

import 'package:almaworks/models/inventory/asset_assignment_model.dart';
import 'package:almaworks/models/inventory/asset_booking_model.dart';
import 'package:almaworks/models/inventory/asset_maintenance_window_model.dart';
import 'package:almaworks/models/inventory/asset_model.dart';
import 'package:almaworks/models/inventory/checkout_request_model.dart';
import 'package:almaworks/models/inventory/material_fabrication_order_model.dart';
import 'package:almaworks/models/inventory/material_model.dart';
import 'package:almaworks/models/inventory/material_movement_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:logger/logger.dart';

/// Firestore + Storage access for the Inventory module: Assets, Tools
/// (both backed by [AssetModel]/[_assetsCollection], distinguished by
/// `itemType`), and Materials (backed by [MaterialModel]).
///
/// Mirrors the shape of lib/services/drawing_service.dart: own Firestore/
/// Storage instances, `Stream<List<T>>` getters for screens, `Future<T>`
/// mutators that log and rethrow on failure.
class InventoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Logger _logger = Logger();

  static const _assetsCollection = 'InventoryAssets';
  static const _assignmentsCollection = 'InventoryAssetAssignments';
  static const _materialsCollection = 'InventoryMaterials';
  static const _movementsCollection = 'InventoryMaterialMovements';
  static const _fabricationOrdersCollection = 'InventoryMaterialFabricationOrders';
  static const _requestsCollection = 'InventoryCheckoutRequests';
  static const _bookingsCollection = 'InventoryAssetBookings';
  static const _maintenanceCollection = 'InventoryAssetMaintenanceWindows';
  static const _adminQueueCollection = 'AdminNotificationQueue';
  static const _userQueueCollection = 'UserNotificationQueue';

  // ── Assets ────────────────────────────────────────────────────────────

  Stream<List<AssetModel>> streamAllAssets() {
    return _firestore
        .collection(_assetsCollection)
        .orderBy('name')
        .snapshots()
        .map((qs) => qs.docs.map(AssetModel.fromFirestore).toList())
        .handleError((e) {
      _logger.e('❌ InventoryService: Error streaming all assets', error: e);
      throw e;
    });
  }

  Stream<AssetModel?> streamAsset(String assetId) {
    return _firestore
        .collection(_assetsCollection)
        .doc(assetId)
        .snapshots()
        .map((doc) => doc.exists ? AssetModel.fromFirestore(doc) : null)
        .handleError((e) {
      _logger.e('❌ InventoryService: Error streaming asset $assetId', error: e);
      throw e;
    });
  }

  Stream<List<AssetModel>> streamAssetsByProject(String projectId) {
    return _firestore
        .collection(_assetsCollection)
        .where('currentProjectId', isEqualTo: projectId)
        .snapshots()
        .map((qs) => qs.docs.map(AssetModel.fromFirestore).toList())
        .handleError((e) {
      _logger.e('❌ InventoryService: Error streaming assets for project $projectId', error: e);
      throw e;
    });
  }

  Stream<List<AssetModel>> streamAssetsByHolder(String userId) {
    return _firestore
        .collection(_assetsCollection)
        .where('currentHolderId', isEqualTo: userId)
        .snapshots()
        .map((qs) => qs.docs.map(AssetModel.fromFirestore).toList())
        .handleError((e) {
      _logger.e('❌ InventoryService: Error streaming assets for holder $userId', error: e);
      throw e;
    });
  }

  Future<AssetModel> createAsset({
    String itemType = AssetModel.typeAsset,
    required String name,
    required String category,
    String? description,
    String? serialNumber,
    String initialCondition = AssetModel.conditionGood,
    required String createdByUid,
    required String createdByName,
    Uint8List? photoBytes,
    String? photoFileName,
  }) async {
    try {
      _logger.i('📦 InventoryService: Creating $itemType "$name"');

      final docRef = _firestore.collection(_assetsCollection).doc();
      String? photoUrl;

      if (photoBytes != null && photoFileName != null) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final storageRef = _storage
            .ref()
            .child('Inventory/Assets/${docRef.id}/photo/${timestamp}_$photoFileName');
        final uploadTask = storageRef.putData(
          photoBytes,
          SettableMetadata(contentType: _contentTypeFor(photoFileName)),
        );
        await uploadTask;
        photoUrl = await storageRef.getDownloadURL();
      }

      final now = DateTime.now();
      final asset = AssetModel(
        id: docRef.id,
        itemType: itemType,
        name: name,
        category: category,
        description: description,
        serialNumber: serialNumber,
        photoUrl: photoUrl,
        status: AssetModel.statusAvailable,
        initialCondition: initialCondition,
        createdByUid: createdByUid,
        createdByName: createdByName,
        createdAt: now,
        updatedAt: now,
      );

      await docRef.set(asset.toFirestore());
      _logger.i('✅ InventoryService: Asset "$name" created (ID: ${docRef.id})');
      return asset;
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to create asset "$name"', error: e);
      rethrow;
    }
  }

  /// Uploads a replacement catalog photo for an existing asset/tool and
  /// returns its download URL — the caller is responsible for saving that
  /// URL via [updateAsset].
  Future<String> uploadAssetPhoto({
    required String assetId,
    required Uint8List photoBytes,
    required String photoFileName,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storageRef =
        _storage.ref().child('Inventory/Assets/$assetId/photo/${timestamp}_$photoFileName');
    await storageRef.putData(photoBytes, SettableMetadata(contentType: _contentTypeFor(photoFileName)));
    return storageRef.getDownloadURL();
  }

  /// MainAdmin-only edit of an asset/tool's descriptive fields. Never
  /// touches custody-pointer fields (status/currentHolder*/etc.) — those are
  /// only ever changed by the checkout/return/request transactions, matching
  /// the Firestore rule that restricts this exact field set.
  Future<void> updateAsset({
    required String assetId,
    required String name,
    required String category,
    String? description,
    String? serialNumber,
    String? photoUrl,
  }) async {
    try {
      _logger.i('✏️ InventoryService: Updating asset $assetId');
      await _firestore.collection(_assetsCollection).doc(assetId).update({
        'name': name,
        'category': category,
        'description': description,
        'serialNumber': serialNumber,
        'photoUrl': ?photoUrl,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      _logger.i('✅ InventoryService: Asset $assetId updated');
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to update asset $assetId', error: e);
      rethrow;
    }
  }

  // ── Custody ledger ───────────────────────────────────────────────────

  Stream<List<AssetAssignmentModel>> streamAssetHistory(String assetId) {
    return _firestore
        .collection(_assignmentsCollection)
        .where('assetId', isEqualTo: assetId)
        .orderBy('eventAt', descending: true)
        .snapshots()
        .map((qs) => qs.docs.map(AssetAssignmentModel.fromFirestore).toList())
        .handleError((e) {
      _logger.e('❌ InventoryService: Error streaming history for asset $assetId', error: e);
      throw e;
    });
  }

  Future<AssetAssignmentModel> createCheckout({
    required String assetId,
    required String assignedToUserId,
    required String assignedToName,
    String? projectId,
    String? projectName,
    required String conditionNotes,
    required List<Uint8List> photoBytesList,
    required List<String> photoFileNames,
    required String recordedByUid,
    required String recordedByName,
    required String recordedByRole,
  }) async {
    try {
      _logger.i('📤 InventoryService: Checking out asset $assetId to $assignedToName');
      final assignmentRef = _firestore.collection(_assignmentsCollection).doc();

      final photoUrls = await _uploadAssignmentPhotos(
        assignmentRef.id,
        photoBytesList,
        photoFileNames,
      );

      final now = DateTime.now();
      final assignment = AssetAssignmentModel(
        id: assignmentRef.id,
        assetId: assetId,
        eventType: AssetAssignmentModel.eventCheckout,
        assignedToUserId: assignedToUserId,
        assignedToName: assignedToName,
        projectId: projectId,
        projectName: projectName,
        conditionNotes: conditionNotes,
        photoUrls: photoUrls,
        recordedByUid: recordedByUid,
        recordedByName: recordedByName,
        recordedByRole: recordedByRole,
        eventAt: now,
        createdAt: now,
      );

      await _firestore.runTransaction((transaction) async {
        final assetRef = _firestore.collection(_assetsCollection).doc(assetId);
        final assetSnap = await transaction.get(assetRef);
        if (!assetSnap.exists) {
          throw Exception('Asset $assetId no longer exists');
        }
        final assetData = assetSnap.data()!;
        final currentStatus = assetData['status'] as String?;
        final pendingRequestId = assetData['pendingRequestId'] as String?;
        if (currentStatus != AssetModel.statusAvailable) {
          throw Exception('Asset is not available for checkout (status: $currentStatus)');
        }
        if (pendingRequestId != null) {
          throw Exception('Asset has a pending checkout request awaiting review');
        }

        transaction.set(assignmentRef, assignment.toFirestore());
        transaction.update(assetRef, {
          'status': AssetModel.statusCheckedOut,
          'currentHolderId': assignedToUserId,
          'currentHolderName': assignedToName,
          'currentProjectId': projectId,
          'currentProjectName': projectName,
          'currentAssignmentId': assignmentRef.id,
          'updatedAt': Timestamp.fromDate(now),
        });
      });

      _logger.i('✅ InventoryService: Checkout recorded (ID: ${assignmentRef.id})');
      return assignment;
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to record checkout for asset $assetId', error: e);
      rethrow;
    }
  }

  Future<AssetAssignmentModel> createReturn({
    required String assetId,
    required String previousAssignmentId,
    required String conditionNotes,
    required List<Uint8List> photoBytesList,
    required List<String> photoFileNames,
    required String recordedByUid,
    required String recordedByName,
    required String recordedByRole,
  }) async {
    try {
      _logger.i('📥 InventoryService: Recording return for asset $assetId');
      final assignmentRef = _firestore.collection(_assignmentsCollection).doc();

      final photoUrls = await _uploadAssignmentPhotos(
        assignmentRef.id,
        photoBytesList,
        photoFileNames,
      );

      final now = DateTime.now();

      await _firestore.runTransaction((transaction) async {
        final assetRef = _firestore.collection(_assetsCollection).doc(assetId);
        final assetSnap = await transaction.get(assetRef);
        if (!assetSnap.exists) {
          throw Exception('Asset $assetId no longer exists');
        }
        final data = assetSnap.data()!;
        final currentStatus = data['status'] as String?;
        final currentAssignmentId = data['currentAssignmentId'] as String?;
        if (currentStatus != AssetModel.statusCheckedOut ||
            currentAssignmentId != previousAssignmentId) {
          throw Exception('Asset is not currently checked out under this assignment');
        }

        final assignment = AssetAssignmentModel(
          id: assignmentRef.id,
          assetId: assetId,
          eventType: AssetAssignmentModel.eventReturn,
          previousAssignmentId: previousAssignmentId,
          assignedToUserId: data['currentHolderId'] as String? ?? '',
          assignedToName: data['currentHolderName'] as String? ?? '',
          projectId: data['currentProjectId'] as String?,
          projectName: data['currentProjectName'] as String?,
          conditionNotes: conditionNotes,
          photoUrls: photoUrls,
          recordedByUid: recordedByUid,
          recordedByName: recordedByName,
          recordedByRole: recordedByRole,
          eventAt: now,
          createdAt: now,
        );

        transaction.set(assignmentRef, assignment.toFirestore());
        transaction.update(assetRef, {
          'status': AssetModel.statusAvailable,
          'currentHolderId': null,
          'currentHolderName': null,
          'currentProjectId': null,
          'currentProjectName': null,
          'currentAssignmentId': null,
          'returnRequestedAt': FieldValue.delete(),
          'updatedAt': Timestamp.fromDate(now),
        });
      });

      _logger.i('✅ InventoryService: Return recorded (ID: ${assignmentRef.id})');

      // Re-read for the return value (the model built above lives inside the
      // transaction closure's scope only).
      final saved = await _firestore.collection(_assignmentsCollection).doc(assignmentRef.id).get();
      return AssetAssignmentModel.fromFirestore(saved);
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to record return for asset $assetId', error: e);
      rethrow;
    }
  }

  // ── Checkout requests (Admin requests → MainAdmin approves/rejects) ────

  Stream<List<CheckoutRequestModel>> streamPendingRequests() {
    return _firestore
        .collection(_requestsCollection)
        .where('status', isEqualTo: CheckoutRequestModel.statusPending)
        .orderBy('requestedAt', descending: true)
        .snapshots()
        .map((qs) => qs.docs.map(CheckoutRequestModel.fromFirestore).toList())
        .handleError((e) {
      _logger.e('❌ InventoryService: Error streaming pending requests', error: e);
      throw e;
    });
  }

  Stream<List<CheckoutRequestModel>> streamMyRequests(String uid) {
    return _firestore
        .collection(_requestsCollection)
        .where('requestedByUid', isEqualTo: uid)
        .orderBy('requestedAt', descending: true)
        .limit(20)
        .snapshots()
        .map((qs) => qs.docs.map(CheckoutRequestModel.fromFirestore).toList())
        .handleError((e) {
      _logger.e('❌ InventoryService: Error streaming requests for $uid', error: e);
      throw e;
    });
  }

  Stream<CheckoutRequestModel?> streamRequest(String requestId) {
    return _firestore
        .collection(_requestsCollection)
        .doc(requestId)
        .snapshots()
        .map((doc) => doc.exists ? CheckoutRequestModel.fromFirestore(doc) : null)
        .handleError((e) {
      _logger.e('❌ InventoryService: Error streaming request $requestId', error: e);
      throw e;
    });
  }

  /// Technician (or Admin/MainAdmin, though they normally use [createBooking]
  /// directly) submits a request for a booking window. Locks the asset
  /// (`pendingRequestId`) so no second request can be raised until a
  /// MainAdmin/Admin approves/rejects this one. The window itself is
  /// validated against existing bookings/maintenance the same way
  /// [createBooking] is — approval just turns this into a real booking.
  Future<CheckoutRequestModel> createCheckoutRequest({
    required String assetId,
    required String assetName,
    required String itemType,
    required String requestedByUid,
    required String requestedByName,
    String? projectId,
    String? projectName,
    required String reason,
    required DateTime requestedStart,
    required DateTime requestedEnd,
  }) async {
    try {
      _logger.i('📝 InventoryService: $requestedByName requesting checkout of $assetName');
      await _assertNoOverlap(assetId: assetId, start: requestedStart, end: requestedEnd);

      final requestRef = _firestore.collection(_requestsCollection).doc();
      final now = DateTime.now();
      final startsNow = !requestedStart.isAfter(now);
      final request = CheckoutRequestModel(
        id: requestRef.id,
        assetId: assetId,
        assetName: assetName,
        itemType: itemType,
        requestedByUid: requestedByUid,
        requestedByName: requestedByName,
        projectId: projectId,
        projectName: projectName,
        reason: reason,
        requestedStart: requestedStart,
        requestedEnd: requestedEnd,
        status: CheckoutRequestModel.statusPending,
        requestedAt: now,
      );

      await _firestore.runTransaction((transaction) async {
        final assetRef = _firestore.collection(_assetsCollection).doc(assetId);
        final assetSnap = await transaction.get(assetRef);
        if (!assetSnap.exists) throw Exception('Asset $assetId no longer exists');

        transaction.set(requestRef, request.toFirestore());

        // Only an immediate request locks the asset's single
        // pending-request slot — it wants the item claimed right now, so a
        // second immediate request racing for the same idle item must be
        // blocked. A future request doesn't affect the asset's current
        // state at all: the current holder (if any) keeps their normal
        // status/actions completely untouched until the day the window
        // actually starts. Several non-overlapping future requests can
        // coexist — conflict prevention for those is _assertNoOverlap above,
        // not this lock. (Approving still goes through the same
        // review/Pending Requests screen either way — that list streams by
        // request status, not this field.)
        if (startsNow) {
          final data = assetSnap.data()!;
          if (data['pendingRequestId'] != null) {
            throw Exception('Asset already has a pending request');
          }
          transaction.update(assetRef, {
            'pendingRequestId': requestRef.id,
            'updatedAt': Timestamp.fromDate(now),
          });
        }
      });

      await _notifyAdmins(
        title: '📦 Checkout Request',
        body: '$requestedByName requested "$assetName" from ${_fmtDate(requestedStart)} '
            'to ${_fmtDate(requestedEnd)}${projectName != null ? ' for $projectName' : ''}.',
        payload: {'type': 'inventory_checkout_request', 'requestId': requestRef.id, 'assetId': assetId},
      );

      _logger.i('✅ InventoryService: Checkout request created (ID: ${requestRef.id})');
      return request;
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to create checkout request for $assetName', error: e);
      rethrow;
    }
  }

  /// MainAdmin rejects a pending request — asset unlocks back to Available.
  Future<void> rejectCheckoutRequest({
    required String requestId,
    required String assetId,
    required String respondedByUid,
    required String respondedByName,
    String? rejectionReason,
  }) async {
    try {
      _logger.i('🚫 InventoryService: Rejecting checkout request $requestId');
      final now = DateTime.now();
      String requesterUid = '';
      String requesterName = '';
      String assetName = '';

      await _firestore.runTransaction((transaction) async {
        final requestRef = _firestore.collection(_requestsCollection).doc(requestId);
        final requestSnap = await transaction.get(requestRef);
        if (!requestSnap.exists) throw Exception('Request $requestId no longer exists');
        final requestData = requestSnap.data()!;
        if (requestData['status'] != CheckoutRequestModel.statusPending) {
          throw Exception('Request has already been responded to');
        }
        requesterUid = requestData['requestedByUid'] as String? ?? '';
        requesterName = requestData['requestedByName'] as String? ?? '';
        assetName = requestData['assetName'] as String? ?? '';

        final assetRef = _firestore.collection(_assetsCollection).doc(assetId);

        transaction.update(requestRef, {
          'status': CheckoutRequestModel.statusRejected,
          'respondedByUid': respondedByUid,
          'respondedByName': respondedByName,
          'respondedAt': Timestamp.fromDate(now),
          'rejectionReason': ?rejectionReason,
        });
        transaction.update(assetRef, {
          'pendingRequestId': null,
          'updatedAt': Timestamp.fromDate(now),
        });
      });

      await _notifyAdmins(
        title: '❌ Checkout Request Rejected',
        body: '$respondedByName rejected $requesterName\'s request for "$assetName"'
            '${rejectionReason != null ? ': $rejectionReason' : '.'}',
        payload: {'type': 'inventory_checkout_rejected', 'requestId': requestId, 'assetId': assetId},
      );

      if (requesterUid.isNotEmpty) {
        await _notifyUser(
          targetUid: requesterUid,
          title: '❌ Checkout Request Rejected',
          body: 'Your request for "$assetName" was rejected'
              '${rejectionReason != null ? ': $rejectionReason' : '.'}',
          payload: {'type': 'inventory_checkout_rejected', 'requestId': requestId, 'assetId': assetId},
        );
      }

      _logger.i('✅ InventoryService: Request $requestId rejected');
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to reject request $requestId', error: e);
      rethrow;
    }
  }

  /// MainAdmin/Admin approves a pending request — creates the real
  /// [AssetBookingModel] for the requested window (immediately active if the
  /// window starts today/earlier, capturing condition + photos as the
  /// handover confirmation; otherwise left scheduled for collection later).
  /// The approving admin is the traced actioning user on the booking, and
  /// the same self-checkout guard applies (an Admin can't approve their own
  /// request onto themself — though in practice Technician is the only role
  /// still using the request flow; MainAdmin is always exempt).
  Future<AssetBookingModel> approveCheckoutRequest({
    required CheckoutRequestModel request,
    required String conditionNotes,
    required List<Uint8List> photoBytesList,
    required List<String> photoFileNames,
    required String respondedByUid,
    required String respondedByName,
    required String respondedByRole,
    String deliveryMethod = AssetBookingModel.deliveryDirect,
    String? driverName,
  }) async {
    try {
      _logger.i('✅ InventoryService: Approving checkout request ${request.id}');
      _assertNotSelfAssignment(
        actingRole: respondedByRole,
        actingUid: respondedByUid,
        targetUid: request.requestedByUid,
      );

      final now = DateTime.now();
      final startsNow = !request.requestedStart.isAfter(now);
      // A future-dated request was never locked to the asset (see
      // createCheckoutRequest) — re-check here, right before approving,
      // that nothing else has since claimed this exact window. Best-effort,
      // same caveat as _assertNoOverlap generally (Firestore transactions
      // can't run multi-doc queries, so this can't be inside the
      // transaction below).
      if (!startsNow) {
        await _assertNoOverlap(assetId: request.assetId, start: request.requestedStart, end: request.requestedEnd);
      }
      final viaDriver = deliveryMethod == AssetBookingModel.deliveryDriver;

      final bookingRef = _firestore.collection(_bookingsCollection).doc();
      final assignmentRef = startsNow ? _firestore.collection(_assignmentsCollection).doc() : null;

      List<String> photoUrls = const [];
      if (startsNow) {
        photoUrls = await _uploadAssignmentPhotos(assignmentRef!.id, photoBytesList, photoFileNames);
      }

      final booking = AssetBookingModel(
        id: bookingRef.id,
        assetId: request.assetId,
        assetName: request.assetName,
        itemType: request.itemType,
        bookedForUid: request.requestedByUid,
        bookedForName: request.requestedByName,
        projectId: request.projectId,
        projectName: request.projectName,
        scheduledStart: request.requestedStart,
        scheduledEnd: request.requestedEnd,
        status: startsNow ? AssetBookingModel.statusActive : AssetBookingModel.statusScheduled,
        checkoutAssignmentId: assignmentRef?.id,
        deliveryMethod: deliveryMethod,
        driverName: viaDriver ? driverName : null,
        dispatchedAt: (startsNow && viaDriver) ? now : null,
        dispatchedByUid: (startsNow && viaDriver) ? respondedByUid : null,
        dispatchedByName: (startsNow && viaDriver) ? respondedByName : null,
        sourceRequestId: request.id,
        createdByUid: respondedByUid,
        createdByName: respondedByName,
        createdByRole: respondedByRole,
        createdAt: now,
      );

      await _firestore.runTransaction((transaction) async {
        final requestRef = _firestore.collection(_requestsCollection).doc(request.id);
        final requestSnap = await transaction.get(requestRef);
        if (!requestSnap.exists) throw Exception('Request ${request.id} no longer exists');
        if (requestSnap.data()!['status'] != CheckoutRequestModel.statusPending) {
          throw Exception('Request has already been responded to');
        }

        final assetRef = _firestore.collection(_assetsCollection).doc(request.assetId);
        final assetSnap = await transaction.get(assetRef);
        if (!assetSnap.exists) throw Exception('Asset ${request.assetId} no longer exists');
        final assetData = assetSnap.data()!;
        // Only an immediate request ever locked the asset's pendingRequestId
        // (see createCheckoutRequest) — a future request never touched it,
        // so there's nothing to reconcile here for that case.
        if (startsNow) {
          if (assetData['pendingRequestId'] != request.id) {
            throw Exception('Asset state no longer matches this request');
          }
          if (assetData['status'] != AssetModel.statusAvailable) {
            throw Exception('Asset is not available for an immediate checkout (status: ${assetData['status']})');
          }
        }

        transaction.set(bookingRef, booking.toFirestore());
        if (startsNow) {
          final assignment = AssetAssignmentModel(
            id: assignmentRef!.id,
            assetId: request.assetId,
            eventType: AssetAssignmentModel.eventCheckout,
            bookingId: bookingRef.id,
            assignedToUserId: request.requestedByUid,
            assignedToName: request.requestedByName,
            projectId: request.projectId,
            projectName: request.projectName,
            conditionNotes: conditionNotes,
            photoUrls: photoUrls,
            recordedByUid: respondedByUid,
            recordedByName: respondedByName,
            recordedByRole: respondedByRole,
            eventAt: now,
            createdAt: now,
          );
          transaction.set(assignmentRef, assignment.toFirestore());
          transaction.update(assetRef, {
            'status': AssetModel.statusCheckedOut,
            'currentHolderId': request.requestedByUid,
            'currentHolderName': request.requestedByName,
            'currentProjectId': request.projectId,
            'currentProjectName': request.projectName,
            'currentAssignmentId': assignmentRef.id,
            'pendingRequestId': null,
            'updatedAt': Timestamp.fromDate(now),
          });
        }
        // Future-dated approval: this only schedules a booking (see
        // `transaction.set(bookingRef, ...)` above) — the asset's current
        // status/holder/pendingRequestId is untouched, since a future
        // request never locked it and the current holder's custody isn't
        // affected until the day the window actually starts (recordCollection
        // performs the real handover then).
        transaction.update(requestRef, {
          'status': CheckoutRequestModel.statusApproved,
          'respondedByUid': respondedByUid,
          'respondedByName': respondedByName,
          'respondedAt': Timestamp.fromDate(now),
        });
      });

      await _refreshNextBooking(request.assetId);

      await _notifyAdmins(
        title: '✅ Checkout Approved',
        body: '$respondedByName approved ${request.requestedByName}\'s request for "${request.assetName}".',
        payload: {'type': 'inventory_checkout_approved', 'requestId': request.id, 'assetId': request.assetId},
      );

      await _notifyUser(
        targetUid: request.requestedByUid,
        title: '✅ Checkout Approved',
        body: 'Your request for "${request.assetName}" was approved by $respondedByName'
            '${startsNow ? ' — it\'s checked out to you now.' : ' — booked for ${_fmtDate(request.requestedStart)}.'}',
        payload: {'type': 'inventory_checkout_approved', 'requestId': request.id, 'assetId': request.assetId},
      );

      if (startsNow && viaDriver) {
        await _notifyUser(
          targetUid: request.requestedByUid,
          title: '🚚 "${request.assetName}" is on the way',
          body: '${driverName != null ? '$driverName is bringing' : 'A driver is bringing'} '
              '"${request.assetName}" to you — tap Acknowledge Receipt once it arrives.',
          payload: {'type': 'inventory_delivery_dispatched', 'assetId': request.assetId, 'bookingId': bookingRef.id},
        );
      }

      _logger.i('✅ InventoryService: Request ${request.id} approved (booking ${bookingRef.id})');
      return booking;
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to approve request ${request.id}', error: e);
      rethrow;
    }
  }

  // ── Bookings (scheduled checkout/return windows) ────────────────────────

  Stream<List<AssetBookingModel>> streamAssetBookings(String assetId) {
    return _firestore
        .collection(_bookingsCollection)
        .where('assetId', isEqualTo: assetId)
        .where('status', whereIn: [AssetBookingModel.statusScheduled, AssetBookingModel.statusActive])
        .orderBy('scheduledStart')
        .snapshots()
        .map((qs) => qs.docs.map(AssetBookingModel.fromFirestore).toList())
        .handleError((e) {
      _logger.e('❌ InventoryService: Error streaming bookings for asset $assetId', error: e);
      throw e;
    });
  }

  /// Direct MainAdmin/Admin booking. If [scheduledStart] is today or earlier,
  /// the physical handover happens immediately (condition/photos captured
  /// now, asset flips to Checked Out); otherwise this only reserves the
  /// window — the asset stays Available until [recordCollection] is called
  /// on the day.
  Future<AssetBookingModel> createBooking({
    required String assetId,
    required String assetName,
    required String itemType,
    required String bookedForUid,
    required String bookedForName,
    String? projectId,
    String? projectName,
    required DateTime scheduledStart,
    required DateTime scheduledEnd,
    required String conditionNotes,
    required List<Uint8List> photoBytesList,
    required List<String> photoFileNames,
    String deliveryMethod = AssetBookingModel.deliveryDirect,
    String? driverName,
    required String createdByUid,
    required String createdByName,
    required String createdByRole,
  }) async {
    try {
      _logger.i('📅 InventoryService: Creating booking for asset $assetId ($bookedForName)');
      _assertNotSelfAssignment(actingRole: createdByRole, actingUid: createdByUid, targetUid: bookedForUid);
      await _assertNoOverlap(assetId: assetId, start: scheduledStart, end: scheduledEnd);

      final now = DateTime.now();
      final startsNow = !scheduledStart.isAfter(now);
      final viaDriver = deliveryMethod == AssetBookingModel.deliveryDriver;

      final bookingRef = _firestore.collection(_bookingsCollection).doc();
      final assignmentRef = startsNow ? _firestore.collection(_assignmentsCollection).doc() : null;

      List<String> photoUrls = const [];
      if (startsNow) {
        photoUrls = await _uploadAssignmentPhotos(assignmentRef!.id, photoBytesList, photoFileNames);
      }

      final booking = AssetBookingModel(
        id: bookingRef.id,
        assetId: assetId,
        assetName: assetName,
        itemType: itemType,
        bookedForUid: bookedForUid,
        bookedForName: bookedForName,
        projectId: projectId,
        projectName: projectName,
        scheduledStart: scheduledStart,
        scheduledEnd: scheduledEnd,
        status: startsNow ? AssetBookingModel.statusActive : AssetBookingModel.statusScheduled,
        checkoutAssignmentId: assignmentRef?.id,
        deliveryMethod: deliveryMethod,
        driverName: viaDriver ? driverName : null,
        dispatchedAt: (startsNow && viaDriver) ? now : null,
        dispatchedByUid: (startsNow && viaDriver) ? createdByUid : null,
        dispatchedByName: (startsNow && viaDriver) ? createdByName : null,
        createdByUid: createdByUid,
        createdByName: createdByName,
        createdByRole: createdByRole,
        createdAt: now,
      );

      String? conflictingHolderId;
      await _firestore.runTransaction((transaction) async {
        final assetRef = _firestore.collection(_assetsCollection).doc(assetId);
        final assetSnap = await transaction.get(assetRef);
        if (!assetSnap.exists) throw Exception('Asset $assetId no longer exists');
        final assetData = assetSnap.data()!;

        if (startsNow) {
          final currentStatus = assetData['status'] as String?;
          if (currentStatus != AssetModel.statusAvailable) {
            throw Exception('Asset is not available for an immediate checkout (status: $currentStatus)');
          }
        } else {
          conflictingHolderId = assetData['currentHolderId'] as String?;
        }

        transaction.set(bookingRef, booking.toFirestore());
        if (startsNow) {
          final assignment = AssetAssignmentModel(
            id: assignmentRef!.id,
            assetId: assetId,
            eventType: AssetAssignmentModel.eventCheckout,
            bookingId: bookingRef.id,
            assignedToUserId: bookedForUid,
            assignedToName: bookedForName,
            projectId: projectId,
            projectName: projectName,
            conditionNotes: conditionNotes,
            photoUrls: photoUrls,
            recordedByUid: createdByUid,
            recordedByName: createdByName,
            recordedByRole: createdByRole,
            eventAt: now,
            createdAt: now,
          );
          transaction.set(assignmentRef, assignment.toFirestore());
          transaction.update(assetRef, {
            'status': AssetModel.statusCheckedOut,
            'currentHolderId': bookedForUid,
            'currentHolderName': bookedForName,
            'currentProjectId': projectId,
            'currentProjectName': projectName,
            'currentAssignmentId': assignmentRef.id,
            'updatedAt': Timestamp.fromDate(now),
          });
        }
      });

      await _refreshNextBooking(assetId);

      // A future booking on an asset someone else already holds — warn them
      // immediately so they can plan the return; the day-before reminder is
      // handled separately by the sendBookingReminders scheduled function.
      if (!startsNow && conflictingHolderId != null && conflictingHolderId != bookedForUid) {
        await _notifyUser(
          targetUid: conflictingHolderId!,
          title: '📅 "$assetName" has been booked',
          body: '$bookedForName has booked "$assetName" starting ${_fmtDate(scheduledStart)}. '
              'Please plan to return it in time.',
          payload: {'type': 'inventory_upcoming_booking', 'assetId': assetId, 'bookingId': bookingRef.id},
        );
      }

      if (startsNow && viaDriver) {
        await _notifyUser(
          targetUid: bookedForUid,
          title: '🚚 "$assetName" is on the way',
          body: '${driverName != null ? '$driverName is bringing' : 'A driver is bringing'} '
              '"$assetName" to you — tap Acknowledge Receipt once it arrives.',
          payload: {'type': 'inventory_delivery_dispatched', 'assetId': assetId, 'bookingId': bookingRef.id},
        );
      }

      _logger.i('✅ InventoryService: Booking created (ID: ${bookingRef.id})');
      return booking;
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to create booking for asset $assetId', error: e);
      rethrow;
    }
  }

  /// Technician confirms a driver-delivered item has physically arrived —
  /// deliberately does NOT touch condition/photos or any custody-pointer
  /// field (those were already captured by the dispatching admin); this is
  /// only ever a receipt-confirmation timestamp, so a holder can never
  /// self-assess their own item's condition.
  Future<void> acknowledgeDelivery({
    required String bookingId,
    required String acknowledgedByUid,
    // The signed physical handover form (see asset_handover_form_pdf.dart),
    // photographed/scanned by the recipient — optional supporting evidence
    // alongside their real, in-app acknowledgment above; uploaded first (out
    // of the transaction, same pattern as _uploadAssignmentPhotos) so its
    // download URL can be written in the same update as the ack fields.
    Uint8List? scanBytes,
    String? scanFileName,
  }) async {
    try {
      _logger.i('📬 InventoryService: Acknowledging delivery for booking $bookingId');
      final now = DateTime.now();
      String assetName = '';
      String bookedForName = '';

      String? scanUrl;
      if (scanBytes != null && scanFileName != null) {
        final urls = await _uploadPhotos('Inventory/AssetBookings/$bookingId/handoverForm', [scanBytes], [scanFileName]);
        scanUrl = urls.isNotEmpty ? urls.first : null;
      }

      await _firestore.runTransaction((transaction) async {
        final bookingRef = _firestore.collection(_bookingsCollection).doc(bookingId);
        final bookingSnap = await transaction.get(bookingRef);
        if (!bookingSnap.exists) throw Exception('Booking $bookingId no longer exists');
        final data = bookingSnap.data()!;
        if (data['bookedForUid'] != acknowledgedByUid) {
          throw Exception('Only the person this item is booked for can acknowledge delivery');
        }
        if (data['deliveryMethod'] != AssetBookingModel.deliveryDriver) {
          throw Exception('This booking is not a driver delivery');
        }
        assetName = data['assetName'] as String? ?? '';
        bookedForName = data['bookedForName'] as String? ?? '';

        transaction.update(bookingRef, {
          'deliveryAcknowledgedAt': Timestamp.fromDate(now),
          'deliveryAcknowledgedByUid': acknowledgedByUid,
          'handoverFormScanUrl': ?scanUrl,
        });
      });

      await _notifyAdmins(
        title: '📬 Delivery Acknowledged',
        body: '$bookedForName confirmed receipt of "$assetName".',
        payload: {'type': 'inventory_delivery_acknowledged', 'bookingId': bookingId},
      );

      _logger.i('✅ InventoryService: Delivery acknowledged for booking $bookingId');
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to acknowledge delivery for booking $bookingId', error: e);
      rethrow;
    }
  }

  /// Physically hands over an item whose scheduled booking date has
  /// arrived — moves the booking scheduled → active and the asset to
  /// Checked Out. Same self-checkout guard as [createBooking].
  Future<AssetAssignmentModel> recordCollection({
    required AssetBookingModel booking,
    required String conditionNotes,
    required List<Uint8List> photoBytesList,
    required List<String> photoFileNames,
    required String recordedByUid,
    required String recordedByName,
    required String recordedByRole,
  }) async {
    try {
      _logger.i('📤 InventoryService: Recording collection for booking ${booking.id}');
      _assertNotSelfAssignment(
        actingRole: recordedByRole,
        actingUid: recordedByUid,
        targetUid: booking.bookedForUid,
      );

      final assignmentRef = _firestore.collection(_assignmentsCollection).doc();
      final photoUrls = await _uploadAssignmentPhotos(assignmentRef.id, photoBytesList, photoFileNames);
      final now = DateTime.now();
      final assignment = AssetAssignmentModel(
        id: assignmentRef.id,
        assetId: booking.assetId,
        eventType: AssetAssignmentModel.eventCheckout,
        bookingId: booking.id,
        assignedToUserId: booking.bookedForUid,
        assignedToName: booking.bookedForName,
        projectId: booking.projectId,
        projectName: booking.projectName,
        conditionNotes: conditionNotes,
        photoUrls: photoUrls,
        recordedByUid: recordedByUid,
        recordedByName: recordedByName,
        recordedByRole: recordedByRole,
        eventAt: now,
        createdAt: now,
      );

      await _firestore.runTransaction((transaction) async {
        final bookingRef = _firestore.collection(_bookingsCollection).doc(booking.id);
        final bookingSnap = await transaction.get(bookingRef);
        if (!bookingSnap.exists) throw Exception('Booking ${booking.id} no longer exists');
        if (bookingSnap.data()!['status'] != AssetBookingModel.statusScheduled) {
          throw Exception('Booking is no longer scheduled');
        }
        final assetRef = _firestore.collection(_assetsCollection).doc(booking.assetId);
        final assetSnap = await transaction.get(assetRef);
        if (!assetSnap.exists) throw Exception('Asset ${booking.assetId} no longer exists');
        if (assetSnap.data()!['status'] != AssetModel.statusAvailable) {
          throw Exception('Asset is not available for collection (status: ${assetSnap.data()!['status']})');
        }

        transaction.set(assignmentRef, assignment.toFirestore());
        transaction.update(bookingRef, {
          'status': AssetBookingModel.statusActive,
          'checkoutAssignmentId': assignmentRef.id,
          if (booking.isViaDriver) ...{
            'dispatchedAt': Timestamp.fromDate(now),
            'dispatchedByUid': recordedByUid,
            'dispatchedByName': recordedByName,
          },
        });
        transaction.update(assetRef, {
          'status': AssetModel.statusCheckedOut,
          'currentHolderId': booking.bookedForUid,
          'currentHolderName': booking.bookedForName,
          'currentProjectId': booking.projectId,
          'currentProjectName': booking.projectName,
          'currentAssignmentId': assignmentRef.id,
          'updatedAt': Timestamp.fromDate(now),
        });
      });

      await _refreshNextBooking(booking.assetId);

      if (booking.isViaDriver) {
        await _notifyUser(
          targetUid: booking.bookedForUid,
          title: '🚚 "${booking.assetName}" is on the way',
          body: '${booking.driverName != null ? '${booking.driverName} is bringing' : 'A driver is bringing'} '
              '"${booking.assetName}" to you — tap Acknowledge Receipt once it arrives.',
          payload: {'type': 'inventory_delivery_dispatched', 'assetId': booking.assetId, 'bookingId': booking.id},
        );
      }

      _logger.i('✅ InventoryService: Collection recorded for booking ${booking.id}');
      return assignment;
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to record collection for booking ${booking.id}', error: e);
      rethrow;
    }
  }

  /// Closes an active booking: writes the return ledger entry (with a
  /// structured [conditionRating] so mishandling is traceable back to
  /// [AssetBookingModel.bookedForName], not just narrative notes), frees the
  /// asset, and refreshes the next-upcoming-booking pointer.
  Future<AssetAssignmentModel> recordBookingReturn({
    required AssetBookingModel booking,
    required String conditionNotes,
    required String conditionRating,
    required List<Uint8List> photoBytesList,
    required List<String> photoFileNames,
    required String recordedByUid,
    required String recordedByName,
    required String recordedByRole,
  }) async {
    try {
      _logger.i('📥 InventoryService: Recording return for booking ${booking.id}');
      if (recordedByUid == booking.bookedForUid) {
        throw Exception(
          'You cannot record your own return — ask a different MainAdmin or System Admin to record it.',
        );
      }
      final assignmentRef = _firestore.collection(_assignmentsCollection).doc();
      final photoUrls = await _uploadAssignmentPhotos(assignmentRef.id, photoBytesList, photoFileNames);
      final now = DateTime.now();
      final assignment = AssetAssignmentModel(
        id: assignmentRef.id,
        assetId: booking.assetId,
        eventType: AssetAssignmentModel.eventReturn,
        previousAssignmentId: booking.checkoutAssignmentId,
        bookingId: booking.id,
        assignedToUserId: booking.bookedForUid,
        assignedToName: booking.bookedForName,
        projectId: booking.projectId,
        projectName: booking.projectName,
        conditionNotes: conditionNotes,
        conditionRating: conditionRating,
        photoUrls: photoUrls,
        recordedByUid: recordedByUid,
        recordedByName: recordedByName,
        recordedByRole: recordedByRole,
        eventAt: now,
        createdAt: now,
      );

      await _firestore.runTransaction((transaction) async {
        final bookingRef = _firestore.collection(_bookingsCollection).doc(booking.id);
        final bookingSnap = await transaction.get(bookingRef);
        if (!bookingSnap.exists) throw Exception('Booking ${booking.id} no longer exists');
        if (bookingSnap.data()!['status'] != AssetBookingModel.statusActive) {
          throw Exception('Booking is not currently active');
        }
        final assetRef = _firestore.collection(_assetsCollection).doc(booking.assetId);

        transaction.set(assignmentRef, assignment.toFirestore());
        transaction.update(bookingRef, {
          'status': AssetBookingModel.statusCompleted,
          'returnAssignmentId': assignmentRef.id,
        });
        transaction.update(assetRef, {
          'status': AssetModel.statusAvailable,
          'currentHolderId': null,
          'currentHolderName': null,
          'currentProjectId': null,
          'currentProjectName': null,
          'currentAssignmentId': null,
          'returnRequestedAt': FieldValue.delete(),
          'updatedAt': Timestamp.fromDate(now),
        });
      });

      await _refreshNextBooking(booking.assetId);

      _logger.i('✅ InventoryService: Return recorded for booking ${booking.id}');
      return assignment;
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to record return for booking ${booking.id}', error: e);
      rethrow;
    }
  }

  /// Closes out an asset that's Checked Out with no [AssetBookingModel] to
  /// link the return to — an item checked out via the pre-booking direct
  /// checkout path (or any other way a custody ledger entry ever gets
  /// written without a paired booking; [AssetAssignmentModel.bookingId] has
  /// always been nullable for exactly this reason). Without this, such an
  /// asset had no return path at all: [recordBookingReturn] requires a real,
  /// active booking, so the UI had nothing to call and silently showed no
  /// action button once the only fitting one — assuming a booking existed —
  /// turned up empty. Mirrors recordBookingReturn's ledger write and asset
  /// field reset exactly, just without a booking to close.
  Future<AssetAssignmentModel> recordLegacyReturn({
    required AssetModel asset,
    required String conditionNotes,
    required String conditionRating,
    required List<Uint8List> photoBytesList,
    required List<String> photoFileNames,
    required String recordedByUid,
    required String recordedByName,
    required String recordedByRole,
  }) async {
    try {
      _logger.i('📥 InventoryService: Recording legacy return for asset ${asset.id}');
      if (recordedByUid == asset.currentHolderId) {
        throw Exception(
          'You cannot record your own return — ask a different MainAdmin or System Admin to record it.',
        );
      }
      final assignmentRef = _firestore.collection(_assignmentsCollection).doc();
      final photoUrls = await _uploadAssignmentPhotos(assignmentRef.id, photoBytesList, photoFileNames);
      final now = DateTime.now();
      final assignment = AssetAssignmentModel(
        id: assignmentRef.id,
        assetId: asset.id,
        eventType: AssetAssignmentModel.eventReturn,
        previousAssignmentId: asset.currentAssignmentId,
        assignedToUserId: asset.currentHolderId ?? '',
        assignedToName: asset.currentHolderName ?? '',
        projectId: asset.currentProjectId,
        projectName: asset.currentProjectName,
        conditionNotes: conditionNotes,
        conditionRating: conditionRating,
        photoUrls: photoUrls,
        recordedByUid: recordedByUid,
        recordedByName: recordedByName,
        recordedByRole: recordedByRole,
        eventAt: now,
        createdAt: now,
      );

      await _firestore.runTransaction((transaction) async {
        final assetRef = _firestore.collection(_assetsCollection).doc(asset.id);
        final assetSnap = await transaction.get(assetRef);
        if (!assetSnap.exists) throw Exception('Asset ${asset.id} no longer exists');
        final assetData = assetSnap.data()!;
        if (assetData['status'] != AssetModel.statusCheckedOut) {
          throw Exception('Asset is not currently checked out');
        }
        // Guards against a booking having been created for this asset
        // between the UI reading "no active booking" and this write —
        // if one now exists, recordBookingReturn is the correct path.
        if (assetData['currentAssignmentId'] != asset.currentAssignmentId) {
          throw Exception('This item\'s custody record changed — please refresh and try again');
        }

        transaction.set(assignmentRef, assignment.toFirestore());
        transaction.update(assetRef, {
          'status': AssetModel.statusAvailable,
          'currentHolderId': null,
          'currentHolderName': null,
          'currentProjectId': null,
          'currentProjectName': null,
          'currentAssignmentId': null,
          'returnRequestedAt': FieldValue.delete(),
          'updatedAt': Timestamp.fromDate(now),
        });
      });

      await _refreshNextBooking(asset.id);

      _logger.i('✅ InventoryService: Legacy return recorded for asset ${asset.id}');
      return assignment;
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to record legacy return for asset ${asset.id}', error: e);
      rethrow;
    }
  }

  /// Cancels a not-yet-collected booking (MainAdmin/Admin, or the original
  /// requester before their scheduled start date).
  Future<void> cancelBooking({
    required String bookingId,
    required String assetId,
    required String cancelledByUid,
    required String cancelledByName,
    String? cancellationReason,
  }) async {
    try {
      _logger.i('🚫 InventoryService: Cancelling booking $bookingId');
      await _firestore.runTransaction((transaction) async {
        final bookingRef = _firestore.collection(_bookingsCollection).doc(bookingId);
        final bookingSnap = await transaction.get(bookingRef);
        if (!bookingSnap.exists) throw Exception('Booking $bookingId no longer exists');
        if (bookingSnap.data()!['status'] != AssetBookingModel.statusScheduled) {
          throw Exception('Only a scheduled (not yet collected) booking can be cancelled');
        }
        transaction.update(bookingRef, {
          'status': AssetBookingModel.statusCancelled,
          'cancelledByUid': cancelledByUid,
          'cancelledByName': cancelledByName,
          'cancelledAt': Timestamp.fromDate(DateTime.now()),
          'cancellationReason': ?cancellationReason,
        });
      });
      await _refreshNextBooking(assetId);
      _logger.i('✅ InventoryService: Booking $bookingId cancelled');
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to cancel booking $bookingId', error: e);
      rethrow;
    }
  }

  // ── Maintenance windows (MainAdmin/Admin blackout dates) ────────────────

  Stream<List<AssetMaintenanceWindowModel>> streamAssetMaintenanceWindows(String assetId) {
    return _firestore
        .collection(_maintenanceCollection)
        .where('assetId', isEqualTo: assetId)
        .orderBy('startDate')
        .snapshots()
        .map((qs) => qs.docs.map(AssetMaintenanceWindowModel.fromFirestore).toList())
        .handleError((e) {
      _logger.e('❌ InventoryService: Error streaming maintenance windows for asset $assetId', error: e);
      throw e;
    });
  }

  /// Maintenance always takes priority over a booking: unlike
  /// `_assertNoOverlap` (used by createCheckoutRequest), this does NOT
  /// reject on an overlapping booking — it cancels a conflicting *scheduled*
  /// one (notifying whoever it was for) and asks the current holder of a
  /// conflicting *active* one to return early, instead of blocking the
  /// maintenance window. It still refuses to overlap another maintenance
  /// window — two blackout periods can't be auto-resolved against each other.
  Future<AssetMaintenanceWindowModel> createMaintenanceWindow({
    required String assetId,
    required String assetName,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    required String createdByUid,
    required String createdByName,
  }) async {
    try {
      _logger.i('🛠️ InventoryService: Creating maintenance window for asset $assetId');

      final maintenanceSnap =
          await _firestore.collection(_maintenanceCollection).where('assetId', isEqualTo: assetId).get();
      for (final doc in maintenanceSnap.docs) {
        final m = AssetMaintenanceWindowModel.fromFirestore(doc);
        if (_rangesOverlap(startDate, endDate, m.startDate, m.endDate)) {
          throw Exception(
            'This window overlaps a scheduled maintenance period '
            '(${_fmtDate(m.startDate)} - ${_fmtDate(m.endDate)}).',
          );
        }
      }

      final ref = _firestore.collection(_maintenanceCollection).doc();
      final window = AssetMaintenanceWindowModel(
        id: ref.id,
        assetId: assetId,
        assetName: assetName,
        startDate: startDate,
        endDate: endDate,
        reason: reason,
        createdByUid: createdByUid,
        createdByName: createdByName,
        createdAt: DateTime.now(),
      );
      await ref.set(window.toFirestore());

      final bookingsSnap = await _firestore
          .collection(_bookingsCollection)
          .where('assetId', isEqualTo: assetId)
          .where('status', whereIn: [AssetBookingModel.statusScheduled, AssetBookingModel.statusActive])
          .get();

      var holderNotifiedViaBooking = false;
      for (final doc in bookingsSnap.docs) {
        final b = AssetBookingModel.fromFirestore(doc);
        if (!_rangesOverlap(startDate, endDate, b.scheduledStart, b.scheduledEnd)) continue;

        if (b.isScheduled) {
          await doc.reference.update({
            'status': AssetBookingModel.statusCancelled,
            'cancelledByUid': createdByUid,
            'cancelledByName': createdByName,
            'cancelledAt': Timestamp.fromDate(DateTime.now()),
            'cancellationReason': 'Cancelled for planned maintenance ($reason).',
          });
          await _notifyUser(
            targetUid: b.bookedForUid,
            title: '🛠️ Booking Cancelled — Maintenance',
            body: 'Your booked "$assetName" will not be available '
                '${_fmtDate(startDate)} - ${_fmtDate(endDate)} due to planned maintenance ($reason).',
            payload: {'type': 'inventory_booking_cancelled_maintenance', 'assetId': assetId, 'bookingId': b.id},
          );
        } else {
          // Active — the item is already out; can't cancel a live checkout,
          // so ask the current holder to bring it back in time instead.
          await _notifyUser(
            targetUid: b.bookedForUid,
            title: '🛠️ Return Needed for Maintenance',
            body: 'Please return "$assetName" by ${_fmtDate(startDate)} — it\'s scheduled for maintenance ($reason).',
            payload: {'type': 'inventory_return_for_maintenance', 'assetId': assetId},
          );
          holderNotifiedViaBooking = true;
        }
      }

      // Legacy-checkout case: currently held with no matching booking at
      // all (see recordLegacyReturn) — still worth telling the holder.
      if (!holderNotifiedViaBooking) {
        final assetSnap = await _firestore.collection(_assetsCollection).doc(assetId).get();
        final assetData = assetSnap.data();
        final holderId = assetData?['currentHolderId'] as String?;
        if (assetData?['status'] == AssetModel.statusCheckedOut && holderId != null) {
          await _notifyUser(
            targetUid: holderId,
            title: '🛠️ Return Needed for Maintenance',
            body: 'Please return "$assetName" by ${_fmtDate(startDate)} — it\'s scheduled for maintenance ($reason).',
            payload: {'type': 'inventory_return_for_maintenance', 'assetId': assetId},
          );
        }
      }

      _logger.i('✅ InventoryService: Maintenance window created (ID: ${ref.id})');
      return window;
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to create maintenance window for asset $assetId', error: e);
      rethrow;
    }
  }

  Future<void> cancelMaintenanceWindow(String windowId) async {
    try {
      _logger.i('🚫 InventoryService: Cancelling maintenance window $windowId');
      await _firestore.collection(_maintenanceCollection).doc(windowId).delete();
      _logger.i('✅ InventoryService: Maintenance window $windowId cancelled');
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to cancel maintenance window $windowId', error: e);
      rethrow;
    }
  }

  // ── Booking/maintenance internals ────────────────────────────────────────

  /// Nobody — not even MainAdmin — may approve/book/collect an asset onto
  /// themself; a different MainAdmin/SystemAdmin must always process it, so
  /// custody assignment always has a second traced actor. [actingRole] is
  /// unused now (kept so call sites don't need to change) but retained for
  /// logging/future use.
  void _assertNotSelfAssignment({
    required String actingRole,
    required String actingUid,
    required String targetUid,
  }) {
    if (actingUid == targetUid) {
      throw Exception(
        'You cannot process this for yourself — ask a different MainAdmin or System Admin to handle it.',
      );
    }
  }

  bool _rangesOverlap(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
    return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
  }

  /// Best-effort pre-check (Firestore transactions can't run multi-doc
  /// queries) that a requested window doesn't collide with an existing
  /// scheduled/active booking or a maintenance blackout for the asset.
  Future<void> _assertNoOverlap({
    required String assetId,
    required DateTime start,
    required DateTime end,
  }) async {
    final bookingsSnap = await _firestore
        .collection(_bookingsCollection)
        .where('assetId', isEqualTo: assetId)
        .where('status', whereIn: [AssetBookingModel.statusScheduled, AssetBookingModel.statusActive])
        .get();
    for (final doc in bookingsSnap.docs) {
      final b = AssetBookingModel.fromFirestore(doc);
      if (_rangesOverlap(start, end, b.scheduledStart, b.scheduledEnd)) {
        throw Exception(
          'This window overlaps an existing booking for "${b.assetName}" '
          '(${b.bookedForName}, ${_fmtDate(b.scheduledStart)} - ${_fmtDate(b.scheduledEnd)}).',
        );
      }
    }

    final maintenanceSnap =
        await _firestore.collection(_maintenanceCollection).where('assetId', isEqualTo: assetId).get();
    for (final doc in maintenanceSnap.docs) {
      final m = AssetMaintenanceWindowModel.fromFirestore(doc);
      if (_rangesOverlap(start, end, m.startDate, m.endDate)) {
        throw Exception(
          'This window overlaps a scheduled maintenance period '
          '(${_fmtDate(m.startDate)} - ${_fmtDate(m.endDate)}).',
        );
      }
    }
  }

  /// Recomputes the asset's denormalized "what's coming next" fields from
  /// the soonest remaining `scheduled` booking. Called after any
  /// create/collect/return/cancel booking operation. Best-effort outside a
  /// transaction (display data only — the bookings collection stays the
  /// source of truth for actual conflict checks).
  Future<void> _refreshNextBooking(String assetId) async {
    try {
      final qs = await _firestore
          .collection(_bookingsCollection)
          .where('assetId', isEqualTo: assetId)
          .where('status', isEqualTo: AssetBookingModel.statusScheduled)
          .orderBy('scheduledStart')
          .limit(1)
          .get();
      final assetRef = _firestore.collection(_assetsCollection).doc(assetId);
      if (qs.docs.isEmpty) {
        await assetRef.update({
          'nextBookingId': null,
          'nextBookingStart': null,
          'nextBookingEnd': null,
          'nextBookingByName': null,
        });
      } else {
        final b = AssetBookingModel.fromFirestore(qs.docs.first);
        await assetRef.update({
          'nextBookingId': b.id,
          'nextBookingStart': Timestamp.fromDate(b.scheduledStart),
          'nextBookingEnd': Timestamp.fromDate(b.scheduledEnd),
          'nextBookingByName': b.bookedForName,
        });
      }
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to refresh nextBooking for asset $assetId', error: e);
    }
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  /// A non-manager holder (Technician) signals that they're bringing an
  /// item back. Deliberately does NOT change any state or capture
  /// condition/photos — that stays an admin-only reception judgment call
  /// (see [recordBookingReturn]), so a holder can never self-certify their
  /// own return condition. Just notifies MainAdmin/Admin to go record it.
  /// Marks the asset's `returnRequestedAt` (the current holder signalling
  /// intent) alongside the existing admin broadcast — this is what lets the
  /// MainAdmin/SystemAdmin "Record Return" button stay disabled/faint until
  /// the holder has actually triggered a return, with an explicit override
  /// for when they're unreachable. Firestore rules allow this one-field
  /// write from whoever `currentHolderId` currently is, regardless of role.
  Future<void> notifyReturnIntent({
    required String assetId,
    required String assetName,
    required String holderName,
  }) async {
    try {
      await _firestore.collection(_assetsCollection).doc(assetId).update({
        'returnRequestedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to mark return intent for asset $assetId', error: e);
    }
    await _notifyAdmins(
      title: '📥 Return Incoming',
      body: '$holderName is returning "$assetName" — please record its reception.',
      payload: {'type': 'inventory_return_intent', 'assetId': assetId},
    );
  }

  /// Writes to the shared AdminNotificationQueue collection that
  /// MainAdmin/SystemAdmin listen to at login (see
  /// rbacsystem/notification_service.dart) — reuses the existing "no Cloud
  /// Functions required" broadcast pattern already used for client-request
  /// notifications, rather than building a parallel notification system.
  /// `targetRoles` scopes delivery to MainAdmin+SystemAdmin only — a plain
  /// Admin no longer approves/returns/issues Inventory items, so they no
  /// longer need (or get) these notifications; client-request notifications
  /// (NotificationService.notifyAdminsOfClientRequest) set their own broader
  /// targetRoles on the same collection and are unaffected by this default.
  Future<void> _notifyAdmins({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    try {
      await _firestore.collection(_adminQueueCollection).add({
        'title': title,
        'body': body,
        'payload': ?payload,
        'createdAt': FieldValue.serverTimestamp(),
        'targetRoles': const ['MainAdmin', 'SystemAdmin'],
      });
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to write admin notification', error: e);
    }
  }

  /// Writes to `UserNotificationQueue`, targeted at a single user via
  /// `targetUid` — the counterpart to [_notifyAdmins]'s broadcast, used when
  /// the recipient (e.g. the current holder of a newly-booked asset) isn't
  /// necessarily an Admin/MainAdmin. Delivered the same way: every device
  /// running `NotificationService.setupUserNotificationListener(uid)` picks
  /// it up in real time, plus an FCM push via the `onUserNotificationQueued`
  /// Cloud Function for devices where the app isn't open.
  Future<void> _notifyUser({
    required String targetUid,
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    try {
      await _firestore.collection(_userQueueCollection).add({
        'targetUid': targetUid,
        'title': title,
        'body': body,
        'payload': ?payload,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to write user notification', error: e);
    }
  }

  Future<List<String>> _uploadAssignmentPhotos(
    String assignmentId,
    List<Uint8List> photoBytesList,
    List<String> photoFileNames,
  ) {
    return _uploadPhotos('Inventory/AssetAssignments/$assignmentId', photoBytesList, photoFileNames);
  }

  Future<List<String>> _uploadMovementPhotos(
    String movementId,
    List<Uint8List> photoBytesList,
    List<String> photoFileNames,
  ) {
    return _uploadPhotos('Inventory/MaterialMovements/$movementId', photoBytesList, photoFileNames);
  }

  Future<List<String>> _uploadPhotos(
    String pathPrefix,
    List<Uint8List> photoBytesList,
    List<String> photoFileNames,
  ) async {
    if (photoBytesList.isEmpty) return const [];
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final uploads = <Future<String>>[];
    for (var i = 0; i < photoBytesList.length; i++) {
      final fileName = photoFileNames[i];
      final storageRef = _storage.ref().child('$pathPrefix/${timestamp}_${i}_$fileName');
      uploads.add(
        storageRef
            .putData(photoBytesList[i], SettableMetadata(contentType: _contentTypeFor(fileName)))
            .then((_) => storageRef.getDownloadURL()),
      );
    }
    return Future.wait(uploads);
  }

  // ── Materials ─────────────────────────────────────────────────────────

  Stream<List<MaterialModel>> streamAllMaterials() {
    return _firestore
        .collection(_materialsCollection)
        .orderBy('name')
        .snapshots()
        .map((qs) => qs.docs.map(MaterialModel.fromFirestore).toList())
        .handleError((e) {
      _logger.e('❌ InventoryService: Error streaming all materials', error: e);
      throw e;
    });
  }

  Stream<MaterialModel?> streamMaterial(String materialId) {
    return _firestore
        .collection(_materialsCollection)
        .doc(materialId)
        .snapshots()
        .map((doc) => doc.exists ? MaterialModel.fromFirestore(doc) : null)
        .handleError((e) {
      _logger.e('❌ InventoryService: Error streaming material $materialId', error: e);
      throw e;
    });
  }

  Stream<List<MaterialMovementModel>> streamMaterialHistory(String materialId) {
    return _firestore
        .collection(_movementsCollection)
        .where('materialId', isEqualTo: materialId)
        .orderBy('eventAt', descending: true)
        .snapshots()
        .map((qs) => qs.docs.map(MaterialMovementModel.fromFirestore).toList())
        .handleError((e) {
      _logger.e('❌ InventoryService: Error streaming history for material $materialId', error: e);
      throw e;
    });
  }

  Future<MaterialModel> createMaterial({
    required String name,
    required String category,
    required String unit,
    required String source,
    String? description,
    double initialQuantity = 0,
    double reorderLevel = 0,
    String initialCondition = MaterialModel.conditionGood,
    required String createdByUid,
    required String createdByName,
    Uint8List? photoBytes,
    String? photoFileName,
  }) async {
    try {
      _logger.i('📦 InventoryService: Creating material "$name"');

      final docRef = _firestore.collection(_materialsCollection).doc();
      String? photoUrl;

      if (photoBytes != null && photoFileName != null) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final storageRef = _storage
            .ref()
            .child('Inventory/Materials/${docRef.id}/photo/${timestamp}_$photoFileName');
        final uploadTask = storageRef.putData(
          photoBytes,
          SettableMetadata(contentType: _contentTypeFor(photoFileName)),
        );
        await uploadTask;
        photoUrl = await storageRef.getDownloadURL();
      }

      final now = DateTime.now();
      final material = MaterialModel(
        id: docRef.id,
        name: name,
        category: category,
        unit: unit,
        source: source,
        description: description,
        photoUrl: photoUrl,
        quantityInStorage: initialQuantity,
        reorderLevel: reorderLevel,
        initialCondition: initialCondition,
        createdByUid: createdByUid,
        createdByName: createdByName,
        createdAt: now,
        updatedAt: now,
      );

      await docRef.set(material.toFirestore());
      _logger.i('✅ InventoryService: Material "$name" created (ID: ${docRef.id})');
      return material;
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to create material "$name"', error: e);
      rethrow;
    }
  }

  /// Uploads a replacement catalog photo for an existing material and
  /// returns its download URL — the caller is responsible for saving that
  /// URL via [updateMaterial].
  Future<String> uploadMaterialPhoto({
    required String materialId,
    required Uint8List photoBytes,
    required String photoFileName,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storageRef =
        _storage.ref().child('Inventory/Materials/$materialId/photo/${timestamp}_$photoFileName');
    await storageRef.putData(photoBytes, SettableMetadata(contentType: _contentTypeFor(photoFileName)));
    return storageRef.getDownloadURL();
  }

  /// MainAdmin-only edit of a material's descriptive fields. Never touches
  /// quantityInStorage — that's only ever changed by receipt/issue
  /// transactions, matching the Firestore rule's restricted field set.
  Future<void> updateMaterial({
    required String materialId,
    required String name,
    required String category,
    required String unit,
    required String source,
    String? description,
    double? reorderLevel,
    String? photoUrl,
  }) async {
    try {
      _logger.i('✏️ InventoryService: Updating material $materialId');
      await _firestore.collection(_materialsCollection).doc(materialId).update({
        'name': name,
        'category': category,
        'unit': unit,
        'source': source,
        'description': description,
        'reorderLevel': ?reorderLevel,
        'photoUrl': ?photoUrl,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      _logger.i('✅ InventoryService: Material $materialId updated');
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to update material $materialId', error: e);
      rethrow;
    }
  }

  /// Records stock coming into storage (from local purchase or an
  /// international shipment) and transactionally increases the material's
  /// running quantity balance.
  Future<MaterialMovementModel> recordMaterialReceipt({
    required String materialId,
    required double quantity,
    String? conditionOnReceipt,
    String? portVerifiedByName,
    String? receivedByName,
    required String notes,
    required List<Uint8List> photoBytesList,
    required List<String> photoFileNames,
    required String recordedByUid,
    required String recordedByName,
    required String recordedByRole,
  }) async {
    try {
      _logger.i('📥 InventoryService: Recording receipt of $quantity units for material $materialId');
      final movementRef = _firestore.collection(_movementsCollection).doc();

      final photoUrls = await _uploadMovementPhotos(movementRef.id, photoBytesList, photoFileNames);

      final now = DateTime.now();
      final movement = MaterialMovementModel(
        id: movementRef.id,
        materialId: materialId,
        movementType: MaterialMovementModel.movementReceived,
        quantity: quantity,
        conditionOnReceipt: conditionOnReceipt,
        portVerifiedByName: portVerifiedByName,
        receivedByName: receivedByName,
        notes: notes,
        photoUrls: photoUrls,
        recordedByUid: recordedByUid,
        recordedByName: recordedByName,
        recordedByRole: recordedByRole,
        eventAt: now,
        createdAt: now,
      );

      await _firestore.runTransaction((transaction) async {
        final materialRef = _firestore.collection(_materialsCollection).doc(materialId);
        final materialSnap = await transaction.get(materialRef);
        if (!materialSnap.exists) {
          throw Exception('Material $materialId no longer exists');
        }
        final currentQty = (materialSnap.data()?['quantityInStorage'] as num?)?.toDouble() ?? 0;

        transaction.set(movementRef, movement.toFirestore());
        transaction.update(materialRef, {
          'quantityInStorage': currentQty + quantity,
          'updatedAt': Timestamp.fromDate(now),
        });
      });

      _logger.i('✅ InventoryService: Receipt recorded (ID: ${movementRef.id})');
      return movement;
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to record receipt for material $materialId', error: e);
      rethrow;
    }
  }

  /// Records stock going out of storage to a project/site and
  /// transactionally decreases the material's running quantity balance.
  /// Rejects the write if it would take the balance negative.
  Future<MaterialMovementModel> recordMaterialIssue({
    required String materialId,
    required double quantity,
    String? projectId,
    String? projectName,
    required String notes,
    required List<Uint8List> photoBytesList,
    required List<String> photoFileNames,
    required String recordedByUid,
    required String recordedByName,
    required String recordedByRole,
  }) async {
    try {
      _logger.i('📤 InventoryService: Recording issue of $quantity units for material $materialId');
      final movementRef = _firestore.collection(_movementsCollection).doc();

      final photoUrls = await _uploadMovementPhotos(movementRef.id, photoBytesList, photoFileNames);

      final now = DateTime.now();
      final movement = MaterialMovementModel(
        id: movementRef.id,
        materialId: materialId,
        movementType: MaterialMovementModel.movementIssued,
        quantity: quantity,
        projectId: projectId,
        projectName: projectName,
        notes: notes,
        photoUrls: photoUrls,
        recordedByUid: recordedByUid,
        recordedByName: recordedByName,
        recordedByRole: recordedByRole,
        eventAt: now,
        createdAt: now,
      );

      await _firestore.runTransaction((transaction) async {
        final materialRef = _firestore.collection(_materialsCollection).doc(materialId);
        final materialSnap = await transaction.get(materialRef);
        if (!materialSnap.exists) {
          throw Exception('Material $materialId no longer exists');
        }
        final currentQty = (materialSnap.data()?['quantityInStorage'] as num?)?.toDouble() ?? 0;
        if (quantity > currentQty) {
          throw Exception('Cannot issue $quantity — only $currentQty remaining in storage');
        }

        transaction.set(movementRef, movement.toFirestore());
        transaction.update(materialRef, {
          'quantityInStorage': currentQty - quantity,
          'updatedAt': Timestamp.fromDate(now),
        });
      });

      _logger.i('✅ InventoryService: Issue recorded (ID: ${movementRef.id})');
      return movement;
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to record issue for material $materialId', error: e);
      rethrow;
    }
  }

  // ── Fabrication orders (paper-form chain of custody) ────────────────────
  //
  // Decided per issue, not a fixed material property: an Admin/MainAdmin
  // issuing a material can choose to route it through fabrication. Unlike
  // a plain material issue (recordMaterialIssue, above — one-shot, no
  // multi-party trail), the Driver and Fabricator here have no app account
  // (per the user's explicit choice), so the chain travels on a printed
  // paper form (see fabrication_form_pdf.dart) carrying this order's id as
  // its human-matchable Form ID. Only the final Technician leg is digital —
  // they scan the completed form back in and confirm/correct OCR's
  // best-effort pre-fill before it becomes the authoritative record.

  Stream<List<MaterialFabricationOrderModel>> streamFabricationOrders(String materialId) {
    return _firestore
        .collection(_fabricationOrdersCollection)
        .where('materialId', isEqualTo: materialId)
        .orderBy('issuedAt', descending: true)
        .snapshots()
        .map((qs) => qs.docs.map(MaterialFabricationOrderModel.fromFirestore).toList())
        .handleError((e) {
      _logger.e('❌ InventoryService: Error streaming fabrication orders for material $materialId', error: e);
      throw e;
    });
  }

  /// Orders needing admin attention: still awaiting their scanned form
  /// (issued, not yet uploaded — `statusScanUploaded` is included too for
  /// forward-compatibility, though [submitFabricationFormScan] currently
  /// jumps straight from issued to verified/discrepancy in one step), or
  /// flagged with a quantity mismatch that needs follow-up
  /// (`statusDiscrepancy`) — the admin-facing worklist across every
  /// material, surfaced via [pending_fabrication_orders_screen.dart].
  Stream<List<MaterialFabricationOrderModel>> streamPendingFabricationOrders() {
    return _firestore
        .collection(_fabricationOrdersCollection)
        .where('status', whereIn: [
          MaterialFabricationOrderModel.statusIssued,
          MaterialFabricationOrderModel.statusScanUploaded,
          MaterialFabricationOrderModel.statusDiscrepancy,
        ])
        .orderBy('issuedAt', descending: true)
        .snapshots()
        .map((qs) => qs.docs.map(MaterialFabricationOrderModel.fromFirestore).toList())
        .handleError((e) {
      _logger.e('❌ InventoryService: Error streaming pending fabrication orders', error: e);
      throw e;
    });
  }

  Stream<MaterialFabricationOrderModel?> streamFabricationOrder(String orderId) {
    return _firestore
        .collection(_fabricationOrdersCollection)
        .doc(orderId)
        .snapshots()
        .map((doc) => doc.exists ? MaterialFabricationOrderModel.fromFirestore(doc) : null)
        .handleError((e) {
      _logger.e('❌ InventoryService: Error streaming fabrication order $orderId', error: e);
      throw e;
    });
  }

  /// Admin/MainAdmin issues a quantity of a material for fabrication —
  /// decrements `quantityInStorage` transactionally the same way
  /// [recordMaterialIssue] does, and creates the order doc that the printed
  /// form (see fabrication_form_pdf.dart) and later the scan-upload review
  /// both key off of.
  Future<MaterialFabricationOrderModel> createFabricationOrder({
    required String materialId,
    required String materialName,
    required String unit,
    required double quantity,
    String? projectId,
    String? projectName,
    String? expectedFabricatorName,
    required String issuedByUid,
    required String issuedByName,
  }) async {
    try {
      _logger.i('🏗️ InventoryService: Creating fabrication order for material $materialId ($quantity $unit)');
      final orderRef = _firestore.collection(_fabricationOrdersCollection).doc();
      final now = DateTime.now();
      final order = MaterialFabricationOrderModel(
        id: orderRef.id,
        materialId: materialId,
        materialName: materialName,
        unit: unit,
        quantityIssued: quantity,
        projectId: projectId,
        projectName: projectName,
        expectedFabricatorName: expectedFabricatorName,
        issuedByUid: issuedByUid,
        issuedByName: issuedByName,
        issuedAt: now,
        status: MaterialFabricationOrderModel.statusIssued,
      );

      await _firestore.runTransaction((transaction) async {
        final materialRef = _firestore.collection(_materialsCollection).doc(materialId);
        final materialSnap = await transaction.get(materialRef);
        if (!materialSnap.exists) throw Exception('Material $materialId no longer exists');
        final currentQty = (materialSnap.data()?['quantityInStorage'] as num?)?.toDouble() ?? 0;
        if (quantity > currentQty) {
          throw Exception('Cannot issue $quantity — only $currentQty remaining in storage');
        }

        transaction.set(orderRef, order.toFirestore());
        transaction.update(materialRef, {
          'quantityInStorage': currentQty - quantity,
          'updatedAt': Timestamp.fromDate(now),
        });
      });

      _logger.i('✅ InventoryService: Fabrication order created (ID: ${orderRef.id})');
      return order;
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to create fabrication order for material $materialId', error: e);
      rethrow;
    }
  }

  /// Technician scans the completed paper form back in. Every field here
  /// (except the technician's own live acknowledgment) is a human-reviewed
  /// value the technician confirmed or corrected after reading the physical
  /// form — OCR only ever pre-filled the review screen, it never writes
  /// here directly. Flags `discrepancy` instead of `verified` if the final
  /// received quantity doesn't reconcile with what was issued/fabricated,
  /// within a small tolerance, so an admin can follow up.
  Future<MaterialFabricationOrderModel> submitFabricationFormScan({
    required MaterialFabricationOrderModel order,
    required Uint8List scanBytes,
    required String scanFileName,
    String? ocrRawText,
    Map<String, dynamic>? ocrExtractedFields,
    required double driverAckQuantityAtPickup,
    required String fabricatorName,
    required double fabricatorAckQuantityReceived,
    required String fabricatorAckCondition,
    String? fabricatorDamageNotes,
    required double fabricatorAckQuantityOutput,
    required double driverAckQuantityFromFabricator,
    required double technicianAckQuantityReceived,
    required String technicianAckByUid,
    required String technicianAckByName,
  }) async {
    try {
      _logger.i('📄 InventoryService: Submitting scanned form for fabrication order ${order.id}');
      final scanUrl = await _uploadFabricationScan(order.id, scanBytes, scanFileName);

      const tolerance = 0.01;
      final expectedOutput = order.quantityIssued;
      final hasDiscrepancy =
          (fabricatorAckQuantityReceived - driverAckQuantityAtPickup).abs() > tolerance ||
              (driverAckQuantityFromFabricator - fabricatorAckQuantityOutput).abs() > tolerance ||
              (technicianAckQuantityReceived - driverAckQuantityFromFabricator).abs() > tolerance ||
              (driverAckQuantityAtPickup - expectedOutput).abs() > tolerance;

      final now = DateTime.now();
      final orderRef = _firestore.collection(_fabricationOrdersCollection).doc(order.id);
      await orderRef.update({
        'status': hasDiscrepancy
            ? MaterialFabricationOrderModel.statusDiscrepancy
            : MaterialFabricationOrderModel.statusVerified,
        'scannedFormUrl': scanUrl,
        'ocrRawText': ?ocrRawText,
        'ocrExtractedFields': ?ocrExtractedFields,
        'driverAckQuantityAtPickup': driverAckQuantityAtPickup,
        'fabricatorName': fabricatorName,
        'fabricatorAckQuantityReceived': fabricatorAckQuantityReceived,
        'fabricatorAckCondition': fabricatorAckCondition,
        'fabricatorDamageNotes': ?fabricatorDamageNotes,
        'fabricatorAckQuantityOutput': fabricatorAckQuantityOutput,
        'driverAckQuantityFromFabricator': driverAckQuantityFromFabricator,
        'technicianAckQuantityReceived': technicianAckQuantityReceived,
        'technicianAckByUid': technicianAckByUid,
        'technicianAckByName': technicianAckByName,
        'technicianAckAt': Timestamp.fromDate(now),
        'verifiedByUid': technicianAckByUid,
        'verifiedByName': technicianAckByName,
        'verifiedAt': Timestamp.fromDate(now),
      });

      await _notifyAdmins(
        title: hasDiscrepancy ? '⚠️ Fabrication Form: Discrepancy' : '📄 Fabrication Form Received',
        body: '$technicianAckByName uploaded the completed form for "${order.materialName}"'
            '${hasDiscrepancy ? ' — quantities don\'t reconcile, please review.' : '.'}',
        payload: {'type': 'inventory_fabrication_scan', 'orderId': order.id},
      );

      _logger.i('✅ InventoryService: Fabrication order ${order.id} ${hasDiscrepancy ? 'flagged (discrepancy)' : 'verified'}');

      final saved = await orderRef.get();
      return MaterialFabricationOrderModel.fromFirestore(saved);
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to submit scan for fabrication order ${order.id}', error: e);
      rethrow;
    }
  }

  Future<String> _uploadFabricationScan(String orderId, Uint8List scanBytes, String scanFileName) async {
    final urls = await _uploadPhotos('Inventory/FabricationOrders/$orderId', [scanBytes], [scanFileName]);
    return urls.first;
  }

  String _contentTypeFor(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }
}
