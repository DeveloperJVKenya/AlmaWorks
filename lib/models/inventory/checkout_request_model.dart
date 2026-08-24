import 'package:cloud_firestore/cloud_firestore.dart';

/// A checkout request: an Admin asks to check out an asset/tool; a
/// MainAdmin reviews and either approves (which performs the actual
/// checkout, capturing condition + photos at that moment) or rejects it.
/// While a request is pending, the asset is locked — no other Admin can
/// request it and it can't be checked out any other way.
class CheckoutRequestModel {
  static const statusPending = 'pending';
  static const statusApproved = 'approved';
  static const statusRejected = 'rejected';

  final String id;
  final String assetId;
  final String assetName;
  final String itemType;
  final String requestedByUid;
  final String requestedByName;
  final String? projectId;
  final String? projectName;
  final String reason;

  /// Wanted booking window — may start today or on a future date; approval
  /// creates an AssetBookingModel for exactly this range.
  final DateTime requestedStart;
  final DateTime requestedEnd;

  final String status;
  final DateTime requestedAt;
  final String? respondedByUid;
  final String? respondedByName;
  final DateTime? respondedAt;
  final String? rejectionReason;

  const CheckoutRequestModel({
    required this.id,
    required this.assetId,
    required this.assetName,
    required this.itemType,
    required this.requestedByUid,
    required this.requestedByName,
    this.projectId,
    this.projectName,
    required this.reason,
    required this.requestedStart,
    required this.requestedEnd,
    required this.status,
    required this.requestedAt,
    this.respondedByUid,
    this.respondedByName,
    this.respondedAt,
    this.rejectionReason,
  });

  bool get isPending => status == statusPending;
  bool get isApproved => status == statusApproved;
  bool get isRejected => status == statusRejected;

  factory CheckoutRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    return CheckoutRequestModel(
      id: doc.id,
      assetId: data['assetId'] ?? '',
      assetName: data['assetName'] ?? '',
      itemType: data['itemType'] ?? 'Asset',
      requestedByUid: data['requestedByUid'] ?? '',
      requestedByName: data['requestedByName'] ?? '',
      projectId: data['projectId'] as String?,
      projectName: data['projectName'] as String?,
      reason: data['reason'] ?? '',
      requestedStart: (data['requestedStart'] as Timestamp?)?.toDate() ?? DateTime.now(),
      requestedEnd: (data['requestedEnd'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: data['status'] ?? statusPending,
      requestedAt: (data['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      respondedByUid: data['respondedByUid'] as String?,
      respondedByName: data['respondedByName'] as String?,
      respondedAt: (data['respondedAt'] as Timestamp?)?.toDate(),
      rejectionReason: data['rejectionReason'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'assetId': assetId,
      'assetName': assetName,
      'itemType': itemType,
      'requestedByUid': requestedByUid,
      'requestedByName': requestedByName,
      if (projectId != null) 'projectId': projectId,
      if (projectName != null) 'projectName': projectName,
      'reason': reason,
      'requestedStart': Timestamp.fromDate(requestedStart),
      'requestedEnd': Timestamp.fromDate(requestedEnd),
      'status': status,
      'requestedAt': Timestamp.fromDate(requestedAt),
      if (respondedByUid != null) 'respondedByUid': respondedByUid,
      if (respondedByName != null) 'respondedByName': respondedByName,
      if (respondedAt != null) 'respondedAt': Timestamp.fromDate(respondedAt!),
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
    };
  }
}
