import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:almaworks/models/safety_training/safety_scenario_model.dart';
import 'package:almaworks/models/safety_training/safety_training_feedback_model.dart';
import 'package:almaworks/models/safety_training/safety_training_review_model.dart';
import 'package:almaworks/models/safety_training/safety_training_session_model.dart';
import 'package:almaworks/models/safety_training/safety_worker_stats_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logger/logger.dart';

/// Per-worker aggregate safety-awareness rating, derived on the fly from
/// [SafetyTrainingSessionModel] history rather than stored as a maintained
/// counter doc — avoids a second write path that could drift from the
/// append-only session ledger it would be summarizing.
///
/// Only a worker's *first* attempt at each scenario counts toward points
/// and accuracy — later attempts, made after seeing the answer, are
/// practice. Determined here from completedAt order rather than trusting
/// the session's own isFirstAttempt flag, so sessions recorded before that
/// flag (or before server-side grading) are scored by the same rule.
class SafetyScoreSummary {
  /// Every recorded attempt, practice included.
  final int totalAttempts;

  /// Distinct scenarios the worker has attempted at least once.
  final int scenariosAttempted;

  /// Scenarios whose first attempt was correct.
  final int firstTryCorrect;

  /// Points from first attempts only.
  final int totalPoints;

  /// Each attempted scenario's first attempt, keyed by scenarioId. Empty
  /// for a summary built [SafetyScoreSummary.fromStats].
  final Map<String, SafetyTrainingSessionModel> firstAttemptByScenario;

  /// Scenarios attempted at least once.
  final Set<String> attemptedScenarioIds;

  const SafetyScoreSummary({
    required this.totalAttempts,
    required this.scenariosAttempted,
    required this.firstTryCorrect,
    required this.totalPoints,
    this.firstAttemptByScenario = const {},
    this.attemptedScenarioIds = const {},
  });

  /// First-try accuracy across attempted scenarios.
  double get accuracy => scenariosAttempted == 0 ? 0 : firstTryCorrect / scenariosAttempted;

  /// How many of [activeScenarioIds] the worker has attempted.
  int completedOf(Iterable<String> activeScenarioIds) => activeScenarioIds.where(attemptedScenarioIds.contains).length;

  static const empty = SafetyScoreSummary(totalAttempts: 0, scenariosAttempted: 0, firstTryCorrect: 0, totalPoints: 0);

  /// Summarizes one worker's sessions (in any order).
  factory SafetyScoreSummary.fromSessions(Iterable<SafetyTrainingSessionModel> sessions) {
    final firstByScenario = <String, SafetyTrainingSessionModel>{};
    var total = 0;
    for (final session in sessions) {
      total++;
      final current = firstByScenario[session.scenarioId];
      if (current == null || session.completedAt.isBefore(current.completedAt)) {
        firstByScenario[session.scenarioId] = session;
      }
    }
    final firsts = firstByScenario.values;
    return SafetyScoreSummary(
      totalAttempts: total,
      scenariosAttempted: firstByScenario.length,
      firstTryCorrect: firsts.where((s) => s.isCorrect).length,
      totalPoints: firsts.fold(0, (total, s) => total + s.pointsEarned),
      firstAttemptByScenario: firstByScenario,
      attemptedScenarioIds: firstByScenario.keys.toSet(),
    );
  }

  /// From the server-maintained per-worker stats doc (same scoring rule).
  factory SafetyScoreSummary.fromStats(SafetyWorkerStatsModel stats) {
    return SafetyScoreSummary(
      totalAttempts: stats.totalAttempts,
      scenariosAttempted: stats.scenariosAttempted,
      firstTryCorrect: stats.firstTryCorrect,
      totalPoints: stats.totalPoints,
      attemptedScenarioIds: stats.attemptedScenarioIds,
    );
  }
}

/// What the grading Cloud Function returns for a submitted attempt — the
/// only point at which the client learns the correct answer.
class SafetyAttemptResult {
  final String sessionId;
  final bool isCorrect;

  /// False when the worker had already attempted this scenario — the
  /// attempt is practice and earns no points.
  final bool isFirstAttempt;
  final int pointsEarned;
  final int correctOptionIndex;
  final String explanation;

