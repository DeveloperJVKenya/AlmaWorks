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

  /// Set while a checkout request is awaiting MainAdmin/Admin review — blocks
  /// any other Admin from requesting the same asset in the meantime. Cleared
  /// on approval (asset moves to Checked Out) or rejection (back to Available).
  final String? pendingRequestId;

  /// Set when the current holder taps "Return Asset/Tool" (see
  /// InventoryService.notifyReturnIntent) — gates the MainAdmin/SystemAdmin
  /// "Record Return" action in the UI so it stays disabled/faint until the
  /// holder has actually signalled they're returning it, with an explicit
  /// override available for when the holder is unreachable. Cleared once the
  /// return is actually recorded.
  final DateTime? returnRequestedAt;

  /// Denormalized snapshot of the soonest upcoming *scheduled* booking (see
  /// AssetBookingModel/InventoryAssetBookings) — lets list/detail screens
  /// show "Booked from 14 Aug by J. Otieno" without a per-asset query. Kept
  /// in sync by InventoryService whenever a booking is created/cancelled/
  /// activated. Not the source of truth — that's the bookings collection.
  final String? nextBookingId;
  final DateTime? nextBookingStart;
  final DateTime? nextBookingEnd;
  final String? nextBookingByName;

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
    this.returnRequestedAt,
    this.nextBookingId,
    this.nextBookingStart,
    this.nextBookingEnd,
    this.nextBookingByName,
    required this.createdByUid,
    required this.createdByName,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isAvailable => status == statusAvailable && pendingRequestId == null;
  bool get isCheckedOut => status == statusCheckedOut;
  bool get hasPendingRequest => pendingRequestId != null;
  bool get hasUpcomingBooking => nextBookingId != null;

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
      returnRequestedAt: (data['returnRequestedAt'] as Timestamp?)?.toDate(),
      nextBookingId: data['nextBookingId'] as String?,
      nextBookingStart: (data['nextBookingStart'] as Timestamp?)?.toDate(),
      nextBookingEnd: (data['nextBookingEnd'] as Timestamp?)?.toDate(),
      nextBookingByName: data['nextBookingByName'] as String?,
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
      if (returnRequestedAt != null) 'returnRequestedAt': Timestamp.fromDate(returnRequestedAt!),
      'nextBookingId': nextBookingId,
      if (nextBookingStart != null) 'nextBookingStart': Timestamp.fromDate(nextBookingStart!),
      if (nextBookingEnd != null) 'nextBookingEnd': Timestamp.fromDate(nextBookingEnd!),
      'nextBookingByName': nextBookingByName,
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
    DateTime? returnRequestedAt,
    bool clearReturnRequestedAt = false,
    String? nextBookingId,
    DateTime? nextBookingStart,
    DateTime? nextBookingEnd,
    String? nextBookingByName,
    bool clearNextBooking = false,
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
      returnRequestedAt: clearReturnRequestedAt ? null : (returnRequestedAt ?? this.returnRequestedAt),
      nextBookingId: clearNextBooking ? null : (nextBookingId ?? this.nextBookingId),
      nextBookingStart: clearNextBooking ? null : (nextBookingStart ?? this.nextBookingStart),
      nextBookingEnd: clearNextBooking ? null : (nextBookingEnd ?? this.nextBookingEnd),
      nextBookingByName: clearNextBooking ? null : (nextBookingByName ?? this.nextBookingByName),
      createdByUid: createdByUid,
      createdByName: createdByName,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
