import 'package:almaworks/models/safety_training/safety_scenario_model.dart';
import 'package:almaworks/models/safety_training/safety_training_feedback_model.dart';
import 'package:almaworks/models/safety_training/safety_training_review_model.dart';
import 'package:almaworks/models/safety_training/safety_training_session_model.dart';
import 'package:almaworks/models/safety_training/safety_worker_stats_model.dart';
import 'package:almaworks/notifications/notification_providers.dart';
import 'package:almaworks/services/safety_training_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Riverpod state for the Safety Training section. Every screen reads the
/// signed-in user and its data from here instead of opening its own
/// Firestore listeners, so streams are shared between screens, cached
/// while in use, and torn down (autoDispose) once nothing watches them.

final safetyServiceProvider = Provider<SafetyTrainingService>((ref) => SafetyTrainingService());

/// The signed-in user as Safety Training sees them. [role] comes from the
/// UserRoles mirror — what firestore.rules and the grading function
/// authorize against — so the UI never offers what the backend refuses.
class SafetyUser {
  final String uid;
  final String name;

  /// Null when the account has no UserRoles mirror doc.
  final String? role;

  const SafetyUser({required this.uid, required this.name, required this.role});

  bool get roleMissing => role == null;
  bool get isAdmin => const {'MainAdmin', 'Admin', 'SystemAdmin'}.contains(role);

  /// Reviewing standing is a MainAdmin/SystemAdmin decision.
  bool get isReviewer => const {'MainAdmin', 'SystemAdmin'}.contains(role);
  String get displayName => name.isEmpty ? 'there' : name;
}

final safetyUserProvider = FutureProvider.autoDispose<SafetyUser?>((ref) async {
  final uid = ref.watch(authUidProvider).valueOrNull;
  if (uid == null) return null;
  final service = ref.watch(safetyServiceProvider);
  final results = await Future.wait([
    service.fetchRole(uid),
    FirebaseFirestore.instance.collection('Users').where('uid', isEqualTo: uid).limit(1).get(),
  ]);
  final users = results[1] as QuerySnapshot<Map<String, dynamic>>;
  return SafetyUser(uid: uid, name: users.docs.isEmpty ? '' : users.docs.first.id, role: results[0] as String?);
});

// ── Scenarios ───────────────────────────────────────────────────────────

final activeScenariosProvider = StreamProvider.autoDispose<List<SafetyScenarioModel>>(
  (ref) => ref.watch(safetyServiceProvider).streamActiveScenarios(),
);

final allScenariosProvider = StreamProvider.autoDispose<List<SafetyScenarioModel>>(
  (ref) => ref.watch(safetyServiceProvider).streamAllScenarios(),
);

// ── One worker ──────────────────────────────────────────────────────────

final workerStatsProvider = StreamProvider.autoDispose.family<SafetyWorkerStatsModel?, String>(
  (ref, uid) => ref.watch(safetyServiceProvider).streamWorkerStats(uid),
);

/// Every session for one worker (used only until their stats doc exists).
final workerAllSessionsProvider = StreamProvider.autoDispose.family<List<SafetyTrainingSessionModel>, String>(
  (ref, uid) => ref.watch(safetyServiceProvider).streamWorkerSessions(uid),
);

final latestReviewProvider = StreamProvider.autoDispose.family<SafetyTrainingReviewModel?, String>(
  (ref, uid) => ref.watch(safetyServiceProvider).streamLatestReviewForWorker(uid),
);

/// The worker's training progress: from their server-maintained stats
/// doc, or — before it exists — derived from their sessions with the same
/// first-attempt rule.
class WorkerProgress {
  final SafetyScoreSummary summary;
  final Map<String, ({bool correct, int points})> firstAttemptResults;
  final Map<String, DateTime> lastAttemptAtByScenario;

  const WorkerProgress(this.summary, this.firstAttemptResults, this.lastAttemptAtByScenario);

  static const empty = WorkerProgress(SafetyScoreSummary.empty, {}, {});

