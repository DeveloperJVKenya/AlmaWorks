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
  final String reasoningAnswer;
  final int pointsEarned;
  final int timeTakenSeconds;

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
    required this.reasoningAnswer,
    required this.pointsEarned,
    required this.timeTakenSeconds,
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
      reasoningAnswer: data['reasoningAnswer'] ?? '',
      pointsEarned: data['pointsEarned'] as int? ?? 0,
      timeTakenSeconds: data['timeTakenSeconds'] as int? ?? 0,
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
      'reasoningAnswer': reasoningAnswer,
      'pointsEarned': pointsEarned,
      'timeTakenSeconds': timeTakenSeconds,
      'completedAt': Timestamp.fromDate(completedAt),
    };
  }
}
