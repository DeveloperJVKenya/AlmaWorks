// models/client_request_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class ClientRequest {
  final String requestId;
  final String clientUsername;
  final String clientEmail;
  final String clientUid;
  final DateTime requestDate;
  final String status; // 'pending', 'approved', 'denied'
  final List<String> grantedProjects; // List of project IDs
  final String? approvedBy; // Admin username who approved/denied
  final String? approvedByUid; // Admin UID
  final DateTime? approvalDate;
  final String? denialReason;

  /// The role granted on approval — 'Client' or 'Technician'. Every account
  /// self-registers as 'Client' (registration_screen.dart hardcodes this)
  /// and submits this same request either way; it's only at approval time
  /// that an Admin/MainAdmin decides which role to actually grant, which
  /// then overwrites Users/{username}.role. Defaults to 'Client' so
  /// pre-existing request docs (written before this field existed) still
  /// parse correctly.
  final String grantedRole;

  ClientRequest({
    required this.requestId,
    required this.clientUsername,
    required this.clientEmail,
    required this.clientUid,
    required this.requestDate,
    required this.status,
    this.grantedProjects = const [],
    this.approvedBy,
    this.approvedByUid,
    this.approvalDate,
    this.denialReason,
    this.grantedRole = 'Client',
  });

  // Convert from Firestore document
  factory ClientRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ClientRequest(
      requestId: doc.id,
      clientUsername: data['clientUsername'] ?? '',
      clientEmail: data['clientEmail'] ?? '',
      clientUid: data['clientUid'] ?? '',
      requestDate: (data['requestDate'] as Timestamp).toDate(),
      status: data['status'] ?? 'pending',
      grantedProjects: List<String>.from(data['grantedProjects'] ?? []),
      approvedBy: data['approvedBy'],
      approvedByUid: data['approvedByUid'],
      approvalDate: data['approvalDate'] != null 
          ? (data['approvalDate'] as Timestamp).toDate() 
          : null,
      denialReason: data['denialReason'],
      grantedRole: data['grantedRole'] as String? ?? 'Client',
    );
  }

  // Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'clientUsername': clientUsername,
      'clientEmail': clientEmail,
      'clientUid': clientUid,
      'requestDate': Timestamp.fromDate(requestDate),
      'status': status,
      'grantedProjects': grantedProjects,
      'approvedBy': approvedBy,
      'approvedByUid': approvedByUid,
      'approvalDate': approvalDate != null 
          ? Timestamp.fromDate(approvalDate!) 
          : null,
      'denialReason': denialReason,
      'grantedRole': grantedRole,
    };
  }

  // Copy with method for updates
  ClientRequest copyWith({
    String? requestId,
    String? clientUsername,
    String? clientEmail,
    String? clientUid,
    DateTime? requestDate,
    String? status,
    List<String>? grantedProjects,
    String? approvedBy,
    String? approvedByUid,
    DateTime? approvalDate,
    String? denialReason,
    String? grantedRole,
  }) {
    return ClientRequest(
      requestId: requestId ?? this.requestId,
      clientUsername: clientUsername ?? this.clientUsername,
      clientEmail: clientEmail ?? this.clientEmail,
      clientUid: clientUid ?? this.clientUid,
      requestDate: requestDate ?? this.requestDate,
      status: status ?? this.status,
      grantedProjects: grantedProjects ?? this.grantedProjects,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedByUid: approvedByUid ?? this.approvedByUid,
      approvalDate: approvalDate ?? this.approvalDate,
      denialReason: denialReason ?? this.denialReason,
      grantedRole: grantedRole ?? this.grantedRole,
    );
  }
}