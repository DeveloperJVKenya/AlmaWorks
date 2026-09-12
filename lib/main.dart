import 'package:almaworks/authentication/login_screen.dart';
import 'package:almaworks/authentication/welcome_screen.dart';
import 'package:almaworks/rbacsystem/firebase_notification_handler.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/providers/locale_provider.dart';
import 'package:almaworks/providers/theme_provider.dart';
import 'package:almaworks/rbacsystem/auth_service.dart';
import 'package:almaworks/screens/communication/communication_message_detail_screen.dart';
import 'package:almaworks/screens/communication/communication_models.dart';
import 'package:almaworks/screens/communication/communication_notification_service.dart';
import 'package:almaworks/screens/communication/communication_screen.dart';
import 'package:almaworks/screens/communication/communication_service.dart';
import 'package:almaworks/models/inventory/checkout_request_model.dart';
import 'package:almaworks/screens/inventory/asset_detail_screen.dart';
import 'package:almaworks/screens/inventory/review_checkout_request_screen.dart';
import 'package:almaworks/screens/schedule/task_progress_monitor_screen.dart';
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

          // ── Client request notifications ────────────────────────────────
          else if (notificationType == 'client_request') {
            widget.logger.d('Client request notification tapped');
          }

          // ── Inventory notifications (checkout requests, returns, etc.) ──
          // Covers every InventoryService._notifyAdmins / _notifyUser type
          // (inventory_return_intent, inventory_checkout_request,
          // inventory_checkout_approved/rejected, inventory_overdue_return,
          // inventory_delivery_dispatched, inventory_booking_*,
          // inventory_return_for_maintenance, etc.) — previously none of
          // these had a tap route at all, so tapping just opened the app
          // with no navigation. A pending checkout request opens straight
          // into its review screen; everything else (which always carries
          // an assetId) opens that asset's detail screen, where the
          // relevant action (Record Return, Acknowledge Receipt, etc.)
          // lives.
          else if (notificationType.startsWith('inventory_')) {
            final assetId = receivedAction.payload!['assetId'];
            final requestId = receivedAction.payload!['requestId'];
            widget.logger.d(
                'Inventory notification tapped: type=$notificationType, assetId=$assetId, requestId=$requestId');

            if (notificationType == 'inventory_checkout_request' && requestId != null) {
              await _navigateToInventoryRequest(requestId: requestId, assetId: assetId);
            } else if (assetId != null) {
              await _navigateToInventoryAsset(assetId: assetId);
            }
          }

          // ── Task Progress date-extension notifications ──────────────────
          // Covers TaskProgressMonitorScreen._notifyUser/_notifyAdmins'
          // project_date_extension_requested/approved/rejected types — all
          // three carry just a projectId (the approval surface lives on
          // the Task Progress Monitor screen itself, not a separate
          // review screen), so tapping any of them opens straight there.
          else if (notificationType.startsWith('project_date_extension')) {
            final projectId = receivedAction.payload!['projectId'];
            widget.logger.d(
                'Project date-extension notification tapped: type=$notificationType, projectId=$projectId');
            if (projectId != null) {
              await _navigateToTaskProgressMonitor(projectId: projectId);
            }
          }

          // ── Communication (message) notifications ───────────────────────
          else if (notificationType == 'communication') {
            final messageId = receivedAction.payload!['messageId'];
            final projectId = receivedAction.payload!['projectId'];
            widget.logger.d(
                'Communication notification tapped: messageId=$messageId, projectId=$projectId');

            if (messageId != null && projectId != null) {
              await _navigateToMessage(
                messageId: messageId,
                projectId: projectId,
              );
            }
          }
        }
      },
    );
  }

  // ─── Deep-link navigation ─────────────────────────────────────────────────
  /// Fetches the project, message, current user, and project users from
  /// Firestore, then pushes [CommunicationScreen] + [CommunicationMessageDetailScreen]
  /// onto the current navigation stack using the global [navigatorKey].
  ///
  /// Called when the user taps a communication notification from the system
  /// tray while the app is open or resuming from background.
  Future<void> _navigateToMessage({
    required String messageId,
    required String projectId,
  }) async {
    final navState = navigatorKey.currentState;
    if (navState == null) {
      widget.logger.w(
          '⚠️ _navigateToMessage: navigatorKey has no current state — app not yet ready');
      return;
    }

    // Show a brief feedback snackbar while we fetch data
    final messenger = ScaffoldMessenger.of(navigatorKey.currentContext!);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Opening message…'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final db = FirebaseFirestore.instance;
      final commService = CommunicationService();

      // 1 ── Fetch the message document ─────────────────────────────────────
      final msgDoc =
          await db.collection('Communication').doc(messageId).get();
      if (!msgDoc.exists) {
        widget.logger.w('⚠️ _navigateToMessage: message $messageId not found');
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(content: Text('Message not found or has been deleted.')),
        );
        return;
      }
      final message = CommunicationMessage.fromDoc(msgDoc);

      // 2 ── Fetch the project document ─────────────────────────────────────
      final projectDoc =
          await db.collection('Projects').doc(projectId).get();
      if (!projectDoc.exists) {
        widget.logger
            .w('⚠️ _navigateToMessage: project $projectId not found');
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(content: Text('Project not found.')),
        );
        return;
      }
      final project = ProjectModel.fromFirestore(projectDoc);

      // 3 ── Fetch the current user's participant record ─────────────────────
      final currentUser = await commService.getCurrentUserParticipant();
      if (currentUser == null) {
        widget.logger.w('⚠️ _navigateToMessage: could not resolve current user');
        messenger.hideCurrentSnackBar();
        return;
      }

      // 4 ── Fetch users who share this project (for Reply / Reply All) ──────
      final projectUsers = await commService.getProjectUsers(projectId);

      messenger.hideCurrentSnackBar();

      // 5 ── Navigate ────────────────────────────────────────────────────────
      // Push CommunicationScreen first so the user can tap Back and land on
      // their inbox rather than wherever they were before the notification.
      navState.push(
        MaterialPageRoute(
          builder: (_) => CommunicationScreen(
            project: project,
            logger: widget.logger,
          ),
        ),
      );

      // Then immediately push the specific message on top.
      navState.push(
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

      widget.logger.i(
          '✅ _navigateToMessage: navigated to message $messageId in project $projectId');
    } catch (e, stack) {
      widget.logger.e('❌ _navigateToMessage failed',
          error: e, stackTrace: stack);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Could not open message. Please try again.')),
      );
    }
  }

  /// Inventory is company-wide, not project-scoped — `project` only exists
  /// so BaseLayout can render its header/project-switcher chrome (see
  /// base_layout.dart's Inventory menu entry). Prefers the asset's own
  /// `currentProjectId` when it has one, falling back to any project so
  /// navigation never dead-ends just because the asset happens to be sitting
  /// unassigned in storage.
  Future<ProjectModel?> _resolveProjectForInventory(String? projectId) async {
    final db = FirebaseFirestore.instance;
    if (projectId != null) {
      final doc = await db.collection('Projects').doc(projectId).get();
      if (doc.exists) return ProjectModel.fromFirestore(doc);
    }
    final anySnap = await db.collection('Projects').limit(1).get();
    if (anySnap.docs.isEmpty) return null;
    return ProjectModel.fromFirestore(anySnap.docs.first);
  }

  /// Resolves the signed-in user's role/username the same way
  /// dashboard_screen.dart does, for screens reached via a notification tap
  /// rather than normal in-app navigation (where these are already
  /// available from a provider).
  Future<({String role, String username})?> _resolveCurrentUser() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return null;
    final snap = await FirebaseFirestore.instance
        .collection('Users')
        .where('uid', isEqualTo: authUser.uid)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return (role: snap.docs.first.data()['role'] as String? ?? 'Client', username: snap.docs.first.id);
  }

  /// Opens Task Progress Monitor for the given project — the destination
  /// for every `project_date_extension_*` notification tap. That screen
  /// itself surfaces the request's detail/approve UI via its AppBar badge
  /// (see task_progress_monitor_screen.dart's _showProjectExtensionDetailDialog),
  /// so there's no separate review screen to route into.
  Future<void> _navigateToTaskProgressMonitor({required String projectId}) async {
    final navState = navigatorKey.currentState;
    if (navState == null) {
      widget.logger.w('⚠️ _navigateToTaskProgressMonitor: navigatorKey has no current state — app not yet ready');
      return;
    }
    final messenger = ScaffoldMessenger.of(navigatorKey.currentContext!);
    messenger.showSnackBar(const SnackBar(content: Text('Opening project…'), duration: Duration(seconds: 2)));

    try {
      final doc = await FirebaseFirestore.instance.collection('Projects').doc(projectId).get();
      if (!doc.exists) {
        widget.logger.w('⚠️ _navigateToTaskProgressMonitor: project $projectId not found');
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(const SnackBar(content: Text('That project no longer exists.')));
        return;
      }
      final project = ProjectModel.fromFirestore(doc);
      messenger.hideCurrentSnackBar();
      navState.push(
        MaterialPageRoute(builder: (_) => TaskProgressMonitorScreen(project: project, logger: widget.logger)),
      );
      widget.logger.i('✅ _navigateToTaskProgressMonitor: navigated to project $projectId');
    } catch (e, stack) {
      widget.logger.e('❌ _navigateToTaskProgressMonitor failed', error: e, stackTrace: stack);
      messenger.hideCurrentSnackBar();
    }
  }

  /// Opens the asset's detail screen — where Record Return, Acknowledge
  /// Receipt, and every other Inventory action actually lives — from an
  /// `inventory_*` notification tap.
  Future<void> _navigateToInventoryAsset({required String assetId, String? projectId}) async {
    final navState = navigatorKey.currentState;
    if (navState == null) {
      widget.logger.w('⚠️ _navigateToInventoryAsset: navigatorKey has no current state — app not yet ready');
      return;
    }
    final messenger = ScaffoldMessenger.of(navigatorKey.currentContext!);
    messenger.showSnackBar(const SnackBar(content: Text('Opening asset…'), duration: Duration(seconds: 2)));

    try {
      final authUser = FirebaseAuth.instance.currentUser;
      final currentUser = await _resolveCurrentUser();
      if (authUser == null || currentUser == null) {
        widget.logger.w('⚠️ _navigateToInventoryAsset: could not resolve current user');
        messenger.hideCurrentSnackBar();
        return;
      }

      final assetDoc = await FirebaseFirestore.instance.collection('InventoryAssets').doc(assetId).get();
      if (!assetDoc.exists) {
        widget.logger.w('⚠️ _navigateToInventoryAsset: asset $assetId not found');
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(const SnackBar(content: Text('Asset not found or has been removed.')));
        return;
      }

      final project = await _resolveProjectForInventory(projectId ?? assetDoc.data()?['currentProjectId'] as String?);
      if (project == null) {
        widget.logger.w('⚠️ _navigateToInventoryAsset: no project available for chrome context');
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(const SnackBar(content: Text('Could not open Inventory right now.')));
        return;
      }

      messenger.hideCurrentSnackBar();
      navState.push(
        MaterialPageRoute(
          builder: (_) => AssetDetailScreen(
            project: project,
            logger: widget.logger,
            assetId: assetId,
            userRole: currentUser.role,
            username: currentUser.username,
            currentUid: authUser.uid,
          ),
        ),
      );
      widget.logger.i('✅ _navigateToInventoryAsset: navigated to asset $assetId');
    } catch (e, stack) {
      widget.logger.e('❌ _navigateToInventoryAsset failed', error: e, stackTrace: stack);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('Could not open asset. Please try again.')));
    }
  }

  /// Opens a pending checkout request straight into its review screen —
  /// this is the direct "review and take an action" surface for
  /// MainAdmin/SystemAdmin tapping an `inventory_checkout_request` push.
  /// Falls back to the asset's detail screen if the request has already
  /// been handled by the time it's tapped.
  Future<void> _navigateToInventoryRequest({required String requestId, String? assetId}) async {
    final navState = navigatorKey.currentState;
    if (navState == null) {
      widget.logger.w('⚠️ _navigateToInventoryRequest: navigatorKey has no current state — app not yet ready');
      return;
    }
    final messenger = ScaffoldMessenger.of(navigatorKey.currentContext!);
    messenger.showSnackBar(const SnackBar(content: Text('Opening request…'), duration: Duration(seconds: 2)));

    try {
      final requestDoc =
          await FirebaseFirestore.instance.collection('InventoryCheckoutRequests').doc(requestId).get();
      if (!requestDoc.exists || requestDoc.data()?['status'] != CheckoutRequestModel.statusPending) {
        widget.logger.i('ℹ️ _navigateToInventoryRequest: request $requestId no longer pending');
        messenger.hideCurrentSnackBar();
        if (assetId != null) {
          await _navigateToInventoryAsset(assetId: assetId);
        } else {
          messenger.showSnackBar(const SnackBar(content: Text('This request has already been handled.')));
        }
        return;
      }
      final request = CheckoutRequestModel.fromFirestore(requestDoc);

      final authUser = FirebaseAuth.instance.currentUser;
      final currentUser = await _resolveCurrentUser();
      if (authUser == null || currentUser == null) {
        widget.logger.w('⚠️ _navigateToInventoryRequest: could not resolve current user');
        messenger.hideCurrentSnackBar();
        return;
      }

      final project = await _resolveProjectForInventory(request.projectId);
      if (project == null) {
        widget.logger.w('⚠️ _navigateToInventoryRequest: no project available for chrome context');
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(const SnackBar(content: Text('Could not open Inventory right now.')));
        return;
      }

      messenger.hideCurrentSnackBar();
      navState.push(
        MaterialPageRoute(
          builder: (_) => ReviewCheckoutRequestScreen(
            project: project,
            logger: widget.logger,
            request: request,
            respondedByUid: authUser.uid,
            respondedByName: currentUser.username,
            respondedByRole: currentUser.role,
          ),
        ),
      );
      widget.logger.i('✅ _navigateToInventoryRequest: navigated to request $requestId');
    } catch (e, stack) {
      widget.logger.e('❌ _navigateToInventoryRequest failed', error: e, stackTrace: stack);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('Could not open request. Please try again.')));
    }
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