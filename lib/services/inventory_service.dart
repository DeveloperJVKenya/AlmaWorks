import 'dart:typed_data';

import 'package:almaworks/models/inventory/asset_assignment_model.dart';
import 'package:almaworks/models/inventory/asset_model.dart';
import 'package:almaworks/models/inventory/checkout_request_model.dart';
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
  static const _requestsCollection = 'InventoryCheckoutRequests';
  static const _adminQueueCollection = 'AdminNotificationQueue';

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

  /// Admin submits a request to check out an Available asset/tool. Locks
  /// the asset (`pendingRequestId`) so no other Admin can request it and it
  /// can't be checked out any other way until a MainAdmin approves/rejects.
  Future<CheckoutRequestModel> createCheckoutRequest({
    required String assetId,
    required String assetName,
    required String itemType,
    required String requestedByUid,
    required String requestedByName,
    String? projectId,
    String? projectName,
    required String reason,
  }) async {
    try {
      _logger.i('📝 InventoryService: $requestedByName requesting checkout of $assetName');
      final requestRef = _firestore.collection(_requestsCollection).doc();
      final now = DateTime.now();
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
        status: CheckoutRequestModel.statusPending,
        requestedAt: now,
      );

      await _firestore.runTransaction((transaction) async {
        final assetRef = _firestore.collection(_assetsCollection).doc(assetId);
        final assetSnap = await transaction.get(assetRef);
        if (!assetSnap.exists) throw Exception('Asset $assetId no longer exists');
        final data = assetSnap.data()!;
        if (data['status'] != AssetModel.statusAvailable) {
          throw Exception('Asset is not available to request');
        }
        if (data['pendingRequestId'] != null) {
          throw Exception('Asset already has a pending request');
        }

        transaction.set(requestRef, request.toFirestore());
        transaction.update(assetRef, {
          'pendingRequestId': requestRef.id,
          'updatedAt': Timestamp.fromDate(now),
        });
      });

      await _notifyAdmins(
        title: '📦 Checkout Request',
        body: '$requestedByName requested to check out "$assetName"'
            '${projectName != null ? ' for $projectName' : ''}.',
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

      _logger.i('✅ InventoryService: Request $requestId rejected');
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to reject request $requestId', error: e);
      rethrow;
    }
  }

  /// MainAdmin approves a pending request — this IS the actual checkout:
  /// condition + photos are captured here as the handover confirmation, in
  /// the same transaction that creates the immutable ledger entry and
  /// resolves the request.
  Future<AssetAssignmentModel> approveCheckoutRequest({
    required CheckoutRequestModel request,
    required String conditionNotes,
    required List<Uint8List> photoBytesList,
    required List<String> photoFileNames,
    required String respondedByUid,
    required String respondedByName,
    required String respondedByRole,
  }) async {
    try {
      _logger.i('✅ InventoryService: Approving checkout request ${request.id}');
      final assignmentRef = _firestore.collection(_assignmentsCollection).doc();

      final photoUrls = await _uploadAssignmentPhotos(assignmentRef.id, photoBytesList, photoFileNames);

      final now = DateTime.now();
      final assignment = AssetAssignmentModel(
        id: assignmentRef.id,
        assetId: request.assetId,
        eventType: AssetAssignmentModel.eventCheckout,
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
        if (assetData['status'] != AssetModel.statusAvailable ||
            assetData['pendingRequestId'] != request.id) {
          throw Exception('Asset state no longer matches this request');
        }

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
        transaction.update(requestRef, {
          'status': CheckoutRequestModel.statusApproved,
          'respondedByUid': respondedByUid,
          'respondedByName': respondedByName,
          'respondedAt': Timestamp.fromDate(now),
        });
      });

      await _notifyAdmins(
        title: '✅ Checkout Approved',
        body: '$respondedByName approved ${request.requestedByName}\'s request for "${request.assetName}".',
        payload: {'type': 'inventory_checkout_approved', 'requestId': request.id, 'assetId': request.assetId},
      );

      _logger.i('✅ InventoryService: Request ${request.id} approved (assignment ${assignmentRef.id})');
      return assignment;
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to approve request ${request.id}', error: e);
      rethrow;
    }
  }

  /// Writes to the shared AdminNotificationQueue collection that every
  /// Admin/MainAdmin already listens to at login (see
  /// rbacsystem/notification_service.dart) — reuses the existing "no Cloud
  /// Functions required" broadcast pattern already used for client-request
  /// notifications, rather than building a parallel notification system.
  /// Note: this broadcasts to ALL currently-listening Admin/MainAdmin
  /// devices (there's no per-user-targeted push in this app), so both the
  /// requester and other admins may see each notification.
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
      });
    } catch (e) {
      _logger.e('❌ InventoryService: Failed to write admin notification', error: e);
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
