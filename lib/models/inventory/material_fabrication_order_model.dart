import 'package:cloud_firestore/cloud_firestore.dart';

/// A single "goes out for fabrication" trip for a quantity of a material —
/// decided per issue (not a fixed material property). Chosen deliberately
/// as a mutable "current state" doc (like [AssetBookingModel]), not an
/// append-only ledger like [MaterialMovementModel], since it needs
/// sequential status updates as the physical paper form comes back through
/// Driver -> Fabricator -> Driver -> Technician (none of whom but the
/// Technician have an app account — see class doc on the upload flow).
///
/// The `id` doubles as the human-matchable **Form ID** printed on the paper
/// form, so a scanned form can always be tied back to this record even if
/// OCR only partially succeeds.
class MaterialFabricationOrderModel {
  static const statusIssued = 'issued';
  // Set when the site recipient submitting the scan is a Technician — sits
  // here until an Admin/MainAdmin reviews it, per the two-step
  // Admin-then-SystemAdmin approval chain. Skipped entirely (straight to
  // statusScanUploaded) when the recipient submitting is Admin/MainAdmin
  // themself — they're already trusted to have checked it.
  static const statusPendingAdminReview = 'pendingAdminReview';
  // "Ready for SystemAdmin/MainAdmin verification" — reached either
  // directly (Admin/MainAdmin submitted) or via an explicit admin review
  // (Technician submitted, then reviewed).
  static const statusScanUploaded = 'scanUploaded';
  static const statusVerified = 'verified';
  static const statusDiscrepancy = 'discrepancy';

  static const conditionGood = 'Good';
  static const conditionDamaged = 'Damaged';

  final String id;
  final String materialId;
  final String materialName;
  final String unit;

  final double quantityIssued;
  final String? projectId;
  final String? projectName;
  final String? expectedFabricatorName;

  final String issuedByUid;
  final String issuedByName;
  final DateTime issuedAt;

  final String status;

  // Scan + OCR — pre-fill only, never trusted blindly.
  final String? scannedFormUrl;
  final String? ocrRawText;
  final Map<String, dynamic>? ocrExtractedFields;

  // Human-verified fields — the authoritative record, entered/corrected by
  // whoever uploads the scan after reading the physical form.
  final double? driverAckQuantityAtPickup;
  final String? fabricatorName;
  final double? fabricatorAckQuantityReceived;
  final String? fabricatorAckCondition; // conditionGood | conditionDamaged
  final String? fabricatorDamageNotes;
  final double? fabricatorAckQuantityOutput;
  final double? driverAckQuantityFromFabricator;
  final double? technicianAckQuantityReceived;

  // Field names kept as "technician" for backward compatibility with
  // existing docs — the site recipient submitting the scan may in fact be
  // an Admin/MainAdmin too (see [InventoryPermissions.canUploadFabricationScan]).
  final String? technicianAckByUid;
  final String? technicianAckByName;
  final DateTime? technicianAckAt;

  // Auto-computed at scan-submission time from the quantity chain above —
  // a hint for whoever reviews/verifies, never trusted as the final call
  // (same "computed hint, human decides" pattern as OCR pre-fill).
  final bool hasQuantityDiscrepancy;

  final String? adminReviewedByUid;
  final String? adminReviewedByName;
  final DateTime? adminReviewedAt;

  final String? verifiedByUid;
  final String? verifiedByName;
  final DateTime? verifiedAt;

  const MaterialFabricationOrderModel({
    required this.id,
    required this.materialId,
    required this.materialName,
    required this.unit,
    required this.quantityIssued,
    this.projectId,
    this.projectName,
    this.expectedFabricatorName,
    required this.issuedByUid,
    required this.issuedByName,
    required this.issuedAt,
    required this.status,
    this.scannedFormUrl,
    this.ocrRawText,
    this.ocrExtractedFields,
    this.driverAckQuantityAtPickup,
    this.fabricatorName,
    this.fabricatorAckQuantityReceived,
    this.fabricatorAckCondition,
    this.fabricatorDamageNotes,
    this.fabricatorAckQuantityOutput,
    this.driverAckQuantityFromFabricator,
    this.technicianAckQuantityReceived,
    this.technicianAckByUid,
    this.technicianAckByName,
    this.technicianAckAt,
    this.hasQuantityDiscrepancy = false,
    this.adminReviewedByUid,
    this.adminReviewedByName,
    this.adminReviewedAt,
    this.verifiedByUid,
    this.verifiedByName,
    this.verifiedAt,
  });

  bool get isIssued => status == statusIssued;
  bool get isPendingAdminReview => status == statusPendingAdminReview;
  bool get isScanUploaded => status == statusScanUploaded;
  bool get isVerified => status == statusVerified;
  bool get isDiscrepancy => status == statusDiscrepancy;

