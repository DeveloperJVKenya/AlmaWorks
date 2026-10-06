import 'package:almaworks/authentication/login_screen.dart';
import 'package:almaworks/authentication/welcome_screen.dart';
import 'package:almaworks/rbacsystem/firebase_notification_handler.dart';
import 'package:almaworks/providers/locale_provider.dart';
import 'package:almaworks/providers/theme_provider.dart';
import 'package:almaworks/notifications/notification_providers.dart';
import 'package:almaworks/notifications/notification_router.dart';
import 'package:almaworks/rbacsystem/auth_service.dart';
import 'package:almaworks/screens/communication/communication_notification_service.dart';
import 'package:almaworks/screens/utils/app_theme.dart';
import 'package:almaworks/services/notification_service.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:logger/logger.dart';
import 'firebase_options.dart';

// ─── Global providers ─────────────────────────────────────────────────────────
final LocaleProvider localeProvider = LocaleProvider();
final ThemeProvider themeProvider = ThemeProvider();
// ─────────────────────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final Logger logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  try {
    logger.i('🚀 Starting AlmaWorks application initialization');

    // Initialize Firebase with proper options
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    logger.i('✅ Firebase initialized successfully');

    // ── Restore persisted language/theme preferences before first frame ────
    await localeProvider.load();
    await themeProvider.load();
    logger.i('✅ Locale/theme preferences restored '
        '(language=${localeProvider.language}, darkMode=${themeProvider.isDarkMode})');

    // ── FCM background handler — MUST be registered before runApp ─────────
    // This top-level function handles FCM pushes when the app is terminated
    // or backgrounded. It is defined in firebase_notification_handler.dart
    // and annotated with @pragma('vm:entry-point') to survive tree-shaking.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    logger.i('✅ FCM background handler registered');

    // Enable Firestore offline persistence
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    logger.i('✅ Firestore settings configured');

    // ── Awesome Notifications ────────────────────────────────────────────────
    // Single notification manager app-wide — every channel (schedule,
    // client requests, Communication) is registered here.
    await AwesomeNotifications().initialize(
      // Was `null` ("use default app icon") — Android has rendered
      // status-bar/notification icons from ONLY their alpha channel since
      // API 21, so falling back to the full-color launcher icon (or
      // whatever "default" resolved to) produced a solid white blob
      // instead of real branding. Points at a dedicated white-silhouette-
      // on-transparent drawable generated from the AlmaWorks mark — see
      // android/app/src/main/res/drawable*/ic_notification.png and the
      // matching AndroidManifest.xml meta-data.
      'resource://drawable/ic_notification',
      [
        NotificationChannel(
          channelKey: 'schedule_overdue',
          channelName: 'Overdue Tasks',
          channelDescription: 'Notifications for overdue tasks',
          defaultColor: Colors.red,
          ledColor: Colors.red,
          importance: NotificationImportance.High,
          channelShowBadge: true,
          playSound: true,
          enableVibration: true,
        ),
        NotificationChannel(
          channelKey: 'schedule_starting_soon',
          channelName: 'Starting Soon Tasks',
          channelDescription: 'Notifications for tasks starting soon',
          defaultColor: Colors.orange,
          ledColor: Colors.orange,
          importance: NotificationImportance.High,
          channelShowBadge: true,
          playSound: true,
          enableVibration: true,
        ),
        NotificationChannel(
          channelKey: 'schedule_summary',
          channelName: 'Task Summary',
          channelDescription: 'Grouped task notifications',
          defaultColor: Colors.blue,
          ledColor: Colors.blue,
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          enableVibration: true,
        ),
        NotificationChannel(
          channelKey: 'client_requests',
          channelName: 'Client Access Requests',
          channelDescription: 'Notifications for client access requests',
          defaultColor: const Color(0xFF0A2E5A),
          ledColor: const Color(0xFF0A2E5A),
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          enableVibration: true,
        ),
        // ── Communication channel ─────────────────────────────────────────
        // Handles in-app message notifications (new messages, replies), both
        // foreground (CommunicationNotificationService) and background/
        // terminated (firebase_notification_handler.dart) — Awesome
        // Notifications is the single notification manager app-wide.
        NotificationChannel(
          channelKey: 'communication_channel',
          channelName: 'Messages',
          channelDescription: 'AlmaWorks in-app communication notifications',
          defaultColor: const Color(0xFF0A2E5A),
          ledColor: const Color(0xFF0A2E5A),
          importance: NotificationImportance.High,
          channelShowBadge: true,
          playSound: true,
          enableVibration: true,
          // Was 'resource://drawable/ic_launcher' — that resource only
          // ever existed under mipmap-*, never drawable*, so it silently
          // failed to resolve. Explicit here (even though it now matches
          // the initialize() default above) so this channel doesn't
          // regress if that default ever changes independently.
          icon: 'resource://drawable/ic_notification',
        ),
      ],
      debug: false,
    );
    logger.i('✅ Awesome Notifications initialized successfully');

    // ── Existing Notification Service (client requests) ───────────────────
    try {
      await NotificationService(logger: logger).initialize();
      logger.i('✅ Notification Service initialized successfully');
    } catch (e) {
      logger.w(
          '⚠️ Notification Service initialization failed (non-critical): $e');
    }

    // ── Communication Notification Service (FCM + foreground messages) ────
    // Handles FCM token registration and foreground message display for the
    // Communication section. Non-critical — app runs fully without it.
    try {
      await CommunicationNotificationService().initialize();
      logger.i(
          '✅ Communication Notification Service initialized successfully');
    } catch (e) {
      logger.w(
          '⚠️ Communication Notification Service initialization failed (non-critical): $e');
    }

    // ProviderScope wraps the whole app because Riverpod requires it as a
    // root ancestor of anything using `ref` — it's additive and does not
    // affect any existing `provider`-package (ChangeNotifierProvider/
    // LocaleProvider) code elsewhere in the app. Currently only the
    // Inventory module (lib/screens/inventory/) consumes Riverpod providers.
    runApp(ProviderScope(child: AlmaWorksApp(logger: logger)));
    logger.i('✅ AlmaWorks app started successfully');
  } catch (e, stackTrace) {
    logger.e('❌ Failed to initialize AlmaWorks app',
        error: e, stackTrace: stackTrace);
    runApp(ErrorApp(error: e.toString()));
  }
}

