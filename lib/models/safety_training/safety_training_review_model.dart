import 'package:cloud_firestore/cloud_firestore.dart';

/// A MainAdmin/SystemAdmin's determination of a worker's overall safety-
/// training standing, based on their accumulated [SafetyTrainingSessionModel]
/// history — append-only, like the session ledger itself (see
/// firestore.rules): once recorded, a review is never edited or deleted. A
/// worker's *current* standing is whichever review has the latest
/// [reviewedAt] for their uid, so re-reviewing a worker adds a new doc
/// rather than overwriting the history of past determinations.
///
/// Each status carries a consequence (enforced by firestore.rules and acted
/// on by the daily sendSafetyTrainingFollowUps Cloud Function):
///   - cleared: lapses at [expiresAt] ([clearanceValidity] after review).
///   - needsRetraining: [assignedScenarioIds] to redo by [dueAt].
///   - escalated: handed to [escalatedToUid] (a MainAdmin/SystemAdmin).
class SafetyTrainingReviewModel {
  static const statusCleared = 'cleared';
  static const statusNeedsRetraining = 'needsRetraining';
  static const statusEscalated = 'escalated';

  /// Stand-in for a review doc with no status field — deliberately not
  /// [statusCleared], so a damaged record never reads as clearance.
  static const statusUnknown = 'unknown';

  /// How long a "Cleared to Work" determination lasts. Must match
  /// CLEARANCE_VALIDITY_DAYS in functions/safetyTraining.js.
  static const clearanceValidity = Duration(days: 90);

  final String id;

  final String workerUid;
  final String workerName;
  final String workerRole;

  final String status;
  final String notes;

  // Snapshot of the worker's score summary at review time, so the record
  // stays meaningful even as later sessions change the live summary (see
  // SafetyScoreSummary — first attempts per scenario are what score).
  // Reviews recorded before first-attempt scoring only carry
  // totalAttempts/correctAttempts/totalPoints over *all* attempts, so
  // [scenariosAttempted]/[firstTryCorrect] are null on those.
  final int totalAttempts;
  final int? scenariosAttempted;
  final int? firstTryCorrect;
  final int totalPoints;

  /// cleared only. Null on clearances recorded before expiry existed —
  /// see [clearanceExpiresAt].
  final DateTime? expiresAt;

  /// needsRetraining only.
  final List<String> assignedScenarioIds;
  final DateTime? dueAt;

  /// escalated only.
  final String? escalatedToUid;
  final String? escalatedToName;

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
    required this.scenariosAttempted,
    required this.firstTryCorrect,
    required this.totalPoints,
    this.expiresAt,
    this.assignedScenarioIds = const [],
    this.dueAt,
    this.escalatedToUid,
    this.escalatedToName,
    required this.reviewedByUid,
    required this.reviewedByName,
    required this.reviewedByRole,
    required this.reviewedAt,
  });

  bool get isCleared => status == statusCleared;
  bool get isNeedsRetraining => status == statusNeedsRetraining;
  bool get isEscalated => status == statusEscalated;

  /// When a clearance lapses; older clearances without [expiresAt] lapse
  /// [clearanceValidity] after they were granted.
  DateTime get clearanceExpiresAt => expiresAt ?? reviewedAt.add(clearanceValidity);

  /// A "Cleared to Work" determination that has lapsed — the worker's
  /// effective standing is then "needs a new review", not cleared.
  bool isClearanceExpired(DateTime now) => isCleared && !now.isBefore(clearanceExpiresAt);

  static String statusLabel(String status) {
    switch (status) {
      case statusCleared:
        return 'Cleared to Work';
      case statusNeedsRetraining:
        return 'Needs Retraining';
      case statusEscalated:
        return 'Escalated';
      case statusUnknown:
        return 'Status Unknown';
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
      status: data['status'] as String? ?? statusUnknown,
      notes: data['notes'] ?? '',
      totalAttempts: data['totalAttempts'] as int? ?? 0,
      scenariosAttempted: data['scenariosAttempted'] as int?,
      firstTryCorrect: data['firstTryCorrect'] as int?,
      totalPoints: data['totalPoints'] as int? ?? 0,
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate(),
      assignedScenarioIds: List<String>.from(data['assignedScenarioIds'] as List? ?? const []),
      dueAt: (data['dueAt'] as Timestamp?)?.toDate(),
      escalatedToUid: data['escalatedToUid'] as String?,
      escalatedToName: data['escalatedToName'] as String?,
      reviewedByUid: data['reviewedByUid'] ?? '',
      reviewedByName: data['reviewedByName'] ?? '',
      reviewedByRole: data['reviewedByRole'] ?? '',
      reviewedAt: (data['reviewedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    final expiresAt = this.expiresAt;
    final dueAt = this.dueAt;
    return {
      'workerUid': workerUid,
      'workerName': workerName,
      'workerRole': workerRole,
      'status': status,
      'notes': notes,
      'totalAttempts': totalAttempts,
      'scenariosAttempted': ?scenariosAttempted,
      'firstTryCorrect': ?firstTryCorrect,
      'totalPoints': totalPoints,
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      if (assignedScenarioIds.isNotEmpty) 'assignedScenarioIds': assignedScenarioIds,
      if (dueAt != null) 'dueAt': Timestamp.fromDate(dueAt),
      'escalatedToUid': ?escalatedToUid,
      'escalatedToName': ?escalatedToName,
      'reviewedByUid': reviewedByUid,
      'reviewedByName': reviewedByName,
      'reviewedByRole': reviewedByRole,
      'reviewedAt': Timestamp.fromDate(reviewedAt),
    };
  }
}

/// Where a worker stands on a "Needs Retraining" determination: which of
/// its assigned scenarios they've attempted since it was recorded.
/// Deactivated scenarios are left out — they can't be played. Must match
/// remainingRetraining() in functions/safetyTraining.js.
class RetrainingProgress {
  final List<String> assigned;
  final List<String> remaining;
  final DateTime? dueAt;

  const RetrainingProgress({required this.assigned, required this.remaining, required this.dueAt});

  /// [lastAttemptAtByScenario]: the worker's most recent attempt per
  /// scenario. [activeScenarioIds]: null while unknown, in which case
  /// nothing is excluded.
  factory RetrainingProgress.of(
    SafetyTrainingReviewModel review,
    Map<String, DateTime> lastAttemptAtByScenario, {
    Set<String>? activeScenarioIds,
  }) {
    final assigned = [
      for (final id in review.assignedScenarioIds)
        if (activeScenarioIds == null || activeScenarioIds.contains(id)) id,
    ];
    final remaining = [
      for (final id in assigned)
        if (!(lastAttemptAtByScenario[id]?.isAfter(review.reviewedAt) ?? false)) id,
    ];
    return RetrainingProgress(assigned: assigned, remaining: remaining, dueAt: review.dueAt);
  }

  int get done => assigned.length - remaining.length;
  bool get isComplete => remaining.isEmpty;
  bool isOverdue(DateTime now) => !isComplete && dueAt != null && now.isAfter(dueAt!);
}
