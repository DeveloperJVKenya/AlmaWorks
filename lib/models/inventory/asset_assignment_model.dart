import 'package:cloud_firestore/cloud_firestore.dart';

/// A single entry in an asset's custody ledger (checkout or return).
///
/// Firestore security rules make this collection append-only: once written,
/// an entry can never be updated or deleted by anyone, including MainAdmin.
/// Do not add any mutation methods here beyond construction.
class AssetAssignmentModel {
  static const eventCheckout = 'checkout';
  static const eventReturn = 'return';

  final String id;
  final String assetId;
  final String eventType; // eventCheckout | eventReturn
  final String? previousAssignmentId; // set on a return, points at the checkout it closes

  /// Links this event to the AssetBookingModel it fulfills — null for events
  /// recorded before booking existed, or for legacy immediate checkouts.
  final String? bookingId;

  final String assignedToUserId;
  final String assignedToName;
  final String? projectId;
  final String? projectName;
  final String conditionNotes;

  /// Structured condition snapshot (AssetModel.condition* constants) taken
  /// at this event — makes condition queryable/filterable (e.g. "all Damaged
  /// returns and who held the asset") rather than only free-text prose.
  final String? conditionRating;

  final List<String> photoUrls;
  final String recordedByUid;
  final String recordedByName;
  final String recordedByRole;
  final DateTime eventAt;
  final DateTime createdAt;

  const AssetAssignmentModel({
    required this.id,
    required this.assetId,
    required this.eventType,
    this.previousAssignmentId,
    this.bookingId,
    required this.assignedToUserId,
    required this.assignedToName,
    this.projectId,
    this.projectName,
    required this.conditionNotes,
    this.conditionRating,
    required this.photoUrls,
    required this.recordedByUid,
    required this.recordedByName,
    required this.recordedByRole,
    required this.eventAt,
    required this.createdAt,
  });

  bool get isCheckout => eventType == eventCheckout;
  bool get isReturn => eventType == eventReturn;

  factory AssetAssignmentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    return AssetAssignmentModel(
      id: doc.id,
      assetId: data['assetId'] ?? '',
      eventType: data['eventType'] ?? eventCheckout,
      previousAssignmentId: data['previousAssignmentId'] as String?,
      bookingId: data['bookingId'] as String?,
      assignedToUserId: data['assignedToUserId'] ?? '',
      assignedToName: data['assignedToName'] ?? '',
      projectId: data['projectId'] as String?,
      projectName: data['projectName'] as String?,
      conditionNotes: data['conditionNotes'] ?? '',
      conditionRating: data['conditionRating'] as String?,
      photoUrls: List<String>.from(data['photoUrls'] as List? ?? const []),
      recordedByUid: data['recordedByUid'] ?? '',
      recordedByName: data['recordedByName'] ?? '',
      recordedByRole: data['recordedByRole'] ?? '',
      eventAt: (data['eventAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'assetId': assetId,
      'eventType': eventType,
      if (previousAssignmentId != null) 'previousAssignmentId': previousAssignmentId,
      if (bookingId != null) 'bookingId': bookingId,
      'assignedToUserId': assignedToUserId,
      'assignedToName': assignedToName,
      if (projectId != null) 'projectId': projectId,
      if (projectName != null) 'projectName': projectName,
      'conditionNotes': conditionNotes,
      if (conditionRating != null) 'conditionRating': conditionRating,
      'photoUrls': photoUrls,
      'recordedByUid': recordedByUid,
      'recordedByName': recordedByName,
      'recordedByRole': recordedByRole,
      'eventAt': Timestamp.fromDate(eventAt),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
