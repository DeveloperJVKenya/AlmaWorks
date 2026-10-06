import 'package:cloud_firestore/cloud_firestore.dart';

/// A single gamified safety scenario: a site hazard situation shown to the
/// worker (animated via [visualKey], or a real photo via [imageUrl] when an
/// admin has uploaded one), a graded multiple-choice hazard question, and a
/// free-text reasoning prompt the worker answers in their own words. The
/// reasoning answer isn't auto-graded (see [SafetyTrainingSessionModel]) —
/// it's captured for a trainer/admin to review, since "explain why this is
/// unsafe" doesn't reduce to a single correct string.
///
/// Holds only what a worker may see *before* answering — the correct option
/// and its explanation live in [SafetyScenarioAnswerKey]
/// (SafetyTrainingAnswerKeys/{scenarioId}), which only admins and the
/// grading Cloud Function can read.
class SafetyScenarioModel {
  static const difficultyBasic = 'Basic';
  static const difficultyIntermediate = 'Intermediate';
  static const difficultyAdvanced = 'Advanced';

  /// Keys understood by HazardSceneVisual's built-in animated illustrations.
  /// Falls back to 'generic' for any unrecognized value, so old content never
  /// breaks if the visual set changes.
  static const visualFallingObject = 'falling_object';
  static const visualMissingPpe = 'missing_ppe';
  static const visualExposedWiring = 'exposed_wiring';
  static const visualUnguardedEdge = 'unguarded_edge';
  static const visualWetFloor = 'wet_floor';
  static const visualUnsecuredLadder = 'unsecured_ladder';
  static const visualGeneric = 'generic';

  final String id;
  final String title;
  final String category;
  final String sceneDescription;
  final String visualKey;
  final String? imageUrl;

  /// Real animated illustrations, when an admin has uploaded one — take
  /// priority over [imageUrl] and the built-in icon animation, in that
  /// order (see HazardSceneVisual). [riveUrl] wins over [lottieUrl] when
  /// both are somehow set, since Rive's runtime state-machine animations
  /// are the richer of the two; in practice an admin uploads at most one.
  final String? lottieUrl;
  final String? riveUrl;

  final String question;
  final List<String> options;
  final String reasoningPrompt;

  final String difficulty;
  final int points;
  final bool isActive;

  final String createdByUid;
  final String createdByName;
  final String createdByRole;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const SafetyScenarioModel({
    required this.id,
    required this.title,
    required this.category,
    required this.sceneDescription,
    required this.visualKey,
    this.imageUrl,
    this.lottieUrl,
    this.riveUrl,
    required this.question,
    required this.options,
    required this.reasoningPrompt,
    this.difficulty = difficultyBasic,
    this.points = 10,
    this.isActive = true,
    required this.createdByUid,
    required this.createdByName,
    required this.createdByRole,
    required this.createdAt,
    this.updatedAt,
  });

  factory SafetyScenarioModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    return SafetyScenarioModel(
      id: doc.id,
      title: data['title'] ?? '',
      category: data['category'] ?? 'General',
      sceneDescription: data['sceneDescription'] ?? '',
      visualKey: data['visualKey'] ?? visualGeneric,
      imageUrl: data['imageUrl'] as String?,
      lottieUrl: data['lottieUrl'] as String?,
      riveUrl: data['riveUrl'] as String?,
      question: data['question'] ?? '',
      options: List<String>.from(data['options'] as List? ?? const []),
      reasoningPrompt: data['reasoningPrompt'] ?? '',
      difficulty: data['difficulty'] ?? difficultyBasic,
      points: data['points'] as int? ?? 10,
      isActive: data['isActive'] as bool? ?? true,
      createdByUid: data['createdByUid'] ?? '',
      createdByName: data['createdByName'] ?? '',
      createdByRole: data['createdByRole'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Whether this scenario doc still carries the answer fields from before
  /// they were split into SafetyTrainingAnswerKeys — see
  /// SafetyTrainingService.secureLegacyScenarios.
  static bool hasLegacyAnswerFields(Map<String, dynamic> data) =>
      data.containsKey('correctOptionIndex') || data.containsKey('explanation');

  /// The editable content fields, for updating an existing scenario —
  /// excludes authorship (immutable per firestore.rules) and isActive
  /// (toggled separately), and writes every media field explicitly so
  /// clearing or switching media removes the stale URL.
  Map<String, dynamic> toContentUpdate() {
    return {
      'title': title,
      'category': category,
      'sceneDescription': sceneDescription,
      'visualKey': visualKey,
      'imageUrl': imageUrl,
      'lottieUrl': lottieUrl,
      'riveUrl': riveUrl,
      'question': question,
      'options': options,
      'reasoningPrompt': reasoningPrompt,
      'difficulty': difficulty,
      'points': points,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'category': category,
      'sceneDescription': sceneDescription,
      'visualKey': visualKey,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (lottieUrl != null) 'lottieUrl': lottieUrl,
      if (riveUrl != null) 'riveUrl': riveUrl,
      'question': question,
      'options': options,
      'reasoningPrompt': reasoningPrompt,
      'difficulty': difficulty,
      'points': points,
      'isActive': isActive,
      'createdByUid': createdByUid,
      'createdByName': createdByName,
      'createdByRole': createdByRole,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt ?? DateTime.now()),
    };
  }
}

/// The graded half of a [SafetyScenarioModel], stored separately at
/// SafetyTrainingAnswerKeys/{scenarioId} so Technicians — who can read
/// scenarios — never see the answer before submitting. Written by admins
/// in the same batch as the scenario; read by admins when editing and by
/// the submitSafetyScenarioAttempt Cloud Function when grading.
class SafetyScenarioAnswerKey {
  final int correctOptionIndex;
  final String explanation;

  const SafetyScenarioAnswerKey({required this.correctOptionIndex, required this.explanation});

  factory SafetyScenarioAnswerKey.fromMap(Map<String, dynamic> data) {
    return SafetyScenarioAnswerKey(
      correctOptionIndex: data['correctOptionIndex'] as int? ?? 0,
      explanation: data['explanation'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore({required String updatedByUid}) {
    return {
      'correctOptionIndex': correctOptionIndex,
      'explanation': explanation,
      'updatedByUid': updatedByUid,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };
  }
}