  factory WorkerProgress.fromStats(SafetyWorkerStatsModel stats) =>
      WorkerProgress(SafetyScoreSummary.fromStats(stats), stats.firstAttemptResults, stats.lastAttemptAtByScenario);

  factory WorkerProgress.fromSessions(List<SafetyTrainingSessionModel> sessions) {
    final summary = SafetyScoreSummary.fromSessions(sessions);
    final lastByScenario = <String, DateTime>{};
    for (final s in sessions) {
      final last = lastByScenario[s.scenarioId];
      if (last == null || s.completedAt.isAfter(last)) lastByScenario[s.scenarioId] = s.completedAt;
    }
    return WorkerProgress(summary, {
      for (final e in summary.firstAttemptByScenario.entries)
        e.key: (correct: e.value.isCorrect, points: e.value.pointsEarned),
    }, lastByScenario);
  }
}

final workerProgressProvider = Provider.autoDispose.family<AsyncValue<WorkerProgress>, String>((ref, uid) {
  final stats = ref.watch(workerStatsProvider(uid));
  return stats.when(
    loading: () => const AsyncLoading(),
    error: (e, st) => AsyncError(e, st),
    data: (s) {
      if (s != null) return AsyncData(WorkerProgress.fromStats(s));
      return ref.watch(workerAllSessionsProvider(uid)).whenData(WorkerProgress.fromSessions);
    },
  );
});

// ── History ─────────────────────────────────────────────────────────────

/// A page of history: one worker's sessions, or everyone's (workerUid null).
typedef HistoryQuery = ({String? workerUid, int limit});

final historySessionsProvider = StreamProvider.autoDispose.family<List<SafetyTrainingSessionModel>, HistoryQuery>((
  ref,
  q,
) {
  final service = ref.watch(safetyServiceProvider);
  return q.workerUid != null
      ? service.streamWorkerSessions(q.workerUid!, limit: q.limit)
      : service.streamAllSessions(limit: q.limit);
});

/// Feedback for one worker, or the most recent across everyone (null).
final feedbackProvider = StreamProvider.autoDispose.family<List<SafetyTrainingFeedbackModel>, String?>((
  ref,
  workerUid,
) {
  final service = ref.watch(safetyServiceProvider);
  return workerUid != null ? service.streamFeedbackForWorker(workerUid) : service.streamRecentFeedback(limit: 300);
});

// ── Reviewer data ───────────────────────────────────────────────────────

final allWorkerStatsProvider = StreamProvider.autoDispose<List<SafetyWorkerStatsModel>>(
  (ref) => ref.watch(safetyServiceProvider).streamAllWorkerStats(),
);

final allReviewsProvider = StreamProvider.autoDispose<List<SafetyTrainingReviewModel>>(
  (ref) => ref.watch(safetyServiceProvider).streamAllReviews(),
);

final traineesProvider = StreamProvider.autoDispose<List<SafetyTrainee>>(
  (ref) => ref.watch(safetyServiceProvider).streamTrainees(),
);

final reviewersProvider = StreamProvider.autoDispose<List<SafetyTrainee>>(
  (ref) => ref.watch(safetyServiceProvider).streamReviewers(),
);

/// Builds every worker's stats doc from history the first time a reviewer
/// opens the review screen after stats docs were introduced. Resolves to
/// how many workers were rebuilt (0 when already built).
final ensureStatsBuiltProvider = FutureProvider.autoDispose<int>((ref) async {
  final service = ref.watch(safetyServiceProvider);
  if (await service.areWorkerStatsBuilt()) return 0;
  return service.rebuildWorkerStats();
});

/// Each worker's current standing: their newest review.
final latestReviewByWorkerProvider = Provider.autoDispose<Map<String, SafetyTrainingReviewModel>>((ref) {
  final reviews = ref.watch(allReviewsProvider).valueOrNull ?? const [];
  final latest = <String, SafetyTrainingReviewModel>{};
  for (final r in reviews) {
    latest.putIfAbsent(r.workerUid, () => r); // streamed newest-first
  }
  return latest;
});
