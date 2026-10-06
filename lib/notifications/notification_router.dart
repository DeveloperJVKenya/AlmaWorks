import 'package:almaworks/models/inventory/checkout_request_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/rbacsystem/client_access_requests_screen.dart';
import 'package:almaworks/screens/communication/communication_message_detail_screen.dart';
import 'package:almaworks/screens/communication/communication_models.dart';
import 'package:almaworks/screens/communication/communication_screen.dart';
import 'package:almaworks/screens/communication/communication_service.dart';
import 'package:almaworks/screens/inventory/asset_detail_screen.dart';
import 'package:almaworks/screens/inventory/review_checkout_request_screen.dart';
import 'package:almaworks/screens/safety_training/safety_training_review_screen.dart';
import 'package:almaworks/screens/safety_training/safety_training_screen.dart';
import 'package:almaworks/screens/safety_training/training_history_screen.dart';
import 'package:almaworks/screens/schedule/task_progress_monitor_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

/// Opens the screen a notification is about, from its payload — the one
/// place that knows every notification type's destination, used both for a
/// tap on the OS tray (main.dart) and a tap in the in-app notification
/// center, so a notification always opens the same place either way.
class NotificationRouter {
  NotificationRouter({required this.navigator, required this.messenger, required this.logger});

  factory NotificationRouter.of(BuildContext context, Logger logger) =>
      NotificationRouter(navigator: Navigator.of(context), messenger: ScaffoldMessenger.of(context), logger: logger);

  final NavigatorState navigator;
  final ScaffoldMessengerState messenger;
  final Logger logger;

  static const _adminTier = {'MainAdmin', 'Admin', 'SystemAdmin'};
  static const _reviewers = {'MainAdmin', 'SystemAdmin'};

  /// Whether [payload] names somewhere to go (otherwise the notification
  /// center shows its details instead).
  static bool hasDestination(Map<String, dynamic> payload) {
    final type = payload['type']?.toString() ?? '';
    String? field(String key) {
      final v = payload[key]?.toString();
      return v == null || v.isEmpty || v == 'null' ? null : v;
    }

    if (type.startsWith('safety_training')) return true;
    if (type == 'client_request') return field('requestId') != null;
    if (type.startsWith('inventory')) return field('assetId') != null || field('requestId') != null;
    if (type == 'communication') return field('messageId') != null && field('projectId') != null;
    if (type.startsWith('project_date_extension') ||
        type.startsWith('task_date_extension') ||
        type.startsWith('schedule')) {
      return field('projectId') != null;
    }
    return false;
  }

  /// Navigates to [payload]'s destination. Returns false if it has none.
  Future<bool> open(Map<String, dynamic> payload) async {
    final type = payload['type']?.toString() ?? '';
    String? field(String key) {
      final v = payload[key]?.toString();
      return v == null || v.isEmpty || v == 'null' ? null : v;
    }

    logger.d('🧭 NotificationRouter: opening type=$type payload=$payload');
    if (!hasDestination(payload)) return false;

    if (type.startsWith('safety_training')) {
      await _openSafetyTraining(type, payload);
    } else if (type == 'client_request') {
      await _openAccessRequests();
    } else if (type.startsWith('inventory')) {
      final requestId = field('requestId');
      if (type == 'inventory_checkout_request' && requestId != null) {
        await _openInventoryRequest(requestId: requestId, assetId: field('assetId'));
      } else if (field('assetId') != null) {
        await _openInventoryAsset(assetId: field('assetId')!);
      }
    } else if (type == 'communication') {
      await _openMessage(messageId: field('messageId')!, projectId: field('projectId')!);
    } else {
      await _openTaskProgressMonitor(projectId: field('projectId')!);
    }
    return true;
  }

  // ── Shared lookups ────────────────────────────────────────────────────────