class AlmaWorksApp extends StatefulWidget {
  final Logger logger;

  const AlmaWorksApp({super.key, required this.logger});

  @override
  State<AlmaWorksApp> createState() => _AlmaWorksAppState();
}

class _AlmaWorksAppState extends State<AlmaWorksApp> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();

    widget.logger.i('🔔 Setting up notification action listeners');

    // Listen to notification actions when user taps from system tray
    AwesomeNotifications().setListeners(
      onActionReceivedMethod: (ReceivedAction receivedAction) async {
        widget.logger.i('👆 User tapped notification: ${receivedAction.id}');

        if (receivedAction.payload != null) {
          final notificationType = receivedAction.payload!['type'];
          // Captured before any await below.
          final navState = navigatorKey.currentState;
          final navContext = navigatorKey.currentContext;
          final messenger = navContext == null ? null : ScaffoldMessenger.maybeOf(navContext);

          // ── Schedule / task notifications ───────────────────────────────
          if (notificationType == 'schedule' || notificationType == null) {
            final projectId = receivedAction.payload!['projectId'];
            final taskId = receivedAction.payload!['taskId'];
            final notificationId = receivedAction.payload!['notificationId'];

            widget.logger.d(
                'Schedule notification: projectId=$projectId, taskId=$taskId, notifId=$notificationId');

            if (notificationId != null) {
              try {
                await FirebaseFirestore.instance
                    .collection('ScheduleNotifications')
                    .doc(notificationId)
                    .update({
                  'isRead': true,
                  'openedFromTray': true,
                  'openedAt': FieldValue.serverTimestamp(),
                  'readSource': 'system_tray',
                });
                widget.logger
                    .i('✅ Marked notification as read from system tray');
              } catch (e) {
                widget.logger.e('Error marking notification as read', error: e);
              }
            }
          }

          // Mark the queue doc this tray notification came from as read
          // (notification_service.dart puts its source and id in the
          // payload), so the in-app notification center agrees.
          final docId = receivedAction.payload!['notificationDocId'];
          final collection = receivedAction.payload!['notificationCollection'];
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (docId != null && collection != null && uid != null) {
            try {
              await NotificationRepository(FirebaseFirestore.instance).markReadById(collection, docId, uid);
            } catch (e) {
              widget.logger.w('⚠️ Could not mark tray notification $collection/$docId read: $e');
            }
          }

          // Everything with a destination (inventory, project date
          // extensions, messages, safety training, …) is routed by the same
          // NotificationRouter the in-app notification center uses, so a
          // notification opens the same place from either.
          final payload = Map<String, dynamic>.from(receivedAction.payload!);
          if (navState == null || messenger == null) {
            widget.logger.w('⚠️ Notification tapped before the app was ready — not navigating');
          } else if (NotificationRouter.hasDestination(payload)) {
            await NotificationRouter(navigator: navState, messenger: messenger, logger: widget.logger).open(payload);
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    widget.logger.i('🏗️ Building AlmaWorks main app widget');

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return ListenableBuilder(
      listenable: Listenable.merge([localeProvider, themeProvider]),
      builder: (context, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'AlmaWorks',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeProvider.themeMode,
        debugShowCheckedModeBanner: false,
        locale: localeProvider.locale,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: LocaleProvider.supportedLocales,
        home: AuthenticationWrapper(logger: widget.logger),
      ),
    );
  }
}

// ─── Authentication wrapper ───────────────────────────────────────────────────
class AuthenticationWrapper extends StatefulWidget {
  final Logger logger;

  const AuthenticationWrapper({super.key, required this.logger});

  @override
  State<AuthenticationWrapper> createState() => _AuthenticationWrapperState();
}

class _AuthenticationWrapperState extends State<AuthenticationWrapper> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  bool _isLoggedIn = false;
  String _username = '';
  String _role = '';

  @override
  void initState() {
    super.initState();
    _checkAuthenticationStatus();
  }

  Future<void> _checkAuthenticationStatus() async {
    try {
      widget.logger.i('🔍 Checking authentication status...');

      final isLoggedIn = await _authService.isUserLoggedIn();

      if (isLoggedIn) {
        widget.logger.i('✅ User is logged in, fetching user data...');
        final userData = await _authService.getUserData();

        if (userData != null) {
          setState(() {
            _isLoggedIn = true;
            _username = userData['username'] ?? '';
            _role = userData['role'] ?? 'Client';
            _isLoading = false;
          });
          widget.logger.i('✅ User data loaded: $_username ($_role)');
        } else {
          widget.logger.w('⚠️ User data not found, redirecting to login');
          setState(() {
            _isLoggedIn = false;
            _isLoading = false;
          });
        }
      } else {
        widget.logger.i('❌ User not logged in');
        setState(() {
          _isLoggedIn = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      widget.logger.e('❌ Error checking authentication: $e');
      setState(() {
        _isLoggedIn = false;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A2E5A),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 20),
              const Text(
                'AlmaWorks',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Site Management System',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoggedIn) {
      widget.logger.i('🎯 Routing to WelcomeScreen for $_username');
      return WelcomeScreen(username: _username, initialRole: _role);
    } else {
      widget.logger.i('🎯 Routing to LoginScreen');
      return const LoginScreen();
    }
  }
}

// ─── Error fallback app ───────────────────────────────────────────────────────
class ErrorApp extends StatelessWidget {
  final String error;

  const ErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Failed to initialize AlmaWorks',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}