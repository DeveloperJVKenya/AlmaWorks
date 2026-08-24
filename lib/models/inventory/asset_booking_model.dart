import 'package:cloud_firestore/cloud_firestore.dart';

/// A scheduled reservation of an asset/tool for a date range — sits above
/// the append-only [AssetAssignmentModel] custody ledger. A booking tracks
/// the *plan* (who will hold the item and when); the ledger tracks what
/// *actually* happened (the physical checkout/return events), linked back
/// via [checkoutAssignmentId]/[returnAssignmentId] once they occur.
///
/// Lifecycle: statusScheduled (future-dated, not yet collected) →
/// statusActive (collected — asset currently in this booking's custody) →
/// statusCompleted (returned). A scheduled booking may instead move to
/// statusCancelled before collection.
class AssetBookingModel {
  static const statusScheduled = 'scheduled';
  static const statusActive = 'active';
  static const statusCompleted = 'completed';
  static const statusCancelled = 'cancelled';

  static const deliveryDirect = 'direct';
  static const deliveryDriver = 'driver';

  final String id;
  final String assetId;
  final String assetName;
  final String itemType;

  final String bookedForUid;
  final String bookedForName;
  final String? projectId;
  final String? projectName;

  final DateTime scheduledStart;
  final DateTime scheduledEnd;
  final String status;

  final String? checkoutAssignmentId;
  final String? returnAssignmentId;

  /// Links back to the CheckoutRequestModel that produced this booking via
  /// approval, if it came from the Technician request flow.
  final String? sourceRequestId;

  /// How the item physically reaches [bookedForUid] — a direct in-person
  /// handoff (default) or via a Driver/Transporter (no app account) who
  /// carries it to site, in which case [bookedForUid] confirms arrival via
  /// [deliveryAcknowledgedAt] rather than the admin's condition-assessment
  /// flow ever being exposed to them.
  final String deliveryMethod;
  final String? driverName;
  final DateTime? dispatchedAt;
  final String? dispatchedByUid;
  final String? dispatchedByName;
  final DateTime? deliveryAcknowledgedAt;
  final String? deliveryAcknowledgedByUid;

  /// Photo/scan of the signed physical handover form — the Driver has no
  /// app account, so their pickup acknowledgment (and the recipient's
  /// receipt acknowledgment) is captured on a printed form (see
  /// asset_handover_form_pdf.dart) rather than in-app; this is that signed
  /// form scanned back in by the recipient alongside their digital
  /// [deliveryAcknowledgedAt] confirmation, kept as the physical evidence.
  final String? handoverFormScanUrl;

  final String createdByUid;
  final String createdByName;
  final String createdByRole;
  final DateTime createdAt;

  final String? cancelledByUid;
  final String? cancelledByName;
  final DateTime? cancelledAt;
  final String? cancellationReason;

  const AssetBookingModel({
    required this.id,
    required this.assetId,
    required this.assetName,
    required this.itemType,
    required this.bookedForUid,
    required this.bookedForName,
    this.projectId,
    this.projectName,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.status,
    this.checkoutAssignmentId,
    this.returnAssignmentId,
    this.sourceRequestId,
    this.deliveryMethod = deliveryDirect,
    this.driverName,
    this.dispatchedAt,
    this.dispatchedByUid,
    this.dispatchedByName,
    this.deliveryAcknowledgedAt,
    this.deliveryAcknowledgedByUid,
    this.handoverFormScanUrl,
    required this.createdByUid,
    required this.createdByName,
    required this.createdByRole,
    required this.createdAt,
    this.cancelledByUid,
    this.cancelledByName,
    this.cancelledAt,
    this.cancellationReason,
  });

  bool get isViaDriver => deliveryMethod == deliveryDriver;
  bool get awaitingDeliveryAck => isViaDriver && deliveryAcknowledgedAt == null;

  bool get isScheduled => status == statusScheduled;
  bool get isActive => status == statusActive;
  bool get isCompleted => status == statusCompleted;
  bool get isCancelled => status == statusCancelled;

