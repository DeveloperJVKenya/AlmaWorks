// communication_notification_service.dart
//
// Handles FCM token registration/refresh and foreground message display for
// the Communication feature. Background/terminated-app display is NOT
// handled here — that's owned by the single app-wide background handler in
// lib/rbacsystem/firebase_notification_handler.dart, which also shows
// Communication pushes (on the 'communication_channel' Awesome Notifications
// channel registered in main.dart). Two competing
// `FirebaseMessaging.onBackgroundMessage()` registrations used to exist (one
// here, one in firebase_notification_handler.dart) — only the last one
// registered actually takes effect, which was silently breaking background
// delivery for whichever notification type registered first. Consolidating
// onto a single handler fixes that.
//
// Delivery to a closed/terminated app is handled entirely server-side by the
// `onCommunicationMessageCreated` Cloud Function (functions/index.js), which
// triggers directly off new `Communication` documents — there is no longer a
// client-written notification queue for messages to pass through.
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Firebase Console → Project Settings → Cloud Messaging → Web Push
/// certificates (for project almaworks-b9a2e) → "Key pair" value.
/// Required for web push to work at all — fill this in before web push
/// (foreground or background) can be tested. Without it, `getToken()` on
/// web either returns null or throws.
const String _webVapidKey = 'BFNsKKhcnjrm3fFaQIxcmv0NUUKE0E5omRsH7Je2EsVk1jiQq7Y1jJLSr5__ETytl0IaGbvvPZiOjoFhdpNrlBI';

class CommunicationNotificationService {
  static final CommunicationNotificationService _instance =
      CommunicationNotificationService._internal();
  factory CommunicationNotificationService() => _instance;
  CommunicationNotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final Logger _log = Logger();

  static const String channelKey = 'communication_channel';

  // ─────────────────────────────────────────────────────────────────────────
  //  INITIALISE (call once from main.dart or app startup)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    // 1. Request FCM permissions
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Foreground FCM messages — shown via Awesome Notifications so the
    //    tray notification looks identical to the background-delivered one
    //    and both dedupe against any live Firestore-listener path the same
    //    way rbac notifications already do.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final data = message.data;
      _showLocalNotification(
        title: message.notification?.title ?? 'New Message',
        body: message.notification?.body ?? '',
        payload: data.map((k, v) => MapEntry(k, v.toString())),
      );
    });

    // 3. Save / refresh FCM token for the current user
    await _saveTokenForCurrentUser();
    _fcm.onTokenRefresh.listen(_updateUserToken);

    _log.i('✅ CommunicationNotificationService: Initialized');
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  SHOW LOCAL NOTIFICATION
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> showMessageNotification({
    required String fromName,
    required String subject,
    required String preview,
    String? messageId,
    String? projectId,
  }) async {
    await _showLocalNotification(
      title: 'New message from $fromName',
      body: '$subject — $preview',
      payload: {
        'type': 'communication',
        'messageId': ?messageId,
        'projectId': ?projectId,
      },
    );
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    Map<String, String>? payload,
  }) async {
    try {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          channelKey: channelKey,
          title: title,
          body: body,
          payload: payload,
          notificationLayout: NotificationLayout.Default,
          wakeUpScreen: true,
          category: NotificationCategory.Message,
        ),
      );
    } catch (e) {
      _log.e('❌ _showLocalNotification: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  FCM TOKEN MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _saveTokenForCurrentUser() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final token = kIsWeb
          ? await _fcm.getToken(vapidKey: _webVapidKey)
          : await _fcm.getToken();
      if (token == null) return;
      await _updateUserToken(token);
    } catch (e) {
      _log.w('⚠️ _saveTokenForCurrentUser: $e');
    }
  }

  Future<void> _updateUserToken(String token) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final snap = await FirebaseFirestore.instance
          .collection('Users')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        await snap.docs.first.reference.update({
          'fcmToken': token,
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
          'fcmTokens.$token': {
            'platform': kIsWeb
                ? 'web'
                : defaultTargetPlatform == TargetPlatform.iOS
                    ? 'ios'
                    : 'android',
            'updatedAt': FieldValue.serverTimestamp(),
          },
        });
        _log.i('✅ FCM token updated for user $uid');
      }
    } catch (e) {
      _log.w('⚠️ _updateUserToken: $e');
    }
  }
}
