import 'package:cloud_firestore/cloud_firestore.dart';

/// A single entry in a material's stock ledger (received or issued).
///
/// Firestore security rules make this collection append-only: once written,
/// an entry can never be updated or deleted by anyone, including MainAdmin.
/// Do not add any mutation methods here beyond construction.
class MaterialMovementModel {
  static const movementReceived = 'received';
  static const movementIssued = 'issued';

  static const conditionGood = 'Good';
  static const conditionDamaged = 'Damaged';
  static const conditionPartial = 'Partially Damaged';

  final String id;
  final String materialId;
  final String movementType; // movementReceived | movementIssued
  final double quantity;

  // Issued-only: where the stock is going.
  final String? projectId;
  final String? projectName;

  // Received-only: provenance/verification for international shipments.
  final String? conditionOnReceipt; // conditionGood | conditionDamaged | conditionPartial
  final String? portVerifiedByName; // who verified at port of arrival (international only)
  final String? receivedByName; // who signed for it into company storage

  final String notes;
  final List<String> photoUrls;
  final String recordedByUid;
  final String recordedByName;
  final String recordedByRole;
  final DateTime eventAt;
  final DateTime createdAt;

  const MaterialMovementModel({
    required this.id,
    required this.materialId,
    required this.movementType,
    required this.quantity,
    this.projectId,
    this.projectName,
    this.conditionOnReceipt,
    this.portVerifiedByName,
    this.receivedByName,
    required this.notes,
    required this.photoUrls,
    required this.recordedByUid,
    required this.recordedByName,
    required this.recordedByRole,
    required this.eventAt,
    required this.createdAt,
  });

  bool get isReceived => movementType == movementReceived;
  bool get isIssued => movementType == movementIssued;

  factory MaterialMovementModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    return MaterialMovementModel(
      id: doc.id,
      materialId: data['materialId'] ?? '',
      movementType: data['movementType'] ?? movementReceived,
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0,
      projectId: data['projectId'] as String?,
      projectName: data['projectName'] as String?,
      conditionOnReceipt: data['conditionOnReceipt'] as String?,
      portVerifiedByName: data['portVerifiedByName'] as String?,
      receivedByName: data['receivedByName'] as String?,
      notes: data['notes'] ?? '',
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
      'materialId': materialId,
      'movementType': movementType,
      'quantity': quantity,
      if (projectId != null) 'projectId': projectId,
      if (projectName != null) 'projectName': projectName,
      if (conditionOnReceipt != null) 'conditionOnReceipt': conditionOnReceipt,
      if (portVerifiedByName != null) 'portVerifiedByName': portVerifiedByName,
      if (receivedByName != null) 'receivedByName': receivedByName,
      'notes': notes,
      'photoUrls': photoUrls,
      'recordedByUid': recordedByUid,
      'recordedByName': recordedByName,
      'recordedByRole': recordedByRole,
      'eventAt': Timestamp.fromDate(eventAt),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
