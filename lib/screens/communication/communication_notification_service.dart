// communication_notification_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'communication_models.dart';

/// Top-level handler required by firebase_messaging for background messages
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final plugin = FlutterLocalNotificationsPlugin();
  const channel = AndroidNotificationChannel(
    'communication_channel',
    'Messages',
    description: 'AlmaWorks in-app communication notifications',
    importance: Importance.high,
  );
  await plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // FIX 1 — flutter_local_notifications v18+: show() now uses named parameters.
  await plugin.show(
    id: message.hashCode,
    title: message.notification?.title ?? 'New Message',
    body: message.notification?.body ?? '',
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
  );
}

class CommunicationNotificationService {
  static final CommunicationNotificationService _instance =
      CommunicationNotificationService._internal();
  factory CommunicationNotificationService() => _instance;
  CommunicationNotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final Logger _log = Logger();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'communication_channel',
    'Messages',
    description: 'AlmaWorks in-app communication notifications',
    importance: Importance.high,
  );

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

    // 2. Register background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 3. Create Android notification channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // 4. Init local notifications
    // FIX 2 — flutter_local_notifications v18+: initialize() now requires the
    //          named parameter `settings:` instead of a positional argument.
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    // 5. Handle foreground FCM messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showLocalNotification(
        title: message.notification?.title ?? 'New Message',
        body: message.notification?.body ?? '',
      );
    });

    // 6. Save / refresh FCM token for the current user
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
  }) async {
    await _showLocalNotification(
      title: 'New message from $fromName',
      body: '$subject — $preview',
    );
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
  }) async {
    // FIX 3 — flutter_local_notifications v18+: show() now uses named parameters.
    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  SEND NOTIFICATION TO RECIPIENTS VIA FIRESTORE TRIGGER PLACEHOLDER
  //  (In production, Firebase Cloud Functions would watch Communication and
  //   send FCM via Admin SDK. Here we write a notification doc that a Cloud
  //   Function can process — no Admin SDK needed client-side.)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> enqueueNotificationsForMessage(
      CommunicationMessage msg) async {
    try {
      final allRecipients = <dynamic>{
        ...msg.to,
        ...msg.cc,
      }.toList();

      final batch = FirebaseFirestore.instance.batch();
      for (final recipient in allRecipients) {
        final docRef =
            FirebaseFirestore.instance.collection('NotificationQueue').doc();
        batch.set(docRef, {
          'to': recipient.uid,
          'fromName': msg.from.username,
          'fromEmail': msg.from.email,
          'subject': msg.subject,
          'preview': msg.bodyPlainText.length > 100
              ? '${msg.bodyPlainText.substring(0, 100)}…'
              : msg.bodyPlainText,
          'messageId': msg.id,
          'projectId': msg.projectId,
          'createdAt': FieldValue.serverTimestamp(),
          'sent': false,
        });
      }
      await batch.commit();
      _log.i(
          '✅ Enqueued ${allRecipients.length} notification(s) for message ${msg.id}');
    } catch (e) {
      _log.e('❌ enqueueNotificationsForMessage: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  FCM TOKEN MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _saveTokenForCurrentUser() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final token = await _fcm.getToken();
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
        await snap.docs.first.reference.update({'fcmToken': token});
        _log.i('✅ FCM token updated for user $uid');
      }
    } catch (e) {
      _log.w('⚠️ _updateUserToken: $e');
    }
  }
}