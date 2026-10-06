import 'package:cloud_firestore/cloud_firestore.dart';

/// One worker's completed attempt at a [SafetyScenarioModel] — append-only,
/// like the Inventory module's custody ledger (see
/// firestore.rules/InventoryAssetAssignments): once written, a session is
/// never edited or deleted, so a worker's safety-awareness history and
/// trainers' review of past reasoning answers can't be quietly altered.
class SafetyTrainingSessionModel {
  final String id;
  final String scenarioId;
  final String scenarioTitle;
  final String category;

  final String? projectId;
  final String? projectName;

  final String workerUid;
  final String workerName;
  final String workerRole;

  final int selectedOptionIndex;
  final bool isCorrect;

  /// Whether this was the worker's first attempt at the scenario (the only
  /// one that scores). Null on sessions recorded before the flag existed —
  /// use SafetyScoreSummary.fromSessions, which derives it from order.
  final bool? isFirstAttempt;
  final String reasoningAnswer;
  final int pointsEarned;
  final int timeTakenSeconds;

  // Snapshot of the question as it was answered (set by the grading Cloud
  // Function), so the record stays readable after the scenario is edited.
  // Null on sessions recorded before server-side grading.
  final String? question;
  final List<String>? options;
  final int? correctOptionIndex;

  final DateTime completedAt;

  const SafetyTrainingSessionModel({
    required this.id,
    required this.scenarioId,
    required this.scenarioTitle,
    required this.category,
    this.projectId,
    this.projectName,
    required this.workerUid,
    required this.workerName,
    required this.workerRole,
    required this.selectedOptionIndex,
    required this.isCorrect,
    this.isFirstAttempt,
    required this.reasoningAnswer,
    required this.pointsEarned,
    required this.timeTakenSeconds,
    this.question,
    this.options,
    this.correctOptionIndex,
    required this.completedAt,
  });

  factory SafetyTrainingSessionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    return SafetyTrainingSessionModel(
      id: doc.id,
      scenarioId: data['scenarioId'] ?? '',
      scenarioTitle: data['scenarioTitle'] ?? '',
      category: data['category'] ?? 'General',
      projectId: data['projectId'] as String?,
      projectName: data['projectName'] as String?,
      workerUid: data['workerUid'] ?? '',
      workerName: data['workerName'] ?? '',
      workerRole: data['workerRole'] ?? '',
      selectedOptionIndex: data['selectedOptionIndex'] as int? ?? -1,
      isCorrect: data['isCorrect'] as bool? ?? false,
      isFirstAttempt: data['isFirstAttempt'] as bool?,
      reasoningAnswer: data['reasoningAnswer'] ?? '',
      pointsEarned: data['pointsEarned'] as int? ?? 0,
      timeTakenSeconds: data['timeTakenSeconds'] as int? ?? 0,
      question: data['question'] as String?,
      options: data['options'] is List ? List<String>.from(data['options'] as List) : null,
      correctOptionIndex: data['correctOptionIndex'] as int?,
      completedAt: (data['completedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'scenarioId': scenarioId,
      'scenarioTitle': scenarioTitle,
      'category': category,
      if (projectId != null) 'projectId': projectId,
      if (projectName != null) 'projectName': projectName,
      'workerUid': workerUid,
      'workerName': workerName,
      'workerRole': workerRole,
      'selectedOptionIndex': selectedOptionIndex,
      'isCorrect': isCorrect,
      'isFirstAttempt': ?isFirstAttempt,
      'reasoningAnswer': reasoningAnswer,
      'pointsEarned': pointsEarned,
      'timeTakenSeconds': timeTakenSeconds,
      if (question != null) 'question': question,
      if (options != null) 'options': options,
      if (correctOptionIndex != null) 'correctOptionIndex': correctOptionIndex,
      'completedAt': Timestamp.fromDate(completedAt),
    };
  }
}
