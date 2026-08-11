// services/client_request_service.dart
import 'package:almaworks/rbacsystem/client_request_model.dart';
import 'package:almaworks/rbacsystem/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

class ClientRequestService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();
  final Logger _logger = Logger();

  // ──────────────────────────────────────────────────────────────────────────
  // Submit
  // ──────────────────────────────────────────────────────────────────────────

  Future<String?> submitClientRequest({
    required String clientUsername,
    required String clientEmail,
    required String clientUid,
  }) async {
    try {
      _logger.i('📝 Submitting client request for: $clientUsername');

      final existingRequest = await _firestore
          .collection('ClientRequests')
          .where('clientUid', isEqualTo: clientUid)
          .where('status', isEqualTo: 'pending')
          .get();

      if (existingRequest.docs.isNotEmpty) {
        _logger.w('⚠️ User already has a pending request');
        return 'You already have a pending access request.';
      }

      final request = ClientRequest(
        requestId: '',
        clientUsername: clientUsername,
        clientEmail: clientEmail,
        clientUid: clientUid,
        requestDate: DateTime.now(),
        status: 'pending',
      );

      final docRef = await _firestore
          .collection('ClientRequests')
          .add(request.toFirestore());

      _logger.i('✅ Client request created: ${docRef.id}');

      await _notificationService.notifyAdminsOfClientRequest(
        clientUsername: clientUsername,
        requestId: docRef.id,
      );

      return null;
    } catch (e) {
      _logger.e('❌ Error submitting client request: $e');
      return 'Failed to submit request. Please try again.';
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Streams
  // ──────────────────────────────────────────────────────────────────────────

  Stream<List<ClientRequest>> getPendingRequests() {
    return _firestore
        .collection('ClientRequests')
        .where('status', isEqualTo: 'pending')
        .orderBy('requestDate', descending: true)
        .snapshots()
        .map((s) => s.docs.map(ClientRequest.fromFirestore).toList());
  }

  Stream<List<ClientRequest>> getAllRequests() {
    return _firestore
        .collection('ClientRequests')
        .orderBy('requestDate', descending: true)
        .snapshots()
        .map((s) => s.docs.map(ClientRequest.fromFirestore).toList());
  }

  Stream<ClientRequest?> getClientRequestStatus(String clientUid) {
    return _firestore
        .collection('ClientRequests')
        .where('clientUid', isEqualTo: clientUid)
        .orderBy('requestDate', descending: true)
        .limit(1)
        .snapshots()
        .map((s) {
      if (s.docs.isEmpty) return null;
      return ClientRequest.fromFirestore(s.docs.first);
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Approve
  // ──────────────────────────────────────────────────────────────────────────

  Future<String?> approveClientRequest({
    required String requestId,
    required List<String> projectIds,
    required String approvedByUsername,
    required String approvedByUid,
    // 'Client' or 'Technician' — every account self-registers as 'Client'
    // and goes through this same request either way; this is the one
    // point where an Admin/MainAdmin actually decides which role the
    // account ends up with. Defaults to 'Client' so every existing call
    // site (which predates Technician) keeps its current behavior exactly.
    String grantedRole = 'Client',
  }) async {
    try {
      _logger.i('✅ Approving request: $requestId as $grantedRole');

      final requestDoc = await _firestore
          .collection('ClientRequests')
          .doc(requestId)
          .get();
      if (!requestDoc.exists) return 'Request not found';

      final request = ClientRequest.fromFirestore(requestDoc);

      await _firestore.collection('ClientRequests').doc(requestId).update({
        'status': 'approved',
        'grantedProjects': projectIds,
        'approvedBy': approvedByUsername,
        'approvedByUid': approvedByUid,
        'approvalDate': Timestamp.now(),
        'denialReason': null,
        'grantedRole': grantedRole,
      });

      await _updateClientProjectAccess(
        clientUid: request.clientUid,
        projectIds: projectIds,
        role: grantedRole,
      );

      final projectNames = await _getProjectNames(projectIds);
      await _notificationService.notifyClientOfApproval(
        clientUsername: request.clientUsername,
        projectNames: projectNames,
      );

      _logger.i('✅ Request approved successfully');
      return null;
    } catch (e) {
      _logger.e('❌ Error approving request: $e');
      return 'Failed to approve request. Please try again.';
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Deny
  // ──────────────────────────────────────────────────────────────────────────

  Future<String?> denyClientRequest({
    required String requestId,
    required String deniedByUsername,
    required String deniedByUid,
    String? reason,
  }) async {
    try {
      _logger.i('❌ Denying request: $requestId');

      final requestDoc = await _firestore
          .collection('ClientRequests')
          .doc(requestId)
          .get();
      if (!requestDoc.exists) return 'Request not found';

      final request = ClientRequest.fromFirestore(requestDoc);

      await _firestore.collection('ClientRequests').doc(requestId).update({
        'status': 'denied',
        'approvedBy': deniedByUsername,
        'approvedByUid': deniedByUid,
        'approvalDate': Timestamp.now(),
        'denialReason': reason,
        'grantedProjects': [],
      });

      await _notificationService.notifyClientOfDenial(
        clientUsername: request.clientUsername,
        reason: reason,
      );

      _logger.i('✅ Request denied successfully');
      return null;
    } catch (e) {
      _logger.e('❌ Error denying request: $e');
      return 'Failed to deny request. Please try again.';
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // History item editing — Approved requests
  // ──────────────────────────────────────────────────────────────────────────

  /// Adds [newProjectIds] to an already-approved request and updates the
  /// user's Firestore access document.
  Future<String?> addProjectsToApprovedRequest({
    required String requestId,
    required String clientUid,
    required String clientUsername,
    required List<String> newProjectIds,
    required String adminUsername,
    required String adminUid,
  }) async {
    try {
      _logger.i('➕ Adding projects to approved request: $requestId');

      final requestDoc = await _firestore
          .collection('ClientRequests')
          .doc(requestId)
          .get();
      if (!requestDoc.exists) return 'Request not found';

      final request = ClientRequest.fromFirestore(requestDoc);
      final current = List<String>.from(request.grantedProjects);
      final merged = {...current, ...newProjectIds}.toList();

      await _firestore.collection('ClientRequests').doc(requestId).update({
        'grantedProjects': merged,
        'approvedBy': adminUsername,
        'approvedByUid': adminUid,
        'approvalDate': Timestamp.now(),
      });

      // Sync user access.
      await _updateClientProjectAccess(
        clientUid: clientUid,
        projectIds: merged,
      );

      final newNames = await _getProjectNames(newProjectIds);
      await _notificationService.notifyClientOfProjectUpdate(
        clientUsername: clientUsername,
        addedProjects: newNames,
        revokedProjects: [],
      );

      _logger.i('✅ Projects added successfully');
      return null;
    } catch (e) {
      _logger.e('❌ Error adding projects: $e');
      return 'Failed to add projects. Please try again.';
    }
  }

  /// Removes [projectIdsToRevoke] from an already-approved request and
  /// updates the user's Firestore access document.
  Future<String?> revokeProjectsFromApprovedRequest({
    required String requestId,
    required String clientUid,
    required String clientUsername,
    required List<String> projectIdsToRevoke,
    required String adminUsername,
    required String adminUid,
  }) async {
    try {
      _logger.i('🔒 Revoking projects from approved request: $requestId');

      final requestDoc = await _firestore
          .collection('ClientRequests')
          .doc(requestId)
          .get();
      if (!requestDoc.exists) return 'Request not found';

      final request = ClientRequest.fromFirestore(requestDoc);
      final updated = request.grantedProjects
          .where((id) => !projectIdsToRevoke.contains(id))
          .toList();

      await _firestore.collection('ClientRequests').doc(requestId).update({
        'grantedProjects': updated,
        'approvedBy': adminUsername,
        'approvedByUid': adminUid,
        'approvalDate': Timestamp.now(),
        // If all projects revoked, mark as denied.
        if (updated.isEmpty) 'status': 'denied',
        if (updated.isEmpty)
          'denialReason': 'All project access has been revoked by admin.',
      });

      // Sync user access — revoke from user document.
      await revokeClientAccess(
        clientUid: clientUid,
        projectIdsToRevoke: projectIdsToRevoke,
      );

      final revokedNames = await _getProjectNames(projectIdsToRevoke);
      await _notificationService.notifyClientOfProjectUpdate(
        clientUsername: clientUsername,
        addedProjects: [],
        revokedProjects: revokedNames,
      );

      _logger.i('✅ Projects revoked successfully');
      return null;
    } catch (e) {
      _logger.e('❌ Error revoking projects: $e');
      return 'Failed to revoke projects. Please try again.';
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // History item editing — Denied requests
  // ──────────────────────────────────────────────────────────────────────────

  /// Re-approves a previously denied request with a new set of [projectIds].
  Future<String?> reApproveRequest({
    required String requestId,
    required List<String> projectIds,
    required String adminUsername,
    required String adminUid,
    String grantedRole = 'Client',
  }) async {
    try {
      _logger.i('🔄 Re-approving denied request: $requestId as $grantedRole');

      final requestDoc = await _firestore
          .collection('ClientRequests')
          .doc(requestId)
          .get();
      if (!requestDoc.exists) return 'Request not found';

      final request = ClientRequest.fromFirestore(requestDoc);

      await _firestore.collection('ClientRequests').doc(requestId).update({
        'status': 'approved',
        'grantedProjects': projectIds,
        'approvedBy': adminUsername,
        'approvedByUid': adminUid,
        'approvalDate': Timestamp.now(),
        'denialReason': null,
        'grantedRole': grantedRole,
      });

      await _updateClientProjectAccess(
        clientUid: request.clientUid,
        projectIds: projectIds,
        role: grantedRole,
      );

      final projectNames = await _getProjectNames(projectIds);
      await _notificationService.notifyClientOfApproval(
        clientUsername: request.clientUsername,
        projectNames: projectNames,
      );

      _logger.i('✅ Request re-approved successfully');
      return null;
    } catch (e) {
      _logger.e('❌ Error re-approving request: $e');
      return 'Failed to re-approve request. Please try again.';
    }
  }

  /// Updates the denial reason on a previously denied request (re-deny).
  Future<String?> reDenyRequest({
    required String requestId,
    required String adminUsername,
    required String adminUid,
    String? newReason,
  }) async {
    try {
      _logger.i('🔄 Re-denying request with updated reason: $requestId');

      final requestDoc = await _firestore
          .collection('ClientRequests')
          .doc(requestId)
          .get();
      if (!requestDoc.exists) return 'Request not found';

      final request = ClientRequest.fromFirestore(requestDoc);

      await _firestore.collection('ClientRequests').doc(requestId).update({
        'status': 'denied',
        'grantedProjects': [],
        'approvedBy': adminUsername,
        'approvedByUid': adminUid,
        'approvalDate': Timestamp.now(),
        'denialReason': newReason,
      });

      await _notificationService.notifyClientOfDenial(
        clientUsername: request.clientUsername,
        reason: newReason,
      );

      _logger.i('✅ Request re-denied successfully');
      return null;
    } catch (e) {
      _logger.e('❌ Error re-denying request: $e');
      return 'Failed to update denial. Please try again.';
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Internal helpers
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _updateClientProjectAccess({
    required String clientUid,
    required List<String> projectIds,
    // Only passed (and only written) from approveClientRequest, where an
    // Admin/MainAdmin is actively deciding the account's role — every
    // other caller here (adding/revoking projects on an already-approved
    // request) leaves the account's existing role untouched.
    String? role,
  }) async {
    try {
      final userQuery = await _firestore
          .collection('Users')
          .where('uid', isEqualTo: clientUid)
          .limit(1)
          .get();
      if (userQuery.docs.isEmpty) throw Exception('User not found');

      final userDoc = userQuery.docs.first;
      final existing = List<String>.from(
        userDoc.data()['grantedProjects'] ?? [],
      );
      final updated = {...existing, ...projectIds}.toList();

      await _firestore.collection('Users').doc(userDoc.id).update({
        'grantedProjects': updated,
        'role': ?role,
      });

      _logger.i('✅ Client project access updated${role != null ? ' (role: $role)' : ''}');
    } catch (e) {
      _logger.e('❌ Error updating client project access: $e');
      rethrow;
    }
  }

  Future<List<String>> _getProjectNames(List<String> projectIds) async {
    try {
      final names = <String>[];
      for (final id in projectIds) {
        final doc =
            await _firestore.collection('projects').doc(id).get();
        if (doc.exists) {
          names.add(doc.data()?['name'] ?? 'Unknown Project');
        }
      }
      return names;
    } catch (e) {
      _logger.e('❌ Error getting project names: $e');
      return [];
    }
  }

  Future<String?> revokeClientAccess({
    required String clientUid,
    required List<String> projectIdsToRevoke,
  }) async {
    try {
      _logger.i('🔒 Revoking access for client: $clientUid');

      final userQuery = await _firestore
          .collection('Users')
          .where('uid', isEqualTo: clientUid)
          .limit(1)
          .get();
      if (userQuery.docs.isEmpty) return 'User not found';

      final userDoc = userQuery.docs.first;
      final current = List<String>.from(
        userDoc.data()['grantedProjects'] ?? [],
      );
      final updated =
          current.where((id) => !projectIdsToRevoke.contains(id)).toList();

      await _firestore
          .collection('Users')
          .doc(userDoc.id)
          .update({'grantedProjects': updated});

      _logger.i('✅ Client access revoked successfully');
      return null;
    } catch (e) {
      _logger.e('❌ Error revoking client access: $e');
      return 'Failed to revoke access. Please try again.';
    }
  }

  Future<List<String>> getClientGrantedProjects(String clientUid) async {
    try {
      final userQuery = await _firestore
          .collection('Users')
          .where('uid', isEqualTo: clientUid)
          .limit(1)
          .get();
      if (userQuery.docs.isEmpty) return [];
      return List<String>.from(
        userQuery.docs.first.data()['grantedProjects'] ?? [],
      );
    } catch (e) {
      _logger.e('❌ Error getting client granted projects: $e');
      return [];
    }
  }
}