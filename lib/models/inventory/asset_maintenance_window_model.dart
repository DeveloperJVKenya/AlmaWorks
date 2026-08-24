import 'package:cloud_firestore/cloud_firestore.dart';

/// A blackout date range during which an asset/tool cannot be booked (e.g.
/// scheduled servicing). Unlike the custody/movement ledgers, this is plain
/// scheduling data, not an audit record — MainAdmin/Admin may cancel one
/// outright if plans change.
class AssetMaintenanceWindowModel {
  final String id;
  final String assetId;
  final String assetName;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;

  final String createdByUid;
  final String createdByName;
  final DateTime createdAt;

  const AssetMaintenanceWindowModel({
    required this.id,
    required this.assetId,
    required this.assetName,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.createdByUid,
    required this.createdByName,
    required this.createdAt,
  });

  factory AssetMaintenanceWindowModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    return AssetMaintenanceWindowModel(
      id: doc.id,
      assetId: data['assetId'] ?? '',
      assetName: data['assetName'] ?? '',
      startDate: (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (data['endDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reason: data['reason'] ?? '',
      createdByUid: data['createdByUid'] ?? '',
      createdByName: data['createdByName'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'assetId': assetId,
      'assetName': assetName,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'reason': reason,
      'createdByUid': createdByUid,
      'createdByName': createdByName,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
