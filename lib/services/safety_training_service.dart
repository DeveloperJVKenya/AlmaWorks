import 'dart:io';
import 'dart:typed_data';

import 'package:almaworks/models/safety_training/safety_scenario_model.dart';
import 'package:almaworks/models/safety_training/safety_training_session_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logger/logger.dart';

/// Per-worker aggregate safety-awareness rating, derived on the fly from
/// [SafetyTrainingSessionModel] history rather than stored as a maintained
/// counter doc — avoids a second write path that could drift from the
/// append-only session ledger it would be summarizing.
class SafetyScoreSummary {
  final int totalAttempts;
  final int correctAttempts;
  final int totalPoints;

  const SafetyScoreSummary({
    required this.totalAttempts,
    required this.correctAttempts,
    required this.totalPoints,
  });

  double get accuracy => totalAttempts == 0 ? 0 : correctAttempts / totalAttempts;

  static const empty = SafetyScoreSummary(totalAttempts: 0, correctAttempts: 0, totalPoints: 0);
}

class SafetyTrainingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Logger _logger = Logger();

  CollectionReference<Map<String, dynamic>> get _scenarios =>
      _firestore.collection('SafetyTrainingScenarios');
  CollectionReference<Map<String, dynamic>> get _sessions =>
      _firestore.collection('SafetyTrainingSessions');

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

  Future<String> createScenario(SafetyScenarioModel scenario) async {
    final doc = await _scenarios.add(scenario.toFirestore());
    _logger.i('✅ SafetyTrainingService: Created scenario ${doc.id} (${scenario.title})');
    return doc.id;
  }

  Future<void> setScenarioActive(String scenarioId, bool isActive) async {
    await _scenarios.doc(scenarioId).update({
      'isActive': isActive,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> setScenarioImage(String scenarioId, String imageUrl) async {
    await _scenarios.doc(scenarioId).update({
      'imageUrl': imageUrl,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<String> uploadScenarioImage({
    required String scenarioId,
    File? file,
    Uint8List? bytes,
  }) async {
    final ref = _storage.ref().child('SafetyTraining/Scenarios/$scenarioId/image.jpg');
    if (kIsWeb) {
      if (bytes == null) throw ArgumentError('bytes required on web');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    } else {
      if (file == null) throw ArgumentError('file required on non-web platforms');
      await ref.putFile(file);
    }
    return ref.getDownloadURL();
  }

  /// Uploads a Lottie (Bodymovin) `.json` animation for a scenario's scene.
  Future<String> uploadScenarioLottie({
    required String scenarioId,
    required Uint8List bytes,
  }) async {
    final ref = _storage.ref().child('SafetyTraining/Scenarios/$scenarioId/animation.json');
    await ref.putData(bytes, SettableMetadata(contentType: 'application/json'));
    return ref.getDownloadURL();
  }

  /// Uploads a Rive `.riv` animation for a scenario's scene.
  Future<String> uploadScenarioRive({
    required String scenarioId,
    required Uint8List bytes,
  }) async {
    final ref = _storage.ref().child('SafetyTraining/Scenarios/$scenarioId/animation.riv');
    await ref.putData(bytes, SettableMetadata(contentType: 'application/octet-stream'));
    return ref.getDownloadURL();
  }

  /// Points the scenario at a freshly uploaded animation, clearing whichever
  /// of lottieUrl/riveUrl the admin didn't just set — a scenario shows at
  /// most one uploaded animation at a time (see HazardSceneVisual's
  /// priority order), so switching kinds shouldn't leave a stale, unused
  /// reference behind.
  Future<void> setScenarioAnimation(String scenarioId, {String? lottieUrl, String? riveUrl}) async {
    await _scenarios.doc(scenarioId).update({
      'lottieUrl': lottieUrl,
      'riveUrl': riveUrl,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> recordSession(SafetyTrainingSessionModel session) async {
    await _sessions.add(session.toFirestore());
    _logger.i(
        '✅ SafetyTrainingService: Recorded session for ${session.workerName} '
        '(scenario: ${session.scenarioTitle}, correct: ${session.isCorrect})');
  }

  Stream<List<SafetyTrainingSessionModel>> streamWorkerSessions(String workerUid) {
    return _sessions
        .where('workerUid', isEqualTo: workerUid)
        .orderBy('completedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(SafetyTrainingSessionModel.fromFirestore).toList());
  }

  Stream<List<SafetyTrainingSessionModel>> streamAllSessions() {
    return _sessions
        .orderBy('completedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(SafetyTrainingSessionModel.fromFirestore).toList());
  }

  Future<SafetyScoreSummary> fetchWorkerScoreSummary(String workerUid) async {
    final snap = await _sessions.where('workerUid', isEqualTo: workerUid).get();
    if (snap.docs.isEmpty) return SafetyScoreSummary.empty;
    var correct = 0;
    var points = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['isCorrect'] == true) correct++;
      points += (data['pointsEarned'] as int?) ?? 0;
    }
    return SafetyScoreSummary(
      totalAttempts: snap.docs.length,
      correctAttempts: correct,
      totalPoints: points,
    );
  }
}
