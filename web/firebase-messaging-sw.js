// firebase-messaging-sw.js
//
// Service worker required for web push to reach a closed tab / browser.
// Handles FCM messages that arrive while no tab is open or the tab is in
// the background; a foreground tab instead gets the message via
// FirebaseMessaging.onMessage in Dart (see communication_notification_service.dart
// and lib/rbacsystem/notification_service.dart) and shows it itself, so this
// worker's onBackgroundMessage handler is the browser-closed/tab-hidden path.
//
// Must live at the web root (served as /firebase-messaging-sw.js) — Firebase
// looks for it there by convention when FirebaseMessaging.instance.getToken()
// is called on web.

importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

// Values from lib/firebase_options.dart's web FirebaseOptions — safe to be
// public, same as any Firebase web app config.
firebase.initializeApp({
  apiKey: 'AIzaSyCmG8Kw6GszgEj9y-OjJ8Si1Kn_IjScSl4',
  appId: '1:609637842223:web:1dc631278e259b301c75da',
  messagingSenderId: '609637842223',
  projectId: 'almaworks-b9a2e',
  authDomain: 'almaworks-b9a2e.firebaseapp.com',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = (payload.notification && payload.notification.title) || 'New Notification';
  const body = (payload.notification && payload.notification.body) || '';
  const data = payload.data || {};

  self.registration.showNotification(title, {
    body,
    icon: '/icon.png',
    data,
    tag: data.messageId || data.docId || undefined,
  });
});

// Deliberately no custom `notificationclick` handler here — the default
// behavior (focus an existing tab, or open one) is what lets
// FirebaseMessaging.onMessageOpenedApp fire correctly in Dart. A custom
// handler would need to reimplement that hand-off itself; not attempting a
// deep link into a specific message from a closed-browser click for now —
// clicking simply brings the app to the foreground, same as any other
// closed-app web push today.
