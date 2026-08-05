import 'dart:typed_data';

import 'package:almaworks/models/inventory/asset_assignment_model.dart';
import 'package:almaworks/models/inventory/asset_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:logger/logger.dart';

/// Firestore + Storage access for the Inventory module (Phase 1: Assets).
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
    required String name,
    required String category,
    String? description,
    String? serialNumber,
    required String createdByUid,
    required String createdByName,
    Uint8List? photoBytes,
    String? photoFileName,
  }) async {
    try {
      _logger.i('📦 InventoryService: Creating asset "$name"');

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
        name: name,
        category: category,
        description: description,
        serialNumber: serialNumber,
        photoUrl: photoUrl,
        status: AssetModel.statusAvailable,
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
        final currentStatus = assetSnap.data()?['status'] as String?;
        if (currentStatus != AssetModel.statusAvailable) {
          throw Exception('Asset is not available for checkout (status: $currentStatus)');
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

  Future<List<String>> _uploadAssignmentPhotos(
    String assignmentId,
    List<Uint8List> photoBytesList,
    List<String> photoFileNames,
  ) async {
    if (photoBytesList.isEmpty) return const [];
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final uploads = <Future<String>>[];
    for (var i = 0; i < photoBytesList.length; i++) {
      final fileName = photoFileNames[i];
      final storageRef = _storage
          .ref()
          .child('Inventory/AssetAssignments/$assignmentId/${timestamp}_${i}_$fileName');
      uploads.add(
        storageRef
            .putData(photoBytesList[i], SettableMetadata(contentType: _contentTypeFor(fileName)))
            .then((_) => storageRef.getDownloadURL()),
      );
    }
    return Future.wait(uploads);
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
