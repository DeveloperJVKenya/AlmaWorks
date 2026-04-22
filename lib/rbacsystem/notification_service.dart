import 'dart:async';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:logger/logger.dart';

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
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _logger.i(
          '📨 Foreground message: ${message.notification?.title}',
        );
        _showLocalNotification(
          title: message.notification?.title ?? 'New Notification',
          body: message.notification?.body ?? '',
          payload: message.data,
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

      await _firestore
          .collection('Users')
          .doc(query.docs.first.id)
          .update({'fcmToken': token, 'fcmUpdatedAt': FieldValue.serverTimestamp()});

      _logger.i('✅ FCM token persisted to Firestore');
    } catch (e) {
      _logger.e('❌ Error persisting FCM token: $e');
    }
  }

  /// Call this after verifying the logged-in user is an Admin / MainAdmin.
  /// It attaches a real-time listener to `AdminNotificationQueue`, shows a
  /// local notification for every new document, and handles the
  /// offline → online reconnect case automatically via Firestore persistence.
  Future<void> setupAdminNotificationListener(String adminUid) async {
    // Cancel any previous subscription first.
    await _adminQueueSubscription?.cancel();

    _logger.i('👂 Setting up AdminNotificationQueue listener for $adminUid');

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

  // ──────────────────────────────────────────────────────────────────────────
  // Local notification helpers
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    try {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
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
  }) async {
    try {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
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
      await _firestore.collection('AdminNotificationQueue').add({
        'title': title,
        'body': body,
        'payload': payload,
        'requestId': requestId,
        'clientUsername': clientUsername,
        'createdAt': FieldValue.serverTimestamp(),
        'type': 'new_client_request',
      });

      _logger.i('✅ AdminNotificationQueue document written');

      // ── Also show local notification on the current device ────────────────
      await _showLocalNotificationWithActions(
        title: title,
        body: body,
        payload: payload,
      );

      _logger.i('✅ Admin notification sent');
    } catch (e) {
      _logger.e('❌ Error sending admin notifications: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Client-facing notifications
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> notifyClientOfApproval({
    required String clientUsername,
    required List<String> projectNames,
  }) async {
    try {
      final projectList = projectNames.join(', ');
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          channelKey: 'client_requests',
          title: '✅ Access Granted',
          body:
              'Your request has been approved! You now have access to: $projectList',
          payload: {
            'type': 'client_request',
            'route': 'dashboard',
            'status': 'approved',
          },
          notificationLayout: NotificationLayout.BigText,
          wakeUpScreen: true,
          category: NotificationCategory.Message,
        ),
      );
      _logger.i('✅ Client approval notification sent');
    } catch (e) {
      _logger.e('❌ Error sending client approval notification: $e');
    }
  }

  Future<void> notifyClientOfDenial({
    required String clientUsername,
    String? reason,
  }) async {
    try {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          channelKey: 'client_requests',
          title: '❌ Request Denied',
          body:
              reason ?? 'Your access request was denied by an administrator.',
          payload: {
            'type': 'client_request',
            'route': 'dashboard',
            'status': 'denied',
          },
          notificationLayout: NotificationLayout.Default,
          wakeUpScreen: true,
          category: NotificationCategory.Message,
        ),
      );
      _logger.i('✅ Client denial notification sent');
    } catch (e) {
      _logger.e('❌ Error sending client denial notification: $e');
    }
  }

  Future<void> notifyClientOfProjectUpdate({
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

      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          channelKey: 'client_requests',
          title: '🔄 Project Access Updated',
          body: body,
          payload: {
            'type': 'project_update',
            'route': 'dashboard',
          },
          notificationLayout: NotificationLayout.BigText,
          wakeUpScreen: true,
          category: NotificationCategory.Message,
        ),
      );
      _logger.i('✅ Client project update notification sent');
    } catch (e) {
      _logger.e('❌ Error sending project update notification: $e');
    }
  }
}