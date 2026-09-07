import 'package:cloud_firestore/cloud_firestore.dart';

/// A single accountability entry for the Documents section: who uploaded or
/// deleted a document, in which tab/sub-tab, and when.
///
/// Firestore security rules make this collection append-only: once written,
/// an entry can never be updated or deleted by anyone. Do not add any
/// mutation methods here beyond construction.
class DocumentAuditEntry {
  static const actionUpload = 'upload';
  static const actionDelete = 'delete';

  final String id;
  final String projectId;
  final String mainTab; // 'Client' | 'Sub-Contractor' | 'Supplier' | a custom team-member role
  final String section; // 'Contract' | 'Communication' | 'Access Requests'
  final String teamMemberName; // '' when not applicable (e.g. Client tab)
  final String documentId;
  final String documentTitle;
  final String action; // actionUpload | actionDelete
  final String actorUid;
  final String actorName;
  final String actorRole;
  final DateTime createdAt;

  const DocumentAuditEntry({
    required this.id,
    required this.projectId,
    required this.mainTab,
    required this.section,
    required this.teamMemberName,
    required this.documentId,
    required this.documentTitle,
    required this.action,
    required this.actorUid,
    required this.actorName,
    required this.actorRole,
    required this.createdAt,
  });

  bool get isUpload => action == actionUpload;
  bool get isDelete => action == actionDelete;

  factory DocumentAuditEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    return DocumentAuditEntry(
      id: doc.id,
      projectId: data['projectId'] ?? '',
      mainTab: data['mainTab'] ?? '',
      section: data['section'] ?? '',
      teamMemberName: data['teamMemberName'] ?? '',
      documentId: data['documentId'] ?? '',
      documentTitle: data['documentTitle'] ?? '',
      action: data['action'] ?? actionUpload,
      actorUid: data['actorUid'] ?? '',
      actorName: data['actorName'] ?? '',
      actorRole: data['actorRole'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'projectId': projectId,
      'mainTab': mainTab,
      'section': section,
      'teamMemberName': teamMemberName,
      'documentId': documentId,
      'documentTitle': documentTitle,
      'action': action,
      'actorUid': actorUid,
      'actorName': actorName,
      'actorRole': actorRole,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