  /// The signed-in user's role/username, from their Users doc.
  Future<({String uid, String role, String username})?> _currentUser() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return null;
    final snap = await FirebaseFirestore.instance
        .collection('Users')
        .where('uid', isEqualTo: authUser.uid)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return (
      uid: authUser.uid,
      role: snap.docs.first.data()['role'] as String? ?? 'Client',
      username: snap.docs.first.id,
    );
  }

  /// Company-wide sections (Inventory, Safety Training) only need a project
  /// for BaseLayout's header chrome — prefer [projectId], else any project,
  /// so navigation never dead-ends for lack of a natural one.
  Future<ProjectModel?> _chromeProject([String? projectId]) async {
    final db = FirebaseFirestore.instance;
    if (projectId != null) {
      final doc = await db.collection('Projects').doc(projectId).get();
      if (doc.exists) return ProjectModel.fromFirestore(doc);
    }
    final anySnap = await db.collection('Projects').limit(1).get();
    return anySnap.docs.isEmpty ? null : ProjectModel.fromFirestore(anySnap.docs.first);
  }

  void _progress(String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  void _fail(String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Access requests ───────────────────────────────────────────────────────

  /// Admin-side access/role request alerts open the access requests screen
  /// (pending, approved and denied tabs), where the request can be acted on
  /// or its outcome seen.
  Future<void> _openAccessRequests() async {
    final user = await _currentUser();
    if (user == null || !_adminTier.contains(user.role)) return;
    navigator.push(MaterialPageRoute(builder: (_) => ClientAccessRequestsScreen(logger: logger)));
  }

  // ── Safety Training ───────────────────────────────────────────────────────

  /// Reviewer-facing notifications (a new attempt, an escalation, overdue
  /// retraining, an expired clearance) open the reviewer's tools; worker-
  /// facing ones open the worker's own view.
  Future<void> _openSafetyTraining(String type, Map<String, dynamic> payload) async {
    try {
      final user = await _currentUser();
      if (user == null || user.role == 'Client') {
        logger.w('⚠️ NotificationRouter: no eligible user for Safety Training');
        return;
      }
      final workerUid = payload['workerUid']?.toString();
      final workerName = payload['workerName']?.toString();
      final reviewerFacing =
          payload['audience'] == 'reviewer' ||
          type == 'safety_training_attempt' ||
          type == 'safety_training_escalation';

      if (reviewerFacing && _adminTier.contains(user.role)) {
        if (type == 'safety_training_attempt' && workerUid != null && workerUid.isNotEmpty) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => TrainingHistoryScreen(logger: logger, workerUid: workerUid, workerName: workerName),
            ),
          );
          return;
        }
        if (_reviewers.contains(user.role)) {
          navigator.push(MaterialPageRoute(builder: (_) => SafetyTrainingReviewScreen(logger: logger)));
          return;
        }
      }

      if (type == 'safety_training_feedback') {
        navigator.push(
          MaterialPageRoute(
            builder: (_) => TrainingHistoryScreen(logger: logger, workerUid: user.uid, workerName: user.username),
          ),
        );
        return;
      }

      _progress('Opening Safety Training…');
      final project = await _chromeProject();
      if (project == null) {
        _fail('Could not open Safety Training right now.');
        return;
      }
      messenger.hideCurrentSnackBar();
      navigator.push(
        MaterialPageRoute(
          builder: (_) => SafetyTrainingScreen(project: project, logger: logger),
        ),
      );
    } catch (e, st) {
      logger.e('❌ NotificationRouter: Safety Training navigation failed', error: e, stackTrace: st);
      _fail('Could not open Safety Training. Please try again.');
    }
  }

  // ── Projects ──────────────────────────────────────────────────────────────

  /// Task Progress Monitor surfaces date-extension requests/decisions and
  /// task schedule alerts for the project.
  Future<void> _openTaskProgressMonitor({required String projectId}) async {
    _progress('Opening project…');
    try {
      final doc = await FirebaseFirestore.instance.collection('Projects').doc(projectId).get();
      if (!doc.exists) {
        _fail('That project no longer exists.');
        return;
      }
      messenger.hideCurrentSnackBar();
      navigator.push(
        MaterialPageRoute(
          builder: (_) => TaskProgressMonitorScreen(project: ProjectModel.fromFirestore(doc), logger: logger),
        ),
      );
    } catch (e, st) {
      logger.e('❌ NotificationRouter: project navigation failed', error: e, stackTrace: st);
      _fail('Could not open the project. Please try again.');
    }
  }

  // ── Communication ─────────────────────────────────────────────────────────

  /// Opens the inbox, then the message on top, so Back lands on the inbox.
  Future<void> _openMessage({required String messageId, required String projectId}) async {
    _progress('Opening message…');
    try {
      final db = FirebaseFirestore.instance;
      final commService = CommunicationService();
      final msgDoc = await db.collection('Communication').doc(messageId).get();
      if (!msgDoc.exists) {
        _fail('Message not found or has been deleted.');
        return;
      }
      final message = CommunicationMessage.fromDoc(msgDoc);
      final projectDoc = await db.collection('Projects').doc(projectId).get();
      if (!projectDoc.exists) {
        _fail('Project not found.');
        return;
      }
      final project = ProjectModel.fromFirestore(projectDoc);
      final currentUser = await commService.getCurrentUserParticipant();
      if (currentUser == null) {
        messenger.hideCurrentSnackBar();
        return;
      }
      final projectUsers = await commService.getProjectUsers(projectId);
      messenger.hideCurrentSnackBar();
      navigator.push(
        MaterialPageRoute(
          builder: (_) => CommunicationScreen(project: project, logger: logger),
        ),
      );
      navigator.push(
        MaterialPageRoute(
          builder: (_) => CommunicationMessageDetailScreen(
            message: message,
            service: commService,
            currentUser: currentUser,
            projectUsers: projectUsers,
            projectId: projectId,
          ),
        ),
      );
    } catch (e, st) {
      logger.e('❌ NotificationRouter: message navigation failed', error: e, stackTrace: st);
      _fail('Could not open message. Please try again.');
    }
  }

  // ── Inventory ─────────────────────────────────────────────────────────────

  /// The asset's detail screen — where Record Return, Acknowledge Receipt
  /// and every other Inventory action lives.
  Future<void> _openInventoryAsset({required String assetId, String? projectId}) async {
    _progress('Opening asset…');
    try {
      final user = await _currentUser();
      if (user == null) {
        messenger.hideCurrentSnackBar();
        return;
      }
      final assetDoc = await FirebaseFirestore.instance.collection('InventoryAssets').doc(assetId).get();
      if (!assetDoc.exists) {
        _fail('Asset not found or has been removed.');
        return;
      }
      final project = await _chromeProject(projectId ?? assetDoc.data()?['currentProjectId'] as String?);
      if (project == null) {
        _fail('Could not open Inventory right now.');
        return;
      }
      messenger.hideCurrentSnackBar();
      navigator.push(
        MaterialPageRoute(
          builder: (_) => AssetDetailScreen(
            project: project,
            logger: logger,
            assetId: assetId,
            userRole: user.role,
            username: user.username,
            currentUid: user.uid,
          ),
        ),
      );
    } catch (e, st) {
      logger.e('❌ NotificationRouter: asset navigation failed', error: e, stackTrace: st);
      _fail('Could not open asset. Please try again.');
    }
  }

  /// A pending checkout request opens its review screen; one already handled
  /// falls back to the asset.
  Future<void> _openInventoryRequest({required String requestId, String? assetId}) async {
    _progress('Opening request…');
    try {
      final requestDoc = await FirebaseFirestore.instance.collection('InventoryCheckoutRequests').doc(requestId).get();
      if (!requestDoc.exists || requestDoc.data()?['status'] != CheckoutRequestModel.statusPending) {
        if (assetId != null) {
          await _openInventoryAsset(assetId: assetId);
        } else {
          _fail('This request has already been handled.');
        }
        return;
      }
      final request = CheckoutRequestModel.fromFirestore(requestDoc);
      final user = await _currentUser();
      if (user == null) {
        messenger.hideCurrentSnackBar();
        return;
      }
      final project = await _chromeProject(request.projectId);
      if (project == null) {
        _fail('Could not open Inventory right now.');
        return;
      }
      messenger.hideCurrentSnackBar();
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ReviewCheckoutRequestScreen(
            project: project,
            logger: logger,
            request: request,
            respondedByUid: user.uid,
            respondedByName: user.username,
            respondedByRole: user.role,
          ),
        ),
      );
    } catch (e, st) {
      logger.e('❌ NotificationRouter: request navigation failed', error: e, stackTrace: st);
      _fail('Could not open request. Please try again.');
    }
  }
}
