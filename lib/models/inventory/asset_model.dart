import 'package:cloud_firestore/cloud_firestore.dart';

/// Company asset/tool register entry — Inventory module.
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

  static const conditionNew = 'New';
  static const conditionGood = 'Good';
  static const conditionFair = 'Fair';
  static const conditionDamaged = 'Damaged';

  /// Distinguishes the "Assets" tab from the "Tools" tab in the Inventory
  /// UI. Both share this exact model/collection/custody-ledger shape (single
  /// item, checked out to one holder at a time, returned to storage) — only
  /// their category options and display grouping differ, so a full parallel
  /// model isn't warranted.
  static const typeAsset = 'Asset';
  static const typeTool = 'Tool';

  final String id;
  final String itemType;
  final String name;
  final String category;
  final String? description;
  final String? serialNumber;
  final String? photoUrl;
  final String status;

  /// Condition recorded when the asset was first registered — distinct from
  /// the condition captured at each checkout/return event in the custody
  /// ledger, which tracks how condition changes over time.
  final String initialCondition;

  final String? currentHolderId;
  final String? currentHolderName;
  final String? currentProjectId;
  final String? currentProjectName;
  final String? currentAssignmentId;

  /// Set while a checkout request is awaiting MainAdmin review — blocks any
  /// other Admin from requesting the same asset in the meantime. Cleared on
  /// approval (asset moves to Checked Out) or rejection (back to Available).
  final String? pendingRequestId;

  final String createdByUid;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AssetModel({
    required this.id,
    this.itemType = typeAsset,
    required this.name,
    required this.category,
    this.description,
    this.serialNumber,
    this.photoUrl,
    required this.status,
    this.initialCondition = conditionGood,
    this.currentHolderId,
    this.currentHolderName,
    this.currentProjectId,
    this.currentProjectName,
    this.currentAssignmentId,
    this.pendingRequestId,
    required this.createdByUid,
    required this.createdByName,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isAvailable => status == statusAvailable && pendingRequestId == null;
  bool get isCheckedOut => status == statusCheckedOut;
  bool get hasPendingRequest => pendingRequestId != null;

  factory AssetModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    return AssetModel(
      id: doc.id,
      itemType: data['itemType'] ?? typeAsset,
      name: data['name'] ?? '',
      category: data['category'] ?? '',
      description: data['description'] as String?,
      serialNumber: data['serialNumber'] as String?,
      photoUrl: data['photoUrl'] as String?,
      status: data['status'] ?? statusAvailable,
      initialCondition: data['initialCondition'] ?? conditionGood,
      currentHolderId: data['currentHolderId'] as String?,
      currentHolderName: data['currentHolderName'] as String?,
      currentProjectId: data['currentProjectId'] as String?,
      currentProjectName: data['currentProjectName'] as String?,
      currentAssignmentId: data['currentAssignmentId'] as String?,
      pendingRequestId: data['pendingRequestId'] as String?,
      createdByUid: data['createdByUid'] ?? '',
      createdByName: data['createdByName'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'itemType': itemType,
      'name': name,
      'category': category,
      if (description != null) 'description': description,
      if (serialNumber != null) 'serialNumber': serialNumber,
      if (photoUrl != null) 'photoUrl': photoUrl,
      'status': status,
      'initialCondition': initialCondition,
      'currentHolderId': currentHolderId,
      'currentHolderName': currentHolderName,
      'currentProjectId': currentProjectId,
      'currentProjectName': currentProjectName,
      'currentAssignmentId': currentAssignmentId,
      'pendingRequestId': pendingRequestId,
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
    String? initialCondition,
    String? currentHolderId,
    String? currentHolderName,
    String? currentProjectId,
    String? currentProjectName,
    String? currentAssignmentId,
    String? pendingRequestId,
    DateTime? updatedAt,
  }) {
    return AssetModel(
      id: id,
      itemType: itemType,
      name: name ?? this.name,
      category: category ?? this.category,
      description: description ?? this.description,
      serialNumber: serialNumber ?? this.serialNumber,
      photoUrl: photoUrl ?? this.photoUrl,
      status: status ?? this.status,
      initialCondition: initialCondition ?? this.initialCondition,
      currentHolderId: currentHolderId ?? this.currentHolderId,
      currentHolderName: currentHolderName ?? this.currentHolderName,
      currentProjectId: currentProjectId ?? this.currentProjectId,
      currentProjectName: currentProjectName ?? this.currentProjectName,
      currentAssignmentId: currentAssignmentId ?? this.currentAssignmentId,
      pendingRequestId: pendingRequestId ?? this.pendingRequestId,
      createdByUid: createdByUid,
      createdByName: createdByName,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
