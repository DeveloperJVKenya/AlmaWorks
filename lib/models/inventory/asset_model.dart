import 'package:cloud_firestore/cloud_firestore.dart';

/// Company asset/tool register entry — Inventory module, Phase 1.
///
/// `currentHolderId`/`currentAssignmentId`/etc. are a denormalized snapshot
/// of "who has it right now", kept in sync by [InventoryService]'s checkout/
/// return transaction. The authoritative history lives in the append-only
/// `InventoryAssetAssignments` ledger — these fields are a read optimization
/// for list/detail screens, not the source of truth.
class AssetModel {
  static const statusAvailable = 'Available';
  static const statusCheckedOut = 'Checked Out';
  static const statusUnderMaintenance = 'Under Maintenance';
  static const statusRetired = 'Retired';

  final String id;
  final String name;
  final String category;
  final String? description;
  final String? serialNumber;
  final String? photoUrl;
  final String status;
  final String? currentHolderId;
  final String? currentHolderName;
  final String? currentProjectId;
  final String? currentProjectName;
  final String? currentAssignmentId;
  final String createdByUid;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AssetModel({
    required this.id,
    required this.name,
    required this.category,
    this.description,
    this.serialNumber,
    this.photoUrl,
    required this.status,
    this.currentHolderId,
    this.currentHolderName,
    this.currentProjectId,
    this.currentProjectName,
    this.currentAssignmentId,
    required this.createdByUid,
    required this.createdByName,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isAvailable => status == statusAvailable;
  bool get isCheckedOut => status == statusCheckedOut;

  factory AssetModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    return AssetModel(
      id: doc.id,
      name: data['name'] ?? '',
      category: data['category'] ?? '',
      description: data['description'] as String?,
      serialNumber: data['serialNumber'] as String?,
      photoUrl: data['photoUrl'] as String?,
      status: data['status'] ?? statusAvailable,
      currentHolderId: data['currentHolderId'] as String?,
      currentHolderName: data['currentHolderName'] as String?,
      currentProjectId: data['currentProjectId'] as String?,
      currentProjectName: data['currentProjectName'] as String?,
      currentAssignmentId: data['currentAssignmentId'] as String?,
      createdByUid: data['createdByUid'] ?? '',
      createdByName: data['createdByName'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'category': category,
      if (description != null) 'description': description,
      if (serialNumber != null) 'serialNumber': serialNumber,
      if (photoUrl != null) 'photoUrl': photoUrl,
      'status': status,
      'currentHolderId': currentHolderId,
      'currentHolderName': currentHolderName,
      'currentProjectId': currentProjectId,
      'currentProjectName': currentProjectName,
      'currentAssignmentId': currentAssignmentId,
      'createdByUid': createdByUid,
      'createdByName': createdByName,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  AssetModel copyWith({
    String? name,
    String? category,
    String? description,
    String? serialNumber,
    String? photoUrl,
    String? status,
    String? currentHolderId,
    String? currentHolderName,
    String? currentProjectId,
    String? currentProjectName,
    String? currentAssignmentId,
    DateTime? updatedAt,
  }) {
    return AssetModel(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      description: description ?? this.description,
      serialNumber: serialNumber ?? this.serialNumber,
      photoUrl: photoUrl ?? this.photoUrl,
      status: status ?? this.status,
      currentHolderId: currentHolderId ?? this.currentHolderId,
      currentHolderName: currentHolderName ?? this.currentHolderName,
      currentProjectId: currentProjectId ?? this.currentProjectId,
      currentProjectName: currentProjectName ?? this.currentProjectName,
      currentAssignmentId: currentAssignmentId ?? this.currentAssignmentId,
      createdByUid: createdByUid,
      createdByName: createdByName,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
