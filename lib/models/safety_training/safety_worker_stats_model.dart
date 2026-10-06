import 'package:cloud_firestore/cloud_firestore.dart';

/// One worker's training aggregates (SafetyTrainingWorkerStats/{uid}),
/// maintained server-side by the submitSafetyScenarioAttempt and
/// rebuildSafetyTrainingStats Cloud Functions — so the review roster can
/// show every worker's standing without loading every session ever
/// recorded. Uses the same first-attempt scoring rule as
/// SafetyScoreSummary.fromSessions.
class SafetyWorkerStatsModel {
  final String workerUid;
  final String workerName;
  final String workerRole;
  final int totalAttempts;
  final int scenariosAttempted;
  final int firstTryCorrect;
  final int totalPoints;
  final DateTime? lastAttemptAt;

  /// Scenarios attempted at least once (the keys of the stored first-
  /// attempt map).
  final Set<String> attemptedScenarioIds;

  /// Each attempted scenario's first (scoring) attempt result.
  final Map<String, ({bool correct, int points})> firstAttemptResults;

  /// The scoring (first) attempt's session id per scenario — lets a paged
  /// history label first attempts exactly, without loading every session.
  final Map<String, String> firstAttemptSessionIds;

  /// Most recent attempt per scenario — what retraining progress is
  /// measured against.
  final Map<String, DateTime> lastAttemptAtByScenario;

  const SafetyWorkerStatsModel({
    required this.workerUid,
    required this.workerName,
    required this.workerRole,
    required this.totalAttempts,
    required this.scenariosAttempted,
    required this.firstTryCorrect,
    required this.totalPoints,
    required this.lastAttemptAt,
    required this.attemptedScenarioIds,
    required this.firstAttemptResults,
    required this.firstAttemptSessionIds,
    required this.lastAttemptAtByScenario,
  });

  factory SafetyWorkerStatsModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    final firstAttempts = data['firstAttempts'] as Map<String, dynamic>? ?? const {};
    final lastByScenario = data['lastAttemptAtByScenario'] as Map<String, dynamic>? ?? const {};
    return SafetyWorkerStatsModel(
      workerUid: data['workerUid'] as String? ?? doc.id,
      workerName: data['workerName'] as String? ?? '',
      workerRole: data['workerRole'] as String? ?? '',
      totalAttempts: data['totalAttempts'] as int? ?? 0,
      scenariosAttempted: data['scenariosAttempted'] as int? ?? 0,
      firstTryCorrect: data['firstTryCorrect'] as int? ?? 0,
      totalPoints: data['totalPoints'] as int? ?? 0,
      lastAttemptAt: (data['lastAttemptAt'] as Timestamp?)?.toDate(),
      attemptedScenarioIds: firstAttempts.keys.toSet(),
      firstAttemptResults: {
        for (final entry in firstAttempts.entries)
          if (entry.value is Map)
            entry.key: (
              correct: (entry.value as Map)['correct'] == true,
              points: ((entry.value as Map)['points'] as num?)?.toInt() ?? 0,
            ),
      },
      firstAttemptSessionIds: {
        for (final entry in firstAttempts.entries)
          if (entry.value is Map && (entry.value as Map)['sessionId'] is String)
            entry.key: (entry.value as Map)['sessionId'] as String,
      },
      lastAttemptAtByScenario: {
        for (final entry in lastByScenario.entries)
          if (entry.value is Timestamp) entry.key: (entry.value as Timestamp).toDate(),
      },
    );
  }
}
