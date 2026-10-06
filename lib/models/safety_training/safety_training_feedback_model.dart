import 'package:cloud_firestore/cloud_firestore.dart';

/// A trainer's comment on one recorded attempt — typically on the worker's
/// free-text reasoning, which isn't auto-graded. Append-only (see
/// firestore.rules/SafetyTrainingFeedback), like the sessions it annotates;
/// the worker is notified by the onSafetyTrainingFeedbackCreated Cloud
/// Function and sees it in their history.
class SafetyTrainingFeedbackModel {
  static const maxLength = 1000;

  final String id;
  final String sessionId;
  final String workerUid;
  final String scenarioTitle;
  final String comment;
  final String byUid;
  final String byName;
  final String byRole;
  final DateTime createdAt;

  const SafetyTrainingFeedbackModel({
    required this.id,
    required this.sessionId,
    required this.workerUid,
    required this.scenarioTitle,
    required this.comment,
    required this.byUid,
    required this.byName,
    required this.byRole,
    required this.createdAt,
  });

  factory SafetyTrainingFeedbackModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    return SafetyTrainingFeedbackModel(
      id: doc.id,
      sessionId: data['sessionId'] ?? '',
      workerUid: data['workerUid'] ?? '',
      scenarioTitle: data['scenarioTitle'] ?? '',
      comment: data['comment'] ?? '',
      byUid: data['byUid'] ?? '',
      byName: data['byName'] ?? '',
      byRole: data['byRole'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'sessionId': sessionId,
      'workerUid': workerUid,
      'scenarioTitle': scenarioTitle,
      'comment': comment,
      'byUid': byUid,
      'byName': byName,
      'byRole': byRole,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
