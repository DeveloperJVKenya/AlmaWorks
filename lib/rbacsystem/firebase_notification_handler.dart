// lib/rbacsystem/firebase_notification_handler.dart
// ─────────────────────────────────────────────────────────────────────────────
// IMPORTANT: This file must be imported in your main.dart BEFORE runApp().
//
// In main.dart add:
//   import 'package:almaworks/rbacsystem/firebase_notification_handler.dart';
//
//   void main() async {
//     WidgetsFlutterBinding.ensureInitialized();
//     await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
//
//     // ── Register background handler BEFORE runApp ──────────────────────
//     FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
//
//     runApp(const MyApp());
//   }
//
// Why a separate file?
//   Flutter's `firebase_messaging` package requires the background handler to
//   be a TOP-LEVEL function (not a class method) annotated with
//   @pragma('vm:entry-point') so Dart's tree-shaker keeps it alive in release
//   builds and the OS can invoke it inside its own isolate when the app is
//   terminated. Placing it here keeps main.dart uncluttered.
//
// Notification channel used: 'client_requests'
//   Defined in main.dart's AwesomeNotifications().initialize() block, so it
//   will always exist when this handler fires.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Top-level background message handler required by `firebase_messaging`.
///
/// Called by the OS when an FCM message arrives and the app is:
///   • Terminated (not running at all), or
///   • In the background (but the Firestore listener is inactive)
///
/// This is the ONLY place where terminated-app notifications are guaranteed
/// to fire. The @pragma annotation prevents tree-shaking in release builds.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Re-initialise Firebase for the background isolate — each isolate is a
  // fresh Dart VM so Firebase must be initialised again here.
  await Firebase.initializeApp();

  debugPrint(
    '🔔 [BG Handler] Message received: ${message.notification?.title}',
  );

  // Show the notification via Awesome Notifications so it surfaces in the
  // system tray even when the app is fully terminated / backgrounded.
  try {
    final title = message.notification?.title ?? '🔔 New Notification';
    final body  = message.notification?.body  ?? '';
    final data  = message.data;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        // Use millisecondsSinceEpoch ~/ 1000 to keep id within int32 range.
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        channelKey: 'client_requests',
        title: title,
        body: body,
        // Forward the FCM data payload so tapping the notification can route
        // the admin to ClientAccessRequestsScreen (handled in main.dart's
        // onActionReceivedMethod via payload['type'] == 'client_request').
        payload: data.map((key, value) => MapEntry(key, value.toString())),
        notificationLayout: NotificationLayout.Default,
        wakeUpScreen: true,
        category: NotificationCategory.Message,
      ),
    );

    debugPrint('✅ [BG Handler] Notification displayed: $title');
  } catch (e) {
    debugPrint('❌ [BG Handler] Error showing notification: $e');
  }
}