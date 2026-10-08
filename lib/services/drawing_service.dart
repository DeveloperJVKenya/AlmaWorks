import 'package:almaworks/models/drawing_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:logger/logger.dart';
import 'dart:typed_data';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/errors/friendly_error.dart';

class DrawingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Logger _logger = Logger();

  // Get all drawings for a project
  Stream<List<DrawingModel>> getProjectDrawings(String projectId) {
    _logger.d('🔥 DrawingService: Fetching all drawings for project: $projectId');
    return _firestore
        .collection('Drawings')
        .where('projectId', isEqualTo: projectId)
        .where('isContract', isEqualTo: false) // Exclude contract drawings
        .where('isAsBuilt', isEqualTo: false)  // Exclude as-built drawings
        .orderBy('title')
        .orderBy('revisionNumber', descending: true)
        .snapshots()
        .map((snapshot) {
      final drawings = snapshot.docs.map((doc) => DrawingModel.fromFirestore(doc)).toList();
      _logger.d('🔥 DrawingService: Fetched ${drawings.length} drawings for project: $projectId');
      return drawings;
    }).handleError((e) {
      _logger.e('❌ DrawingService: Error fetching project drawings', error: e);
      throw e;
    });
  }

  // Get revision drawings (not as-built)
  Stream<List<DrawingModel>> getRevisionDrawings(String projectId) {
    _logger.d('🔥 DrawingService: Fetching revision drawings for project: $projectId');
    return _firestore
        .collection('Drawings')
        .where('projectId', isEqualTo: projectId)
        .where('isAsBuilt', isEqualTo: false)
        .where('isContract', isEqualTo: false) // Exclude contract drawings
        .orderBy('title')
        .orderBy('revisionNumber', descending: true)
        .snapshots()
        .map((snapshot) {
      final drawings = snapshot.docs.map((doc) => DrawingModel.fromFirestore(doc)).toList();
      _logger.d('🔥 DrawingService: Fetched ${drawings.length} revision drawings for project: $projectId');
      return drawings;
    }).handleError((e) {
      _logger.e('❌ DrawingService: Error fetching revision drawings', error: e);
      throw e;
    });
  }

  // Get as-built drawings
  Stream<List<DrawingModel>> getAsBuiltDrawings(String projectId) {
    _logger.d('📥 DrawingService: Fetching as-built drawings for project: $projectId');
    return _firestore
        .collection('Drawings')
        .where('projectId', isEqualTo: projectId)
        .where('isAsBuilt', isEqualTo: true)
        .orderBy('finalizedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final drawings = snapshot.docs.map((doc) => DrawingModel.fromFirestore(doc)).toList();
      _logger.d('📥 DrawingService: Fetched ${drawings.length} as-built drawings for project: $projectId');
      return drawings;
    }).handleError((e) {
      _logger.e('❌ DrawingService: Error fetching as-built drawings', error: e);
      throw e;
    });
  }

  // Group drawings by title
  List<DrawingGroup> groupDrawingsByTitle(List<DrawingModel> drawings) {
    _logger.d('📋 DrawingService: Grouping ${drawings.length} drawings by title');
    final Map<String, List<DrawingModel>> groupedDrawings = {};

    for (final drawing in drawings) {
      if (!groupedDrawings.containsKey(drawing.title)) {
        groupedDrawings[drawing.title] = [];
      }
      groupedDrawings[drawing.title]!.add(drawing);
    }

    final groups = groupedDrawings.entries
        .map((entry) => DrawingGroup.fromDrawings(entry.key, entry.value))
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));

    _logger.d('📋 DrawingService: Created ${groups.length} drawing groups');
    return groups;
  }

  // Upload new drawing
  Future<DrawingModel> uploadDrawing({
    required String projectId,
    required String title,
    required String fileName,
    required List<int> fileBytes,
    required String fileExtension,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      _logger.i('📤 DrawingService: Starting upload for $fileName with title: $title');

      // Validate title for revision uploads
      final existingDrawings = await _firestore
          .collection('Drawings')
          .where('projectId', isEqualTo: projectId)
          .where('title', isEqualTo: title)
          .where('isContract', isEqualTo: false) // Only check non-contract drawings
          .where('isAsBuilt', isEqualTo: false)  // Only check non-as-built drawings
          .get();

      final isNewCategory = existingDrawings.docs.isEmpty;
      _logger.d('📤 DrawingService: Is new category? $isNewCategory');

      if (!isNewCategory) {
        _logger.d('📤 DrawingService: Existing title found, treating as revision');
      } else {
        _logger.d('📤 DrawingService: New title, creating new category');
      }

      // Get next revision number for this title
      final nextRevision = isNewCategory
          ? 1
          : existingDrawings.docs
                  .map((doc) => (doc.data()['revisionNumber'] as int?) ?? 1)
                  .reduce((a, b) => a > b ? a : b) +
              1;

      _logger.d('📤 DrawingService: Assigned revision number: $nextRevision');

      // Validate file size (e.g., max 100MB)
      const maxSizeBytes = 100 * 1024 * 1024; // 100MB
      if (fileBytes.length > maxSizeBytes) {
        _logger.e('❌ DrawingService: File size exceeds limit (${fileBytes.length} bytes > $maxSizeBytes bytes)');
        throw UserFacingException(l10nNow.fileTooLarge100);
      }

      // Upload to Firebase Storage
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = _storage
          .ref()
          .child('$projectId/Drawings/$title/rev_${nextRevision}_${timestamp}_$fileName');

      _logger.d('📤 DrawingService: Uploading to storage path: ${storageRef.fullPath}');

      final uploadTask = storageRef.putData(
        Uint8List.fromList(fileBytes),
        SettableMetadata(
          contentType: _getContentType(fileExtension),
          customMetadata: {
            'projectId': projectId,
            'title': title,
            'revisionNumber': nextRevision.toString(),
            'isContract': 'false',
            'isAsBuilt': 'false', // Explicitly set to false
            ...?metadata,
          },
        ),
      );

      await uploadTask;
      final downloadUrl = await storageRef.getDownloadURL();
      _logger.d('📤 DrawingService: File uploaded, download URL: $downloadUrl');

      // Create drawing document
      final drawing = DrawingModel(
        id: '', // Will be set by Firestore
        projectId: projectId,
        title: title,
        fileName: fileName,
        url: downloadUrl,
        type: fileExtension,
        revisionNumber: nextRevision,
        uploadedAt: DateTime.now(),
        isContract: false, // Explicitly set to false for revision drawings
        isAsBuilt: false,  // Explicitly set to false for revision drawings
        isFinal: false,    // Explicitly set to false for revision drawings
        metadata: metadata,
      );

      // Save to Firestore
      final docRef = await _firestore
          .collection('Drawings')
          .add(drawing.toFirestore());

      _logger.i('✅ DrawingService: Upload completed for $fileName (ID: ${docRef.id})');
      return drawing.copyWith(id: docRef.id);
    } catch (e) {
      _logger.e('❌ DrawingService: Upload failed for $fileName', error: e);
      rethrow;
    }
  }

  // Add to drawing_service.dart
  Future<DrawingModel> uploadAsBuiltDrawing({
    required String projectId,
    required String title,
    required String fileName,
    required List<int> fileBytes,
    required String fileExtension,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      _logger.i('📤 DrawingService: Starting as-built drawing upload for $fileName with title: $title');

      // Validate file size (e.g., max 100MB)
      const maxSizeBytes = 100 * 1024 * 1024; // 100MB
      if (fileBytes.length > maxSizeBytes) {
        _logger.e('❌ DrawingService: File size exceeds limit (${fileBytes.length} bytes > $maxSizeBytes bytes)');
        throw UserFacingException(l10nNow.fileTooLarge100);
      }

      // Upload to Firebase Storage
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = _storage
          .ref()
          .child('$projectId/Drawings/as-built/${timestamp}_$fileName');

      _logger.d('📤 DrawingService: Uploading to storage path: ${storageRef.fullPath}');

      final uploadTask = storageRef.putData(
        Uint8List.fromList(fileBytes),
        SettableMetadata(
          contentType: _getContentType(fileExtension),
          customMetadata: {
            'projectId': projectId,
            'title': title,
            'isAsBuilt': 'true',
            ...?metadata,
          },
        ),
      );

      await uploadTask;
      final downloadUrl = await storageRef.getDownloadURL();
      _logger.d('📤 DrawingService: File uploaded, download URL: $downloadUrl');

      // Create drawing document
      final drawing = DrawingModel(
        id: '', // Will be set by Firestore
        projectId: projectId,
        title: title,
        fileName: fileName,
        url: downloadUrl,
        type: fileExtension,
        revisionNumber: 0, // As-Built drawings don't have revisions
        uploadedAt: DateTime.now(),
        isAsBuilt: true, // Mark as as-built drawing
        isFinal: true, // Mark as final
        isContract: false,
        finalizedAt: DateTime.now(),
        metadata: metadata,
      );

      // Save to Firestore
      final docRef = await _firestore
          .collection('Drawings')
          .add(drawing.toFirestore());

      _logger.i('✅ DrawingService: As-Built drawing upload completed for $fileName (ID: ${docRef.id})');
      return drawing.copyWith(id: docRef.id);
    } catch (e) {
      _logger.e('❌ DrawingService: As-Built drawing upload failed for $fileName', error: e);
      rethrow;
    }
  }

  // Mark revision as final and move to as-built
  Future<DrawingModel> markAsFinal(String drawingId) async {
    try {
      _logger.i('🏁 DrawingService: Marking drawing as final: $drawingId');

      final drawingDoc = await _firestore
          .collection('Drawings')
          .doc(drawingId)
          .get();

      if (!drawingDoc.exists) {
        _logger.e('❌ DrawingService: Drawing not found: $drawingId');
        throw UserFacingException(l10nNow.drawingNotFound);
      }

      final drawing = DrawingModel.fromFirestore(drawingDoc);

      // Check if there's already a final revision for this title
      final existingFinal = await _firestore
          .collection('Drawings')
          .where('projectId', isEqualTo: drawing.projectId)
          .where('title', isEqualTo: drawing.title)
          .where('isFinal', isEqualTo: true)
          .get();

      if (existingFinal.docs.isNotEmpty) {
        _logger.d('🏁 DrawingService: Found ${existingFinal.docs.length} existing final revisions for title: ${drawing.title}');
        // Remove final status from existing final revision
        for (final doc in existingFinal.docs) {
          await doc.reference.update({
            'isFinal': false,
            'isAsBuilt': false,
          });
          _logger.d('🏁 DrawingService: Removed final status from drawing: ${doc.id}');
        }
      }

      // Update current drawing as final and as-built
      await _firestore.collection('Drawings').doc(drawingId).update({
        'isFinal': true,
        'isAsBuilt': true,
        'finalizedAt': Timestamp.now(),
      });

      _logger.i('✅ DrawingService: Drawing marked as final: $drawingId');
      return drawing.copyWith(
        isFinal: true,
        isAsBuilt: true,
        finalizedAt: DateTime.now(),
      );
    } catch (e) {
      _logger.e('❌ DrawingService: Failed to mark as final: $drawingId', error: e);
      rethrow;
    }
  }

  // Delete drawing
  Future<void> deleteDrawing(String drawingId) async {
    try {
      _logger.i('🗑️ DrawingService: Deleting drawing: $drawingId');

      final drawingDoc = await _firestore
          .collection('Drawings')
          .doc(drawingId)
          .get();

      if (!drawingDoc.exists) {
        _logger.e('❌ DrawingService: Drawing not found: $drawingId');
        throw UserFacingException(l10nNow.drawingNotFound);
      }

      final drawing = DrawingModel.fromFirestore(drawingDoc);

      // Delete from Storage
      final ref = _storage.refFromURL(drawing.url);
      await ref.delete();
      _logger.d('🗑️ DrawingService: Deleted file from storage: ${drawing.url}');

      // Delete from Firestore
      await _firestore.collection('Drawings').doc(drawingId).delete();
      _logger.d('🗑️ DrawingService: Deleted document from Firestore: $drawingId');

      _logger.i('✅ DrawingService: Drawing deleted successfully: $drawingId');
    } catch (e) {
      _logger.e('❌ DrawingService: Failed to delete drawing: $drawingId', error: e);
      rethrow;
    }
  }

  Stream<List<DrawingModel>> getContractDrawings(String projectId) {
    _logger.d('🔥 DrawingService: Fetching contract drawings for project: $projectId');
    return _firestore
        .collection('Drawings')
        .where('projectId', isEqualTo: projectId)
        .where('isContract', isEqualTo: true)
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final drawings = snapshot.docs.map((doc) => DrawingModel.fromFirestore(doc)).toList();
      _logger.d('🔥 DrawingService: Fetched ${drawings.length} contract drawings for project: $projectId');
      return drawings;
    }).handleError((e) {
      _logger.e('❌ DrawingService: Error fetching contract drawings', error: e);
      throw e;
    });
  }

  Future<DrawingModel> uploadContractDrawing({
    required String projectId,
    required String title,
    required String fileName,
    required List<int> fileBytes,
    required String fileExtension,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      _logger.i('📤 DrawingService: Starting contract drawing upload for $fileName with title: $title');

      // Validate file size (e.g., max 100MB)
      const maxSizeBytes = 100 * 1024 * 1024; // 100MB
      if (fileBytes.length > maxSizeBytes) {
        _logger.e('❌ DrawingService: File size exceeds limit (${fileBytes.length} bytes > $maxSizeBytes bytes)');
        throw UserFacingException(l10nNow.fileTooLarge100);
      }

      // Upload to Firebase Storage
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = _storage
          .ref()
          .child('$projectId/Drawings/contract/${timestamp}_$fileName');

      _logger.d('📤 DrawingService: Uploading to storage path: ${storageRef.fullPath}');

      final uploadTask = storageRef.putData(
        Uint8List.fromList(fileBytes),
        SettableMetadata(
          contentType: _getContentType(fileExtension),
          customMetadata: {
            'projectId': projectId,
            'title': title,
            'isContract': 'true',
            ...?metadata,
          },
        ),
      );

      await uploadTask;
      final downloadUrl = await storageRef.getDownloadURL();
      _logger.d('📤 DrawingService: File uploaded, download URL: $downloadUrl');

      // Create drawing document
      final drawing = DrawingModel(
        id: '', // Will be set by Firestore
        projectId: projectId,
        title: title,
        fileName: fileName,
        url: downloadUrl,
        type: fileExtension,
        revisionNumber: 0, // Contract drawings don't have revisions
        uploadedAt: DateTime.now(),
        isContract: true, // Mark as contract drawing
        metadata: metadata,
      );

      // Save to Firestore
      final docRef = await _firestore
          .collection('Drawings')
          .add(drawing.toFirestore());

      _logger.i('✅ DrawingService: Contract drawing upload completed for $fileName (ID: ${docRef.id})');
      return drawing.copyWith(id: docRef.id);
    } catch (e) {
      _logger.e('❌ DrawingService: Contract drawing upload failed for $fileName', error: e);
      rethrow;
    }
  }

  String _getContentType(String extension) {
    _logger.d('📋 DrawingService: Getting content type for extension: $extension');
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'dwg':
        return 'application/acad';
      case 'dxf':
        return 'application/dxf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }
}