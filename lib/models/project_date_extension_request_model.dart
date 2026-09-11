import 'package:cloud_firestore/cloud_firestore.dart';

/// A request to change a PROJECT's own start/end date — raised by an
/// Admin/MainAdmin, approved or rejected by the project's linked Project
/// Manager or any MainAdmin. This is the single top-level approval gate:
/// once approved, the project's live dates (Projects/{id}) move, any
/// TaskProgressMonitor phase/project-title row whose date matched the old
/// project boundary shifts with it, and individual task dates become
/// freely editable by Admin/MainAdmin within the new project bounds —
/// no separate per-task approval.
class ProjectDateExtensionRequestModel {
  static const statusPending = 'pending';
  static const statusApproved = 'approved';
  static const statusRejected = 'rejected';

  final String id;
  final String projectId;
  final String projectName;

  /// Snapshot of the project's linked PM at request time (see
  /// ProjectModel.projectManagerUid) — who this request was routed to,
  /// even if the project's link later changes.
  final String? projectManagerUid;
  final String? projectManagerName;

  final DateTime originalStartDate;
  final DateTime? originalEndDate;
  final DateTime requestedStartDate;
  final DateTime? requestedEndDate;
  final String reason;

  final String status;

  final String requestedByUid;
  final String requestedByName;
  final String requestedByRole;
  final DateTime requestedAt;

  final String? respondedByUid;
  final String? respondedByName;
  final DateTime? respondedAt;
  final String? rejectionReason;

  const ProjectDateExtensionRequestModel({
    required this.id,
    required this.projectId,
    required this.projectName,
    this.projectManagerUid,
    this.projectManagerName,
    required this.originalStartDate,
    this.originalEndDate,
    required this.requestedStartDate,
    this.requestedEndDate,
    required this.reason,
    this.status = statusPending,
    required this.requestedByUid,
    required this.requestedByName,
    required this.requestedByRole,
    required this.requestedAt,
    this.respondedByUid,
    this.respondedByName,
    this.respondedAt,
    this.rejectionReason,
  });

  bool get isPending => status == statusPending;
  bool get isApproved => status == statusApproved;
  bool get isRejected => status == statusRejected;

  bool get changesStart => requestedStartDate != originalStartDate;
  bool get changesEnd => requestedEndDate != originalEndDate;

  factory ProjectDateExtensionRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    return ProjectDateExtensionRequestModel(
      id: doc.id,
      projectId: data['projectId'] ?? '',
      projectName: data['projectName'] ?? '',
      projectManagerUid: data['projectManagerUid'] as String?,
      projectManagerName: data['projectManagerName'] as String?,
      originalStartDate: (data['originalStartDate'] as Timestamp).toDate(),
      originalEndDate: (data['originalEndDate'] as Timestamp?)?.toDate(),
      requestedStartDate: (data['requestedStartDate'] as Timestamp).toDate(),
      requestedEndDate: (data['requestedEndDate'] as Timestamp?)?.toDate(),
      reason: data['reason'] ?? '',
      status: data['status'] ?? statusPending,
      requestedByUid: data['requestedByUid'] ?? '',
      requestedByName: data['requestedByName'] ?? '',
      requestedByRole: data['requestedByRole'] ?? '',
      requestedAt: (data['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      respondedByUid: data['respondedByUid'] as String?,
      respondedByName: data['respondedByName'] as String?,
      respondedAt: (data['respondedAt'] as Timestamp?)?.toDate(),
      rejectionReason: data['rejectionReason'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'projectId': projectId,
      'projectName': projectName,
      'projectManagerUid': projectManagerUid,
      'projectManagerName': projectManagerName,
      'originalStartDate': Timestamp.fromDate(originalStartDate),
      if (originalEndDate != null) 'originalEndDate': Timestamp.fromDate(originalEndDate!),
      'requestedStartDate': Timestamp.fromDate(requestedStartDate),
      if (requestedEndDate != null) 'requestedEndDate': Timestamp.fromDate(requestedEndDate!),
      'reason': reason,
      'status': status,
      'requestedByUid': requestedByUid,
      'requestedByName': requestedByName,
      'requestedByRole': requestedByRole,
      'requestedAt': Timestamp.fromDate(requestedAt),
      if (respondedByUid != null) 'respondedByUid': respondedByUid,
      if (respondedByName != null) 'respondedByName': respondedByName,
      if (respondedAt != null) 'respondedAt': Timestamp.fromDate(respondedAt!),
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
    };
  }
}
