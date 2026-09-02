import 'dart:async';
import 'package:almaworks/rbacsystem/notification_id_util.dart';
import 'package:almaworks/services/notification_preferences.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// A device's own FCM token is unique to itself, so a user signed in on both
/// web and mobile needs both remembered — see Users.fcmTokens in
/// _persistFcmToken. `fcmToken` (singular) is kept alongside it purely as a
/// legacy fallback for any Cloud Function code path not yet reading the map.
String get _currentPlatformLabel {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    default:
      return 'other';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// How cross-device admin notifications work (no Cloud Functions required):
//
//  1. Each user's FCM token is saved to Firestore at login.
//  2. When a client submits a request, a document is written to the
//     `AdminNotificationQueue` collection in Firestore.
//  3. Every admin device calls `setupAdminNotificationListener()` at login,
//     which attaches a real-time Firestore snapshot listener.
//  4. Firestore's offline persistence means: if the device is offline when
//     the request arrives, the snapshot fires the moment the device reconnects
//     and the app is in foreground or background.
//  5. For completely terminated apps the OS-level FCM push (sent from your
//     Cloud Function or backend) wakes the app. The FCM token stored in
//     Firestore makes this trivial to implement server-side later.
//
// For production: add a Firebase Cloud Function that triggers on
//   `AdminNotificationQueue/{id}` creation, reads all admin FCM tokens from
//   Firestore, and sends FCM pushes — giving terminated-app delivery too.
// ─────────────────────────────────────────────────────────────────────────────

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Logger _logger = Logger();

  // Active Firestore listener subscriptions — cancelled on logout.
  StreamSubscription<QuerySnapshot>? _adminQueueSubscription;
  StreamSubscription<QuerySnapshot>? _userQueueSubscription;

  // Tracks which notification document IDs have already been shown so we
  // never display the same notification twice across sessions.
  final Set<String> _shownNotificationIds = {};

  // ──────────────────────────────────────────────────────────────────────────
  // Initialisation
  // ──────────────────────────────────────────────────────────────────────────

  /// Call once at app start, after Firebase.initializeApp().
  Future<void> initialize() async {
    try {
      await _requestPermissions();
      await _configureFCM();
      _logger.i('✅ NotificationService: Initialized successfully');
    } catch (e) {
      _logger.e('❌ NotificationService: Initialization failed', error: e);
    }
  }

  Future<void> _requestPermissions() async {
    try {
      final isAllowed = await AwesomeNotifications().isNotificationAllowed();
      if (!isAllowed) {
        await AwesomeNotifications().requestPermissionToSendNotifications();
      }
      await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      _logger.i('✅ Notification permissions requested');
    } catch (e) {
      _logger.e('❌ Error requesting permissions', error: e);
    }
  }

  Future<void> _configureFCM() async {
    try {
      // Save initial token.
      final token = await _fcm.getToken();
      _logger.i('📱 FCM Token obtained');
      if (token != null) await _persistFcmToken(token);

      // Keep token fresh — rotate whenever FCM issues a new one.
      _fcm.onTokenRefresh.listen((newToken) async {
        _logger.i('🔄 FCM Token refreshed');
        await _persistFcmToken(newToken);
      });

      // Foreground messages — show a local notification manually.
      //
      // Messages sourced from AdminNotificationQueue (docId present in the
      // data payload) carry a stable id derived from that doc's id — the
      // same id setupAdminNotificationListener() below uses when it shows
      // the notification straight off the Firestore snapshot. Whichever of
      // the two fires first shows it; the other silently updates the same
      // notification instead of creating a visible duplicate.
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _logger.i(
          '📨 Foreground message: ${message.notification?.title}',
        );
        final docId = message.data['docId'];
        _showLocalNotification(
          title: message.notification?.title ?? 'New Notification',
          body: message.notification?.body ?? '',
          payload: message.data,
          id: docId != null ? stableNotificationId(docId) : null,
        );
      });

      // User tapped a notification while app was in background.
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _logger.i('📬 Notification tapped (background): ${message.data}');
        _handleNotificationRoute(message.data);
      });

      // User tapped a notification while app was terminated.
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        _logger.i(
          '📭 Notification tapped (terminated): ${initialMessage.data}',
        );
        _handleNotificationRoute(initialMessage.data);
      }
    } catch (e) {
      _logger.e('❌ Error configuring FCM', error: e);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FCM Token persistence
  // ──────────────────────────────────────────────────────────────────────────

  /// Saves (or refreshes) the FCM token on the current user's Firestore
  /// document so that a backend / Cloud Function can look it up to send
  /// targeted pushes later.
  Future<void> _persistFcmToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Find the user document (document ID == username).
      final query = await _firestore
          .collection('Users')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (query.docs.isEmpty) return;

      await _firestore.collection('Users').doc(query.docs.first.id).update({
        'fcmToken': token,
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
        'fcmTokens.$token': {
          'platform': _currentPlatformLabel,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      });

      _logger.i('✅ FCM token persisted to Firestore');
    } catch (e) {
      _logger.e('❌ Error persisting FCM token: $e');
    }
  }

  /// Call this after verifying the logged-in user is an Admin / MainAdmin /
  /// SystemAdmin. It attaches a real-time listener to `AdminNotificationQueue`,
  /// shows a local notification for every new document, and handles the
  /// offline → online reconnect case automatically via Firestore persistence.
  ///
  /// [role] is the caller's own role — a doc may carry a `targetRoles` list
  /// (see InventoryService._notifyAdmins / notifyAdminsOfClientRequest below)
  /// scoping it to a subset of Admin-tier roles (e.g. Inventory
  /// approvals/returns now go to MainAdmin+SystemAdmin only, not plain
  /// Admin). A doc with no `targetRoles` field is shown to everyone, for
  /// backward compatibility with anything queued before this field existed.
  Future<void> setupAdminNotificationListener(String adminUid, {required String role}) async {
    // Cancel any previous subscription first.
    await _adminQueueSubscription?.cancel();

    _logger.i('👂 Setting up AdminNotificationQueue listener for $adminUid ($role)');

    // We only listen for notifications created in the last 24 hours to avoid
    // flooding the admin with old notifications on first login.
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(hours: 24)),
    );

    _adminQueueSubscription = _firestore
        .collection('AdminNotificationQueue')
        .where('createdAt', isGreaterThan: cutoff)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen(
      (snapshot) {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final docId = change.doc.id;

            // Skip if we've already shown this one in this session.
            if (_shownNotificationIds.contains(docId)) continue;
            _shownNotificationIds.add(docId);

            final data = change.doc.data() as Map<String, dynamic>;

            final targetRoles = (data['targetRoles'] as List?)?.cast<String>();
            if (targetRoles != null && !targetRoles.contains(role)) continue;

            final title = data['title'] as String? ?? '🔔 New Notification';
            final body = data['body'] as String? ?? '';
            final payload =
                (data['payload'] as Map<String, dynamic>?)?.map(
                  (k, v) => MapEntry(k, v.toString()),
                ) ??
                {};

            _showLocalNotificationWithActions(
              title: title,
              body: body,
              payload: payload,
              id: stableNotificationId(docId),
            );

            _logger.i('🔔 Admin notification shown: $title');
          }
        }
      },
      onError: (e) =>
          _logger.e('❌ AdminNotificationQueue listener error: $e'),
    );
  }

  /// Cancel the admin listener (call on logout).
  Future<void> cancelAdminNotificationListener() async {
    await _adminQueueSubscription?.cancel();
    _adminQueueSubscription = null;
    _shownNotificationIds.clear();
    _logger.i('🛑 AdminNotificationQueue listener cancelled');
  }

  /// Call once at login for every user, regardless of role — the
  /// counterpart to [setupAdminNotificationListener] for notifications
  /// targeted at one specific person (e.g. "your booked asset is needed
  /// back soon") rather than broadcast to every Admin/MainAdmin. Written by
  /// InventoryService._notifyUser() to `UserNotificationQueue` with a
  /// `targetUid` field; delivered the same way (live listener here, FCM push
  /// via the `onUserNotificationQueued` Cloud Function for closed apps).
  Future<void> setupUserNotificationListener(String uid) async {
    await _userQueueSubscription?.cancel();

    _logger.i('👂 Setting up UserNotificationQueue listener for $uid');

    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(hours: 24)),
    );

    _userQueueSubscription = _firestore
        .collection('UserNotificationQueue')
        .where('targetUid', isEqualTo: uid)
        .where('createdAt', isGreaterThan: cutoff)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen(
      (snapshot) {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final docId = change.doc.id;
            if (_shownNotificationIds.contains(docId)) continue;
            _shownNotificationIds.add(docId);

            final data = change.doc.data() as Map<String, dynamic>;
            final title = data['title'] as String? ?? '🔔 New Notification';
            final body = data['body'] as String? ?? '';
            final payload =
                (data['payload'] as Map<String, dynamic>?)?.map(
                  (k, v) => MapEntry(k, v.toString()),
                ) ??
                {};

            _showLocalNotificationWithActions(
              title: title,
              body: body,
              payload: payload,
              id: stableNotificationId(docId),
            );

            _logger.i('🔔 User notification shown: $title');
          }
        }
      },
      onError: (e) => _logger.e('❌ UserNotificationQueue listener error: $e'),
    );
  }

  /// Cancel the per-user listener (call on logout).
  Future<void> cancelUserNotificationListener() async {
    await _userQueueSubscription?.cancel();
    _userQueueSubscription = null;
    _logger.i('🛑 UserNotificationQueue listener cancelled');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Local notification helpers
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
    int? id,
  }) async {
    if (!await NotificationPreferences.isEnabled()) return;
    try {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
          channelKey: 'client_requests',
          title: title,
          body: body,
          payload:
              payload?.map((k, v) => MapEntry(k, v.toString())),
          notificationLayout: NotificationLayout.Default,
          wakeUpScreen: true,
          category: NotificationCategory.Message,
        ),
      );
    } catch (e) {
      _logger.e('❌ Error showing local notification: $e');
    }
  }

  Future<void> _showLocalNotificationWithActions({
    required String title,
    required String body,
    Map<String, String>? payload,
    int? id,
  }) async {
    if (!await NotificationPreferences.isEnabled()) return;
    try {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
          channelKey: 'client_requests',
          title: title,
          body: body,
          payload: payload,
          notificationLayout: NotificationLayout.Default,
          wakeUpScreen: true,
          category: NotificationCategory.Message,
        ),
        actionButtons: [
          NotificationActionButton(
            key: 'VIEW',
            label: 'View Request',
            actionType: ActionType.Default,
          ),
        ],
      );
    } catch (e) {
      _logger.e('❌ Error showing notification with actions: $e');
    }
  }

  void _handleNotificationRoute(Map<String, dynamic> data) {
    final route = data['route'] ?? '';
    _logger.i('📍 Routing to: $route');
    // Wire up your app's navigator here if needed.
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Admin notifications — new client request
  // ──────────────────────────────────────────────────────────────────────────

  /// Called when a client submits an access request.
  ///
  /// Writes a document to `AdminNotificationQueue` (all online admin devices
  /// pick this up via their Firestore listener) AND shows a local notification
  /// on the submitting device so the admin who happens to be logged in there
  /// also sees it immediately.
  Future<void> notifyAdminsOfClientRequest({
    required String clientUsername,
    required String requestId,
  }) async {
    try {
      final title = '🔔 New Client Access Request';
      final body = '$clientUsername is requesting access to projects';
      final payload = {
        'type': 'client_request',
        'route': 'client_requests',
        'requestId': requestId,
      };

      // ── Write to Firestore queue so every admin device is notified ────────
      // Explicit targetRoles keeps this reaching every Admin-tier role even
      // though InventoryService._notifyAdmins (same collection) now scopes
      // its own notifications down to MainAdmin+SystemAdmin only.
      await _firestore.collection('AdminNotificationQueue').add({
        'title': title,
        'body': body,
        'payload': payload,
        'requestId': requestId,
        'clientUsername': clientUsername,
        'createdAt': FieldValue.serverTimestamp(),
        'type': 'new_client_request',
        'targetRoles': const ['MainAdmin', 'Admin', 'SystemAdmin'],
      });

      _logger.i('✅ AdminNotificationQueue document written');

      // NOTE: deliberately no direct local notification here — this method
      // runs on the SUBMITTING CLIENT's device (called from
      // ClientRequestService.submitClientRequest), so calling
      // AwesomeNotifications().createNotification() here would show the
      // "new client request" message to the client themselves, not to any
      // admin. Every admin device already gets this via its own
      // AdminNotificationQueue listener (setupAdminNotificationListener) and
      // the onAdminNotificationQueued Cloud Function for closed apps.
      _logger.i('✅ Admin notification queued');
    } catch (e) {
      _logger.e('❌ Error sending admin notifications: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Client-facing notifications
  // ──────────────────────────────────────────────────────────────────────────
  //
  // These are called by ClientRequestService on the ADMIN's device (the one
  // approving/denying/revoking), so they must NEVER show a local
  // notification directly — that would display the client's message on the
  // admin's own screen instead of reaching the client. Instead they enqueue
  // a targeted `UserNotificationQueue` document (targetUid = the client's
  // uid), the same mechanism InventoryService._notifyUser() uses. Delivery
  // to the actual target happens via:
  //   • setupUserNotificationListener(uid) — live Firestore listener, shows
  //     a local notification on the TARGET's device while it's foreground/
  //     background and online (attached for every role at dashboard load).
  //   • onUserNotificationQueued Cloud Function — FCM push, covers the
  //     target's device being fully closed/terminated.

  Future<void> notifyClientOfApproval({
    required String clientUid,
    required String clientUsername,
    required List<String> projectNames,
  }) async {
    try {
      final projectList = projectNames.join(', ');
      await _firestore.collection('UserNotificationQueue').add({
        'targetUid': clientUid,
        'title': '✅ Access Granted',
        'body':
            'Your request has been approved! You now have access to: $projectList',
        'payload': {
          'type': 'client_request',
          'route': 'dashboard',
          'status': 'approved',
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
      _logger.i('✅ Client approval notification queued for $clientUsername');
    } catch (e) {
      _logger.e('❌ Error queuing client approval notification: $e');
    }
  }

  Future<void> notifyClientOfDenial({
    required String clientUid,
    required String clientUsername,
    String? reason,
  }) async {
    try {
      await _firestore.collection('UserNotificationQueue').add({
        'targetUid': clientUid,
        'title': '❌ Request Denied',
        'body':
            reason ?? 'Your access request was denied by an administrator.',
        'payload': {
          'type': 'client_request',
          'route': 'dashboard',
          'status': 'denied',
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
      _logger.i('✅ Client denial notification queued for $clientUsername');
    } catch (e) {
      _logger.e('❌ Error queuing client denial notification: $e');
    }
  }

  Future<void> notifyClientOfProjectUpdate({
    required String clientUid,
    required String clientUsername,
    required List<String> addedProjects,
    required List<String> revokedProjects,
  }) async {
    try {
      String body;
      if (addedProjects.isNotEmpty && revokedProjects.isNotEmpty) {
        body =
            'Your project access has been updated. Added: ${addedProjects.join(', ')}. '
            'Removed: ${revokedProjects.join(', ')}.';
      } else if (addedProjects.isNotEmpty) {
        body =
            'You have been granted access to: ${addedProjects.join(', ')}.';
      } else {
        body =
            'Your access to the following projects has been revoked: ${revokedProjects.join(', ')}.';
      }

      await _firestore.collection('UserNotificationQueue').add({
        'targetUid': clientUid,
        'title': '🔄 Project Access Updated',
        'body': body,
        'payload': {
          'type': 'project_update',
          'route': 'dashboard',
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
      _logger.i('✅ Client project update notification queued for $clientUsername');
    } catch (e) {
      _logger.e('❌ Error queuing project update notification: $e');
    }
  }
}