  /// Still occupies the asset's calendar (blocks overlapping bookings).
  bool get blocksCalendar => isScheduled || isActive;

  factory AssetBookingModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    return AssetBookingModel(
      id: doc.id,
      assetId: data['assetId'] ?? '',
      assetName: data['assetName'] ?? '',
      itemType: data['itemType'] ?? 'Asset',
      bookedForUid: data['bookedForUid'] ?? '',
      bookedForName: data['bookedForName'] ?? '',
      projectId: data['projectId'] as String?,
      projectName: data['projectName'] as String?,
      scheduledStart: (data['scheduledStart'] as Timestamp?)?.toDate() ?? DateTime.now(),
      scheduledEnd: (data['scheduledEnd'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: data['status'] ?? statusScheduled,
      checkoutAssignmentId: data['checkoutAssignmentId'] as String?,
      returnAssignmentId: data['returnAssignmentId'] as String?,
      sourceRequestId: data['sourceRequestId'] as String?,
      deliveryMethod: data['deliveryMethod'] ?? deliveryDirect,
      driverName: data['driverName'] as String?,
      dispatchedAt: (data['dispatchedAt'] as Timestamp?)?.toDate(),
      dispatchedByUid: data['dispatchedByUid'] as String?,
      dispatchedByName: data['dispatchedByName'] as String?,
      deliveryAcknowledgedAt: (data['deliveryAcknowledgedAt'] as Timestamp?)?.toDate(),
      deliveryAcknowledgedByUid: data['deliveryAcknowledgedByUid'] as String?,
      handoverFormScanUrl: data['handoverFormScanUrl'] as String?,
      createdByUid: data['createdByUid'] ?? '',
      createdByName: data['createdByName'] ?? '',
      createdByRole: data['createdByRole'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      cancelledByUid: data['cancelledByUid'] as String?,
      cancelledByName: data['cancelledByName'] as String?,
      cancelledAt: (data['cancelledAt'] as Timestamp?)?.toDate(),
      cancellationReason: data['cancellationReason'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'assetId': assetId,
      'assetName': assetName,
      'itemType': itemType,
      'bookedForUid': bookedForUid,
      'bookedForName': bookedForName,
      if (projectId != null) 'projectId': projectId,
      if (projectName != null) 'projectName': projectName,
      'scheduledStart': Timestamp.fromDate(scheduledStart),
      'scheduledEnd': Timestamp.fromDate(scheduledEnd),
      'status': status,
      'checkoutAssignmentId': checkoutAssignmentId,
      'returnAssignmentId': returnAssignmentId,
      if (sourceRequestId != null) 'sourceRequestId': sourceRequestId,
      'deliveryMethod': deliveryMethod,
      if (driverName != null) 'driverName': driverName,
      if (dispatchedAt != null) 'dispatchedAt': Timestamp.fromDate(dispatchedAt!),
      if (dispatchedByUid != null) 'dispatchedByUid': dispatchedByUid,
      if (dispatchedByName != null) 'dispatchedByName': dispatchedByName,
      if (deliveryAcknowledgedAt != null) 'deliveryAcknowledgedAt': Timestamp.fromDate(deliveryAcknowledgedAt!),
      if (deliveryAcknowledgedByUid != null) 'deliveryAcknowledgedByUid': deliveryAcknowledgedByUid,
      if (handoverFormScanUrl != null) 'handoverFormScanUrl': handoverFormScanUrl,
      'createdByUid': createdByUid,
      'createdByName': createdByName,
      'createdByRole': createdByRole,
      'createdAt': Timestamp.fromDate(createdAt),
      if (cancelledByUid != null) 'cancelledByUid': cancelledByUid,
      if (cancelledByName != null) 'cancelledByName': cancelledByName,
      if (cancelledAt != null) 'cancelledAt': Timestamp.fromDate(cancelledAt!),
      if (cancellationReason != null) 'cancellationReason': cancellationReason,
    };
  }
}
