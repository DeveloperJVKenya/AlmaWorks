// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get close => 'Close';

  @override
  String get ok => 'OK';

  @override
  String get retry => 'Try again';

  @override
  String get confirm => 'Confirm';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get back => 'Back';

  @override
  String get next => 'Next';

  @override
  String get done => 'Done';

  @override
  String get add => 'Add';

  @override
  String get remove => 'Remove';

  @override
  String get submit => 'Submit';

  @override
  String get search => 'Search';

  @override
  String get refresh => 'Refresh';

  @override
  String get loading => 'Loading…';

  @override
  String get view => 'View';

  @override
  String get open => 'Open';

  @override
  String get download => 'Download';

  @override
  String get upload => 'Upload';

  @override
  String get share => 'Share';

  @override
  String get approve => 'Approve';

  @override
  String get reject => 'Reject';

  @override
  String get select => 'Select';

  @override
  String get clear => 'Clear';

  @override
  String get apply => 'Apply';

  @override
  String get continueLabel => 'Continue';

  @override
  String get logout => 'Log out';

  @override
  String get settings => 'Settings';

  @override
  String get account => 'Account';

  @override
  String get notifications => 'Notifications';

  @override
  String get required => 'Required';

  @override
  String get optional => 'Optional';

  @override
  String get all => 'All';

  @override
  String get none => 'None';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get unknown => 'Unknown';

  @override
  String get notAvailable => 'N/A';

  @override
  String get appTagline => 'Site Management System';

  @override
  String get copyrightFooter => '© 2026 JV Alma C.I.S Site Management System';

  @override
  String get errGeneric =>
      'Something went wrong. Please try again — if it keeps happening, contact your administrator.';

  @override
  String get errTryAgain => 'Please try again.';

  @override
  String get errNoPermission =>
      'You don\'t have permission to do this. If you think that\'s a mistake, ask an administrator to check your access.';

  @override
  String get errNetwork =>
      'No internet connection. Check your connection and try again.';

  @override
  String get errTimeout => 'This is taking too long. Please try again.';

  @override
  String get errNotFound =>
      'We couldn\'t find this. It may have been moved or deleted.';

  @override
  String get errAlreadyExists => 'This already exists.';

  @override
  String get errSignInAgain => 'Your session has ended. Please sign in again.';

  @override
  String get errBusy =>
      'The service is busy right now. Please try again in a moment.';

  @override
  String get errStorageFull =>
      'Storage is full. Please contact your administrator.';

  @override
  String get errCancelled => 'The action was cancelled.';

  @override
  String get errInvalidData =>
      'Some information is missing or not valid. Please check and try again.';

  @override
  String get errWrongCredentials => 'The email or password is incorrect.';

  @override
  String get errInvalidEmail => 'Please enter a valid email address.';

  @override
  String get errEmailInUse => 'An account with this email already exists.';

  @override
  String get errWeakPassword =>
      'Please choose a stronger password (at least 6 characters).';

  @override
  String get errTooManyAttempts =>
      'Too many attempts. Please wait a few minutes and try again.';

  @override
  String get errAccountDisabled =>
      'This account has been disabled. Please contact your administrator.';

  @override
  String get settingsSubtitle => 'Appearance, accessibility and language';

  @override
  String get appearance => 'Appearance';

  @override
  String get appearanceHint => 'Choose how AlmaWorks looks on this device.';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeSystemHint => 'Matches your device';

  @override
  String get themeLight => 'Light';

  @override
  String get themeLightHint => 'Bright and clear';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeDarkHint => 'Easier on the eyes at night';

  @override
  String get font => 'Font';

  @override
  String get fontHint => 'Pick the typeface that\'s easiest for you to read.';

  @override
  String get fontPoppinsDesc => 'Default · modern and rounded';

  @override
  String get fontInterDesc => 'Crisp and neutral';

  @override
  String get fontRobotoDesc => 'Familiar and compact';

  @override
  String get fontOpenSansDesc => 'Open and friendly';

  @override
  String get fontNunitoDesc => 'Soft and rounded';

  @override
  String get fontAtkinsonDesc => 'Made for low-vision readers';

  @override
  String get fontMerriweatherDesc => 'Classic serif for long reading';

  @override
  String get accessibility => 'Accessibility';

  @override
  String get accessibilityHint =>
      'Make text and screens easier to read and use.';

  @override
  String get textSize => 'Text size';

  @override
  String get textSizeHint =>
      'Applies to every screen, on top of your device setting.';

  @override
  String get textSizeSmall => 'Small';

  @override
  String get textSizeDefault => 'Default';

  @override
  String get textSizeLarge => 'Large';

  @override
  String get textSizeExtraLarge => 'Extra large';

  @override
  String get boldText => 'Bold text';

  @override
  String get boldTextHint => 'Makes all text thicker and easier to see.';

  @override
  String get highContrast => 'High contrast';

  @override
  String get highContrastHint => 'Stronger colors for text and borders.';

  @override
  String get reduceMotion => 'Reduce motion';

  @override
  String get reduceMotionHint =>
      'Turns off page transitions and moving effects.';

  @override
  String get resetDisplaySettings => 'Reset to defaults';

  @override
  String get resetDisplaySettingsDone =>
      'Appearance and accessibility settings are back to their defaults.';

  @override
  String get language => 'Language';

  @override
  String get languageHint => 'Used on every screen, message and notification.';

  @override
  String languageChanged(String language) {
    return 'Language changed to $language';
  }

  @override
  String get languageNotificationNote =>
      'Notifications sent to you will also arrive in this language.';

  @override
  String get deviceNotifications => 'Alerts on this device';

  @override
  String get deviceNotificationsHint =>
      'Pop-up alerts for tasks, requests and messages. Your notification inbox keeps everything either way.';

  @override
  String get preview => 'Preview';

  @override
  String get previewTitle => 'Site inspection — Block A';

  @override
  String get previewBody =>
      'Foundation works are 80% complete. The next inspection is on Friday.';

  @override
  String get previewStatus => 'On track';

  @override
  String get previewAction => 'View details';

  @override
  String get about => 'About';

  @override
  String get aboutApp => 'JV Alma C.I.S Site Management System';

  @override
  String get aboutAppHint =>
      'Projects, schedules, documents, safety and inventory in one place.';

  @override
  String get selected => 'Selected';

  @override
  String get settingsSavedAutomatically =>
      'Changes are saved automatically on this device.';

  @override
  String get channelOverdueTasks => 'Overdue tasks';

  @override
  String get channelOverdueTasksDesc =>
      'Alerts for tasks that are past their end date';

  @override
  String get channelStartingSoon => 'Tasks starting soon';

  @override
  String get channelStartingSoonDesc => 'Alerts for tasks about to start';

  @override
  String get channelTaskSummary => 'Task summary';

  @override
  String get channelTaskSummaryDesc => 'Grouped task alerts';

  @override
  String get channelRequests => 'Requests and approvals';

  @override
  String get channelRequestsDesc =>
      'Access requests, inventory, safety training and project updates';

  @override
  String get channelMessages => 'Messages';

  @override
  String get channelMessagesDesc => 'New messages and replies';

  @override
  String get startupFailedTitle => 'AlmaWorks couldn\'t start';

  @override
  String get startupFailedMessage =>
      'Please check your internet connection and open the app again. If this keeps happening, contact your administrator.';

  @override
  String get roleMainAdmin => 'Main Admin';

  @override
  String get roleSystemAdmin => 'System Admin';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleClient => 'Client';

  @override
  String get roleTechnician => 'Technician';

  @override
  String get roleSubContractor => 'Subcontractor';

  @override
  String get roleManager => 'Manager';

  @override
  String get roleMember => 'Member';

  @override
  String get myProjectDashboard => 'My Project Dashboard';

  @override
  String get projectDashboard => 'Project Dashboard';

  @override
  String get navSwitchProject => 'Switch Project';

  @override
  String get navMyProjects => 'My Projects';

  @override
  String get navOverview => 'Overview';

  @override
  String get navDocuments => 'Documents';

  @override
  String get navDrawings => 'Drawings';

  @override
  String get navSchedule => 'Schedule';

  @override
  String get navQualitySafety => 'Quality & Safety';

  @override
  String get navReports => 'Reports';

  @override
  String get navPhotoGallery => 'Photo Gallery';

  @override
  String get navPhotos => 'Photos';

  @override
  String get navFinancials => 'Financials';

  @override
  String get navAccount => 'Account';

  @override
  String get myAccount => 'My Account';

  @override
  String get editProfile => 'Edit profile';

  @override
  String get refreshProfile => 'Refresh profile';

  @override
  String get loadingProfile => 'Loading your profile…';

  @override
  String get couldNotLoadProfile => 'Couldn\'t load your profile';

  @override
  String get profileNotFound =>
      'We couldn\'t find your profile. Please contact your administrator.';

  @override
  String get nameCannotBeEmpty => 'Please enter your name.';

  @override
  String get profileUpdated => 'Your profile has been updated.';

  @override
  String get couldNotSaveProfile => 'Couldn\'t save your profile.';

  @override
  String get fullName => 'Full name';

  @override
  String get emailAddress => 'Email address';

  @override
  String get email => 'Email';

  @override
  String get emailChangeNote =>
      'Changing your email here updates your profile only — not the email you sign in with.';

  @override
  String get unknownUser => 'Unknown user';

  @override
  String get noEmailOnRecord => 'No email on record';

  @override
  String get openSettings => 'Open settings';

  @override
  String textSizePercent(int percent) {
    return 'Text $percent%';
  }

  @override
  String get on => 'On';

  @override
  String get off => 'Off';

  @override
  String get logoutConfirm => 'Are you sure you want to log out?';

  @override
  String get notificationsHint => 'Choose how AlmaWorks alerts you.';

  @override
  String get loadingDashboard => 'Loading dashboard…';

  @override
  String get welcomeToAlmaWorks => 'Welcome to AlmaWorks';

  @override
  String get getStarted => 'Get started';

  @override
  String get requestAccessIntro =>
      'To see construction projects and work with your team, you\'ll need to ask an administrator for access.';

  @override
  String get requestAccessStep1 => 'Tap the button below to send your request';

  @override
  String get requestAccessStep2 => 'An administrator will review it';

  @override
  String get requestAccessStep3 => 'You\'ll be notified once access is granted';

  @override
  String get previousRequestDenied => 'Your previous request was not approved';

  @override
  String get accessRequestSent => 'Your access request has been sent.';

  @override
  String get couldNotSendAccessRequest => 'Couldn\'t send your access request.';

  @override
  String get sending => 'Sending…';

  @override
  String get requestAccess => 'Request access';

  @override
  String get requestPending => 'Request pending';

  @override
  String get requestPendingMessage =>
      'An administrator is reviewing your access request. You\'ll get access as soon as it\'s approved.';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navProjects => 'Projects';

  @override
  String get navClientAccessRequests => 'Access Requests';

  @override
  String get couldNotLoadScreen => 'This screen couldn\'t be opened';

  @override
  String get goToDashboard => 'Go to dashboard';

  @override
  String get myProjectsOverview => 'My Projects Overview';

  @override
  String get generalOverview => 'General Overview';

  @override
  String get totalProjects => 'Total Projects';

  @override
  String get activeProjects => 'Active Projects';

  @override
  String get completedProjects => 'Completed Projects';

  @override
  String get previous => 'Previous';

  @override
  String get openingSafetyTraining => 'Opening Safety Training…';

  @override
  String get couldNotOpenSafetyTraining =>
      'Safety Training couldn\'t be opened right now. Please try again.';

  @override
  String get openingProject => 'Opening project…';

  @override
  String get projectNoLongerExists => 'This project no longer exists.';

  @override
  String get couldNotOpenProject =>
      'The project couldn\'t be opened. Please try again.';

  @override
  String get openingMessage => 'Opening message…';

  @override
  String get messageNotFound =>
      'This message was not found or has been deleted.';

  @override
  String get projectNotFound => 'Project not found.';

  @override
  String get couldNotOpenMessage =>
      'The message couldn\'t be opened. Please try again.';

  @override
  String get openingAsset => 'Opening item…';

  @override
  String get assetNotFound => 'This item was not found or has been removed.';

  @override
  String get couldNotOpenInventory =>
      'Inventory couldn\'t be opened right now. Please try again.';

  @override
  String get couldNotOpenAsset =>
      'The item couldn\'t be opened. Please try again.';

  @override
  String get openingRequest => 'Opening request…';

  @override
  String get requestAlreadyHandled => 'This request has already been handled.';

  @override
  String get couldNotOpenRequest =>
      'The request couldn\'t be opened. Please try again.';

  @override
  String notificationsUnread(int count) {
    return 'Notifications ($count unread)';
  }

  @override
  String get catSafety => 'Safety';

  @override
  String get catProjects => 'Projects';

  @override
  String get catInventory => 'Inventory';

  @override
  String get catMessages => 'Messages';

  @override
  String get catAccess => 'Access';

  @override
  String get catOther => 'Other';

  @override
  String get notificationFallbackTitle => 'Notification';

  @override
  String get taskUpdate => 'Task update';

  @override
  String get justNow => 'just now';

  @override
  String minutesAgo(int n) {
    return '${n}m ago';
  }

  @override
  String hoursAgo(int n) {
    return '${n}h ago';
  }

  @override
  String daysAgo(int n) {
    return '${n}d ago';
  }

  @override
  String monthsAgo(int n) {
    return '${n}mo ago';
  }

  @override
  String get allCaughtUp => 'You\'re all caught up';

  @override
  String unreadCount(int count) {
    return '$count unread';
  }

  @override
  String get markAllRead => 'Mark all read';

  @override
  String get couldNotLoadNotifications => 'Couldn\'t load notifications';

  @override
  String get someNotificationsMissing =>
      'Some notifications couldn\'t be loaded — the list may be incomplete.';

  @override
  String get noUnreadNotifications => 'No unread notifications';

  @override
  String get nothingHereYet => 'Nothing here yet';

  @override
  String get notificationsEmptyHint =>
      'Updates about your projects, inventory, safety training and messages will appear here.';

  @override
  String get tryAnotherFilter => 'Try another filter to see more.';

  @override
  String get allMarkedRead => 'All notifications marked as read';

  @override
  String get couldNotMarkRead => 'Couldn\'t mark the notifications as read.';

  @override
  String get unread => 'Unread';

  @override
  String get safetyUnread => 'Safety (unread)';

  @override
  String get total => 'Total';

  @override
  String get markUnread => 'Mark unread';

  @override
  String get markRead => 'Mark read';

  @override
  String get more => 'More';

  @override
  String get viewDetails => 'View details';

  @override
  String get markAsUnread => 'Mark as unread';

  @override
  String get markAsRead => 'Mark as read';

  @override
  String get couldNotUpdateNotification => 'Couldn\'t update the notification.';

  @override
  String get notificationRemoved => 'Notification removed';

  @override
  String get couldNotRemoveNotification => 'Couldn\'t remove the notification.';

  @override
  String get noFurtherDetails => 'No further details.';

  @override
  String get requestNoLongerExists => 'Request no longer exists';

  @override
  String get thisUser => 'This user';

  @override
  String get anAdmin => 'an admin';

  @override
  String accessApprovedTitle(String name) {
    return '✅ Access approved — $name';
  }

  @override
  String accessApprovedBody(String name, String role, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count projects',
      one: '1 project',
    );
    return '$name was approved as $role with access to $_temp0.';
  }

  @override
  String approvedByWhen(String name, String when) {
    return 'Approved by $name$when';
  }

  @override
  String accessDeniedTitle(String name) {
    return '❌ Access denied — $name';
  }

  @override
  String accessDeniedBody(String name) {
    return '$name\'s access request was denied.';
  }

  @override
  String reasonLabel(String reason) {
    return 'Reason: $reason';
  }

  @override
  String deniedByWhen(String name, String when) {
    return 'Denied by $name$when';
  }

  @override
  String get awaitingDecision => 'Awaiting a decision';

  @override
  String get newNotification => '🔔 New notification';

  @override
  String get viewRequest => 'View request';

  @override
  String get notifNewAccessRequestTitle => '🔔 New access request';

  @override
  String notifNewAccessRequestBody(String name) {
    return '$name is asking for access to projects';
  }

  @override
  String get notifAccessGrantedTitle => '✅ Access granted';

  @override
  String notifAccessGrantedBody(String projects) {
    return 'Your request has been approved! You now have access to: $projects';
  }

  @override
  String get notifRequestDeniedTitle => '❌ Request denied';

  @override
  String get notifRequestDeniedBody =>
      'Your access request was not approved by an administrator.';

  @override
  String get notifProjectAccessUpdatedTitle => '🔄 Project access updated';

  @override
  String notifProjectAccessAddedRemoved(String added, String removed) {
    return 'Your project access has changed. Added: $added. Removed: $removed.';
  }

  @override
  String notifProjectAccessAdded(String projects) {
    return 'You now have access to: $projects.';
  }

  @override
  String notifProjectAccessRemoved(String projects) {
    return 'Your access to these projects has been removed: $projects.';
  }

  @override
  String taskOverdueTitle(String task) {
    return '⚠️ Overdue: $task';
  }

  @override
  String taskStartingSoonTitle(String task) {
    return '📅 Starting soon: $task';
  }

  @override
  String get taskOverdueBody => 'This task is overdue and needs attention.';

  @override
  String taskStartsInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Starts in $days days',
      one: 'Starts in 1 day',
      zero: 'Starts today',
    );
    return '$_temp0';
  }

  @override
  String get markReadAction => 'Mark read';

  @override
  String taskAlertsSummaryBoth(int overdue, int soon) {
    return '$overdue overdue, $soon starting soon';
  }

  @override
  String taskAlertsSummaryOverdue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count overdue tasks',
      one: '1 overdue task',
    );
    return '$_temp0';
  }

  @override
  String taskAlertsSummarySoon(int count) {
    return '$count starting soon';
  }

  @override
  String taskAlertsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '🔔 $count task alerts',
      one: '🔔 1 task alert',
    );
    return '$_temp0';
  }

  @override
  String get viewAll => 'View all';

  @override
  String get taskIsOverdue => 'Task is overdue';

  @override
  String get taskStartsSoon => 'Task starts soon';

  @override
  String get chooseLanguage => 'Choose language';

  @override
  String get accountNotFound =>
      'No account was found with this email address. Please check it and try again.';

  @override
  String get incorrectPassword =>
      'Incorrect password. Please try again or reset your password.';

  @override
  String get tooManyLoginAttempts =>
      'Too many failed sign-in attempts. Please wait a few minutes or reset your password.';

  @override
  String get signInFailed => 'We couldn\'t sign you in.';

  @override
  String get enterEmailFirst => 'Please enter your email address first.';

  @override
  String passwordResetSent(String email) {
    return 'A password reset email has been sent to $email. Please check your inbox.';
  }

  @override
  String get couldNotSendResetEmail =>
      'Couldn\'t send the password reset email.';

  @override
  String get welcomeBackHeadline => 'Welcome back to\nAlmaWorks';

  @override
  String get welcomeBackSubtext =>
      'Sign in to manage your projects, inventory and team communication — all in one place.';

  @override
  String get signIn => 'Sign in';

  @override
  String get signInSubtitle => 'Enter your details to access your account';

  @override
  String get emailHint => 'you@company.com';

  @override
  String get emailRequired => 'Please enter your email';

  @override
  String get password => 'Password';

  @override
  String get passwordHint => 'Enter your password';

  @override
  String get passwordRequired => 'Please enter your password';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get login => 'Sign in';

  @override
  String get noAccountYet => 'Don\'t have an account? ';

  @override
  String get signUp => 'Sign up';

  @override
  String get usernameRequired => 'Please choose a username';

  @override
  String get usernameTaken =>
      'This username is already taken. Please choose a different one.';

  @override
  String get registrationSuccess =>
      'Your account has been created. Welcome to AlmaWorks!';

  @override
  String get emailAlreadyRegistered =>
      'This email address is already registered. Please sign in instead.';

  @override
  String get couldNotCreateAccount => 'We couldn\'t create your account.';

  @override
  String get joinHeadline => 'Join the\nAlmaWorks team';

  @override
  String get joinSubtext =>
      'Create an account to start tracking projects, assets and communication in one workspace.';

  @override
  String get createAccount => 'Create account';

  @override
  String get createAccountSubtitle => 'Fill in your details to get started';

  @override
  String get username => 'Username';

  @override
  String get usernameHint => 'Choose a unique username';

  @override
  String get usernameTooShort => 'Your username needs at least 3 characters';

  @override
  String get usernameInvalidChars =>
      'Use only letters, numbers and underscores (_)';

  @override
  String get newPasswordHint => 'Create a strong password';

  @override
  String get passwordTooShort => 'Your password needs at least 6 characters';

  @override
  String get alreadyHaveAccount => 'Already have an account? ';

  @override
  String roleUpdatedTo(String role) {
    return 'Your role has been updated to $role';
  }

  @override
  String get couldNotCheckRole => 'We couldn\'t check your role.';

  @override
  String welcomeUser(String name) {
    return 'Welcome, $name!';
  }

  @override
  String roleLabel(String role) {
    return 'Role: $role';
  }

  @override
  String get almaWorksSiteManagement => 'AlmaWorks Site Management';

  @override
  String get featureProjectManagement => 'Project management';

  @override
  String get featureProjectManagementDesc =>
      'Organise and track construction projects from start to finish';

  @override
  String get featureTeamCollaboration => 'Team collaboration';

  @override
  String get featureTeamCollaborationDesc =>
      'Coordinate with your team and manage tasks efficiently';

  @override
  String get featureRealtimeInsights => 'Real-time insights';

  @override
  String get featureRealtimeInsightsDesc =>
      'Follow progress with live updates and clear reports';

  @override
  String get featureSiteTracking => 'Site tracking';

  @override
  String get featureSiteTrackingDesc =>
      'Manage several construction sites with location-based tools';

  @override
  String get continueToDashboard => 'Continue to dashboard';

  @override
  String get noAccessToProject => 'You don\'t have access to this project.';

  @override
  String get noProjectSelected => 'Please choose a project first.';

  @override
  String get navSafetyTraining => 'Safety Training';

  @override
  String get navTaskProgress => 'Task Progress';

  @override
  String get navInventory => 'Inventory';

  @override
  String get navCommunication => 'Communication';

  @override
  String get stNotReviewed => 'Not reviewed';

  @override
  String get stClearanceExpired => 'Clearance expired';

  @override
  String stClearanceLapsedOn(String date) {
    return 'Lapsed on $date — a new review is needed.';
  }

  @override
  String get stClearedToWork => 'Cleared to work';

  @override
  String stValidUntil(String date) {
    return 'Valid until $date';
  }

  @override
  String stAllAssignedDone(int count) {
    return 'All $count assigned scenarios done — awaiting a new review.';
  }

  @override
  String stAssignedProgress(int done, int total) {
    return '$done of $total assigned scenarios done';
  }

  @override
  String stOverdueSince(String date) {
    return ' · overdue since $date';
  }

  @override
  String stDue(String date) {
    return ' · due $date';
  }

  @override
  String get stRetrainingOverdue => 'Retraining overdue';

  @override
  String get stRetrainingDone => 'Retraining done';

  @override
  String get stNeedsRetraining => 'Needs retraining';

  @override
  String get stEscalated => 'Escalated';

  @override
  String get stSupervisorFollowUp => 'A supervisor will follow up.';

  @override
  String stEscalatedTo(String name) {
    return 'Escalated to $name for follow-up.';
  }

  @override
  String get stStatusUnknown => 'Status unknown';

  @override
  String get difficultyBasic => 'Basic';

  @override
  String get difficultyIntermediate => 'Intermediate';

  @override
  String get difficultyAdvanced => 'Advanced';

  @override
  String get categoryGeneral => 'General';

  @override
  String get filterNotStarted => 'Not started';

  @override
  String get filterPassed => 'Passed';

  @override
  String get filterMissed => 'Missed';

  @override
  String get filterAssignedToMe => 'Assigned to me';

  @override
  String get couldNotLoadAccount => 'Couldn\'t load your account';

  @override
  String get safetyTrainingUnavailable =>
      'Safety Training isn\'t available yet';

  @override
  String get roleNotSetUp =>
      'Your account\'s access role hasn\'t been set up yet. Please contact an administrator.';

  @override
  String safetyScenariosCount(int count) {
    return 'Safety scenarios ($count)';
  }

  @override
  String get safetyScenarios => 'Safety scenarios';

  @override
  String get closeSearch => 'Close search';

  @override
  String get searchScenarios => 'Search scenarios';

  @override
  String get searchScenariosHint => 'Search by title, category or scene';

  @override
  String get couldNotLoadScenarios => 'Couldn\'t load the scenarios';

  @override
  String get pullToRetry => 'Pull down to try again.';

  @override
  String get noScenariosYet => 'No scenarios yet';

  @override
  String get noScenariosMatch => 'No scenarios match';

  @override
  String get noScenariosAdminHint =>
      'Tap \"New scenario\" in the toolbar to create the first one.';

  @override
  String get noScenariosWorkerHint =>
      'Safety scenarios will appear here once an admin publishes them.';

  @override
  String get tryDifferentSearch => 'Try a different search or filter.';

  @override
  String clearedUntil(String date) {
    return 'Cleared · until $date';
  }

  @override
  String get myStanding => 'My standing';

  @override
  String get myAttempts => 'My attempts';

  @override
  String get myHistory => 'My history';

  @override
  String get reviewStanding => 'Review standing';

  @override
  String get allAttempts => 'All attempts';

  @override
  String get manage => 'Manage';

  @override
  String get newScenario => 'New scenario';

  @override
  String get firstAttemptCountsHint =>
      'Only your first attempt at each scenario counts toward your score — replays are practice.';

  @override
  String get points => 'Points';

  @override
  String get firstTryAccuracy => 'First-try accuracy';

  @override
  String get completed => 'Completed';

  @override
  String get mySafetyStanding => 'My safety standing';

  @override
  String get notAssessedYet =>
      'A reviewer hasn\'t assessed your training yet. Keep working through the scenarios — your first attempts are what they\'ll look at.';

  @override
  String get clearanceValidity => 'Clearance validity';

  @override
  String get expired => 'Expired';

  @override
  String daysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days left',
      one: '1 day left',
    );
    return '$_temp0';
  }

  @override
  String get retrainingProgress => 'Retraining progress';

  @override
  String get assignedListedFirst =>
      'Assigned scenarios are listed first on the Safety Training screen.';

  @override
  String get aReviewer => 'a reviewer';

  @override
  String reviewedByOn(String name, String date) {
    return 'Reviewed by $name on $date';
  }

  @override
  String get incompleteFixInManage => 'Incomplete — fix in Manage';

  @override
  String retrainingDue(String date) {
    return 'Retraining · due $date';
  }

  @override
  String get retraining => 'Retraining';

  @override
  String passedPoints(int points) {
    return 'Passed · +$points pts';
  }

  @override
  String get missedPractise => 'Missed · practise again';

  @override
  String pointsShort(int points) {
    return '$points pts';
  }

  @override
  String get start => 'Start';

  @override
  String get practice => 'Practice';

  @override
  String get scenarioNoLongerExists => 'This scenario no longer exists.';

  @override
  String get scenarioUnavailableTellAdmin =>
      'This scenario can\'t be answered right now. Please let an admin know.';

  @override
  String get roleCannotTakeTraining => 'Your role can\'t take safety training.';

  @override
  String get answerNotAccepted =>
      'Your answer wasn\'t accepted. Please check it and try again.';

  @override
  String get answerSubmitFailed =>
      'Your answer couldn\'t be submitted. Check your connection and tap Retry.';

  @override
  String get answerNotConfirmed =>
      'We couldn\'t confirm your answer was saved. Check your connection and tap Retry — it won\'t be counted twice.';

  @override
  String scenarioSubtitle(String category, String difficulty, int points) {
    return '$category · $difficulty · $points pts';
  }

  @override
  String get scenarioIncomplete =>
      'This scenario is incomplete and can\'t be answered yet. Please let an admin know.';

  @override
  String get questionLabel => 'QUESTION';

  @override
  String get yourAnswer => 'Your answer';

  @override
  String get change => 'Change';

  @override
  String get explainYourThinking => 'EXPLAIN YOUR THINKING';

  @override
  String get explainInOwnWords =>
      'In your own words — this helps your trainer see how well you understand the risk.';

  @override
  String moreCharactersNeeded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more characters needed',
      one: '1 more character needed',
    );
    return '$_temp0';
  }

  @override
  String get explainHint => 'Explain the cause and how to prevent it…';

  @override
  String get submittingAnswer => 'Submitting your answer…';

  @override
  String get submitAnswer => 'Submit answer';

  @override
  String get correctWellSpotted => 'Correct — well spotted!';

  @override
  String get notQuiteRight => 'Not quite right';

  @override
  String plusPoints(int points) {
    return '+$points points';
  }

  @override
  String get noPointsThisTime => 'No points this time';

  @override
  String get practiceAttemptOnly =>
      'Practice attempt — only your first attempt scores';

  @override
  String get correctAnswer => 'Correct answer';

  @override
  String get whyItMatters => 'Why it matters';

  @override
  String get noExplanation => 'No explanation was provided for this scenario.';

  @override
  String get practiceAgain => 'Practice again';

  @override
  String get backToScenarios => 'Back to scenarios';

  @override
  String get whatYouSee => 'WHAT YOU SEE';

  @override
  String get stepObserve => 'Observe';

  @override
  String get stepAnswer => 'Answer';

  @override
  String get stepExplain => 'Explain';

  @override
  String get stepResult => 'Result';

  @override
  String get filterCorrect => 'Correct';

  @override
  String get filterIncorrect => 'Incorrect';

  @override
  String get filterFirstAttempts => 'First attempts';

  @override
  String get filterPractice => 'Practice';

  @override
  String get filterWithFeedback => 'With feedback';

  @override
  String get safetyHistory => 'Safety history';

  @override
  String get mySafetyHistory => 'My safety history';

  @override
  String workersHistory(String name) {
    return '$name\'s history';
  }

  @override
  String get worker => 'Worker';

  @override
  String get everyWorkersAnswers =>
      'Every worker\'s answers, reasoning and feedback';

  @override
  String get answersReasoningFeedback =>
      'Answers, reasoning and trainer feedback';

  @override
  String get couldNotLoadHistory => 'Couldn\'t load the history';

  @override
  String get searchScenarioOrWorker => 'Search by scenario or worker';

  @override
  String get searchByScenario => 'Search by scenario';

  @override
  String get noAttemptsYet => 'No attempts yet';

  @override
  String get noAttemptsHint =>
      'Completed scenarios will appear here with the answer and reasoning given.';

  @override
  String get nothingMatches => 'Nothing matches';

  @override
  String get loadOlderAttempts => 'Load older attempts';

  @override
  String feedbackSentTo(String name) {
    return 'Feedback sent to $name';
  }

  @override
  String get couldNotSendFeedback => 'Couldn\'t send the feedback.';

  @override
  String pointsCount(int count) {
    return '$count points';
  }

  @override
  String get passedFirstTry => 'Passed first try';

  @override
  String get attempts => 'Attempts';

  @override
  String tookDuration(String duration) {
    return 'took $duration';
  }

  @override
  String get answered => 'Answered';

  @override
  String get reasoningLabel => 'REASONING';

  @override
  String get giveFeedback => 'Give feedback';

  @override
  String get trainer => 'Trainer';

  @override
  String feedbackFor(String name) {
    return 'Feedback for $name';
  }

  @override
  String get feedbackHint =>
      'What did they get right, and what should they reconsider?';

  @override
  String get sendFeedback => 'Send feedback';

  @override
  String get filterNeedsAttention => 'Needs attention';

  @override
  String get filterNeverTrained => 'Never trained';

  @override
  String get filterCleared => 'Cleared';

  @override
  String get workerSafetyStanding => 'Worker safety standing';

  @override
  String get workerSafetyStandingSubtitle =>
      'Review training results and decide next steps';

  @override
  String get reviewersOnly => 'Reviewers only';

  @override
  String get reviewersOnlyHint =>
      'Only Main Admin and System Admin accounts can review worker standing.';

  @override
  String get couldNotLoadWorkers => 'Couldn\'t load workers';

  @override
  String get buildingStats =>
      'Building training statistics from past attempts…';

  @override
  String get couldNotBuildStats =>
      'Couldn\'t build training statistics from past attempts — some workers may show no results.';

  @override
  String get couldNotLoadDeterminations =>
      'Couldn\'t load past decisions — the statuses below may be incomplete.';

  @override
  String get workers => 'Workers';

  @override
  String get needAttention => 'Need attention';

  @override
  String get searchWorkers => 'Search workers';

  @override
  String get noWorkersYet => 'No workers yet';

  @override
  String get noWorkersHint =>
      'Technicians and anyone who has trained will appear here.';

  @override
  String get noWorkersMatch => 'No workers match';

  @override
  String determinationRecorded(String name) {
    return 'Decision recorded — $name has been notified';
  }

  @override
  String get couldNotRecordDetermination => 'Couldn\'t record the decision.';

  @override
  String get unknownWorker => 'Unknown worker';

  @override
  String workerScoreLine(int points, int correct, int attempted) {
    return '$points pts · $correct/$attempted first try';
  }

  @override
  String get scenariosCompleted => 'Scenarios completed';

  @override
  String get neverCompletedScenario => 'Has never completed a scenario';

  @override
  String newAttemptsSinceReview(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new attempts since last review',
      one: '1 new attempt since last review',
    );
    return '$_temp0';
  }

  @override
  String get reviewedByAnother => 'Reviewed by another reviewer';

  @override
  String get review => 'Review';

  @override
  String reviewName(String name) {
    return 'Review $name';
  }

  @override
  String reviewSummaryLine(
    int correct,
    int attempted,
    int percent,
    int points,
  ) {
    return '$correct/$attempted correct first try · $percent% · $points pts';
  }

  @override
  String get noScenarioCompletedYet => 'Has not completed any scenario yet';

  @override
  String get nextStep => 'NEXT STEP';

  @override
  String get fitToWork90 => 'Fit to work for 90 days';

  @override
  String get assignScenariosToRedo => 'Assign scenarios to redo';

  @override
  String get handToSeniorAdmin => 'Hand to a senior admin';

  @override
  String clearanceValidUntil(String date) {
    return 'Clearance will be valid until $date.';
  }

  @override
  String get clearingWithoutTraining =>
      'This worker hasn\'t completed any scenario — clearing them isn\'t backed by any training results.';

  @override
  String get notesOptionalShown => 'Notes (optional — shown to the worker)';

  @override
  String get chooseNextStep => 'Choose a next step';

  @override
  String get saveDetermination => 'Save decision';

  @override
  String get scenariosToRetrain => 'Scenarios to retrain on';

  @override
  String dueDate(String date) {
    return 'Due $date';
  }

  @override
  String get noActiveScenarios => 'There are no active scenarios to assign.';

  @override
  String get neverAttempted => 'Never attempted';

  @override
  String get passed => 'Passed';

  @override
  String get missed => 'Missed';

  @override
  String get couldNotLoadReviewers => 'Couldn\'t load reviewers';

  @override
  String get noOtherReviewer =>
      'There\'s no other Main Admin or System Admin to escalate to.';

  @override
  String get escalateTo => 'Escalate to';

  @override
  String get visibleToWorkers => 'Visible to workers';

  @override
  String get hidden => 'Hidden';

  @override
  String get needsFixing => 'Needs fixing';

  @override
  String scenarioNowVisible(String title) {
    return '\"$title\" is now visible to workers';
  }

  @override
  String scenarioNowHidden(String title) {
    return '\"$title\" is hidden from workers';
  }

  @override
  String couldNotUpdateScenario(String title) {
    return '\"$title\" couldn\'t be updated. Open it with Edit and save it to repair it.';
  }

  @override
  String get manageScenarios => 'Manage scenarios';

  @override
  String get manageScenariosSubtitle =>
      'Edit, publish or hide safety scenarios';

  @override
  String get authorScenario => 'Author scenario';

  @override
  String get scenarios => 'Scenarios';

  @override
  String get visible => 'Visible';

  @override
  String get hiddenSingular => 'Hidden';

  @override
  String get noScenariosAuthorHint =>
      'Tap \"Author scenario\" to create the first one.';

  @override
  String get incomplete => 'Incomplete';

  @override
  String updatedOn(String date) {
    return 'Updated $date';
  }

  @override
  String get editScenario => 'Edit scenario';

  @override
  String get defaultReasoningPrompt =>
      'Explain why this could lead to injury and how to prevent it.';

  @override
  String get visualFallingObject => 'Falling object';

  @override
  String get visualMissingPpe => 'Missing PPE';

  @override
  String get visualExposedWiring => 'Exposed wiring';

  @override
  String get visualUnguardedEdge => 'Unguarded edge';

  @override
  String get visualWetFloor => 'Wet floor / slip';

  @override
  String get visualUnsecuredLadder => 'Unsecured ladder';

  @override
  String get visualGeneric => 'Generic hazard';

  @override
  String get couldNotLoadAnswerKey =>
      'This scenario\'s answer key couldn\'t be loaded.';

  @override
  String get unsupportedPhotoType =>
      'This photo type isn\'t supported — please use a JPEG, PNG, WebP or GIF image.';

  @override
  String photoTooLarge(String limit) {
    return 'This photo is too large — the limit is $limit.';
  }

  @override
  String get lottieWebUnsafeTitle =>
      'This animation won\'t play in web browsers';

  @override
  String get lottieWebUnsafeBody =>
      'This file uses a shape effect that web browsers can\'t display. It plays fine on Android and iOS, but anyone opening this scenario in a browser will see the standard illustration instead.';

  @override
  String get pickAnotherFile => 'Pick another file';

  @override
  String get useItAnyway => 'Use it anyway';

  @override
  String animationTooLarge(String limit) {
    return 'This animation is too large — the limit is $limit.';
  }

  @override
  String get selectAnimationImages => 'Select this animation\'s images';

  @override
  String selectAnimationImagesBody(int count, Object names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'This animation uses $count separate image files ($names) that aren\'t inside the .json. Select them — usually in the \"images\" folder exported next to it — to add them to the animation.',
      one:
          'This animation uses a separate image file ($names) that isn\'t inside the .json. Select it — usually in the \"images\" folder exported next to it — to add it to the animation.',
    );
    return '$_temp0';
  }

  @override
  String get selectImages => 'Select images';

  @override
  String missingImagesNotAdded(String names) {
    return 'Missing image(s): $names — the animation was not added.';
  }

  @override
  String get couldNotEmbedImages =>
      'The images couldn\'t be added to this animation.';

  @override
  String get addTwoOptions => 'Please add at least two answer options.';

  @override
  String get correctOptionEmpty =>
      'The option marked correct is empty — fill it in or mark a different option.';

  @override
  String get onlyAdminsSaveScenarios => 'Only admins can save scenarios.';

  @override
  String get couldNotSaveScenario => 'Couldn\'t save the scenario.';

  @override
  String get sceneMedia => 'Scene media';

  @override
  String get sceneMediaHint =>
      'Optional — a built-in animated illustration is used otherwise';

  @override
  String get riveFile => 'Rive (.riv)';

  @override
  String get lottieFile => 'Lottie (.json)';

  @override
  String get realPhoto => 'Real photo';

  @override
  String get photoSelected => 'Photo selected';

  @override
  String get fallbackIllustration => 'Fallback illustration';

  @override
  String get scenarioDetails => 'Scenario details';

  @override
  String get scenarioTitleField => 'Scenario title *';

  @override
  String get categoryField =>
      'Category (e.g. Falling objects, PPE, Electrical)';

  @override
  String get sceneDescriptionField =>
      'Scene description — what the worker sees *';

  @override
  String get questionAndAnswers => 'Question & answers';

  @override
  String get markCorrectHint => 'Mark the correct answer with the round button';

  @override
  String get questionField => 'Question (e.g. \"What is the hazard here?\") *';

  @override
  String optionRequired(int n) {
    return 'Option $n *';
  }

  @override
  String optionOptional(int n) {
    return 'Option $n (optional)';
  }

  @override
  String get correct => 'Correct';

  @override
  String get feedbackAndScoring => 'Feedback & scoring';

  @override
  String get explanationField => 'Explanation shown after answering *';

  @override
  String get reasoningPromptField => 'Free-text reasoning prompt *';

  @override
  String get difficulty => 'Difficulty';

  @override
  String pointsRange(int max) {
    return 'Points (1–$max)';
  }

  @override
  String get loadingAnswerKey => 'Loading this scenario\'s answer key…';

  @override
  String savingDisabledAnswerKey(String error) {
    return '$error Saving is turned off so the current answer isn\'t overwritten.';
  }

  @override
  String get noAnswerKeyYet =>
      'This scenario has no answer key yet. Mark the correct option and add an explanation, then save.';

  @override
  String get requiredFieldsNote => 'Fields marked * are required';

  @override
  String get saving => 'Saving…';

  @override
  String get publishScenario => 'Publish scenario';

  @override
  String get lottiePreviewUnavailableWeb =>
      'Preview unavailable in the browser for this animation — it will play on Android and iOS.';

  @override
  String get lottiePreviewFailed =>
      'This file can\'t be previewed — is it a valid Lottie animation?';

  @override
  String riveSelected(String name) {
    return '$name selected';
  }

  @override
  String get riveFileDefault => 'Rive file';

  @override
  String get previewAfterSaving => 'Preview available after saving';

  @override
  String get invItemNoLongerExists =>
      'This item no longer exists — it may have been removed.';

  @override
  String get invItemNotAvailable =>
      'This item isn\'t available right now — someone may have just checked it out or booked it.';

  @override
  String get invItemHasPendingRequest =>
      'This item already has a request waiting for a decision.';

  @override
  String get invItemNotCheckedOut =>
      'This item isn\'t checked out at the moment.';

  @override
  String get invRequestNoLongerExists => 'This request no longer exists.';

  @override
  String get invRequestAlreadyHandled =>
      'This request was already handled by someone else.';

  @override
  String get invItemChangedRefresh =>
      'This item\'s record changed while you were working. Please refresh and try again.';

  @override
  String get invBookingNoLongerExists => 'This booking no longer exists.';

  @override
  String get invOnlyBookedPersonCanAcknowledge =>
      'Only the person this item is booked for can confirm it arrived.';

  @override
  String get invNotDriverDelivery =>
      'This item isn\'t being delivered by a driver, so there\'s nothing to confirm.';

  @override
  String get invBookingNotScheduled =>
      'This booking is no longer waiting to be collected.';

  @override
  String get invBookingNotActive => 'This booking is no longer active.';

  @override
  String get invCannotRecordOwnReturn =>
      'You can\'t record your own return — please ask another Main Admin or System Admin to do it.';

  @override
  String get invOnlyScheduledCanBeCancelled =>
      'Only a booking that hasn\'t been collected yet can be cancelled.';

  @override
  String invOverlapsMaintenance(String start, String end) {
    return 'These dates overlap planned maintenance ($start – $end). Please choose different dates.';
  }

  @override
  String invOverlapsBooking(
    String asset,
    String who,
    String start,
    String end,
  ) {
    return 'These dates overlap an existing booking of \"$asset\" ($who, $start – $end). Please choose different dates.';
  }

  @override
  String get invCannotProcessForSelf =>
      'You can\'t do this for yourself — please ask another Main Admin or System Admin to handle it.';

  @override
  String invCancelledForMaintenance(String reason) {
    return 'Cancelled for planned maintenance ($reason).';
  }

  @override
  String get invMaterialNoLongerExists =>
      'This material no longer exists — it may have been removed.';

  @override
  String invNotEnoughStock(String requested, String available) {
    return 'There isn\'t enough in storage: you asked for $requested, but only $available is left.';
  }

  @override
  String get invNoPermissionIssueFabrication =>
      'You don\'t have permission to issue material for fabrication.';

  @override
  String get invNoPermissionSubmitScan =>
      'You don\'t have permission to upload a fabrication form.';

  @override
  String get invNoPermissionReviewFabrication =>
      'You don\'t have permission to review this fabrication order.';

  @override
  String get invNoPermissionVerifyFabrication =>
      'You don\'t have permission to verify this fabrication order.';

  @override
  String get invFabricationOrderNoLongerExists =>
      'This fabrication order no longer exists.';

  @override
  String get invOrderNotAwaitingReview =>
      'This order isn\'t waiting for an admin review.';

  @override
  String get invOrderNotReadyForVerification =>
      'This order isn\'t ready to be verified yet.';

  @override
  String invIssuedForFabricationNote(String id) {
    return 'Issued for fabrication — Form ID $id';
  }

  @override
  String invFabricatorNote(String name) {
    return ' — Fabricator: $name';
  }

  @override
  String invReceivedFromFabricationNote(String id) {
    return 'Received back from fabrication — Form ID $id';
  }

  @override
  String get invQuantitiesFlaggedNote => ' — quantities flagged for review';

  @override
  String get nInvCheckoutRequestTitle => '📦 Checkout request';

  @override
  String nInvCheckoutRequestBody(
    String who,
    String asset,
    String start,
    String end,
  ) {
    return '$who asked for \"$asset\" from $start to $end.';
  }

  @override
  String nInvCheckoutRequestBodyProject(
    String who,
    String asset,
    String start,
    String end,
    String project,
  ) {
    return '$who asked for \"$asset\" from $start to $end for $project.';
  }

  @override
  String get nInvRequestRejectedTitle => '❌ Checkout request rejected';

  @override
  String nInvRequestRejectedAdminBody(String admin, String who, String asset) {
    return '$admin rejected $who\'s request for \"$asset\".';
  }

  @override
  String nInvRequestRejectedAdminBodyReason(
    String admin,
    String who,
    String asset,
    String reason,
  ) {
    return '$admin rejected $who\'s request for \"$asset\": $reason';
  }

  @override
  String nInvRequestRejectedUserBody(String asset) {
    return 'Your request for \"$asset\" was rejected.';
  }

  @override
  String nInvRequestRejectedUserBodyReason(String asset, String reason) {
    return 'Your request for \"$asset\" was rejected: $reason';
  }

  @override
  String get nInvCheckoutApprovedTitle => '✅ Checkout approved';

  @override
  String nInvCheckoutApprovedAdminBody(String admin, String who, String asset) {
    return '$admin approved $who\'s request for \"$asset\".';
  }

  @override
  String nInvCheckoutApprovedNowBody(String asset, String admin) {
    return 'Your request for \"$asset\" was approved by $admin — it\'s checked out to you now.';
  }

  @override
  String nInvCheckoutApprovedLaterBody(
    String asset,
    String admin,
    String date,
  ) {
    return 'Your request for \"$asset\" was approved by $admin — booked for $date.';
  }

  @override
  String nInvOnTheWayTitle(String asset) {
    return '🚚 \"$asset\" is on the way';
  }

  @override
  String nInvOnTheWayBodyDriver(String driver, String asset) {
    return '$driver is bringing \"$asset\" to you — tap Acknowledge Receipt once it arrives.';
  }

  @override
  String nInvOnTheWayBody(String asset) {
    return 'A driver is bringing \"$asset\" to you — tap Acknowledge Receipt once it arrives.';
  }

  @override
  String nInvBookedTitle(String asset) {
    return '📅 \"$asset\" has been booked';
  }

  @override
  String nInvBookedBody(String who, String asset, String date) {
    return '$who has booked \"$asset\" starting $date. Please plan to return it in time.';
  }

  @override
  String get nInvDeliveryAckTitle => '📬 Delivery confirmed';

  @override
  String nInvDeliveryAckBody(String who, String asset) {
    return '$who confirmed receiving \"$asset\".';
  }

  @override
  String get nInvBookingCancelledMaintTitle =>
      '🛠️ Booking cancelled — maintenance';

  @override
  String nInvBookingCancelledMaintBody(
    String asset,
    String start,
    String end,
    String reason,
  ) {
    return 'Your booked \"$asset\" won\'t be available $start – $end because of planned maintenance ($reason).';
  }

  @override
  String get nInvReturnForMaintTitle => '🛠️ Return needed for maintenance';

  @override
  String nInvReturnForMaintBody(String asset, String date, String reason) {
    return 'Please return \"$asset\" by $date — it\'s scheduled for maintenance ($reason).';
  }

  @override
  String get nInvReturnIncomingTitle => '📥 Return on the way';

  @override
  String nInvReturnIncomingBody(String who, String asset) {
    return '$who is returning \"$asset\" — please record when it arrives.';
  }

  @override
  String get nInvFabDiscrepancyTitle =>
      '⚠️ Fabrication form: quantities don\'t match';

  @override
  String get nInvFabReadyTitle => '📄 Fabrication form ready to verify';

  @override
  String nInvFabUploadedDiscrepancyBody(String who, String material) {
    return '$who uploaded the completed form for \"$material\" — the quantities don\'t match, please review.';
  }

  @override
  String nInvFabUploadedReadyBody(String who, String material) {
    return '$who uploaded the completed form for \"$material\" — ready to verify.';
  }

  @override
  String get nInvFabAwaitingReviewTitle =>
      '📄 Fabrication form waiting for review';

  @override
  String nInvFabAwaitingReviewBody(String who, String material) {
    return '$who uploaded the completed form for \"$material\" — it needs an admin review.';
  }

  @override
  String nInvFabReviewedBody(String who, String material) {
    return '$who reviewed the form for \"$material\" — ready to verify.';
  }

  @override
  String get invStatusAvailable => 'Available';

  @override
  String get invStatusCheckedOut => 'Checked out';

  @override
  String get invStatusUnderMaintenance => 'Under maintenance';

  @override
  String get invStatusRetired => 'Retired';

  @override
  String get invConditionNew => 'New';

  @override
  String get invConditionGood => 'Good';

  @override
  String get invConditionFair => 'Fair';

  @override
  String get invConditionDamaged => 'Damaged';

  @override
  String get invConditionPartiallyDamaged => 'Partially damaged';

  @override
  String get invTypeAsset => 'Asset';

  @override
  String get invTypeTool => 'Tool';

  @override
  String get invSourceLocal => 'Local';

  @override
  String get invSourceInternational => 'International';

  @override
  String get invCatHeavyEquipment => 'Heavy equipment';

  @override
  String get invCatVehicle => 'Vehicle';

  @override
  String get invCatItEquipment => 'IT equipment / electronics';

  @override
  String get invCatOfficeEquipment => 'Office equipment';

  @override
  String get invCatFurniture => 'Furniture';

  @override
  String get invCatSafetyEquipment => 'Safety equipment';

  @override
  String get invCatPowerTool => 'Power tool';

  @override
  String get invCatHandTool => 'Hand tool';

  @override
  String get invCatMeasuringTool => 'Measuring tool';

  @override
  String get invCatSafetyTool => 'Safety tool';

  @override
  String get invCatCement => 'Cement & aggregates';

  @override
  String get invCatSteel => 'Steel & metal';

  @override
  String get invCatElectrical => 'Electrical';

  @override
  String get invCatPlumbing => 'Plumbing';

  @override
  String get invCatTimber => 'Timber';

  @override
  String get invCatFinishes => 'Finishes';

  @override
  String get invCatOther => 'Other';

  @override
  String get invBookingScheduled => 'Scheduled';

  @override
  String get invBookingActive => 'Active';

  @override
  String get invBookingCompleted => 'Completed';

  @override
  String get invBookingCancelled => 'Cancelled';

  @override
  String get invRequestPending => 'Pending';

  @override
  String get invRequestApproved => 'Approved';

  @override
  String get invRequestRejected => 'Rejected';

  @override
  String get invFabIssued => 'Issued';

  @override
  String get invFabPendingAdminReview => 'Waiting for admin review';

  @override
  String get invFabScanUploaded => 'Ready to verify';

  @override
  String get invFabVerified => 'Verified';

  @override
  String get invFabDiscrepancy => 'Quantities don\'t match';

  @override
  String get invMovementReceived => 'Received';

  @override
  String get invDeliveryDirect => 'Collected in person';

  @override
  String get invDeliveryDriver => 'Delivered by driver';

  @override
  String get tomorrow => 'Tomorrow';

  @override
  String inDays(int count) {
    return 'In $count days';
  }

  @override
  String daysAgoLong(int count) {
    return '$count days ago';
  }

  @override
  String get noUpcomingBookings =>
      'No upcoming bookings or maintenance — free for the foreseeable future.';

  @override
  String maintenanceReason(String reason) {
    return 'Maintenance: $reason';
  }

  @override
  String checkedOutTo(String name) {
    return 'Checked out to $name';
  }

  @override
  String bookedFor(String name) {
    return 'Booked for $name';
  }

  @override
  String get cancelMaintenance => 'Cancel maintenance';

  @override
  String get cancelBooking => 'Cancel booking';

  @override
  String get noInventoryAccess => 'You don\'t have access to Inventory.';

  @override
  String get tabAssets => 'Assets';

  @override
  String get tabTools => 'Tools';

  @override
  String get tabMaterials => 'Materials';

  @override
  String get noAssetsYet => 'No assets yet';

  @override
  String get noAssetsHint => 'Assets you register will show up here.';

  @override
  String get noToolsYet => 'No tools yet';

  @override
  String get noToolsHint => 'Tools you register will show up here.';

  @override
  String get addAsset => 'Add asset';

  @override
  String get addTool => 'Add tool';

  @override
  String get addMaterial => 'Add material';

  @override
  String get fabricationOrders => 'Fabrication orders';

  @override
  String get pendingRequests => 'Pending requests';

  @override
  String get accessStillSyncing => 'Your access is still being set up';

  @override
  String get couldNotLoadItems => 'Couldn\'t load this list';

  @override
  String get accessStillSyncingHint =>
      'This usually sorts itself out in a moment. Tap Try again.';

  @override
  String get searchAssets => 'Search assets…';

  @override
  String get searchTools => 'Search tools…';

  @override
  String get status => 'Status';

  @override
  String get category => 'Category';

  @override
  String get requestPendingStatus => 'Request pending';

  @override
  String get booked => 'Booked';

  @override
  String heldBy(String category, String name) {
    return '$category • Held by $name';
  }

  @override
  String availableOfTotal(int available, int total) {
    return '$available of $total available';
  }

  @override
  String get inStock => 'In stock';

  @override
  String get lowStock => 'Low stock';

  @override
  String get outOfStock => 'Out of stock';

  @override
  String get noMaterialsYet => 'No materials yet';

  @override
  String get noMaterialsHint => 'Materials you register will show up here.';

  @override
  String get searchMaterials => 'Search materials…';

  @override
  String get source => 'Source';

  @override
  String get stock => 'Stock';

  @override
  String get assetDetails => 'Item details';

  @override
  String get scheduleMaintenance => 'Schedule maintenance';

  @override
  String get couldNotLoadAsset => 'This item couldn\'t be loaded.';

  @override
  String get couldNotLoadBookings => 'The bookings couldn\'t be loaded.';

  @override
  String get availability => 'Availability';

  @override
  String get custodyHistory => 'Custody history';

  @override
  String get couldNotLoadHistoryShort => 'The history couldn\'t be loaded.';

  @override
  String get noCustodyEvents => 'No handovers recorded yet';

  @override
  String serialNumber(String serial) {
    return 'S/N: $serial';
  }

  @override
  String conditionAtIntake(String condition) {
    return 'Condition when registered: $condition';
  }

  @override
  String get inMyPossession => 'With me';

  @override
  String heldByName(String name) {
    return 'Held by $name';
  }

  @override
  String get requestAwaitingReview =>
      'A checkout request for this item is waiting for review.';

  @override
  String get couldNotLoadRequest => 'The request couldn\'t be loaded.';

  @override
  String get ownRequestAwaitingReview =>
      'Your request is waiting for review by another Main Admin or System Admin.';

  @override
  String reviewRequestFrom(String name) {
    return 'Review request from $name';
  }

  @override
  String recordCollectionFor(String name) {
    return 'Record collection — $name';
  }

  @override
  String get requestCheckout => 'Request checkout';

  @override
  String driverBringingToYou(String driver) {
    return '$driver is bringing this to you.';
  }

  @override
  String get aDriver => 'A driver';

  @override
  String get acknowledgeReceipt => 'Confirm receipt';

  @override
  String get requestFutureDate => 'Request a future date';

  @override
  String get returnNotified =>
      'Return notified — waiting for a Main Admin or System Admin to confirm it arrived.';

  @override
  String get toolReturn => 'Return tool';

  @override
  String get assetReturn => 'Return asset';

  @override
  String get recordReturn => 'Record return';

  @override
  String get overrideRecordReturn => 'Override & record return';

  @override
  String acknowledgeReceiptBody(String asset) {
    return 'Confirm that \"$asset\" has physically arrived with you. If you have the signed handover form, you can attach a photo of it too.';
  }

  @override
  String get attachFormPhoto => 'Attach form photo';

  @override
  String get confirmReceipt => 'Confirm receipt';

  @override
  String get receiptAcknowledged => 'Receipt confirmed.';

  @override
  String get couldNotConfirmReceipt => 'Couldn\'t confirm the receipt.';

  @override
  String get returnAssetTitle => 'Return item';

  @override
  String returnAssetMessage(String asset) {
    return 'Let a Main Admin or System Admin know you\'re returning \"$asset\"? They\'ll confirm it arrived and record its condition.';
  }

  @override
  String get notify => 'Notify';

  @override
  String get returnNotifiedSnack =>
      'An admin has been notified — they\'ll confirm the item arrived.';

  @override
  String get couldNotNotifyReturn => 'Couldn\'t send the return notice.';

  @override
  String get overrideReturnTitle => 'Override return';

  @override
  String overrideReturnMessage(String holder, String asset) {
    return '$holder hasn\'t said they\'re returning \"$asset\" yet. Only continue if they can\'t be reached and you\'ve confirmed the item is physically back.';
  }

  @override
  String get theCurrentHolder => 'The current holder';

  @override
  String get overrideContinue => 'Override & continue';

  @override
  String cancelBookingMessage(String name) {
    return 'Cancel the booking for $name?';
  }

  @override
  String get keep => 'Keep';

  @override
  String get couldNotCancelBooking => 'Couldn\'t cancel the booking.';

  @override
  String cancelMaintenanceMessage(String reason) {
    return 'Cancel this maintenance window ($reason)?';
  }

  @override
  String get cancelWindow => 'Cancel maintenance';

  @override
  String get couldNotCancelMaintenance => 'Couldn\'t cancel the maintenance.';

  @override
  String get checkedOutEvent => 'Checked out';

  @override
  String get returnedEvent => 'Returned';

  @override
  String conditionLabel(String condition) {
    return 'Condition: $condition';
  }

  @override
  String recordedBy(String name, String role) {
    return 'Recorded by $name ($role)';
  }

  @override
  String get camera => 'Camera';

  @override
  String get gallery => 'Gallery';

  @override
  String get editTool => 'Edit tool';

  @override
  String get editAsset => 'Edit asset';

  @override
  String confirmSaveAndAddUnits(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more units',
      one: '1 more unit',
    );
    return 'Save changes and register $_temp0 of \"$name\"? Each new unit gets its own handover history.';
  }

  @override
  String confirmSaveChangesTo(String name) {
    return 'Save changes to \"$name\"?';
  }

  @override
  String confirmRegisterToolUnits(int count, String name, String category) {
    return 'Register $count units of \"$name\" ($category) as new company tools? Each unit is tracked separately, with its own handover history.';
  }

  @override
  String confirmRegisterAssetUnits(int count, String name, String category) {
    return 'Register $count units of \"$name\" ($category) as new company assets? Each unit is tracked separately, with its own handover history.';
  }

  @override
  String confirmRegisterTool(String name, String category) {
    return 'Register \"$name\" ($category) as a new company tool?';
  }

  @override
  String confirmRegisterAsset(String name, String category) {
    return 'Register \"$name\" ($category) as a new company asset?';
  }

  @override
  String changesSavedUnitsAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more units',
      one: '1 more unit',
    );
    return 'Changes saved, $_temp0 added.';
  }

  @override
  String get changesSaved => 'Changes saved.';

  @override
  String unitsAdded(int count) {
    return '$count units added.';
  }

  @override
  String get toolAdded => 'Tool added.';

  @override
  String get assetAdded => 'Asset added.';

  @override
  String get couldNotSaveItem => 'Couldn\'t save this item.';

  @override
  String get photo => 'Photo';

  @override
  String get tapToAddPhoto => 'Tap to add a photo (optional)';

  @override
  String get details => 'Details';

  @override
  String get toolName => 'Tool name';

  @override
  String get assetName => 'Asset name';

  @override
  String get nameRequired => 'Please enter a name';

  @override
  String get quantity => 'Quantity';

  @override
  String get quantityUnitsHint => 'Number of identical units to register';

  @override
  String get wholeNumberOneOrMore => 'Enter a whole number of 1 or more';

  @override
  String get addMoreUnitsOptional => 'Add more units (optional)';

  @override
  String get addMoreUnitsHint => 'e.g. 2 more of this tool just arrived';

  @override
  String get zeroOrMore => 'Enter 0 or more';

  @override
  String get serialNumberOptional => 'Serial number (optional)';

  @override
  String get descriptionOptional => 'Description (optional)';

  @override
  String get conditionAtIntakeNewUnits =>
      'Condition when registered (for new units)';

  @override
  String get conditionAtIntakeLabel => 'Condition when registered';

  @override
  String get classification => 'Classification';

  @override
  String get toolCategoryHint => 'e.g. Power tool, IT equipment / electronics';

  @override
  String get assetCategoryHint => 'e.g. Heavy equipment, Vehicle';

  @override
  String get categoryRequired => 'Please enter a category';

  @override
  String get unitBags => 'bags';

  @override
  String get unitPieces => 'pieces';

  @override
  String get unitTonnes => 'tonnes';

  @override
  String get unitLitres => 'litres';

  @override
  String get unitRolls => 'rolls';

  @override
  String get editMaterial => 'Edit material';

  @override
  String confirmRegisterMaterial(String name, String category) {
    return 'Register \"$name\" ($category) as a new material in the stock register?';
  }

  @override
  String get materialAdded => 'Material added.';

  @override
  String get couldNotSaveMaterial => 'Couldn\'t save this material.';

  @override
  String get materialName => 'Material name';

  @override
  String get materialCategoryHint => 'e.g. Cement & aggregates, Steel & metal';

  @override
  String get unit => 'Unit';

  @override
  String get initialQuantity => 'Starting quantity';

  @override
  String get reorderLevel => 'Reorder level';

  @override
  String get reorderLevelHint => 'Low-stock warning level';

  @override
  String quantityEditNote(String quantity, String unit) {
    return 'The quantity in storage ($quantity $unit) can only change by recording a receipt or issue — not by editing.';
  }

  @override
  String get couldNotLoadUsers => 'The list of people couldn\'t be loaded.';

  @override
  String get couldNotLoadProjects =>
      'The list of projects couldn\'t be loaded.';

  @override
  String get selectWhoBookingFor => 'Please choose who this booking is for.';

  @override
  String get checkOutNow => 'Check out now';

  @override
  String get bookTool => 'Book tool';

  @override
  String get bookAsset => 'Book asset';

  @override
  String confirmCheckOutNow(String asset, String who) {
    return 'Check out \"$asset\" to $who now?';
  }

  @override
  String confirmCheckOutNowProject(String asset, String who, String project) {
    return 'Check out \"$asset\" to $who now for project $project?';
  }

  @override
  String confirmBookFor(String asset, String who, String start, String end) {
    return 'Book \"$asset\" for $who from $start to $end?';
  }

  @override
  String get toolCheckedOut => 'Tool checked out.';

  @override
  String get assetCheckedOut => 'Asset checked out.';

  @override
  String get bookingCreated => 'Booking created.';

  @override
  String get couldNotCreateBooking => 'Couldn\'t create the booking.';

  @override
  String get handoverForm => 'Handover form';

  @override
  String handoverFormBody(String who) {
    return 'Download the printable handover form for the driver to sign at pickup, and for $who to sign on receipt.';
  }

  @override
  String get skip => 'Skip';

  @override
  String get downloadForm => 'Download form';

  @override
  String get bookingWindow => 'Booking dates';

  @override
  String get startsTodayHint =>
      'Starts today — the item is handed over right away';

  @override
  String get futureWindowHint =>
      'Future dates — the item stays available until it is collected on the day';

  @override
  String fromDate(String date) {
    return 'From $date';
  }

  @override
  String toDate(String date) {
    return 'To $date';
  }

  @override
  String get handover => 'Handover';

  @override
  String get deliveryMethod => 'Delivery method';

  @override
  String get directHandoff => 'Direct handoff';

  @override
  String get viaDriver => 'Via driver/transporter';

  @override
  String get driverName => 'Driver / transporter name';

  @override
  String get driverNameHint => 'e.g. James, company driver';

  @override
  String get recipientMustAcknowledge =>
      'The recipient will need to tap \"Confirm receipt\" once it arrives on site.';

  @override
  String get conditionAndPhotos => 'Condition & photos';

  @override
  String get capturedAtCollection =>
      'Recorded when the item is actually collected';

  @override
  String get conditionNotes => 'Condition notes';

  @override
  String get conditionAtHandover => 'Condition at handover';

  @override
  String get addPhotos => 'Add photos';

  @override
  String get checkOut => 'Check out';

  @override
  String get bookFor => 'Book for';

  @override
  String get bookForMyself => 'Book for myself';

  @override
  String get projectOptionalStorage =>
      'Project (optional — leave blank for company storage)';

  @override
  String overlapsBookingFor(String who, String start, String end) {
    return 'These dates overlap a booking for $who ($start – $end).';
  }

  @override
  String overlapsMaintenanceShort(String start, String end) {
    return 'These dates overlap planned maintenance ($start – $end).';
  }

  @override
  String confirmSendCheckoutRequest(String asset, String start, String end) {
    return 'Send a checkout request for \"$asset\" ($start – $end) to a Main Admin or System Admin for approval?';
  }

  @override
  String get sendRequest => 'Send request';

  @override
  String get requestSentWaiting =>
      'Request sent — waiting for a Main Admin or System Admin to approve it.';

  @override
  String get couldNotSendRequest => 'Couldn\'t send the request.';

  @override
  String get noPermissionRequestCheckout =>
      'You don\'t have permission to request a checkout.';

  @override
  String get bookingWindowHint => 'When you need it and when you\'ll return it';

  @override
  String get alreadyOnCalendar => 'Already on the calendar';

  @override
  String get requestDetails => 'Request details';

  @override
  String get reasonForCheckout => 'Reason for checkout';

  @override
  String get reasonForCheckoutHint => 'e.g. Needed for site work at …';

  @override
  String get reasonRequired => 'Please enter a reason';

  @override
  String get projectOptional => 'Project (optional)';

  @override
  String get approveAndCheckOut => 'Approve & check out';

  @override
  String confirmApproveRequest(String who, String asset) {
    return 'Approve $who\'s request for \"$asset\"? This checks the item out to them straight away.';
  }

  @override
  String get approvedCheckedOut => 'Approved — the item is checked out.';

  @override
  String get couldNotApprove => 'Couldn\'t approve the request.';

  @override
  String get rejectRequest => 'Reject request';

  @override
  String get reasonOptional => 'Reason (optional)';

  @override
  String get requestRejected => 'Request rejected.';

  @override
  String get couldNotReject => 'Couldn\'t reject the request.';

  @override
  String get reviewRequest => 'Review request';

  @override
  String get requestedBy => 'Requested by';

  @override
  String get project => 'Project';

  @override
  String get reason => 'Reason';

  @override
  String get approveConditionAtHandover => 'Approve — condition at handover';

  @override
  String approveChecksOutNote(String who) {
    return 'Filling this in and tapping Approve checks the item out to $who straight away.';
  }

  @override
  String get delivery => 'Delivery';

  @override
  String get driverNameShort => 'Driver name';

  @override
  String get recordCollection => 'Record collection';

  @override
  String get storage => 'storage';

  @override
  String confirmHandoverNow(String asset, String who) {
    return 'Confirm that \"$asset\" is being handed over to $who now?';
  }

  @override
  String confirmRecordReturnFrom(String asset, String who) {
    return 'Record the return of \"$asset\" from $who?';
  }

  @override
  String get collectionRecorded => 'Collection recorded.';

  @override
  String get returnRecorded => 'Return recorded.';

  @override
  String get couldNotRecord => 'Couldn\'t save this record.';

  @override
  String get noPermissionRecord => 'You don\'t have permission to record this.';

  @override
  String get returnTitle => 'Return';

  @override
  String get handingOverTo => 'Handing over to';

  @override
  String get returningFrom => 'Returning from';

  @override
  String get conditionRating => 'Condition';

  @override
  String get conditionAtReturn => 'Condition at return';

  @override
  String get confirmCollection => 'Confirm collection';

  @override
  String get enterValidQuantity => 'Please enter a valid quantity.';

  @override
  String onlyRemainingInStorage(String quantity, String unit) {
    return 'Only $quantity $unit left in storage.';
  }

  @override
  String get recordReceipt => 'Record receipt';

  @override
  String get recordIssue => 'Record issue';

  @override
  String confirmRecordReceipt(String quantity, String unit, String material) {
    return 'Record receipt of $quantity $unit of \"$material\" into storage?';
  }

  @override
  String confirmIssue(String quantity, String unit, String material) {
    return 'Issue $quantity $unit of \"$material\"?';
  }

  @override
  String confirmIssueToProject(
    String quantity,
    String unit,
    String material,
    String project,
  ) {
    return 'Issue $quantity $unit of \"$material\" to project $project?';
  }

  @override
  String get receiptRecorded => 'Receipt recorded.';

  @override
  String get issueRecorded => 'Issue recorded.';

  @override
  String get noPermissionMaterialMovement =>
      'You don\'t have permission to record material movements.';

  @override
  String currentlyInStorage(String quantity, String unit) {
    return '$quantity $unit currently in storage';
  }

  @override
  String get receipt => 'Receipt';

  @override
  String get issue => 'Issue';

  @override
  String quantityWithUnit(String unit) {
    return 'Quantity ($unit)';
  }

  @override
  String get quantityRequired => 'Please enter a quantity';

  @override
  String get conditionOnReceipt => 'Condition on receipt';

  @override
  String get verifiedAtPortBy => 'Checked at the port of arrival by';

  @override
  String get verifiedAtPortHint =>
      'Name of the person who checked this shipment';

  @override
  String get receivedIntoStorageBy => 'Received into storage by';

  @override
  String get receivedIntoStorageHint => 'Name of the person who signed for it';

  @override
  String get notesAndPhotos => 'Notes & photos';

  @override
  String get notes => 'Notes';

  @override
  String get receiptNotesHint => 'Condition / state on receipt';

  @override
  String get issueNotesHint => 'Reason / extra notes';

  @override
  String get destinationProject => 'Destination project';

  @override
  String get materialDetails => 'Material details';

  @override
  String get couldNotLoadMaterial => 'This material couldn\'t be loaded.';

  @override
  String get materialNotFound => 'Material not found.';

  @override
  String get movementHistory => 'Movement history';

  @override
  String get noMovementsYet => 'No movements yet';

  @override
  String inStorageQuantity(String quantity, String unit) {
    return '$quantity $unit in storage';
  }

  @override
  String receivedQuantity(String quantity, String unit) {
    return 'Received: $quantity $unit';
  }

  @override
  String issuedQuantity(String quantity, String unit) {
    return 'Issued: $quantity $unit';
  }

  @override
  String toProject(String project) {
    return 'To project: $project';
  }

  @override
  String verifiedAtPortByName(String name) {
    return 'Checked at port by: $name';
  }

  @override
  String receivedIntoStorageByName(String name) {
    return 'Received into storage by: $name';
  }

  @override
  String get newOrder => 'New order';

  @override
  String get couldNotLoadOrders => 'The orders couldn\'t be loaded.';

  @override
  String noFabricationOrdersFor(String material) {
    return 'No fabrication orders yet for \"$material\"';
  }

  @override
  String get fabStatusWithDriver => 'With driver — on the way to fabrication';

  @override
  String quantityIssued(String quantity, String unit) {
    return '$quantity $unit issued';
  }

  @override
  String formId(String id) {
    return 'Form ID: $id';
  }

  @override
  String issuedByOn(String name, String date) {
    return 'Issued by $name on $date';
  }

  @override
  String destination(String project) {
    return 'Destination: $project';
  }

  @override
  String fabricatorWithCondition(String name, String condition) {
    return 'Fabricator: $name ($condition)';
  }

  @override
  String receivedByQuantity(String name, String quantity, String unit) {
    return 'Received by $name: $quantity $unit';
  }

  @override
  String reviewedBy(String name) {
    return 'Reviewed by $name';
  }

  @override
  String get quantitiesDontReconcile =>
      '⚠ The quantities don\'t fully match — check before verifying';

  @override
  String get tapToUploadScan => 'Tap to upload the completed scanned form';

  @override
  String get markReviewed => 'Mark reviewed';

  @override
  String get verify => 'Verify';

  @override
  String get flagDiscrepancy => 'Flag mismatch';

  @override
  String confirmMarkReviewed(String material) {
    return 'Confirm you\'ve checked the scanned form for \"$material\"? It will then be ready for a System Admin to verify.';
  }

  @override
  String get couldNotMarkReviewed => 'Couldn\'t mark it as reviewed.';

  @override
  String get verifyOrder => 'Verify order';

  @override
  String confirmFlagDiscrepancy(String material) {
    return 'Flag \"$material\" as a quantity mismatch for follow-up?';
  }

  @override
  String confirmVerifyOrder(String material) {
    return 'Confirm \"$material\" is verified and the quantities match?';
  }

  @override
  String get couldNotVerify => 'Couldn\'t verify the order.';

  @override
  String get traceHandedToDriver => 'Handed to the driver (movement recorded)';

  @override
  String get traceReceivedBack =>
      'Received back — form uploaded (movement recorded)';

  @override
  String traceReceivedBackBy(String name) {
    return 'Received back — form uploaded by $name (movement recorded)';
  }

  @override
  String get traceDiscrepancyFlagged => 'Mismatch flagged';

  @override
  String get pendingFabricationSubtitle =>
      'Waiting for a scanned form, or flagged with a mismatch';

  @override
  String get nothingNeedsAttention => 'Nothing needs attention';

  @override
  String get newFabricationOrdersHint =>
      'New fabrication orders will show up here.';

  @override
  String issuedByName(String name) {
    return 'Issued by $name';
  }

  @override
  String get materialNoLongerExists => 'That material no longer exists.';

  @override
  String get pendingRequestsSubtitle =>
      'Waiting for your approval before checkout';

  @override
  String get couldNotLoadRequests => 'The requests couldn\'t be loaded.';

  @override
  String get noPendingRequests => 'No pending requests';

  @override
  String get newCheckoutRequestsHint =>
      'New checkout requests will show up here.';

  @override
  String requestedByName(String name) {
    return 'Requested by $name';
  }

  @override
  String confirmBlockForMaintenance(String asset, String start, String end) {
    return 'Block \"$asset\" from being booked between $start and $end?';
  }

  @override
  String get schedule => 'Schedule';

  @override
  String get maintenanceScheduled => 'Maintenance scheduled.';

  @override
  String get couldNotScheduleMaintenance =>
      'Couldn\'t schedule the maintenance.';

  @override
  String get noPermissionScheduleMaintenance =>
      'You don\'t have permission to schedule maintenance.';

  @override
  String get maintenanceDates => 'Maintenance dates';

  @override
  String get maintenanceReasonHint => 'e.g. Scheduled servicing';

  @override
  String get issueForFabrication => 'Issue for fabrication';

  @override
  String confirmIssueForFabrication(
    String quantity,
    String unit,
    String material,
  ) {
    return 'Issue $quantity $unit of \"$material\" for fabrication?';
  }

  @override
  String get issueAction => 'Issue';

  @override
  String get couldNotIssue => 'Couldn\'t issue the material.';

  @override
  String quantityToIssue(String unit) {
    return 'Quantity to issue ($unit)';
  }

  @override
  String onlyAvailable(String quantity) {
    return 'Only $quantity available';
  }

  @override
  String get destinationSite => 'Destination site';

  @override
  String get expectedFabricatorOptional => 'Expected fabricator (optional)';

  @override
  String get expectedFabricatorHint =>
      'Best guess — corrected from the scanned form later';

  @override
  String get orderCreated => 'Order created';

  @override
  String orderCreatedBody(String material) {
    return 'Download and print the handover form, then give it to the driver/transporter together with \"$material\". The completed form is scanned back into the app once it reaches the technician.';
  }

  @override
  String get couldNotOpenScanner => 'The document scanner couldn\'t be opened.';

  @override
  String get couldNotOpenFile =>
      'This file couldn\'t be opened. Please try another one.';

  @override
  String get fillEveryFieldAndScan =>
      'Please fill in every field and attach the scan before submitting.';

  @override
  String get submitVerifiedForm => 'Submit checked form';

  @override
  String confirmSubmitVerifiedForm(String material) {
    return 'Confirm these values match the completed paper form for \"$material\"? This becomes the permanent digital record.';
  }

  @override
  String get attachScanFirst =>
      'Please scan the form or upload a file before submitting.';

  @override
  String get formSubmitted => 'Form submitted.';

  @override
  String get couldNotSubmitForm => 'Couldn\'t submit the form.';

  @override
  String get uploadCompletedForm => 'Upload completed form';

  @override
  String formIdIssued(String id, String quantity, String unit) {
    return 'Form ID: $id • Issued $quantity $unit';
  }

  @override
  String get scan => 'Scan';

  @override
  String get scanSubtitle =>
      'Scan the completed form (several pages are fine) or upload an existing document';

  @override
  String get scanDocument => 'Scan document';

  @override
  String get uploadFile => 'Upload file';

  @override
  String get readingForm =>
      'Reading the form (a starting point only — check everything below)…';

  @override
  String pagesCaptured(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages captured',
      one: '1 page captured',
    );
    return '$_temp0';
  }

  @override
  String get verifyValues => 'Check the values';

  @override
  String get verifyValuesSubtitle =>
      'Every value below must match the paper form — correct anything that was read wrong';

  @override
  String get driverPickupQuantity => 'Driver pickup quantity (from office)';

  @override
  String get fabricatorName => 'Fabricator name';

  @override
  String get fabricatorQuantityReceived => 'Fabricator: quantity received';

  @override
  String get fabricatorCondition => 'Condition at fabricator';

  @override
  String get damageDescription => 'Damage description';

  @override
  String get fabricatorOutputQuantity => 'Fabricator: finished quantity';

  @override
  String get driverCollectedQuantity =>
      'Driver: quantity collected from fabricator';

  @override
  String get technicianReceivedQuantity => 'Quantity you received (technician)';

  @override
  String pdfUnit(String unit) {
    return 'Unit: $unit';
  }

  @override
  String get pdfPrintedName => 'Printed name: ';

  @override
  String get pdfSignature => 'Signature: ';

  @override
  String get pdfDate => 'Date: ';

  @override
  String pdfFormIdPage(String id, int page, int pages) {
    return 'Form ID: $id  •  Page $page of $pages';
  }

  @override
  String get pdfFabricationTitle =>
      'AlmaWorks — Material Fabrication Chain of Custody';

  @override
  String get pdfScanAndUploadNote =>
      'Scan and upload this completed form in the AlmaWorks app after the technician section is signed.';

  @override
  String get pdfIssueDetails => '1. Issue details (filled in by the office)';

  @override
  String get pdfMaterial => 'Material';

  @override
  String get pdfQuantityIssued => 'Quantity issued';

  @override
  String get pdfDateIssued => 'Date issued';

  @override
  String get pdfIssuedBy => 'Issued by';

  @override
  String get pdfExpectedFabricator => 'Expected fabricator';

  @override
  String get pdfDriverPickup => '2. Driver/transporter — pickup confirmation';

  @override
  String get pdfQuantityTaken => 'Quantity taken';

  @override
  String get pdfFabricatorReceipt => '3. Fabricator — receipt confirmation';

  @override
  String get pdfQuantityReceived => 'Quantity received';

  @override
  String get pdfConditionGoodDamaged => 'Condition:  [ ] Good   [ ] Damaged';

  @override
  String get pdfIfDamagedDescribe => 'If damaged, describe:';

  @override
  String get pdfFabricatorName => 'Fabricator name: ';

  @override
  String get pdfFabricatorOutput =>
      '4. Finished material — driver/transporter confirmation';

  @override
  String get pdfFabricatedCollected => 'Fabricated quantity collected';

  @override
  String get pdfTechnicianReceipt =>
      '5. Technician — final receipt confirmation (on site)';

  @override
  String formSavedToDownloads(String file) {
    return 'Form saved to Downloads: $file';
  }

  @override
  String pdfHandoverTitle(String type) {
    return 'AlmaWorks — $type handover via driver/transporter';
  }

  @override
  String get pdfHandoverScanNote =>
      'Scan and upload this completed form in the AlmaWorks app after the recipient section is signed.';

  @override
  String get pdfDispatchDetails =>
      '1. Dispatch details (filled in by the office)';

  @override
  String get pdfDateDispatched => 'Date dispatched';

  @override
  String get pdfDispatchedBy => 'Dispatched by';

  @override
  String get pdfDriverTransporter => 'Driver / transporter';

  @override
  String get pdfRecipient => 'Recipient';

  @override
  String get pdfRecipientReceipt =>
      '3. Recipient — receipt confirmation (on site)';

  @override
  String get projectStatusActive => 'Active';

  @override
  String get projectStatusCompleted => 'Completed';

  @override
  String get projectStatusUntracked => 'Untracked';

  @override
  String get allProjects => 'All projects';

  @override
  String get active => 'Active';

  @override
  String get couldNotLoadProjectsTitle => 'Couldn\'t load the projects';

  @override
  String get noProjectsAssigned => 'No projects assigned to you yet';

  @override
  String get noProjectsFound => 'No projects found';

  @override
  String get noActiveProjectsAssigned => 'No active projects assigned to you';

  @override
  String get noCompletedProjectsAssigned =>
      'No completed projects assigned to you';

  @override
  String get noActiveProjects => 'No active projects';

  @override
  String get noCompletedProjects => 'No completed projects';

  @override
  String get tapPlusToCreateProject =>
      'Tap the + button to create your first project';

  @override
  String get couldNotOpenProjectAction => 'Couldn\'t open the project.';

  @override
  String get editProject => 'Edit project';

  @override
  String get deleteProject => 'Delete project';

  @override
  String deleteProjectConfirm(String name) {
    return 'Are you sure you want to delete \"$name\"? This can\'t be undone.';
  }

  @override
  String projectDeleted(String name) {
    return 'Project \"$name\" deleted.';
  }

  @override
  String get couldNotDeleteProject => 'Couldn\'t delete the project.';

  @override
  String get addProject => 'Add project';

  @override
  String get addNewProject => 'Add new project';

  @override
  String sectionComingSoon(String section) {
    return '$section is coming soon.';
  }

  @override
  String get basicInformation => 'Basic information';

  @override
  String get projectName => 'Project name';

  @override
  String get enterProjectName => 'Please enter a project name';

  @override
  String get descriptionOptionalCap => 'Description (optional)';

  @override
  String get contractNumberOptional => 'Contract number (optional)';

  @override
  String get location => 'Location';

  @override
  String get enterProjectLocation => 'Please enter the project location';

  @override
  String get projectDetails => 'Project details';

  @override
  String get budgetUsd => 'Budget (USD)';

  @override
  String get statusOptional => 'Status (optional)';

  @override
  String get projectManager => 'Project manager';

  @override
  String get enterProjectManager => 'Please enter the project manager';

  @override
  String get timeline => 'Timeline';

  @override
  String get startDate => 'Start date';

  @override
  String get endDateOptional => 'End date (optional)';

  @override
  String get notSet => 'Not set';

  @override
  String get teamMembers => 'Team members';

  @override
  String get role => 'Role';

  @override
  String get teamRoleSubcontractor => 'Subcontractor';

  @override
  String get teamRoleSupplier => 'Supplier';

  @override
  String get teamRoleTechnician => 'Technician';

  @override
  String get teamRoleManager => 'Manager';

  @override
  String get defineNew => 'Define new';

  @override
  String get defineRoleName => 'Role name *';

  @override
  String get defineRoleHint => 'e.g. Site foreman, Safety officer';

  @override
  String get teamMemberName => 'Team member name';

  @override
  String get categoryOptional => 'Category (optional)';

  @override
  String get teamMembersColon => 'Team members:';

  @override
  String get noTeamMembersYet => 'No team members added yet';

  @override
  String get creatingProject => 'Creating project…';

  @override
  String get createProject => 'Create project';

  @override
  String get selectRole => 'Please choose a role.';

  @override
  String get enterCustomRole => 'Please enter a name for the new role.';

  @override
  String get enterTeamMemberName => 'Please enter a team member name.';

  @override
  String get teamMemberExists => 'This team member is already on the list.';

  @override
  String projectCreated(String name) {
    return 'Project \"$name\" created.';
  }

  @override
  String get couldNotCreateProject => 'Couldn\'t create the project.';

  @override
  String editProjectName(String name) {
    return 'Edit $name';
  }

  @override
  String get updating => 'Updating…';

  @override
  String get updateProject => 'Update project';

  @override
  String get linkedPmAccount => 'Linked project manager account (optional)';

  @override
  String get linkedPmHelper =>
      'Lets this person receive and approve task date-change requests';

  @override
  String get loadingAccounts => 'Loading accounts…';

  @override
  String get noLinkedAccount => 'No linked account';

  @override
  String get teamMemberNameRequired => 'Team member name *';

  @override
  String get roleRequired => 'Role *';

  @override
  String get projectManagerRequired => 'Project manager *';

  @override
  String projectUpdated(String name) {
    return 'Project \"$name\" updated.';
  }

  @override
  String get couldNotUpdateProject => 'Couldn\'t update the project.';

  @override
  String get healthCompleted => 'Completed';

  @override
  String get healthOnTrack => 'On track';

  @override
  String get healthInProgress => 'In progress';

  @override
  String get healthEarlyStage => 'Early stage';

  @override
  String get healthOverdue => 'Overdue';

  @override
  String get healthAhead => 'Ahead of schedule';

  @override
  String get healthSlightDelay => 'Slight delay';

  @override
  String get healthAtRisk => 'At risk';

  @override
  String get projectUpdatedShort => 'Project updated.';

  @override
  String get projectOverview => 'Project overview';

  @override
  String get progress => 'Progress';

  @override
  String get progressLive => 'Progress (live)';

  @override
  String get teamSize => 'Team size';

  @override
  String membersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String get endDate => 'End date';

  @override
  String get tbd => 'TBD';

  @override
  String get daysRemaining => 'Days remaining';

  @override
  String daysCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get dueToday => 'Due today';

  @override
  String daysOverdueShort(int count) {
    return '${count}d overdue';
  }

  @override
  String get overallProgress => 'Overall progress';

  @override
  String get healthStatus => 'Health';

  @override
  String get pmShort => 'PM';

  @override
  String get taskTypeMain => 'Main task';

  @override
  String get taskTypeSub => 'Subtask';

  @override
  String get taskTypeTask => 'Task';

  @override
  String get taskNotStarted => 'Not started';

  @override
  String get taskStarted => 'Started';

  @override
  String get taskCompleted => 'Completed';

  @override
  String get monitorOverdue => 'Overdue';

  @override
  String get monitorOngoing => 'Ongoing';

  @override
  String get monitorUpcoming => 'Upcoming';

  @override
  String get healthExcellent => 'Excellent';

  @override
  String get healthGood => 'Good';

  @override
  String get healthFair => 'Fair';

  @override
  String get healthBehind => 'Behind schedule';

  @override
  String get storagePermissionDenied =>
      'Storage access is turned off. Please allow it in your device settings and try again.';

  @override
  String get downloadStartedWeb =>
      'Download started. Check your browser downloads.';

  @override
  String get downloadFailed =>
      'We couldn\'t download the file. Please try again.';

  @override
  String get fileTooLarge100 =>
      'This file is larger than 100 MB. Please choose a smaller file.';

  @override
  String get drawingNotFound =>
      'This drawing no longer exists. It may have been deleted.';

  @override
  String get typeEmailOrName => 'Type email or name…';

  @override
  String get addRecipientTo =>
      'Please add at least one recipient in the To field.';

  @override
  String get enterSubject => 'Please enter a subject.';

  @override
  String get messageSent => 'Message sent!';

  @override
  String get couldNotSendMessage =>
      'We couldn\'t send your message. Please try again.';

  @override
  String get draftSaved => 'Draft saved.';

  @override
  String get discardMessageTitle => 'Discard message?';

  @override
  String get discardMessageBody => 'This message will not be saved.';

  @override
  String get discard => 'Discard';

  @override
  String get reply => 'Reply';

  @override
  String get replyAll => 'Reply all';

  @override
  String get forward => 'Forward';

  @override
  String get forwarded => 'Forwarded';

  @override
  String get newMessage => 'New message';

  @override
  String get msgTo => 'To';

  @override
  String get msgFrom => 'From';

  @override
  String get msgCc => 'Cc';

  @override
  String get subject => 'Subject';

  @override
  String get writeMessageHere => 'Write your message here…';

  @override
  String get send => 'Send';

  @override
  String get attachFiles => 'Attach files';

  @override
  String get saveDraft => 'Save draft';

  @override
  String get moveToTrashTitle => 'Move to Trash?';

  @override
  String get moveToTrashBody => 'This message will be moved to your Trash.';

  @override
  String get moveToTrash => 'Move to Trash';

  @override
  String attachmentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attachments',
      one: '1 attachment',
    );
    return '$_temp0';
  }

  @override
  String repliesInThread(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count replies in this thread',
      one: '1 reply in this thread',
    );
    return '$_temp0';
  }

  @override
  String get noContent => '(no content)';

  @override
  String get noSubject => '(No subject)';

  @override
  String newMessageFrom(String name) {
    return 'New message from $name';
  }

  @override
  String get communication => 'Communication';

  @override
  String get compose => 'Compose';

  @override
  String get inbox => 'Inbox';

  @override
  String get sentFolder => 'Sent';

  @override
  String get drafts => 'Drafts';

  @override
  String get trash => 'Trash';

  @override
  String get searchMessages => 'Search messages…';

  @override
  String get inboxEmpty => 'Your inbox is empty';

  @override
  String get noSentMessages => 'No sent messages';

  @override
  String get trashEmpty => 'Trash is empty';

  @override
  String get couldNotLoadMessages => 'We couldn\'t load your messages';

  @override
  String get noDraftsSaved => 'No drafts saved';

  @override
  String get restore => 'Restore';

  @override
  String get noRecipients => 'No recipients';

  @override
  String toRecipient(String name) {
    return 'To: $name';
  }

  @override
  String toRecipientMore(String name, int count) {
    return 'To: $name +$count';
  }

  @override
  String get draft => 'Draft';

  @override
  String get deleteDraft => 'Delete draft';
}