  factory MaterialFabricationOrderModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    double? asDouble(String key) => (data[key] as num?)?.toDouble();
    return MaterialFabricationOrderModel(
      id: doc.id,
      materialId: data['materialId'] ?? '',
      materialName: data['materialName'] ?? '',
      unit: data['unit'] ?? '',
      quantityIssued: (data['quantityIssued'] as num?)?.toDouble() ?? 0,
      projectId: data['projectId'] as String?,
      projectName: data['projectName'] as String?,
      expectedFabricatorName: data['expectedFabricatorName'] as String?,
      issuedByUid: data['issuedByUid'] ?? '',
      issuedByName: data['issuedByName'] ?? '',
      issuedAt: (data['issuedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: data['status'] ?? statusIssued,
      scannedFormUrl: data['scannedFormUrl'] as String?,
      ocrRawText: data['ocrRawText'] as String?,
      ocrExtractedFields: (data['ocrExtractedFields'] as Map?)?.cast<String, dynamic>(),
      driverAckQuantityAtPickup: asDouble('driverAckQuantityAtPickup'),
      fabricatorName: data['fabricatorName'] as String?,
      fabricatorAckQuantityReceived: asDouble('fabricatorAckQuantityReceived'),
      fabricatorAckCondition: data['fabricatorAckCondition'] as String?,
      fabricatorDamageNotes: data['fabricatorDamageNotes'] as String?,
      fabricatorAckQuantityOutput: asDouble('fabricatorAckQuantityOutput'),
      driverAckQuantityFromFabricator: asDouble('driverAckQuantityFromFabricator'),
      technicianAckQuantityReceived: asDouble('technicianAckQuantityReceived'),
      technicianAckByUid: data['technicianAckByUid'] as String?,
      technicianAckByName: data['technicianAckByName'] as String?,
      technicianAckAt: (data['technicianAckAt'] as Timestamp?)?.toDate(),
      hasQuantityDiscrepancy: data['hasQuantityDiscrepancy'] as bool? ?? false,
      adminReviewedByUid: data['adminReviewedByUid'] as String?,
      adminReviewedByName: data['adminReviewedByName'] as String?,
      adminReviewedAt: (data['adminReviewedAt'] as Timestamp?)?.toDate(),
      verifiedByUid: data['verifiedByUid'] as String?,
      verifiedByName: data['verifiedByName'] as String?,
      verifiedAt: (data['verifiedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'materialId': materialId,
      'materialName': materialName,
      'unit': unit,
      'quantityIssued': quantityIssued,
      if (projectId != null) 'projectId': projectId,
      if (projectName != null) 'projectName': projectName,
      if (expectedFabricatorName != null) 'expectedFabricatorName': expectedFabricatorName,
      'issuedByUid': issuedByUid,
      'issuedByName': issuedByName,
      'issuedAt': Timestamp.fromDate(issuedAt),
      'status': status,
      if (scannedFormUrl != null) 'scannedFormUrl': scannedFormUrl,
      if (ocrRawText != null) 'ocrRawText': ocrRawText,
      if (ocrExtractedFields != null) 'ocrExtractedFields': ocrExtractedFields,
      if (driverAckQuantityAtPickup != null) 'driverAckQuantityAtPickup': driverAckQuantityAtPickup,
      if (fabricatorName != null) 'fabricatorName': fabricatorName,
      if (fabricatorAckQuantityReceived != null) 'fabricatorAckQuantityReceived': fabricatorAckQuantityReceived,
      if (fabricatorAckCondition != null) 'fabricatorAckCondition': fabricatorAckCondition,
      if (fabricatorDamageNotes != null) 'fabricatorDamageNotes': fabricatorDamageNotes,
      if (fabricatorAckQuantityOutput != null) 'fabricatorAckQuantityOutput': fabricatorAckQuantityOutput,
      if (driverAckQuantityFromFabricator != null)
        'driverAckQuantityFromFabricator': driverAckQuantityFromFabricator,
      if (technicianAckQuantityReceived != null) 'technicianAckQuantityReceived': technicianAckQuantityReceived,
      if (technicianAckByUid != null) 'technicianAckByUid': technicianAckByUid,
      if (technicianAckByName != null) 'technicianAckByName': technicianAckByName,
      if (technicianAckAt != null) 'technicianAckAt': Timestamp.fromDate(technicianAckAt!),
      'hasQuantityDiscrepancy': hasQuantityDiscrepancy,
      if (adminReviewedByUid != null) 'adminReviewedByUid': adminReviewedByUid,
      if (adminReviewedByName != null) 'adminReviewedByName': adminReviewedByName,
      if (adminReviewedAt != null) 'adminReviewedAt': Timestamp.fromDate(adminReviewedAt!),
      if (verifiedByUid != null) 'verifiedByUid': verifiedByUid,
      if (verifiedByName != null) 'verifiedByName': verifiedByName,
      if (verifiedAt != null) 'verifiedAt': Timestamp.fromDate(verifiedAt!),
    };
  }
}
