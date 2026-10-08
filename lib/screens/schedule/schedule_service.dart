import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

class ScheduleDocument {
  final String id;
  final String title;
  final String fileName;
  final String url;
  final String fileExtension;
  final DateTime uploadedAt;

  ScheduleDocument({
    required this.id,
    required this.title,
    required this.fileName,
    required this.url,
    required this.fileExtension,
    required this.uploadedAt,
  });

  factory ScheduleDocument.fromFirestore(Map<String, dynamic> data, String id) {
    // Handle the case where uploadedAt might be null (during initial write with serverTimestamp)
    DateTime uploadedAtDate;
    try {
      final uploadedAtField = data['uploadedAt'];
      if (uploadedAtField == null) {
        // If null, use current time as fallback
        uploadedAtDate = DateTime.now();
      } else if (uploadedAtField is Timestamp) {
        uploadedAtDate = uploadedAtField.toDate();
      } else {
        uploadedAtDate = DateTime.now();
      }
    } catch (e) {
      uploadedAtDate = DateTime.now();
    }

    return ScheduleDocument(
      id: id,
      title: data['title'] ?? '',
      fileName: data['fileName'] ?? '',
      url: data['url'] ?? '',
      fileExtension: data['fileExtension'] ?? '',
      uploadedAt: uploadedAtDate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'fileName': fileName,
      'url': url,
      'fileExtension': fileExtension,
      'uploadedAt': Timestamp.fromDate(uploadedAt),
    };
  }
}

class ScheduleService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Get all general schedule documents for a project
  Stream<List<ScheduleDocument>> getGeneralScheduleDocuments(String projectId) {
    return _firestore
        .collection('GeneralSchedules')
        .where('projectId', isEqualTo: projectId)
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ScheduleDocument.fromFirestore(doc.data(), doc.id))
            .toList());
  }

  /// Upload a general schedule document
  Future<void> uploadGeneralScheduleDocument({
    required String projectId,
    required String title,
    required String fileName,
    required List<int> fileBytes,
    required String fileExtension,
  }) async {
    try {
      // Generate a unique file name to avoid conflicts
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final uniqueFileName = '${timestamp}_$fileName';

      // Upload to Firebase Storage
      final storageRef = _storage
          .ref()
          .child('projects/$projectId/generalSchedules/$uniqueFileName');

      final uploadTask = storageRef.putData(
        Uint8List.fromList(fileBytes),
        SettableMetadata(
          contentType: _getContentType(fileExtension),
        ),
      );

      // Wait for upload to complete
      await uploadTask;

      // Get download URL
      final url = await storageRef.getDownloadURL();

      // Save metadata to Firestore (top-level collection with projectId field)
      await _firestore
          .collection('GeneralSchedules')
          .add({
        'projectId': projectId,
        'title': title,
        'fileName': fileName,
        'url': url,
        'fileExtension': fileExtension,
        'uploadedAt': FieldValue.serverTimestamp(),
        'storagePath': 'projects/$projectId/generalSchedules/$uniqueFileName',
      });
    } catch (_) {
      rethrow;
    }
  }

  /// Delete a schedule document
  Future<void> deleteScheduleDocument(String documentId) async {
    try {
      // Get document data to find storage path
      final docSnapshot = await _firestore
          .collection('GeneralSchedules')
          .doc(documentId)
          .get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        final storagePath = data?['storagePath'] as String?;

        // Delete from Storage if path exists
        if (storagePath != null && storagePath.isNotEmpty) {
          try {
            await _storage.ref(storagePath).delete();
          } catch (e) {
            // Continue even if storage deletion fails
            debugPrint('Warning: Could not delete file from storage: $e');
          }
        }

        // Delete from Firestore
        await docSnapshot.reference.delete();
      }
    } catch (_) {
      rethrow;
    }
  }

  /// Helper method to get content type based on file extension
  String _getContentType(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'mpp':
        return 'application/vnd.ms-project';
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