  const SafetyAttemptResult({
    required this.sessionId,
    required this.isCorrect,
    required this.isFirstAttempt,
    required this.pointsEarned,
    required this.correctOptionIndex,
    required this.explanation,
  });

  /// From the callable's response.
  factory SafetyAttemptResult.fromCallable(Map<String, dynamic> data) {
    return SafetyAttemptResult(
      sessionId: data['sessionId'] as String? ?? '',
      isCorrect: data['isCorrect'] as bool? ?? false,
      isFirstAttempt: data['isFirstAttempt'] as bool? ?? true,
      pointsEarned: (data['pointsEarned'] as num?)?.toInt() ?? 0,
      correctOptionIndex: (data['correctOptionIndex'] as num?)?.toInt() ?? -1,
      explanation: data['explanation'] as String? ?? '',
    );
  }

  /// From the session doc the grading function wrote — same fields.
  factory SafetyAttemptResult.fromSession(String sessionId, Map<String, dynamic> data) {
    return SafetyAttemptResult.fromCallable({...data, 'sessionId': sessionId});
  }
}

/// A worker expected to take safety training, from the Users collection.
class SafetyTrainee {
  final String uid;
  final String name;
  final String role;
  const SafetyTrainee({required this.uid, required this.name, required this.role});
}

/// Upload caps for scenario media — mirrored by storage.rules, and checked
/// in the author form at pick time so an admin gets a clear message rather
/// than a rejected upload.
class SafetyMediaLimits {
  static const maxImageBytes = 10 * 1024 * 1024;
  static const maxLottieBytes = 5 * 1024 * 1024;
  static const maxRiveBytes = 10 * 1024 * 1024;

  static const _imageTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
  };

  /// The upload content type for a picked photo, from its reported MIME
  /// type or else its file extension — null if it isn't a supported image.
  static String? imageContentType({required String fileName, String? mimeType}) {
    if (mimeType != null && _imageTypes.containsValue(mimeType)) return mimeType;
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? null : _imageTypes[fileName.substring(dot + 1).toLowerCase()];
  }

  static String describe(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
}

/// The scene media an admin chose for a scenario — at most one of these is
/// set (see HazardSceneVisual's priority order).
class SafetyScenarioMedia {
  final String? imageUrl;
  final String? lottieUrl;
  final String? riveUrl;

  const SafetyScenarioMedia({this.imageUrl, this.lottieUrl, this.riveUrl});

  static const none = SafetyScenarioMedia();
}

class SafetyTrainingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final Logger _logger = Logger();

  CollectionReference<Map<String, dynamic>> get _scenarios => _firestore.collection('SafetyTrainingScenarios');
  CollectionReference<Map<String, dynamic>> get _answerKeys => _firestore.collection('SafetyTrainingAnswerKeys');
  CollectionReference<Map<String, dynamic>> get _feedback => _firestore.collection('SafetyTrainingFeedback');
  CollectionReference<Map<String, dynamic>> get _sessions => _firestore.collection('SafetyTrainingSessions');
  CollectionReference<Map<String, dynamic>> get _reviews => _firestore.collection('SafetyTrainingReviews');

  Stream<List<SafetyScenarioModel>> streamActiveScenarios() {
    return _scenarios
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(SafetyScenarioModel.fromFirestore).toList());
  }

  Stream<List<SafetyScenarioModel>> streamAllScenarios() {
    return _scenarios
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(SafetyScenarioModel.fromFirestore).toList());
  }

  /// A fresh scenario id, reserved before saving so media can be uploaded
  /// to its Storage path first and the scenario + answer key then written
  /// in one batch — the scenario never goes live half-saved, and a retry
  /// after a failure reuses the same id instead of creating a duplicate.
  String newScenarioId() => _scenarios.doc().id;

  /// Creates a scenario and its answer key atomically (firestore.rules
  /// requires the key to exist in the same batch).
  Future<void> createScenario({
    required String scenarioId,
    required SafetyScenarioModel scenario,
    required SafetyScenarioAnswerKey answerKey,
  }) async {
    final batch = _firestore.batch()
      ..set(_scenarios.doc(scenarioId), scenario.toFirestore())
      ..set(_answerKeys.doc(scenarioId), answerKey.toFirestore(updatedByUid: scenario.createdByUid));
    await batch.commit();
    _logger.i('✅ SafetyTrainingService: Created scenario $scenarioId (${scenario.title})');
  }

  /// Updates an existing scenario's content and answer key atomically,
  /// keeping its authorship and active state. Also strips any legacy
  /// answer fields left on the scenario doc.
  Future<void> updateScenario({
    required SafetyScenarioModel scenario,
    required SafetyScenarioAnswerKey answerKey,
    required String editedByUid,
  }) async {
    final batch = _firestore.batch()
      ..update(_scenarios.doc(scenario.id), {
        ...scenario.toContentUpdate(),
        'correctOptionIndex': FieldValue.delete(),
        'explanation': FieldValue.delete(),
      })
      ..set(_answerKeys.doc(scenario.id), answerKey.toFirestore(updatedByUid: editedByUid));
    await batch.commit();
    _logger.i('✅ SafetyTrainingService: Updated scenario ${scenario.id} (${scenario.title})');
  }

  Future<SafetyScenarioAnswerKey?> fetchAnswerKey(String scenarioId) async {
    final snap = await _answerKeys.doc(scenarioId).get();
    final data = snap.data();
    if (data != null) return SafetyScenarioAnswerKey.fromMap(data);
    // Not migrated yet — the answer still lives on the scenario doc.
    final scenarioData = (await _scenarios.doc(scenarioId).get()).data();
    if (scenarioData != null && SafetyScenarioModel.hasLegacyAnswerFields(scenarioData)) {
      return SafetyScenarioAnswerKey.fromMap(scenarioData);
    }
    return null;
  }

  Future<void> setScenarioActive(String scenarioId, bool isActive) async {
    await _scenarios.doc(scenarioId).update({'isActive': isActive, 'updatedAt': Timestamp.fromDate(DateTime.now())});
  }

  /// Moves the answer fields of scenarios authored before answer keys were
  /// split out (correctOptionIndex/explanation on the scenario doc itself,
  /// readable by every Technician) into SafetyTrainingAnswerKeys, and
  /// deletes them from the scenario. Idempotent — returns how many
  /// scenarios it secured, 0 once everything is migrated. Admin-only.
  Future<int> secureLegacyScenarios({required String adminUid}) async {
    final legacy = <String, Map<String, dynamic>>{};
    // An inequality filter only matches docs that have the field at all.
    final byIndex = await _scenarios.where('correctOptionIndex', isGreaterThanOrEqualTo: 0).get();
    final byExplanation = await _scenarios.where('explanation', isGreaterThanOrEqualTo: '').get();
    for (final doc in [...byIndex.docs, ...byExplanation.docs]) {
      legacy[doc.id] = doc.data();
    }
    if (legacy.isEmpty) return 0;

    var secured = 0;
    for (final entry in legacy.entries) {
      final existingKey = (await _answerKeys.doc(entry.key).get()).data();
      final legacyKey = SafetyScenarioAnswerKey.fromMap(entry.value);
      final options = (entry.value['options'] as List?) ?? const [];
      final batch = _firestore.batch();
      // An existing answer key is authoritative; only seed it from the
      // legacy fields when there isn't one yet.
      if (existingKey == null) {
        final index = legacyKey.correctOptionIndex;
        batch.set(
          _answerKeys.doc(entry.key),
          SafetyScenarioAnswerKey(
            correctOptionIndex: (index >= 0 && index < options.length) ? index : 0,
            explanation: legacyKey.explanation,
          ).toFirestore(updatedByUid: adminUid),
        );
      }
      batch.update(_scenarios.doc(entry.key), {
        'correctOptionIndex': FieldValue.delete(),
        'explanation': FieldValue.delete(),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      try {
        await batch.commit();
        secured++;
      } catch (e) {
        // One malformed legacy doc (e.g. fewer than 2 options) mustn't
        // stop the rest from being secured.
        _logger.e('❌ SafetyTrainingService: Could not secure scenario ${entry.key}: $e');
      }
    }
    _logger.i('✅ SafetyTrainingService: Secured $secured of ${legacy.length} legacy scenario answer key(s)');
    return secured;
  }

  /// Uploads the scene photo. Always stored as `image.jpg` (the fixed name
  /// storage.rules and [deleteUnusedScenarioMedia] expect) but tagged with
  /// its real [contentType], so a PNG/WebP is served as what it is.
  Future<String> uploadScenarioImage({
    required String scenarioId,
    required String contentType,
    File? file,
    Uint8List? bytes,
  }) async {
    final ref = _storage.ref().child('SafetyTraining/Scenarios/$scenarioId/image.jpg');
    final metadata = SettableMetadata(contentType: contentType);
    if (kIsWeb) {
      if (bytes == null) throw ArgumentError('bytes required on web');
      await ref.putData(bytes, metadata);
    } else {
      if (file == null) throw ArgumentError('file required on non-web platforms');
      await ref.putFile(file, metadata);
    }
    return ref.getDownloadURL();
  }

  /// Uploads a Lottie (Bodymovin) `.json` animation for a scenario's scene.
  Future<String> uploadScenarioLottie({required String scenarioId, required Uint8List bytes}) async {
    final ref = _storage.ref().child('SafetyTraining/Scenarios/$scenarioId/animation.json');
    await ref.putData(bytes, SettableMetadata(contentType: 'application/json'));
    return ref.getDownloadURL();
  }

  /// Uploads a Rive `.riv` animation for a scenario's scene.
  Future<String> uploadScenarioRive({required String scenarioId, required Uint8List bytes}) async {
    final ref = _storage.ref().child('SafetyTraining/Scenarios/$scenarioId/animation.riv');
    await ref.putData(bytes, SettableMetadata(contentType: 'application/octet-stream'));
    return ref.getDownloadURL();
  }

  /// Best-effort removal of a scenario's media files that are no longer
  /// referenced after a save (e.g. a photo replaced by a Lottie animation).
  Future<void> deleteUnusedScenarioMedia(String scenarioId, SafetyScenarioMedia keep) async {
    final unused = <String>[
      if (keep.imageUrl == null) 'image.jpg',
      if (keep.lottieUrl == null) 'animation.json',
      if (keep.riveUrl == null) 'animation.riv',
    ];
    for (final name in unused) {
      try {
        await _storage.ref().child('SafetyTraining/Scenarios/$scenarioId/$name').delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') {
          _logger.w('⚠️ SafetyTrainingService: Could not delete $name for $scenarioId: ${e.code}');
        }
      }
    }
  }

  /// A fresh attempt id — generated once per attempt so a retry after a
  /// lost response re-submits the *same* attempt (the grading function is
  /// idempotent per id) instead of recording a second one.
  String newAttemptId() => _sessions.doc().id;

  /// How long a submission may take before the worker is told it couldn't
  /// be confirmed (they can then safely retry with the same attempt id).
  static const submitTimeout = Duration(seconds: 45);

  /// Errors that say nothing about whether the attempt was recorded — the
  /// response may simply have been lost — so keep waiting for the session
  /// doc rather than failing straight away.
  static const _transientCallErrors = {'unavailable', 'deadline-exceeded', 'internal', 'unknown', 'cancelled'};

  /// Submits a worker's answer to the submitSafetyScenarioAttempt Cloud
  /// Function, which grades it against the server-only answer key and
  /// records the session (clients can't write sessions directly).
  ///
  /// Resolves from whichever arrives first: the call's response, or the
  /// session doc [attemptId] appearing in Firestore. The second path is what
  /// keeps the result screen from hanging when the session was recorded but
  /// the response never made it back to the browser. A genuine grading
  /// error (bad input, inactive scenario, …) still fails immediately; if
  /// neither path succeeds within [submitTimeout] a [TimeoutException] is
  /// thrown and the caller can retry with the same [attemptId].
  Future<SafetyAttemptResult> submitAttempt({
    required String attemptId,
    required String scenarioId,
    required int selectedOptionIndex,
    required String reasoningAnswer,
    required int timeTakenSeconds,
    String? projectId,
    String? projectName,
  }) async {
    final completer = Completer<SafetyAttemptResult>();
    final watch = _sessions.doc(attemptId).snapshots().listen(
      (snap) {
        final data = snap.data();
        if (data != null && !completer.isCompleted) {
          _logger.i('✅ SafetyTrainingService: Attempt $attemptId recorded (seen via session doc)');
          completer.complete(SafetyAttemptResult.fromSession(snap.id, data));
        }
      },
      // Only a fallback — the call below is still in flight.
      onError: (Object e) => _logger.w('⚠️ SafetyTrainingService: Could not watch attempt $attemptId: $e'),
    );

    _functions
        .httpsCallable(
          'submitSafetyScenarioAttempt',
          options: HttpsCallableOptions(timeout: submitTimeout - const Duration(seconds: 5)),
        )
        .call<dynamic>({
          'attemptId': attemptId,
          'scenarioId': scenarioId,
          'selectedOptionIndex': selectedOptionIndex,
          'reasoningAnswer': reasoningAnswer,
          'timeTakenSeconds': timeTakenSeconds,
          'projectId': ?projectId,
          'projectName': ?projectName,
        })
        .then(
          (response) {
            if (completer.isCompleted) return;
            _logger.i('✅ SafetyTrainingService: Attempt $attemptId graded (seen via callable)');
            completer.complete(SafetyAttemptResult.fromCallable(Map<String, dynamic>.from(response.data as Map)));
          },
          onError: (Object e, StackTrace st) {
            if (completer.isCompleted) return;
            if (e is FirebaseFunctionsException && _transientCallErrors.contains(e.code)) {
              _logger.w('⚠️ SafetyTrainingService: Submit call for $attemptId failed (${e.code}); '
                  'waiting for the session doc instead');
              return;
            }
            completer.completeError(e, st);
          },
        );

    try {
      return await completer.future.timeout(submitTimeout);
    } finally {
      await watch.cancel();
    }
  }

  /// One worker's sessions, newest first; [limit] pages the history view.
  Stream<List<SafetyTrainingSessionModel>> streamWorkerSessions(String workerUid, {int? limit}) {
    Query<Map<String, dynamic>> query = _sessions
        .where('workerUid', isEqualTo: workerUid)
        .orderBy('completedAt', descending: true);
    if (limit != null) query = query.limit(limit);
    return query.snapshots().map((snap) => snap.docs.map(SafetyTrainingSessionModel.fromFirestore).toList());
  }

  /// Every worker's sessions, newest first, a page at a time.
  Stream<List<SafetyTrainingSessionModel>> streamAllSessions({required int limit}) {
    return _sessions
        .orderBy('completedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(SafetyTrainingSessionModel.fromFirestore).toList());
  }

  // ── Worker stats (server-maintained aggregates) ──────────────────────

  Stream<List<SafetyWorkerStatsModel>> streamAllWorkerStats() {
    return _firestore
        .collection('SafetyTrainingWorkerStats')
        .snapshots()
        .map((snap) => snap.docs.map(SafetyWorkerStatsModel.fromFirestore).toList());
  }

  /// One worker's stats doc (null until built — see [rebuildWorkerStats]).
  Stream<SafetyWorkerStatsModel?> streamWorkerStats(String workerUid) {
    return _firestore
        .collection('SafetyTrainingWorkerStats')
        .doc(workerUid)
        .snapshots()
        .map((snap) => snap.exists ? SafetyWorkerStatsModel.fromFirestore(snap) : null);
  }

  /// Whether every worker's stats doc has been built from their history
  /// (rebuildSafetyTrainingStats stamps SafetyTrainingMeta/stats when done).
  Future<bool> areWorkerStatsBuilt() async {
    final snap = await _firestore.collection('SafetyTrainingMeta').doc('stats').get();
    return snap.exists;
  }

  /// Builds every worker's stats doc from their sessions (reviewer-only).
  Future<int> rebuildWorkerStats() async {
    final response = await _functions
        .httpsCallable('rebuildSafetyTrainingStats', options: HttpsCallableOptions(timeout: const Duration(minutes: 5)))
        .call<dynamic>();
    final workers = (Map<String, dynamic>.from(response.data as Map)['workers'] as num?)?.toInt() ?? 0;
    _logger.i('✅ SafetyTrainingService: Rebuilt stats for $workers worker(s)');
    return workers;
  }

  // ── Trainer feedback ──────────────────────────────────────────────────

  Future<void> addFeedback(SafetyTrainingFeedbackModel feedback) async {
    await _feedback.add(feedback.toFirestore());
    _logger.i('✅ SafetyTrainingService: Added feedback on session ${feedback.sessionId}');
  }

  /// All feedback on one worker's attempts.
  Stream<List<SafetyTrainingFeedbackModel>> streamFeedbackForWorker(String workerUid) {
    return _feedback
        .where('workerUid', isEqualTo: workerUid)
        .snapshots()
        .map((snap) => snap.docs.map(SafetyTrainingFeedbackModel.fromFirestore).toList());
  }

  /// The most recent feedback across all workers (admin all-worker view).
  Stream<List<SafetyTrainingFeedbackModel>> streamRecentFeedback({required int limit}) {
    return _feedback
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(SafetyTrainingFeedbackModel.fromFirestore).toList());
  }

  // ── People ────────────────────────────────────────────────────────────

  /// The caller's role from the UserRoles/{uid} mirror — the same source
  /// firestore.rules and the Cloud Functions authorize against, so the UI
  /// never offers an action the backend would then refuse.
  Future<String?> fetchRole(String uid) async {
    final snap = await _firestore.collection('UserRoles').doc(uid).get();
    return snap.data()?['role'] as String?;
  }

  /// MainAdmin/SystemAdmin users — who an escalation can be handed to.
  Stream<List<SafetyTrainee>> streamReviewers() {
    return _firestore
        .collection('Users')
        .where('role', whereIn: const ['MainAdmin', 'SystemAdmin'])
        .snapshots()
        .map(
          (snap) => [
            for (final doc in snap.docs)
              if ((doc.data()['uid'] as String?)?.isNotEmpty ?? false)
                SafetyTrainee(uid: doc.data()['uid'] as String, name: doc.id, role: doc.data()['role'] as String),
          ],
        );
  }

  /// Every Technician — the workforce the weekly reminder targets and the
  /// review roster must cover, including anyone who has never completed a
  /// scenario (and so has no sessions to be discovered from). Users docs
  /// are keyed by username, with the auth uid as a field.
  Stream<List<SafetyTrainee>> streamTrainees() {
    return _firestore
        .collection('Users')
        .where('role', isEqualTo: 'Technician')
        .snapshots()
        .map(
          (snap) => [
            for (final doc in snap.docs)
              if ((doc.data()['uid'] as String?)?.isNotEmpty ?? false)
                SafetyTrainee(
                  uid: doc.data()['uid'] as String,
                  name: doc.id,
                  role: doc.data()['role'] as String? ?? 'Technician',
                ),
          ],
        );
  }

  /// Records a MainAdmin/SystemAdmin's determination of a worker's overall
  /// safety-training standing (cleared / needs retraining / escalated).
  Future<void> recordReview(SafetyTrainingReviewModel review) async {
    await _reviews.add(review.toFirestore());
    _logger.i(
      '✅ SafetyTrainingService: Recorded review for ${review.workerName} '
      '(status: ${review.status})',
    );
  }

  /// Every review ever recorded, newest first — callers building a
  /// per-worker "current standing" view should take the first entry for
  /// each workerUid, since re-reviewing a worker adds a new doc rather than
  /// overwriting the previous one.
  Stream<List<SafetyTrainingReviewModel>> streamAllReviews() {
    return _reviews
        .orderBy('reviewedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(SafetyTrainingReviewModel.fromFirestore).toList());
  }

  /// Live version of [fetchLatestReviewForWorker].
  Stream<SafetyTrainingReviewModel?> streamLatestReviewForWorker(String workerUid) {
    return _reviews
        .where('workerUid', isEqualTo: workerUid)
        .orderBy('reviewedAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty ? null : SafetyTrainingReviewModel.fromFirestore(snap.docs.first));
  }

  /// The most recent review recorded for one worker, or `null` if they've
  /// never been reviewed — used to show a worker their own current standing.
  Future<SafetyTrainingReviewModel?> fetchLatestReviewForWorker(String workerUid) async {
    final snap = await _reviews
        .where('workerUid', isEqualTo: workerUid)
        .orderBy('reviewedAt', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return SafetyTrainingReviewModel.fromFirestore(snap.docs.first);
  }
}
