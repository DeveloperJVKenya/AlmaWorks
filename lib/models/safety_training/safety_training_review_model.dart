import 'package:cloud_firestore/cloud_firestore.dart';

/// A MainAdmin/SystemAdmin's determination of a worker's overall safety-
/// training standing, based on their accumulated [SafetyTrainingSessionModel]
/// history — append-only, like the session ledger itself (see
/// firestore.rules): once recorded, a review is never edited or deleted. A
/// worker's *current* standing is whichever review has the latest
/// [reviewedAt] for their uid, so re-reviewing a worker adds a new doc
/// rather than overwriting the history of past determinations.
class SafetyTrainingReviewModel {
  static const statusCleared = 'cleared';
  static const statusNeedsRetraining = 'needsRetraining';
  static const statusEscalated = 'escalated';

  final String id;

  final String workerUid;
  final String workerName;
  final String workerRole;

  final String status;
  final String notes;

  // Snapshot of the worker's score summary at review time, so the record
  // stays meaningful even as later sessions change the live summary.
  final int totalAttempts;
  final int correctAttempts;
  final int totalPoints;

  final String reviewedByUid;
  final String reviewedByName;
  final String reviewedByRole;
  final DateTime reviewedAt;

  const SafetyTrainingReviewModel({
    required this.id,
    required this.workerUid,
    required this.workerName,
    required this.workerRole,
    required this.status,
    required this.notes,
    required this.totalAttempts,
    required this.correctAttempts,
    required this.totalPoints,
    required this.reviewedByUid,
    required this.reviewedByName,
    required this.reviewedByRole,
    required this.reviewedAt,
  });

  bool get isCleared => status == statusCleared;
  bool get isNeedsRetraining => status == statusNeedsRetraining;
  bool get isEscalated => status == statusEscalated;

  static String statusLabel(String status) {
    switch (status) {
      case statusCleared:
        return 'Cleared to Work';
      case statusNeedsRetraining:
        return 'Needs Retraining';
      case statusEscalated:
        return 'Escalated';
      default:
        return status;
    }
  }

  factory SafetyTrainingReviewModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    return SafetyTrainingReviewModel(
      id: doc.id,
      workerUid: data['workerUid'] ?? '',
      workerName: data['workerName'] ?? '',
      workerRole: data['workerRole'] ?? '',
      status: data['status'] ?? statusCleared,
      notes: data['notes'] ?? '',
      totalAttempts: data['totalAttempts'] as int? ?? 0,
      correctAttempts: data['correctAttempts'] as int? ?? 0,
      totalPoints: data['totalPoints'] as int? ?? 0,
      reviewedByUid: data['reviewedByUid'] ?? '',
      reviewedByName: data['reviewedByName'] ?? '',
      reviewedByRole: data['reviewedByRole'] ?? '',
      reviewedAt: (data['reviewedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'workerUid': workerUid,
      'workerName': workerName,
      'workerRole': workerRole,
      'status': status,
      'notes': notes,
      'totalAttempts': totalAttempts,
      'correctAttempts': correctAttempts,
      'totalPoints': totalPoints,
      'reviewedByUid': reviewedByUid,
      'reviewedByName': reviewedByName,
      'reviewedByRole': reviewedByRole,
      'reviewedAt': Timestamp.fromDate(reviewedAt),
    };
  }
}
