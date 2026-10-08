import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('it'),
  ];

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @upload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get upload;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logout;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @notAvailable.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get notAvailable;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Site Management System'**
  String get appTagline;

  /// No description provided for @copyrightFooter.
  ///
  /// In en, this message translates to:
  /// **'© 2026 JV Alma C.I.S Site Management System'**
  String get copyrightFooter;

  /// No description provided for @errGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again — if it keeps happening, contact your administrator.'**
  String get errGeneric;

  /// No description provided for @errTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Please try again.'**
  String get errTryAgain;

  /// No description provided for @errNoPermission.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to do this. If you think that\'s a mistake, ask an administrator to check your access.'**
  String get errNoPermission;

  /// No description provided for @errNetwork.
  ///
  /// In en, this message translates to:
  /// **'No internet connection. Check your connection and try again.'**
  String get errNetwork;

  /// No description provided for @errTimeout.
  ///
  /// In en, this message translates to:
  /// **'This is taking too long. Please try again.'**
  String get errTimeout;

  /// No description provided for @errNotFound.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find this. It may have been moved or deleted.'**
  String get errNotFound;

  /// No description provided for @errAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'This already exists.'**
  String get errAlreadyExists;

  /// No description provided for @errSignInAgain.
  ///
  /// In en, this message translates to:
  /// **'Your session has ended. Please sign in again.'**
  String get errSignInAgain;

  /// No description provided for @errBusy.
  ///
  /// In en, this message translates to:
  /// **'The service is busy right now. Please try again in a moment.'**
  String get errBusy;

  /// No description provided for @errStorageFull.
  ///
  /// In en, this message translates to:
  /// **'Storage is full. Please contact your administrator.'**
  String get errStorageFull;

  /// No description provided for @errCancelled.
  ///
  /// In en, this message translates to:
  /// **'The action was cancelled.'**
  String get errCancelled;

  /// No description provided for @errInvalidData.
  ///
  /// In en, this message translates to:
  /// **'Some information is missing or not valid. Please check and try again.'**
  String get errInvalidData;

  /// No description provided for @errWrongCredentials.
  ///
  /// In en, this message translates to:
  /// **'The email or password is incorrect.'**
  String get errWrongCredentials;

  /// No description provided for @errInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address.'**
  String get errInvalidEmail;

  /// No description provided for @errEmailInUse.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists.'**
  String get errEmailInUse;

  /// No description provided for @errWeakPassword.
  ///
  /// In en, this message translates to:
  /// **'Please choose a stronger password (at least 6 characters).'**
  String get errWeakPassword;

  /// No description provided for @errTooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a few minutes and try again.'**
  String get errTooManyAttempts;

  /// No description provided for @errAccountDisabled.
  ///
  /// In en, this message translates to:
  /// **'This account has been disabled. Please contact your administrator.'**
  String get errAccountDisabled;

  /// No description provided for @settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance, accessibility and language'**
  String get settingsSubtitle;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @appearanceHint.
  ///
  /// In en, this message translates to:
  /// **'Choose how AlmaWorks looks on this device.'**
  String get appearanceHint;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeSystemHint.
  ///
  /// In en, this message translates to:
  /// **'Matches your device'**
  String get themeSystemHint;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeLightHint.
  ///
  /// In en, this message translates to:
  /// **'Bright and clear'**
  String get themeLightHint;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeDarkHint.
  ///
  /// In en, this message translates to:
  /// **'Easier on the eyes at night'**
  String get themeDarkHint;

  /// No description provided for @font.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get font;

  /// No description provided for @fontHint.
  ///
  /// In en, this message translates to:
  /// **'Pick the typeface that\'s easiest for you to read.'**
  String get fontHint;

  /// No description provided for @fontPoppinsDesc.
  ///
  /// In en, this message translates to:
  /// **'Default · modern and rounded'**
  String get fontPoppinsDesc;

  /// No description provided for @fontInterDesc.
  ///
  /// In en, this message translates to:
  /// **'Crisp and neutral'**
  String get fontInterDesc;

  /// No description provided for @fontRobotoDesc.
  ///
  /// In en, this message translates to:
  /// **'Familiar and compact'**
  String get fontRobotoDesc;

  /// No description provided for @fontOpenSansDesc.
  ///
  /// In en, this message translates to:
  /// **'Open and friendly'**
  String get fontOpenSansDesc;

  /// No description provided for @fontNunitoDesc.
  ///
  /// In en, this message translates to:
  /// **'Soft and rounded'**
  String get fontNunitoDesc;

  /// No description provided for @fontAtkinsonDesc.
  ///
  /// In en, this message translates to:
  /// **'Made for low-vision readers'**
  String get fontAtkinsonDesc;

  /// No description provided for @fontMerriweatherDesc.
  ///
  /// In en, this message translates to:
  /// **'Classic serif for long reading'**
  String get fontMerriweatherDesc;

  /// No description provided for @accessibility.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get accessibility;

  /// No description provided for @accessibilityHint.
  ///
  /// In en, this message translates to:
  /// **'Make text and screens easier to read and use.'**
  String get accessibilityHint;

  /// No description provided for @textSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get textSize;

  /// No description provided for @textSizeHint.
  ///
  /// In en, this message translates to:
  /// **'Applies to every screen, on top of your device setting.'**
  String get textSizeHint;

  /// No description provided for @textSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get textSizeSmall;

  /// No description provided for @textSizeDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get textSizeDefault;

  /// No description provided for @textSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get textSizeLarge;

  /// No description provided for @textSizeExtraLarge.
  ///
  /// In en, this message translates to:
  /// **'Extra large'**
  String get textSizeExtraLarge;

  /// No description provided for @boldText.
  ///
  /// In en, this message translates to:
  /// **'Bold text'**
  String get boldText;

  /// No description provided for @boldTextHint.
  ///
  /// In en, this message translates to:
  /// **'Makes all text thicker and easier to see.'**
  String get boldTextHint;

  /// No description provided for @highContrast.
  ///
  /// In en, this message translates to:
  /// **'High contrast'**
  String get highContrast;

  /// No description provided for @highContrastHint.
  ///
  /// In en, this message translates to:
  /// **'Stronger colors for text and borders.'**
  String get highContrastHint;

  /// No description provided for @reduceMotion.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get reduceMotion;

  /// No description provided for @reduceMotionHint.
  ///
  /// In en, this message translates to:
  /// **'Turns off page transitions and moving effects.'**
  String get reduceMotionHint;

  /// No description provided for @resetDisplaySettings.
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults'**
  String get resetDisplaySettings;

  /// No description provided for @resetDisplaySettingsDone.
  ///
  /// In en, this message translates to:
  /// **'Appearance and accessibility settings are back to their defaults.'**
  String get resetDisplaySettingsDone;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageHint.
  ///
  /// In en, this message translates to:
  /// **'Used on every screen, message and notification.'**
  String get languageHint;

  /// No description provided for @languageChanged.
  ///
  /// In en, this message translates to:
  /// **'Language changed to {language}'**
  String languageChanged(String language);

  /// No description provided for @languageNotificationNote.
  ///
  /// In en, this message translates to:
  /// **'Notifications sent to you will also arrive in this language.'**
  String get languageNotificationNote;

  /// No description provided for @deviceNotifications.
  ///
  /// In en, this message translates to:
  /// **'Alerts on this device'**
  String get deviceNotifications;

  /// No description provided for @deviceNotificationsHint.
  ///
  /// In en, this message translates to:
  /// **'Pop-up alerts for tasks, requests and messages. Your notification inbox keeps everything either way.'**
  String get deviceNotificationsHint;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @previewTitle.
  ///
  /// In en, this message translates to:
  /// **'Site inspection — Block A'**
  String get previewTitle;

  /// No description provided for @previewBody.
  ///
  /// In en, this message translates to:
  /// **'Foundation works are 80% complete. The next inspection is on Friday.'**
  String get previewBody;

  /// No description provided for @previewStatus.
  ///
  /// In en, this message translates to:
  /// **'On track'**
  String get previewStatus;

  /// No description provided for @previewAction.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get previewAction;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'JV Alma C.I.S Site Management System'**
  String get aboutApp;

  /// No description provided for @aboutAppHint.
  ///
  /// In en, this message translates to:
  /// **'Projects, schedules, documents, safety and inventory in one place.'**
  String get aboutAppHint;

  /// No description provided for @selected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get selected;

  /// No description provided for @settingsSavedAutomatically.
  ///
  /// In en, this message translates to:
  /// **'Changes are saved automatically on this device.'**
  String get settingsSavedAutomatically;

  /// No description provided for @channelOverdueTasks.
  ///
  /// In en, this message translates to:
  /// **'Overdue tasks'**
  String get channelOverdueTasks;

  /// No description provided for @channelOverdueTasksDesc.
  ///
  /// In en, this message translates to:
  /// **'Alerts for tasks that are past their end date'**
  String get channelOverdueTasksDesc;

  /// No description provided for @channelStartingSoon.
  ///
  /// In en, this message translates to:
  /// **'Tasks starting soon'**
  String get channelStartingSoon;

  /// No description provided for @channelStartingSoonDesc.
  ///
  /// In en, this message translates to:
  /// **'Alerts for tasks about to start'**
  String get channelStartingSoonDesc;

  /// No description provided for @channelTaskSummary.
  ///
  /// In en, this message translates to:
  /// **'Task summary'**
  String get channelTaskSummary;

  /// No description provided for @channelTaskSummaryDesc.
  ///
  /// In en, this message translates to:
  /// **'Grouped task alerts'**
  String get channelTaskSummaryDesc;

  /// No description provided for @channelRequests.
  ///
  /// In en, this message translates to:
  /// **'Requests and approvals'**
  String get channelRequests;

  /// No description provided for @channelRequestsDesc.
  ///
  /// In en, this message translates to:
  /// **'Access requests, inventory, safety training and project updates'**
  String get channelRequestsDesc;

  /// No description provided for @channelMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get channelMessages;

  /// No description provided for @channelMessagesDesc.
  ///
  /// In en, this message translates to:
  /// **'New messages and replies'**
  String get channelMessagesDesc;

  /// No description provided for @startupFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'AlmaWorks couldn\'t start'**
  String get startupFailedTitle;

  /// No description provided for @startupFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Please check your internet connection and open the app again. If this keeps happening, contact your administrator.'**
  String get startupFailedMessage;

  /// No description provided for @roleMainAdmin.
  ///
  /// In en, this message translates to:
  /// **'Main Admin'**
  String get roleMainAdmin;

  /// No description provided for @roleSystemAdmin.
  ///
  /// In en, this message translates to:
  /// **'System Admin'**
  String get roleSystemAdmin;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @roleClient.
  ///
  /// In en, this message translates to:
  /// **'Client'**
  String get roleClient;

  /// No description provided for @roleTechnician.
  ///
  /// In en, this message translates to:
  /// **'Technician'**
  String get roleTechnician;

  /// No description provided for @roleSubContractor.
  ///
  /// In en, this message translates to:
  /// **'Subcontractor'**
  String get roleSubContractor;

  /// No description provided for @roleManager.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get roleManager;

  /// No description provided for @roleMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get roleMember;

  /// No description provided for @myProjectDashboard.
  ///
  /// In en, this message translates to:
  /// **'My Project Dashboard'**
  String get myProjectDashboard;

  /// No description provided for @projectDashboard.
  ///
  /// In en, this message translates to:
  /// **'Project Dashboard'**
  String get projectDashboard;

  /// No description provided for @navSwitchProject.
  ///
  /// In en, this message translates to:
  /// **'Switch Project'**
  String get navSwitchProject;

  /// No description provided for @navMyProjects.
  ///
  /// In en, this message translates to:
  /// **'My Projects'**
  String get navMyProjects;

  /// No description provided for @navOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get navOverview;

  /// No description provided for @navDocuments.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get navDocuments;

  /// No description provided for @navDrawings.
  ///
  /// In en, this message translates to:
  /// **'Drawings'**
  String get navDrawings;

  /// No description provided for @navSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get navSchedule;

  /// No description provided for @navQualitySafety.
  ///
  /// In en, this message translates to:
  /// **'Quality & Safety'**
  String get navQualitySafety;

  /// No description provided for @navReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get navReports;

  /// No description provided for @navPhotoGallery.
  ///
  /// In en, this message translates to:
  /// **'Photo Gallery'**
  String get navPhotoGallery;

  /// No description provided for @navPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get navPhotos;

  /// No description provided for @navFinancials.
  ///
  /// In en, this message translates to:
  /// **'Financials'**
  String get navFinancials;

  /// No description provided for @navAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get navAccount;

  /// No description provided for @myAccount.
  ///
  /// In en, this message translates to:
  /// **'My Account'**
  String get myAccount;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfile;

  /// No description provided for @refreshProfile.
  ///
  /// In en, this message translates to:
  /// **'Refresh profile'**
  String get refreshProfile;

  /// No description provided for @loadingProfile.
  ///
  /// In en, this message translates to:
  /// **'Loading your profile…'**
  String get loadingProfile;

  /// No description provided for @couldNotLoadProfile.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your profile'**
  String get couldNotLoadProfile;

  /// No description provided for @profileNotFound.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find your profile. Please contact your administrator.'**
  String get profileNotFound;

  /// No description provided for @nameCannotBeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Please enter your name.'**
  String get nameCannotBeEmpty;

  /// No description provided for @profileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Your profile has been updated.'**
  String get profileUpdated;

  /// No description provided for @couldNotSaveProfile.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your profile.'**
  String get couldNotSaveProfile;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullName;

  /// No description provided for @emailAddress.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get emailAddress;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @emailChangeNote.
  ///
  /// In en, this message translates to:
  /// **'Changing your email here updates your profile only — not the email you sign in with.'**
  String get emailChangeNote;

  /// No description provided for @unknownUser.
  ///
  /// In en, this message translates to:
  /// **'Unknown user'**
  String get unknownUser;

  /// No description provided for @noEmailOnRecord.
  ///
  /// In en, this message translates to:
  /// **'No email on record'**
  String get noEmailOnRecord;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// No description provided for @textSizePercent.
  ///
  /// In en, this message translates to:
  /// **'Text {percent}%'**
  String textSizePercent(int percent);

  /// No description provided for @on.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get on;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @logoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to log out?'**
  String get logoutConfirm;

  /// No description provided for @notificationsHint.
  ///
  /// In en, this message translates to:
  /// **'Choose how AlmaWorks alerts you.'**
  String get notificationsHint;

  /// No description provided for @loadingDashboard.
  ///
  /// In en, this message translates to:
  /// **'Loading dashboard…'**
  String get loadingDashboard;

  /// No description provided for @welcomeToAlmaWorks.
  ///
  /// In en, this message translates to:
  /// **'Welcome to AlmaWorks'**
  String get welcomeToAlmaWorks;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @requestAccessIntro.
  ///
  /// In en, this message translates to:
  /// **'To see construction projects and work with your team, you\'ll need to ask an administrator for access.'**
  String get requestAccessIntro;

  /// No description provided for @requestAccessStep1.
  ///
  /// In en, this message translates to:
  /// **'Tap the button below to send your request'**
  String get requestAccessStep1;

  /// No description provided for @requestAccessStep2.
  ///
  /// In en, this message translates to:
  /// **'An administrator will review it'**
  String get requestAccessStep2;

  /// No description provided for @requestAccessStep3.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be notified once access is granted'**
  String get requestAccessStep3;

  /// No description provided for @previousRequestDenied.
  ///
  /// In en, this message translates to:
  /// **'Your previous request was not approved'**
  String get previousRequestDenied;

  /// No description provided for @accessRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Your access request has been sent.'**
  String get accessRequestSent;

  /// No description provided for @couldNotSendAccessRequest.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send your access request.'**
  String get couldNotSendAccessRequest;

  /// No description provided for @sending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get sending;

  /// No description provided for @requestAccess.
  ///
  /// In en, this message translates to:
  /// **'Request access'**
  String get requestAccess;

  /// No description provided for @requestPending.
  ///
  /// In en, this message translates to:
  /// **'Request pending'**
  String get requestPending;

  /// No description provided for @requestPendingMessage.
  ///
  /// In en, this message translates to:
  /// **'An administrator is reviewing your access request. You\'ll get access as soon as it\'s approved.'**
  String get requestPendingMessage;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navProjects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get navProjects;

  /// No description provided for @navClientAccessRequests.
  ///
  /// In en, this message translates to:
  /// **'Access Requests'**
  String get navClientAccessRequests;

  /// No description provided for @couldNotLoadScreen.
  ///
  /// In en, this message translates to:
  /// **'This screen couldn\'t be opened'**
  String get couldNotLoadScreen;

  /// No description provided for @goToDashboard.
  ///
  /// In en, this message translates to:
  /// **'Go to dashboard'**
  String get goToDashboard;

  /// No description provided for @myProjectsOverview.
  ///
  /// In en, this message translates to:
  /// **'My Projects Overview'**
  String get myProjectsOverview;

  /// No description provided for @generalOverview.
  ///
  /// In en, this message translates to:
  /// **'General Overview'**
  String get generalOverview;

  /// No description provided for @totalProjects.
  ///
  /// In en, this message translates to:
  /// **'Total Projects'**
  String get totalProjects;

  /// No description provided for @activeProjects.
  ///
  /// In en, this message translates to:
  /// **'Active Projects'**
  String get activeProjects;

  /// No description provided for @completedProjects.
  ///
  /// In en, this message translates to:
  /// **'Completed Projects'**
  String get completedProjects;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @openingSafetyTraining.
  ///
  /// In en, this message translates to:
  /// **'Opening Safety Training…'**
  String get openingSafetyTraining;

  /// No description provided for @couldNotOpenSafetyTraining.
  ///
  /// In en, this message translates to:
  /// **'Safety Training couldn\'t be opened right now. Please try again.'**
  String get couldNotOpenSafetyTraining;

  /// No description provided for @openingProject.
  ///
  /// In en, this message translates to:
  /// **'Opening project…'**
  String get openingProject;

  /// No description provided for @projectNoLongerExists.
  ///
  /// In en, this message translates to:
  /// **'This project no longer exists.'**
  String get projectNoLongerExists;

  /// No description provided for @couldNotOpenProject.
  ///
  /// In en, this message translates to:
  /// **'The project couldn\'t be opened. Please try again.'**
  String get couldNotOpenProject;

  /// No description provided for @openingMessage.
  ///
  /// In en, this message translates to:
  /// **'Opening message…'**
  String get openingMessage;

  /// No description provided for @messageNotFound.
  ///
  /// In en, this message translates to:
  /// **'This message was not found or has been deleted.'**
  String get messageNotFound;

  /// No description provided for @projectNotFound.
  ///
  /// In en, this message translates to:
  /// **'Project not found.'**
  String get projectNotFound;

  /// No description provided for @couldNotOpenMessage.
  ///
  /// In en, this message translates to:
  /// **'The message couldn\'t be opened. Please try again.'**
  String get couldNotOpenMessage;

  /// No description provided for @openingAsset.
  ///
  /// In en, this message translates to:
  /// **'Opening item…'**
  String get openingAsset;

  /// No description provided for @assetNotFound.
  ///
  /// In en, this message translates to:
  /// **'This item was not found or has been removed.'**
  String get assetNotFound;

  /// No description provided for @couldNotOpenInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory couldn\'t be opened right now. Please try again.'**
  String get couldNotOpenInventory;

  /// No description provided for @couldNotOpenAsset.
  ///
  /// In en, this message translates to:
  /// **'The item couldn\'t be opened. Please try again.'**
  String get couldNotOpenAsset;

  /// No description provided for @openingRequest.
  ///
  /// In en, this message translates to:
  /// **'Opening request…'**
  String get openingRequest;

  /// No description provided for @requestAlreadyHandled.
  ///
  /// In en, this message translates to:
  /// **'This request has already been handled.'**
  String get requestAlreadyHandled;

  /// No description provided for @couldNotOpenRequest.
  ///
  /// In en, this message translates to:
  /// **'The request couldn\'t be opened. Please try again.'**
  String get couldNotOpenRequest;

  /// No description provided for @notificationsUnread.
  ///
  /// In en, this message translates to:
  /// **'Notifications ({count} unread)'**
  String notificationsUnread(int count);

  /// No description provided for @catSafety.
  ///
  /// In en, this message translates to:
  /// **'Safety'**
  String get catSafety;

  /// No description provided for @catProjects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get catProjects;

  /// No description provided for @catInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get catInventory;

  /// No description provided for @catMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get catMessages;

  /// No description provided for @catAccess.
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get catAccess;

  /// No description provided for @catOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get catOther;

  /// No description provided for @notificationFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification'**
  String get notificationFallbackTitle;

  /// No description provided for @taskUpdate.
  ///
  /// In en, this message translates to:
  /// **'Task update'**
  String get taskUpdate;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}m ago'**
  String minutesAgo(int n);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}h ago'**
  String hoursAgo(int n);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}d ago'**
  String daysAgo(int n);

  /// No description provided for @monthsAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}mo ago'**
  String monthsAgo(int n);

  /// No description provided for @allCaughtUp.
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up'**
  String get allCaughtUp;

  /// No description provided for @unreadCount.
  ///
  /// In en, this message translates to:
  /// **'{count} unread'**
  String unreadCount(int count);

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get markAllRead;

  /// No description provided for @couldNotLoadNotifications.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load notifications'**
  String get couldNotLoadNotifications;

  /// No description provided for @someNotificationsMissing.
  ///
  /// In en, this message translates to:
  /// **'Some notifications couldn\'t be loaded — the list may be incomplete.'**
  String get someNotificationsMissing;

  /// No description provided for @noUnreadNotifications.
  ///
  /// In en, this message translates to:
  /// **'No unread notifications'**
  String get noUnreadNotifications;

  /// No description provided for @nothingHereYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get nothingHereYet;

  /// No description provided for @notificationsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Updates about your projects, inventory, safety training and messages will appear here.'**
  String get notificationsEmptyHint;

  /// No description provided for @tryAnotherFilter.
  ///
  /// In en, this message translates to:
  /// **'Try another filter to see more.'**
  String get tryAnotherFilter;

  /// No description provided for @allMarkedRead.
  ///
  /// In en, this message translates to:
  /// **'All notifications marked as read'**
  String get allMarkedRead;

  /// No description provided for @couldNotMarkRead.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t mark the notifications as read.'**
  String get couldNotMarkRead;

  /// No description provided for @unread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get unread;

  /// No description provided for @safetyUnread.
  ///
  /// In en, this message translates to:
  /// **'Safety (unread)'**
  String get safetyUnread;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @markUnread.
  ///
  /// In en, this message translates to:
  /// **'Mark unread'**
  String get markUnread;

  /// No description provided for @markRead.
  ///
  /// In en, this message translates to:
  /// **'Mark read'**
  String get markRead;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @viewDetails.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get viewDetails;

  /// No description provided for @markAsUnread.
  ///
  /// In en, this message translates to:
  /// **'Mark as unread'**
  String get markAsUnread;

  /// No description provided for @markAsRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get markAsRead;

  /// No description provided for @couldNotUpdateNotification.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update the notification.'**
  String get couldNotUpdateNotification;

  /// No description provided for @notificationRemoved.
  ///
  /// In en, this message translates to:
  /// **'Notification removed'**
  String get notificationRemoved;

  /// No description provided for @couldNotRemoveNotification.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove the notification.'**
  String get couldNotRemoveNotification;

  /// No description provided for @noFurtherDetails.
  ///
  /// In en, this message translates to:
  /// **'No further details.'**
  String get noFurtherDetails;

  /// No description provided for @requestNoLongerExists.
  ///
  /// In en, this message translates to:
  /// **'Request no longer exists'**
  String get requestNoLongerExists;

  /// No description provided for @thisUser.
  ///
  /// In en, this message translates to:
  /// **'This user'**
  String get thisUser;

  /// No description provided for @anAdmin.
  ///
  /// In en, this message translates to:
  /// **'an admin'**
  String get anAdmin;

  /// No description provided for @accessApprovedTitle.
  ///
  /// In en, this message translates to:
  /// **'✅ Access approved — {name}'**
  String accessApprovedTitle(String name);

  /// No description provided for @accessApprovedBody.
  ///
  /// In en, this message translates to:
  /// **'{name} was approved as {role} with access to {count, plural, =1{1 project} other{{count} projects}}.'**
  String accessApprovedBody(String name, String role, int count);

  /// No description provided for @approvedByWhen.
  ///
  /// In en, this message translates to:
  /// **'Approved by {name}{when}'**
  String approvedByWhen(String name, String when);

  /// No description provided for @accessDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'❌ Access denied — {name}'**
  String accessDeniedTitle(String name);

  /// No description provided for @accessDeniedBody.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s access request was denied.'**
  String accessDeniedBody(String name);

  /// No description provided for @reasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String reasonLabel(String reason);

  /// No description provided for @deniedByWhen.
  ///
  /// In en, this message translates to:
  /// **'Denied by {name}{when}'**
  String deniedByWhen(String name, String when);

  /// No description provided for @awaitingDecision.
  ///
  /// In en, this message translates to:
  /// **'Awaiting a decision'**
  String get awaitingDecision;

  /// No description provided for @newNotification.
  ///
  /// In en, this message translates to:
  /// **'🔔 New notification'**
  String get newNotification;

  /// No description provided for @viewRequest.
  ///
  /// In en, this message translates to:
  /// **'View request'**
  String get viewRequest;

  /// No description provided for @notifNewAccessRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'🔔 New access request'**
  String get notifNewAccessRequestTitle;

  /// No description provided for @notifNewAccessRequestBody.
  ///
  /// In en, this message translates to:
  /// **'{name} is asking for access to projects'**
  String notifNewAccessRequestBody(String name);

  /// No description provided for @notifAccessGrantedTitle.
  ///
  /// In en, this message translates to:
  /// **'✅ Access granted'**
  String get notifAccessGrantedTitle;

  /// No description provided for @notifAccessGrantedBody.
  ///
  /// In en, this message translates to:
  /// **'Your request has been approved! You now have access to: {projects}'**
  String notifAccessGrantedBody(String projects);

  /// No description provided for @notifRequestDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'❌ Request denied'**
  String get notifRequestDeniedTitle;

  /// No description provided for @notifRequestDeniedBody.
  ///
  /// In en, this message translates to:
  /// **'Your access request was not approved by an administrator.'**
  String get notifRequestDeniedBody;

  /// No description provided for @notifProjectAccessUpdatedTitle.
  ///
  /// In en, this message translates to:
  /// **'🔄 Project access updated'**
  String get notifProjectAccessUpdatedTitle;

  /// No description provided for @notifProjectAccessAddedRemoved.
  ///
  /// In en, this message translates to:
  /// **'Your project access has changed. Added: {added}. Removed: {removed}.'**
  String notifProjectAccessAddedRemoved(String added, String removed);

  /// No description provided for @notifProjectAccessAdded.
  ///
  /// In en, this message translates to:
  /// **'You now have access to: {projects}.'**
  String notifProjectAccessAdded(String projects);

  /// No description provided for @notifProjectAccessRemoved.
  ///
  /// In en, this message translates to:
  /// **'Your access to these projects has been removed: {projects}.'**
  String notifProjectAccessRemoved(String projects);

  /// No description provided for @taskOverdueTitle.
  ///
  /// In en, this message translates to:
  /// **'⚠️ Overdue: {task}'**
  String taskOverdueTitle(String task);

  /// No description provided for @taskStartingSoonTitle.
  ///
  /// In en, this message translates to:
  /// **'📅 Starting soon: {task}'**
  String taskStartingSoonTitle(String task);

  /// No description provided for @taskOverdueBody.
  ///
  /// In en, this message translates to:
  /// **'This task is overdue and needs attention.'**
  String get taskOverdueBody;

  /// No description provided for @taskStartsInDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{Starts today} =1{Starts in 1 day} other{Starts in {days} days}}'**
  String taskStartsInDays(int days);

  /// No description provided for @markReadAction.
  ///
  /// In en, this message translates to:
  /// **'Mark read'**
  String get markReadAction;

  /// No description provided for @taskAlertsSummaryBoth.
  ///
  /// In en, this message translates to:
  /// **'{overdue} overdue, {soon} starting soon'**
  String taskAlertsSummaryBoth(int overdue, int soon);

  /// No description provided for @taskAlertsSummaryOverdue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 overdue task} other{{count} overdue tasks}}'**
  String taskAlertsSummaryOverdue(int count);

  /// No description provided for @taskAlertsSummarySoon.
  ///
  /// In en, this message translates to:
  /// **'{count} starting soon'**
  String taskAlertsSummarySoon(int count);

  /// No description provided for @taskAlertsTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{🔔 1 task alert} other{🔔 {count} task alerts}}'**
  String taskAlertsTitle(int count);

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get viewAll;

  /// No description provided for @taskIsOverdue.
  ///
  /// In en, this message translates to:
  /// **'Task is overdue'**
  String get taskIsOverdue;

  /// No description provided for @taskStartsSoon.
  ///
  /// In en, this message translates to:
  /// **'Task starts soon'**
  String get taskStartsSoon;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get chooseLanguage;

  /// No description provided for @accountNotFound.
  ///
  /// In en, this message translates to:
  /// **'No account was found with this email address. Please check it and try again.'**
  String get accountNotFound;

  /// No description provided for @incorrectPassword.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password. Please try again or reset your password.'**
  String get incorrectPassword;

  /// No description provided for @tooManyLoginAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many failed sign-in attempts. Please wait a few minutes or reset your password.'**
  String get tooManyLoginAttempts;

  /// No description provided for @signInFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t sign you in.'**
  String get signInFailed;

  /// No description provided for @enterEmailFirst.
  ///
  /// In en, this message translates to:
  /// **'Please enter your email address first.'**
  String get enterEmailFirst;

  /// No description provided for @passwordResetSent.
  ///
  /// In en, this message translates to:
  /// **'A password reset email has been sent to {email}. Please check your inbox.'**
  String passwordResetSent(String email);

  /// No description provided for @couldNotSendResetEmail.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the password reset email.'**
  String get couldNotSendResetEmail;

  /// No description provided for @welcomeBackHeadline.
  ///
  /// In en, this message translates to:
  /// **'Welcome back to\nAlmaWorks'**
  String get welcomeBackHeadline;

  /// No description provided for @welcomeBackSubtext.
  ///
  /// In en, this message translates to:
  /// **'Sign in to manage your projects, inventory and team communication — all in one place.'**
  String get welcomeBackSubtext;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your details to access your account'**
  String get signInSubtitle;

  /// No description provided for @emailHint.
  ///
  /// In en, this message translates to:
  /// **'you@company.com'**
  String get emailHint;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter your email'**
  String get emailRequired;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @passwordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get passwordHint;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password'**
  String get passwordRequired;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get login;

  /// No description provided for @noAccountYet.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? '**
  String get noAccountYet;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get signUp;

  /// No description provided for @usernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please choose a username'**
  String get usernameRequired;

  /// No description provided for @usernameTaken.
  ///
  /// In en, this message translates to:
  /// **'This username is already taken. Please choose a different one.'**
  String get usernameTaken;

  /// No description provided for @registrationSuccess.
  ///
  /// In en, this message translates to:
  /// **'Your account has been created. Welcome to AlmaWorks!'**
  String get registrationSuccess;

  /// No description provided for @emailAlreadyRegistered.
  ///
  /// In en, this message translates to:
  /// **'This email address is already registered. Please sign in instead.'**
  String get emailAlreadyRegistered;

  /// No description provided for @couldNotCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t create your account.'**
  String get couldNotCreateAccount;

  /// No description provided for @joinHeadline.
  ///
  /// In en, this message translates to:
  /// **'Join the\nAlmaWorks team'**
  String get joinHeadline;

  /// No description provided for @joinSubtext.
  ///
  /// In en, this message translates to:
  /// **'Create an account to start tracking projects, assets and communication in one workspace.'**
  String get joinSubtext;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @createAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fill in your details to get started'**
  String get createAccountSubtitle;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @usernameHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a unique username'**
  String get usernameHint;

  /// No description provided for @usernameTooShort.
  ///
  /// In en, this message translates to:
  /// **'Your username needs at least 3 characters'**
  String get usernameTooShort;

  /// No description provided for @usernameInvalidChars.
  ///
  /// In en, this message translates to:
  /// **'Use only letters, numbers and underscores (_)'**
  String get usernameInvalidChars;

  /// No description provided for @newPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Create a strong password'**
  String get newPasswordHint;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Your password needs at least 6 characters'**
  String get passwordTooShort;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? '**
  String get alreadyHaveAccount;

  /// No description provided for @roleUpdatedTo.
  ///
  /// In en, this message translates to:
  /// **'Your role has been updated to {role}'**
  String roleUpdatedTo(String role);

  /// No description provided for @couldNotCheckRole.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t check your role.'**
  String get couldNotCheckRole;

  /// No description provided for @welcomeUser.
  ///
  /// In en, this message translates to:
  /// **'Welcome, {name}!'**
  String welcomeUser(String name);

  /// No description provided for @roleLabel.
  ///
  /// In en, this message translates to:
  /// **'Role: {role}'**
  String roleLabel(String role);

  /// No description provided for @almaWorksSiteManagement.
  ///
  /// In en, this message translates to:
  /// **'AlmaWorks Site Management'**
  String get almaWorksSiteManagement;

  /// No description provided for @featureProjectManagement.
  ///
  /// In en, this message translates to:
  /// **'Project management'**
  String get featureProjectManagement;

  /// No description provided for @featureProjectManagementDesc.
  ///
  /// In en, this message translates to:
  /// **'Organise and track construction projects from start to finish'**
  String get featureProjectManagementDesc;

  /// No description provided for @featureTeamCollaboration.
  ///
  /// In en, this message translates to:
  /// **'Team collaboration'**
  String get featureTeamCollaboration;

  /// No description provided for @featureTeamCollaborationDesc.
  ///
  /// In en, this message translates to:
  /// **'Coordinate with your team and manage tasks efficiently'**
  String get featureTeamCollaborationDesc;

  /// No description provided for @featureRealtimeInsights.
  ///
  /// In en, this message translates to:
  /// **'Real-time insights'**
  String get featureRealtimeInsights;

  /// No description provided for @featureRealtimeInsightsDesc.
  ///
  /// In en, this message translates to:
  /// **'Follow progress with live updates and clear reports'**
  String get featureRealtimeInsightsDesc;

  /// No description provided for @featureSiteTracking.
  ///
  /// In en, this message translates to:
  /// **'Site tracking'**
  String get featureSiteTracking;

  /// No description provided for @featureSiteTrackingDesc.
  ///
  /// In en, this message translates to:
  /// **'Manage several construction sites with location-based tools'**
  String get featureSiteTrackingDesc;

  /// No description provided for @continueToDashboard.
  ///
  /// In en, this message translates to:
  /// **'Continue to dashboard'**
  String get continueToDashboard;

  /// No description provided for @noAccessToProject.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have access to this project.'**
  String get noAccessToProject;

  /// No description provided for @noProjectSelected.
  ///
  /// In en, this message translates to:
  /// **'Please choose a project first.'**
  String get noProjectSelected;

  /// No description provided for @navSafetyTraining.
  ///
  /// In en, this message translates to:
  /// **'Safety Training'**
  String get navSafetyTraining;

  /// No description provided for @navTaskProgress.
  ///
  /// In en, this message translates to:
  /// **'Task Progress'**
  String get navTaskProgress;

  /// No description provided for @navInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get navInventory;

  /// No description provided for @navCommunication.
  ///
  /// In en, this message translates to:
  /// **'Communication'**
  String get navCommunication;

  /// No description provided for @stNotReviewed.
  ///
  /// In en, this message translates to:
  /// **'Not reviewed'**
  String get stNotReviewed;

  /// No description provided for @stClearanceExpired.
  ///
  /// In en, this message translates to:
  /// **'Clearance expired'**
  String get stClearanceExpired;

  /// No description provided for @stClearanceLapsedOn.
  ///
  /// In en, this message translates to:
  /// **'Lapsed on {date} — a new review is needed.'**
  String stClearanceLapsedOn(String date);

  /// No description provided for @stClearedToWork.
  ///
  /// In en, this message translates to:
  /// **'Cleared to work'**
  String get stClearedToWork;

  /// No description provided for @stValidUntil.
  ///
  /// In en, this message translates to:
  /// **'Valid until {date}'**
  String stValidUntil(String date);

  /// No description provided for @stAllAssignedDone.
  ///
  /// In en, this message translates to:
  /// **'All {count} assigned scenarios done — awaiting a new review.'**
  String stAllAssignedDone(int count);

  /// No description provided for @stAssignedProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} assigned scenarios done'**
  String stAssignedProgress(int done, int total);

  /// No description provided for @stOverdueSince.
  ///
  /// In en, this message translates to:
  /// **' · overdue since {date}'**
  String stOverdueSince(String date);

  /// No description provided for @stDue.
  ///
  /// In en, this message translates to:
  /// **' · due {date}'**
  String stDue(String date);

  /// No description provided for @stRetrainingOverdue.
  ///
  /// In en, this message translates to:
  /// **'Retraining overdue'**
  String get stRetrainingOverdue;

  /// No description provided for @stRetrainingDone.
  ///
  /// In en, this message translates to:
  /// **'Retraining done'**
  String get stRetrainingDone;

  /// No description provided for @stNeedsRetraining.
  ///
  /// In en, this message translates to:
  /// **'Needs retraining'**
  String get stNeedsRetraining;

  /// No description provided for @stEscalated.
  ///
  /// In en, this message translates to:
  /// **'Escalated'**
  String get stEscalated;

  /// No description provided for @stSupervisorFollowUp.
  ///
  /// In en, this message translates to:
  /// **'A supervisor will follow up.'**
  String get stSupervisorFollowUp;

  /// No description provided for @stEscalatedTo.
  ///
  /// In en, this message translates to:
  /// **'Escalated to {name} for follow-up.'**
  String stEscalatedTo(String name);

  /// No description provided for @stStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Status unknown'**
  String get stStatusUnknown;

  /// No description provided for @difficultyBasic.
  ///
  /// In en, this message translates to:
  /// **'Basic'**
  String get difficultyBasic;

  /// No description provided for @difficultyIntermediate.
  ///
  /// In en, this message translates to:
  /// **'Intermediate'**
  String get difficultyIntermediate;

  /// No description provided for @difficultyAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get difficultyAdvanced;

  /// No description provided for @categoryGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get categoryGeneral;

  /// No description provided for @filterNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get filterNotStarted;

  /// No description provided for @filterPassed.
  ///
  /// In en, this message translates to:
  /// **'Passed'**
  String get filterPassed;

  /// No description provided for @filterMissed.
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get filterMissed;

  /// No description provided for @filterAssignedToMe.
  ///
  /// In en, this message translates to:
  /// **'Assigned to me'**
  String get filterAssignedToMe;

  /// No description provided for @couldNotLoadAccount.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your account'**
  String get couldNotLoadAccount;

  /// No description provided for @safetyTrainingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Safety Training isn\'t available yet'**
  String get safetyTrainingUnavailable;

  /// No description provided for @roleNotSetUp.
  ///
  /// In en, this message translates to:
  /// **'Your account\'s access role hasn\'t been set up yet. Please contact an administrator.'**
  String get roleNotSetUp;

  /// No description provided for @safetyScenariosCount.
  ///
  /// In en, this message translates to:
  /// **'Safety scenarios ({count})'**
  String safetyScenariosCount(int count);

  /// No description provided for @safetyScenarios.
  ///
  /// In en, this message translates to:
  /// **'Safety scenarios'**
  String get safetyScenarios;

  /// No description provided for @closeSearch.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get closeSearch;

  /// No description provided for @searchScenarios.
  ///
  /// In en, this message translates to:
  /// **'Search scenarios'**
  String get searchScenarios;

  /// No description provided for @searchScenariosHint.
  ///
  /// In en, this message translates to:
  /// **'Search by title, category or scene'**
  String get searchScenariosHint;

  /// No description provided for @couldNotLoadScenarios.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the scenarios'**
  String get couldNotLoadScenarios;

  /// No description provided for @pullToRetry.
  ///
  /// In en, this message translates to:
  /// **'Pull down to try again.'**
  String get pullToRetry;

  /// No description provided for @noScenariosYet.
  ///
  /// In en, this message translates to:
  /// **'No scenarios yet'**
  String get noScenariosYet;

  /// No description provided for @noScenariosMatch.
  ///
  /// In en, this message translates to:
  /// **'No scenarios match'**
  String get noScenariosMatch;

  /// No description provided for @noScenariosAdminHint.
  ///
  /// In en, this message translates to:
  /// **'Tap \"New scenario\" in the toolbar to create the first one.'**
  String get noScenariosAdminHint;

  /// No description provided for @noScenariosWorkerHint.
  ///
  /// In en, this message translates to:
  /// **'Safety scenarios will appear here once an admin publishes them.'**
  String get noScenariosWorkerHint;

  /// No description provided for @tryDifferentSearch.
  ///
  /// In en, this message translates to:
  /// **'Try a different search or filter.'**
  String get tryDifferentSearch;

  /// No description provided for @clearedUntil.
  ///
  /// In en, this message translates to:
  /// **'Cleared · until {date}'**
  String clearedUntil(String date);

  /// No description provided for @myStanding.
  ///
  /// In en, this message translates to:
  /// **'My standing'**
  String get myStanding;

  /// No description provided for @myAttempts.
  ///
  /// In en, this message translates to:
  /// **'My attempts'**
  String get myAttempts;

  /// No description provided for @myHistory.
  ///
  /// In en, this message translates to:
  /// **'My history'**
  String get myHistory;

  /// No description provided for @reviewStanding.
  ///
  /// In en, this message translates to:
  /// **'Review standing'**
  String get reviewStanding;

  /// No description provided for @allAttempts.
  ///
  /// In en, this message translates to:
  /// **'All attempts'**
  String get allAttempts;

  /// No description provided for @manage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manage;

  /// No description provided for @newScenario.
  ///
  /// In en, this message translates to:
  /// **'New scenario'**
  String get newScenario;

  /// No description provided for @firstAttemptCountsHint.
  ///
  /// In en, this message translates to:
  /// **'Only your first attempt at each scenario counts toward your score — replays are practice.'**
  String get firstAttemptCountsHint;

  /// No description provided for @points.
  ///
  /// In en, this message translates to:
  /// **'Points'**
  String get points;

  /// No description provided for @firstTryAccuracy.
  ///
  /// In en, this message translates to:
  /// **'First-try accuracy'**
  String get firstTryAccuracy;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @mySafetyStanding.
  ///
  /// In en, this message translates to:
  /// **'My safety standing'**
  String get mySafetyStanding;

  /// No description provided for @notAssessedYet.
  ///
  /// In en, this message translates to:
  /// **'A reviewer hasn\'t assessed your training yet. Keep working through the scenarios — your first attempts are what they\'ll look at.'**
  String get notAssessedYet;

  /// No description provided for @clearanceValidity.
  ///
  /// In en, this message translates to:
  /// **'Clearance validity'**
  String get clearanceValidity;

  /// No description provided for @expired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get expired;

  /// No description provided for @daysLeft.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day left} other{{count} days left}}'**
  String daysLeft(int count);

  /// No description provided for @retrainingProgress.
  ///
  /// In en, this message translates to:
  /// **'Retraining progress'**
  String get retrainingProgress;

  /// No description provided for @assignedListedFirst.
  ///
  /// In en, this message translates to:
  /// **'Assigned scenarios are listed first on the Safety Training screen.'**
  String get assignedListedFirst;

  /// No description provided for @aReviewer.
  ///
  /// In en, this message translates to:
  /// **'a reviewer'**
  String get aReviewer;

  /// No description provided for @reviewedByOn.
  ///
  /// In en, this message translates to:
  /// **'Reviewed by {name} on {date}'**
  String reviewedByOn(String name, String date);

  /// No description provided for @incompleteFixInManage.
  ///
  /// In en, this message translates to:
  /// **'Incomplete — fix in Manage'**
  String get incompleteFixInManage;

  /// No description provided for @retrainingDue.
  ///
  /// In en, this message translates to:
  /// **'Retraining · due {date}'**
  String retrainingDue(String date);

  /// No description provided for @retraining.
  ///
  /// In en, this message translates to:
  /// **'Retraining'**
  String get retraining;

  /// No description provided for @passedPoints.
  ///
  /// In en, this message translates to:
  /// **'Passed · +{points} pts'**
  String passedPoints(int points);

  /// No description provided for @missedPractise.
  ///
  /// In en, this message translates to:
  /// **'Missed · practise again'**
  String get missedPractise;

  /// No description provided for @pointsShort.
  ///
  /// In en, this message translates to:
  /// **'{points} pts'**
  String pointsShort(int points);

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @practice.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get practice;

  /// No description provided for @scenarioNoLongerExists.
  ///
  /// In en, this message translates to:
  /// **'This scenario no longer exists.'**
  String get scenarioNoLongerExists;

  /// No description provided for @scenarioUnavailableTellAdmin.
  ///
  /// In en, this message translates to:
  /// **'This scenario can\'t be answered right now. Please let an admin know.'**
  String get scenarioUnavailableTellAdmin;

  /// No description provided for @roleCannotTakeTraining.
  ///
  /// In en, this message translates to:
  /// **'Your role can\'t take safety training.'**
  String get roleCannotTakeTraining;

  /// No description provided for @answerNotAccepted.
  ///
  /// In en, this message translates to:
  /// **'Your answer wasn\'t accepted. Please check it and try again.'**
  String get answerNotAccepted;

  /// No description provided for @answerSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Your answer couldn\'t be submitted. Check your connection and tap Retry.'**
  String get answerSubmitFailed;

  /// No description provided for @answerNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm your answer was saved. Check your connection and tap Retry — it won\'t be counted twice.'**
  String get answerNotConfirmed;

  /// No description provided for @scenarioSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{category} · {difficulty} · {points} pts'**
  String scenarioSubtitle(String category, String difficulty, int points);

  /// No description provided for @scenarioIncomplete.
  ///
  /// In en, this message translates to:
  /// **'This scenario is incomplete and can\'t be answered yet. Please let an admin know.'**
  String get scenarioIncomplete;

  /// No description provided for @questionLabel.
  ///
  /// In en, this message translates to:
  /// **'QUESTION'**
  String get questionLabel;

  /// No description provided for @yourAnswer.
  ///
  /// In en, this message translates to:
  /// **'Your answer'**
  String get yourAnswer;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @explainYourThinking.
  ///
  /// In en, this message translates to:
  /// **'EXPLAIN YOUR THINKING'**
  String get explainYourThinking;

  /// No description provided for @explainInOwnWords.
  ///
  /// In en, this message translates to:
  /// **'In your own words — this helps your trainer see how well you understand the risk.'**
  String get explainInOwnWords;

  /// No description provided for @moreCharactersNeeded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more character needed} other{{count} more characters needed}}'**
  String moreCharactersNeeded(int count);

  /// No description provided for @explainHint.
  ///
  /// In en, this message translates to:
  /// **'Explain the cause and how to prevent it…'**
  String get explainHint;

  /// No description provided for @submittingAnswer.
  ///
  /// In en, this message translates to:
  /// **'Submitting your answer…'**
  String get submittingAnswer;

  /// No description provided for @submitAnswer.
  ///
  /// In en, this message translates to:
  /// **'Submit answer'**
  String get submitAnswer;

  /// No description provided for @correctWellSpotted.
  ///
  /// In en, this message translates to:
  /// **'Correct — well spotted!'**
  String get correctWellSpotted;

  /// No description provided for @notQuiteRight.
  ///
  /// In en, this message translates to:
  /// **'Not quite right'**
  String get notQuiteRight;

  /// No description provided for @plusPoints.
  ///
  /// In en, this message translates to:
  /// **'+{points} points'**
  String plusPoints(int points);

  /// No description provided for @noPointsThisTime.
  ///
  /// In en, this message translates to:
  /// **'No points this time'**
  String get noPointsThisTime;

  /// No description provided for @practiceAttemptOnly.
  ///
  /// In en, this message translates to:
  /// **'Practice attempt — only your first attempt scores'**
  String get practiceAttemptOnly;

  /// No description provided for @correctAnswer.
  ///
  /// In en, this message translates to:
  /// **'Correct answer'**
  String get correctAnswer;

  /// No description provided for @whyItMatters.
  ///
  /// In en, this message translates to:
  /// **'Why it matters'**
  String get whyItMatters;

  /// No description provided for @noExplanation.
  ///
  /// In en, this message translates to:
  /// **'No explanation was provided for this scenario.'**
  String get noExplanation;

  /// No description provided for @practiceAgain.
  ///
  /// In en, this message translates to:
  /// **'Practice again'**
  String get practiceAgain;

  /// No description provided for @backToScenarios.
  ///
  /// In en, this message translates to:
  /// **'Back to scenarios'**
  String get backToScenarios;

  /// No description provided for @whatYouSee.
  ///
  /// In en, this message translates to:
  /// **'WHAT YOU SEE'**
  String get whatYouSee;

  /// No description provided for @stepObserve.
  ///
  /// In en, this message translates to:
  /// **'Observe'**
  String get stepObserve;

  /// No description provided for @stepAnswer.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get stepAnswer;

  /// No description provided for @stepExplain.
  ///
  /// In en, this message translates to:
  /// **'Explain'**
  String get stepExplain;

  /// No description provided for @stepResult.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get stepResult;

  /// No description provided for @filterCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get filterCorrect;

  /// No description provided for @filterIncorrect.
  ///
  /// In en, this message translates to:
  /// **'Incorrect'**
  String get filterIncorrect;

  /// No description provided for @filterFirstAttempts.
  ///
  /// In en, this message translates to:
  /// **'First attempts'**
  String get filterFirstAttempts;

  /// No description provided for @filterPractice.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get filterPractice;

  /// No description provided for @filterWithFeedback.
  ///
  /// In en, this message translates to:
  /// **'With feedback'**
  String get filterWithFeedback;

  /// No description provided for @safetyHistory.
  ///
  /// In en, this message translates to:
  /// **'Safety history'**
  String get safetyHistory;

  /// No description provided for @mySafetyHistory.
  ///
  /// In en, this message translates to:
  /// **'My safety history'**
  String get mySafetyHistory;

  /// No description provided for @workersHistory.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s history'**
  String workersHistory(String name);

  /// No description provided for @worker.
  ///
  /// In en, this message translates to:
  /// **'Worker'**
  String get worker;

  /// No description provided for @everyWorkersAnswers.
  ///
  /// In en, this message translates to:
  /// **'Every worker\'s answers, reasoning and feedback'**
  String get everyWorkersAnswers;

  /// No description provided for @answersReasoningFeedback.
  ///
  /// In en, this message translates to:
  /// **'Answers, reasoning and trainer feedback'**
  String get answersReasoningFeedback;

  /// No description provided for @couldNotLoadHistory.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the history'**
  String get couldNotLoadHistory;

  /// No description provided for @searchScenarioOrWorker.
  ///
  /// In en, this message translates to:
  /// **'Search by scenario or worker'**
  String get searchScenarioOrWorker;

  /// No description provided for @searchByScenario.
  ///
  /// In en, this message translates to:
  /// **'Search by scenario'**
  String get searchByScenario;

  /// No description provided for @noAttemptsYet.
  ///
  /// In en, this message translates to:
  /// **'No attempts yet'**
  String get noAttemptsYet;

  /// No description provided for @noAttemptsHint.
  ///
  /// In en, this message translates to:
  /// **'Completed scenarios will appear here with the answer and reasoning given.'**
  String get noAttemptsHint;

  /// No description provided for @nothingMatches.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches'**
  String get nothingMatches;

  /// No description provided for @loadOlderAttempts.
  ///
  /// In en, this message translates to:
  /// **'Load older attempts'**
  String get loadOlderAttempts;

  /// No description provided for @feedbackSentTo.
  ///
  /// In en, this message translates to:
  /// **'Feedback sent to {name}'**
  String feedbackSentTo(String name);

  /// No description provided for @couldNotSendFeedback.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the feedback.'**
  String get couldNotSendFeedback;

  /// No description provided for @pointsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} points'**
  String pointsCount(int count);

  /// No description provided for @passedFirstTry.
  ///
  /// In en, this message translates to:
  /// **'Passed first try'**
  String get passedFirstTry;

  /// No description provided for @attempts.
  ///
  /// In en, this message translates to:
  /// **'Attempts'**
  String get attempts;

  /// No description provided for @tookDuration.
  ///
  /// In en, this message translates to:
  /// **'took {duration}'**
  String tookDuration(String duration);

  /// No description provided for @answered.
  ///
  /// In en, this message translates to:
  /// **'Answered'**
  String get answered;

  /// No description provided for @reasoningLabel.
  ///
  /// In en, this message translates to:
  /// **'REASONING'**
  String get reasoningLabel;

  /// No description provided for @giveFeedback.
  ///
  /// In en, this message translates to:
  /// **'Give feedback'**
  String get giveFeedback;

  /// No description provided for @trainer.
  ///
  /// In en, this message translates to:
  /// **'Trainer'**
  String get trainer;

  /// No description provided for @feedbackFor.
  ///
  /// In en, this message translates to:
  /// **'Feedback for {name}'**
  String feedbackFor(String name);

  /// No description provided for @feedbackHint.
  ///
  /// In en, this message translates to:
  /// **'What did they get right, and what should they reconsider?'**
  String get feedbackHint;

  /// No description provided for @sendFeedback.
  ///
  /// In en, this message translates to:
  /// **'Send feedback'**
  String get sendFeedback;

  /// No description provided for @filterNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get filterNeedsAttention;

  /// No description provided for @filterNeverTrained.
  ///
  /// In en, this message translates to:
  /// **'Never trained'**
  String get filterNeverTrained;

  /// No description provided for @filterCleared.
  ///
  /// In en, this message translates to:
  /// **'Cleared'**
  String get filterCleared;

  /// No description provided for @workerSafetyStanding.
  ///
  /// In en, this message translates to:
  /// **'Worker safety standing'**
  String get workerSafetyStanding;

  /// No description provided for @workerSafetyStandingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review training results and decide next steps'**
  String get workerSafetyStandingSubtitle;

  /// No description provided for @reviewersOnly.
  ///
  /// In en, this message translates to:
  /// **'Reviewers only'**
  String get reviewersOnly;

  /// No description provided for @reviewersOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Only Main Admin and System Admin accounts can review worker standing.'**
  String get reviewersOnlyHint;

  /// No description provided for @couldNotLoadWorkers.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load workers'**
  String get couldNotLoadWorkers;

  /// No description provided for @buildingStats.
  ///
  /// In en, this message translates to:
  /// **'Building training statistics from past attempts…'**
  String get buildingStats;

  /// No description provided for @couldNotBuildStats.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t build training statistics from past attempts — some workers may show no results.'**
  String get couldNotBuildStats;

  /// No description provided for @couldNotLoadDeterminations.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load past decisions — the statuses below may be incomplete.'**
  String get couldNotLoadDeterminations;

  /// No description provided for @workers.
  ///
  /// In en, this message translates to:
  /// **'Workers'**
  String get workers;

  /// No description provided for @needAttention.
  ///
  /// In en, this message translates to:
  /// **'Need attention'**
  String get needAttention;

  /// No description provided for @searchWorkers.
  ///
  /// In en, this message translates to:
  /// **'Search workers'**
  String get searchWorkers;

  /// No description provided for @noWorkersYet.
  ///
  /// In en, this message translates to:
  /// **'No workers yet'**
  String get noWorkersYet;

  /// No description provided for @noWorkersHint.
  ///
  /// In en, this message translates to:
  /// **'Technicians and anyone who has trained will appear here.'**
  String get noWorkersHint;

  /// No description provided for @noWorkersMatch.
  ///
  /// In en, this message translates to:
  /// **'No workers match'**
  String get noWorkersMatch;

  /// No description provided for @determinationRecorded.
  ///
  /// In en, this message translates to:
  /// **'Decision recorded — {name} has been notified'**
  String determinationRecorded(String name);

  /// No description provided for @couldNotRecordDetermination.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t record the decision.'**
  String get couldNotRecordDetermination;

  /// No description provided for @unknownWorker.
  ///
  /// In en, this message translates to:
  /// **'Unknown worker'**
  String get unknownWorker;

  /// No description provided for @workerScoreLine.
  ///
  /// In en, this message translates to:
  /// **'{points} pts · {correct}/{attempted} first try'**
  String workerScoreLine(int points, int correct, int attempted);

  /// No description provided for @scenariosCompleted.
  ///
  /// In en, this message translates to:
  /// **'Scenarios completed'**
  String get scenariosCompleted;

  /// No description provided for @neverCompletedScenario.
  ///
  /// In en, this message translates to:
  /// **'Has never completed a scenario'**
  String get neverCompletedScenario;

  /// No description provided for @newAttemptsSinceReview.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new attempt since last review} other{{count} new attempts since last review}}'**
  String newAttemptsSinceReview(int count);

  /// No description provided for @reviewedByAnother.
  ///
  /// In en, this message translates to:
  /// **'Reviewed by another reviewer'**
  String get reviewedByAnother;

  /// No description provided for @review.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get review;

  /// No description provided for @reviewName.
  ///
  /// In en, this message translates to:
  /// **'Review {name}'**
  String reviewName(String name);

  /// No description provided for @reviewSummaryLine.
  ///
  /// In en, this message translates to:
  /// **'{correct}/{attempted} correct first try · {percent}% · {points} pts'**
  String reviewSummaryLine(int correct, int attempted, int percent, int points);

  /// No description provided for @noScenarioCompletedYet.
  ///
  /// In en, this message translates to:
  /// **'Has not completed any scenario yet'**
  String get noScenarioCompletedYet;

  /// No description provided for @nextStep.
  ///
  /// In en, this message translates to:
  /// **'NEXT STEP'**
  String get nextStep;

  /// No description provided for @fitToWork90.
  ///
  /// In en, this message translates to:
  /// **'Fit to work for 90 days'**
  String get fitToWork90;

  /// No description provided for @assignScenariosToRedo.
  ///
  /// In en, this message translates to:
  /// **'Assign scenarios to redo'**
  String get assignScenariosToRedo;

  /// No description provided for @handToSeniorAdmin.
  ///
  /// In en, this message translates to:
  /// **'Hand to a senior admin'**
  String get handToSeniorAdmin;

  /// No description provided for @clearanceValidUntil.
  ///
  /// In en, this message translates to:
  /// **'Clearance will be valid until {date}.'**
  String clearanceValidUntil(String date);

  /// No description provided for @clearingWithoutTraining.
  ///
  /// In en, this message translates to:
  /// **'This worker hasn\'t completed any scenario — clearing them isn\'t backed by any training results.'**
  String get clearingWithoutTraining;

  /// No description provided for @notesOptionalShown.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional — shown to the worker)'**
  String get notesOptionalShown;

  /// No description provided for @chooseNextStep.
  ///
  /// In en, this message translates to:
  /// **'Choose a next step'**
  String get chooseNextStep;

  /// No description provided for @saveDetermination.
  ///
  /// In en, this message translates to:
  /// **'Save decision'**
  String get saveDetermination;

  /// No description provided for @scenariosToRetrain.
  ///
  /// In en, this message translates to:
  /// **'Scenarios to retrain on'**
  String get scenariosToRetrain;

  /// No description provided for @dueDate.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String dueDate(String date);

  /// No description provided for @noActiveScenarios.
  ///
  /// In en, this message translates to:
  /// **'There are no active scenarios to assign.'**
  String get noActiveScenarios;

  /// No description provided for @neverAttempted.
  ///
  /// In en, this message translates to:
  /// **'Never attempted'**
  String get neverAttempted;

  /// No description provided for @passed.
  ///
  /// In en, this message translates to:
  /// **'Passed'**
  String get passed;

  /// No description provided for @missed.
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get missed;

  /// No description provided for @couldNotLoadReviewers.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load reviewers'**
  String get couldNotLoadReviewers;

  /// No description provided for @noOtherReviewer.
  ///
  /// In en, this message translates to:
  /// **'There\'s no other Main Admin or System Admin to escalate to.'**
  String get noOtherReviewer;

  /// No description provided for @escalateTo.
  ///
  /// In en, this message translates to:
  /// **'Escalate to'**
  String get escalateTo;

  /// No description provided for @visibleToWorkers.
  ///
  /// In en, this message translates to:
  /// **'Visible to workers'**
  String get visibleToWorkers;

  /// No description provided for @hidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get hidden;

  /// No description provided for @needsFixing.
  ///
  /// In en, this message translates to:
  /// **'Needs fixing'**
  String get needsFixing;

  /// No description provided for @scenarioNowVisible.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" is now visible to workers'**
  String scenarioNowVisible(String title);

  /// No description provided for @scenarioNowHidden.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" is hidden from workers'**
  String scenarioNowHidden(String title);

  /// No description provided for @couldNotUpdateScenario.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" couldn\'t be updated. Open it with Edit and save it to repair it.'**
  String couldNotUpdateScenario(String title);

  /// No description provided for @manageScenarios.
  ///
  /// In en, this message translates to:
  /// **'Manage scenarios'**
  String get manageScenarios;

  /// No description provided for @manageScenariosSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Edit, publish or hide safety scenarios'**
  String get manageScenariosSubtitle;

  /// No description provided for @authorScenario.
  ///
  /// In en, this message translates to:
  /// **'Author scenario'**
  String get authorScenario;

  /// No description provided for @scenarios.
  ///
  /// In en, this message translates to:
  /// **'Scenarios'**
  String get scenarios;

  /// No description provided for @visible.
  ///
  /// In en, this message translates to:
  /// **'Visible'**
  String get visible;

  /// No description provided for @hiddenSingular.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get hiddenSingular;

  /// No description provided for @noScenariosAuthorHint.
  ///
  /// In en, this message translates to:
  /// **'Tap \"Author scenario\" to create the first one.'**
  String get noScenariosAuthorHint;

  /// No description provided for @incomplete.
  ///
  /// In en, this message translates to:
  /// **'Incomplete'**
  String get incomplete;

  /// No description provided for @updatedOn.
  ///
  /// In en, this message translates to:
  /// **'Updated {date}'**
  String updatedOn(String date);

  /// No description provided for @editScenario.
  ///
  /// In en, this message translates to:
  /// **'Edit scenario'**
  String get editScenario;

  /// No description provided for @defaultReasoningPrompt.
  ///
  /// In en, this message translates to:
  /// **'Explain why this could lead to injury and how to prevent it.'**
  String get defaultReasoningPrompt;

  /// No description provided for @visualFallingObject.
  ///
  /// In en, this message translates to:
  /// **'Falling object'**
  String get visualFallingObject;

  /// No description provided for @visualMissingPpe.
  ///
  /// In en, this message translates to:
  /// **'Missing PPE'**
  String get visualMissingPpe;

  /// No description provided for @visualExposedWiring.
  ///
  /// In en, this message translates to:
  /// **'Exposed wiring'**
  String get visualExposedWiring;

  /// No description provided for @visualUnguardedEdge.
  ///
  /// In en, this message translates to:
  /// **'Unguarded edge'**
  String get visualUnguardedEdge;

  /// No description provided for @visualWetFloor.
  ///
  /// In en, this message translates to:
  /// **'Wet floor / slip'**
  String get visualWetFloor;

  /// No description provided for @visualUnsecuredLadder.
  ///
  /// In en, this message translates to:
  /// **'Unsecured ladder'**
  String get visualUnsecuredLadder;

  /// No description provided for @visualGeneric.
  ///
  /// In en, this message translates to:
  /// **'Generic hazard'**
  String get visualGeneric;

  /// No description provided for @couldNotLoadAnswerKey.
  ///
  /// In en, this message translates to:
  /// **'This scenario\'s answer key couldn\'t be loaded.'**
  String get couldNotLoadAnswerKey;

  /// No description provided for @unsupportedPhotoType.
  ///
  /// In en, this message translates to:
  /// **'This photo type isn\'t supported — please use a JPEG, PNG, WebP or GIF image.'**
  String get unsupportedPhotoType;

  /// No description provided for @photoTooLarge.
  ///
  /// In en, this message translates to:
  /// **'This photo is too large — the limit is {limit}.'**
  String photoTooLarge(String limit);

  /// No description provided for @lottieWebUnsafeTitle.
  ///
  /// In en, this message translates to:
  /// **'This animation won\'t play in web browsers'**
  String get lottieWebUnsafeTitle;

  /// No description provided for @lottieWebUnsafeBody.
  ///
  /// In en, this message translates to:
  /// **'This file uses a shape effect that web browsers can\'t display. It plays fine on Android and iOS, but anyone opening this scenario in a browser will see the standard illustration instead.'**
  String get lottieWebUnsafeBody;

  /// No description provided for @pickAnotherFile.
  ///
  /// In en, this message translates to:
  /// **'Pick another file'**
  String get pickAnotherFile;

  /// No description provided for @useItAnyway.
  ///
  /// In en, this message translates to:
  /// **'Use it anyway'**
  String get useItAnyway;

  /// No description provided for @animationTooLarge.
  ///
  /// In en, this message translates to:
  /// **'This animation is too large — the limit is {limit}.'**
  String animationTooLarge(String limit);

  /// No description provided for @selectAnimationImages.
  ///
  /// In en, this message translates to:
  /// **'Select this animation\'s images'**
  String get selectAnimationImages;

  /// No description provided for @selectAnimationImagesBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This animation uses a separate image file ({names}) that isn\'t inside the .json. Select it — usually in the \"images\" folder exported next to it — to add it to the animation.} other{This animation uses {count} separate image files ({names}) that aren\'t inside the .json. Select them — usually in the \"images\" folder exported next to it — to add them to the animation.}}'**
  String selectAnimationImagesBody(int count, Object names);

  /// No description provided for @selectImages.
  ///
  /// In en, this message translates to:
  /// **'Select images'**
  String get selectImages;

  /// No description provided for @missingImagesNotAdded.
  ///
  /// In en, this message translates to:
  /// **'Missing image(s): {names} — the animation was not added.'**
  String missingImagesNotAdded(String names);

  /// No description provided for @couldNotEmbedImages.
  ///
  /// In en, this message translates to:
  /// **'The images couldn\'t be added to this animation.'**
  String get couldNotEmbedImages;

  /// No description provided for @addTwoOptions.
  ///
  /// In en, this message translates to:
  /// **'Please add at least two answer options.'**
  String get addTwoOptions;

  /// No description provided for @correctOptionEmpty.
  ///
  /// In en, this message translates to:
  /// **'The option marked correct is empty — fill it in or mark a different option.'**
  String get correctOptionEmpty;

  /// No description provided for @onlyAdminsSaveScenarios.
  ///
  /// In en, this message translates to:
  /// **'Only admins can save scenarios.'**
  String get onlyAdminsSaveScenarios;

  /// No description provided for @couldNotSaveScenario.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the scenario.'**
  String get couldNotSaveScenario;

  /// No description provided for @sceneMedia.
  ///
  /// In en, this message translates to:
  /// **'Scene media'**
  String get sceneMedia;

  /// No description provided for @sceneMediaHint.
  ///
  /// In en, this message translates to:
  /// **'Optional — a built-in animated illustration is used otherwise'**
  String get sceneMediaHint;

  /// No description provided for @riveFile.
  ///
  /// In en, this message translates to:
  /// **'Rive (.riv)'**
  String get riveFile;

  /// No description provided for @lottieFile.
  ///
  /// In en, this message translates to:
  /// **'Lottie (.json)'**
  String get lottieFile;

  /// No description provided for @realPhoto.
  ///
  /// In en, this message translates to:
  /// **'Real photo'**
  String get realPhoto;

  /// No description provided for @photoSelected.
  ///
  /// In en, this message translates to:
  /// **'Photo selected'**
  String get photoSelected;

  /// No description provided for @fallbackIllustration.
  ///
  /// In en, this message translates to:
  /// **'Fallback illustration'**
  String get fallbackIllustration;

  /// No description provided for @scenarioDetails.
  ///
  /// In en, this message translates to:
  /// **'Scenario details'**
  String get scenarioDetails;

  /// No description provided for @scenarioTitleField.
  ///
  /// In en, this message translates to:
  /// **'Scenario title *'**
  String get scenarioTitleField;

  /// No description provided for @categoryField.
  ///
  /// In en, this message translates to:
  /// **'Category (e.g. Falling objects, PPE, Electrical)'**
  String get categoryField;

  /// No description provided for @sceneDescriptionField.
  ///
  /// In en, this message translates to:
  /// **'Scene description — what the worker sees *'**
  String get sceneDescriptionField;

  /// No description provided for @questionAndAnswers.
  ///
  /// In en, this message translates to:
  /// **'Question & answers'**
  String get questionAndAnswers;

  /// No description provided for @markCorrectHint.
  ///
  /// In en, this message translates to:
  /// **'Mark the correct answer with the round button'**
  String get markCorrectHint;

  /// No description provided for @questionField.
  ///
  /// In en, this message translates to:
  /// **'Question (e.g. \"What is the hazard here?\") *'**
  String get questionField;

  /// No description provided for @optionRequired.
  ///
  /// In en, this message translates to:
  /// **'Option {n} *'**
  String optionRequired(int n);

  /// No description provided for @optionOptional.
  ///
  /// In en, this message translates to:
  /// **'Option {n} (optional)'**
  String optionOptional(int n);

  /// No description provided for @correct.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get correct;

  /// No description provided for @feedbackAndScoring.
  ///
  /// In en, this message translates to:
  /// **'Feedback & scoring'**
  String get feedbackAndScoring;

  /// No description provided for @explanationField.
  ///
  /// In en, this message translates to:
  /// **'Explanation shown after answering *'**
  String get explanationField;

  /// No description provided for @reasoningPromptField.
  ///
  /// In en, this message translates to:
  /// **'Free-text reasoning prompt *'**
  String get reasoningPromptField;

  /// No description provided for @difficulty.
  ///
  /// In en, this message translates to:
  /// **'Difficulty'**
  String get difficulty;

  /// No description provided for @pointsRange.
  ///
  /// In en, this message translates to:
  /// **'Points (1–{max})'**
  String pointsRange(int max);

  /// No description provided for @loadingAnswerKey.
  ///
  /// In en, this message translates to:
  /// **'Loading this scenario\'s answer key…'**
  String get loadingAnswerKey;

  /// No description provided for @savingDisabledAnswerKey.
  ///
  /// In en, this message translates to:
  /// **'{error} Saving is turned off so the current answer isn\'t overwritten.'**
  String savingDisabledAnswerKey(String error);

  /// No description provided for @noAnswerKeyYet.
  ///
  /// In en, this message translates to:
  /// **'This scenario has no answer key yet. Mark the correct option and add an explanation, then save.'**
  String get noAnswerKeyYet;

  /// No description provided for @requiredFieldsNote.
  ///
  /// In en, this message translates to:
  /// **'Fields marked * are required'**
  String get requiredFieldsNote;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @publishScenario.
  ///
  /// In en, this message translates to:
  /// **'Publish scenario'**
  String get publishScenario;

  /// No description provided for @lottiePreviewUnavailableWeb.
  ///
  /// In en, this message translates to:
  /// **'Preview unavailable in the browser for this animation — it will play on Android and iOS.'**
  String get lottiePreviewUnavailableWeb;

  /// No description provided for @lottiePreviewFailed.
  ///
  /// In en, this message translates to:
  /// **'This file can\'t be previewed — is it a valid Lottie animation?'**
  String get lottiePreviewFailed;

  /// No description provided for @riveSelected.
  ///
  /// In en, this message translates to:
  /// **'{name} selected'**
  String riveSelected(String name);

  /// No description provided for @riveFileDefault.
  ///
  /// In en, this message translates to:
  /// **'Rive file'**
  String get riveFileDefault;

  /// No description provided for @previewAfterSaving.
  ///
  /// In en, this message translates to:
  /// **'Preview available after saving'**
  String get previewAfterSaving;

  /// No description provided for @invItemNoLongerExists.
  ///
  /// In en, this message translates to:
  /// **'This item no longer exists — it may have been removed.'**
  String get invItemNoLongerExists;

  /// No description provided for @invItemNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'This item isn\'t available right now — someone may have just checked it out or booked it.'**
  String get invItemNotAvailable;

  /// No description provided for @invItemHasPendingRequest.
  ///
  /// In en, this message translates to:
  /// **'This item already has a request waiting for a decision.'**
  String get invItemHasPendingRequest;

  /// No description provided for @invItemNotCheckedOut.
  ///
  /// In en, this message translates to:
  /// **'This item isn\'t checked out at the moment.'**
  String get invItemNotCheckedOut;

  /// No description provided for @invRequestNoLongerExists.
  ///
  /// In en, this message translates to:
  /// **'This request no longer exists.'**
  String get invRequestNoLongerExists;

  /// No description provided for @invRequestAlreadyHandled.
  ///
  /// In en, this message translates to:
  /// **'This request was already handled by someone else.'**
  String get invRequestAlreadyHandled;

  /// No description provided for @invItemChangedRefresh.
  ///
  /// In en, this message translates to:
  /// **'This item\'s record changed while you were working. Please refresh and try again.'**
  String get invItemChangedRefresh;

  /// No description provided for @invBookingNoLongerExists.
  ///
  /// In en, this message translates to:
  /// **'This booking no longer exists.'**
  String get invBookingNoLongerExists;

  /// No description provided for @invOnlyBookedPersonCanAcknowledge.
  ///
  /// In en, this message translates to:
  /// **'Only the person this item is booked for can confirm it arrived.'**
  String get invOnlyBookedPersonCanAcknowledge;

  /// No description provided for @invNotDriverDelivery.
  ///
  /// In en, this message translates to:
  /// **'This item isn\'t being delivered by a driver, so there\'s nothing to confirm.'**
  String get invNotDriverDelivery;

  /// No description provided for @invBookingNotScheduled.
  ///
  /// In en, this message translates to:
  /// **'This booking is no longer waiting to be collected.'**
  String get invBookingNotScheduled;

  /// No description provided for @invBookingNotActive.
  ///
  /// In en, this message translates to:
  /// **'This booking is no longer active.'**
  String get invBookingNotActive;

  /// No description provided for @invCannotRecordOwnReturn.
  ///
  /// In en, this message translates to:
  /// **'You can\'t record your own return — please ask another Main Admin or System Admin to do it.'**
  String get invCannotRecordOwnReturn;

  /// No description provided for @invOnlyScheduledCanBeCancelled.
  ///
  /// In en, this message translates to:
  /// **'Only a booking that hasn\'t been collected yet can be cancelled.'**
  String get invOnlyScheduledCanBeCancelled;

  /// No description provided for @invOverlapsMaintenance.
  ///
  /// In en, this message translates to:
  /// **'These dates overlap planned maintenance ({start} – {end}). Please choose different dates.'**
  String invOverlapsMaintenance(String start, String end);

  /// No description provided for @invOverlapsBooking.
  ///
  /// In en, this message translates to:
  /// **'These dates overlap an existing booking of \"{asset}\" ({who}, {start} – {end}). Please choose different dates.'**
  String invOverlapsBooking(String asset, String who, String start, String end);

  /// No description provided for @invCannotProcessForSelf.
  ///
  /// In en, this message translates to:
  /// **'You can\'t do this for yourself — please ask another Main Admin or System Admin to handle it.'**
  String get invCannotProcessForSelf;

  /// No description provided for @invCancelledForMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Cancelled for planned maintenance ({reason}).'**
  String invCancelledForMaintenance(String reason);

  /// No description provided for @invMaterialNoLongerExists.
  ///
  /// In en, this message translates to:
  /// **'This material no longer exists — it may have been removed.'**
  String get invMaterialNoLongerExists;

  /// No description provided for @invNotEnoughStock.
  ///
  /// In en, this message translates to:
  /// **'There isn\'t enough in storage: you asked for {requested}, but only {available} is left.'**
  String invNotEnoughStock(String requested, String available);

  /// No description provided for @invNoPermissionIssueFabrication.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to issue material for fabrication.'**
  String get invNoPermissionIssueFabrication;

  /// No description provided for @invNoPermissionSubmitScan.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to upload a fabrication form.'**
  String get invNoPermissionSubmitScan;

  /// No description provided for @invNoPermissionReviewFabrication.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to review this fabrication order.'**
  String get invNoPermissionReviewFabrication;

  /// No description provided for @invNoPermissionVerifyFabrication.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to verify this fabrication order.'**
  String get invNoPermissionVerifyFabrication;

  /// No description provided for @invFabricationOrderNoLongerExists.
  ///
  /// In en, this message translates to:
  /// **'This fabrication order no longer exists.'**
  String get invFabricationOrderNoLongerExists;

  /// No description provided for @invOrderNotAwaitingReview.
  ///
  /// In en, this message translates to:
  /// **'This order isn\'t waiting for an admin review.'**
  String get invOrderNotAwaitingReview;

  /// No description provided for @invOrderNotReadyForVerification.
  ///
  /// In en, this message translates to:
  /// **'This order isn\'t ready to be verified yet.'**
  String get invOrderNotReadyForVerification;

  /// No description provided for @invIssuedForFabricationNote.
  ///
  /// In en, this message translates to:
  /// **'Issued for fabrication — Form ID {id}'**
  String invIssuedForFabricationNote(String id);

  /// No description provided for @invFabricatorNote.
  ///
  /// In en, this message translates to:
  /// **' — Fabricator: {name}'**
  String invFabricatorNote(String name);

  /// No description provided for @invReceivedFromFabricationNote.
  ///
  /// In en, this message translates to:
  /// **'Received back from fabrication — Form ID {id}'**
  String invReceivedFromFabricationNote(String id);

  /// No description provided for @invQuantitiesFlaggedNote.
  ///
  /// In en, this message translates to:
  /// **' — quantities flagged for review'**
  String get invQuantitiesFlaggedNote;

  /// No description provided for @nInvCheckoutRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'📦 Checkout request'**
  String get nInvCheckoutRequestTitle;

  /// No description provided for @nInvCheckoutRequestBody.
  ///
  /// In en, this message translates to:
  /// **'{who} asked for \"{asset}\" from {start} to {end}.'**
  String nInvCheckoutRequestBody(
    String who,
    String asset,
    String start,
    String end,
  );

  /// No description provided for @nInvCheckoutRequestBodyProject.
  ///
  /// In en, this message translates to:
  /// **'{who} asked for \"{asset}\" from {start} to {end} for {project}.'**
  String nInvCheckoutRequestBodyProject(
    String who,
    String asset,
    String start,
    String end,
    String project,
  );

  /// No description provided for @nInvRequestRejectedTitle.
  ///
  /// In en, this message translates to:
  /// **'❌ Checkout request rejected'**
  String get nInvRequestRejectedTitle;

  /// No description provided for @nInvRequestRejectedAdminBody.
  ///
  /// In en, this message translates to:
  /// **'{admin} rejected {who}\'s request for \"{asset}\".'**
  String nInvRequestRejectedAdminBody(String admin, String who, String asset);

  /// No description provided for @nInvRequestRejectedAdminBodyReason.
  ///
  /// In en, this message translates to:
  /// **'{admin} rejected {who}\'s request for \"{asset}\": {reason}'**
  String nInvRequestRejectedAdminBodyReason(
    String admin,
    String who,
    String asset,
    String reason,
  );

  /// No description provided for @nInvRequestRejectedUserBody.
  ///
  /// In en, this message translates to:
  /// **'Your request for \"{asset}\" was rejected.'**
  String nInvRequestRejectedUserBody(String asset);

  /// No description provided for @nInvRequestRejectedUserBodyReason.
  ///
  /// In en, this message translates to:
  /// **'Your request for \"{asset}\" was rejected: {reason}'**
  String nInvRequestRejectedUserBodyReason(String asset, String reason);

  /// No description provided for @nInvCheckoutApprovedTitle.
  ///
  /// In en, this message translates to:
  /// **'✅ Checkout approved'**
  String get nInvCheckoutApprovedTitle;

  /// No description provided for @nInvCheckoutApprovedAdminBody.
  ///
  /// In en, this message translates to:
  /// **'{admin} approved {who}\'s request for \"{asset}\".'**
  String nInvCheckoutApprovedAdminBody(String admin, String who, String asset);

  /// No description provided for @nInvCheckoutApprovedNowBody.
  ///
  /// In en, this message translates to:
  /// **'Your request for \"{asset}\" was approved by {admin} — it\'s checked out to you now.'**
  String nInvCheckoutApprovedNowBody(String asset, String admin);

  /// No description provided for @nInvCheckoutApprovedLaterBody.
  ///
  /// In en, this message translates to:
  /// **'Your request for \"{asset}\" was approved by {admin} — booked for {date}.'**
  String nInvCheckoutApprovedLaterBody(String asset, String admin, String date);

  /// No description provided for @nInvOnTheWayTitle.
  ///
  /// In en, this message translates to:
  /// **'🚚 \"{asset}\" is on the way'**
  String nInvOnTheWayTitle(String asset);

  /// No description provided for @nInvOnTheWayBodyDriver.
  ///
  /// In en, this message translates to:
  /// **'{driver} is bringing \"{asset}\" to you — tap Acknowledge Receipt once it arrives.'**
  String nInvOnTheWayBodyDriver(String driver, String asset);

  /// No description provided for @nInvOnTheWayBody.
  ///
  /// In en, this message translates to:
  /// **'A driver is bringing \"{asset}\" to you — tap Acknowledge Receipt once it arrives.'**
  String nInvOnTheWayBody(String asset);

  /// No description provided for @nInvBookedTitle.
  ///
  /// In en, this message translates to:
  /// **'📅 \"{asset}\" has been booked'**
  String nInvBookedTitle(String asset);

  /// No description provided for @nInvBookedBody.
  ///
  /// In en, this message translates to:
  /// **'{who} has booked \"{asset}\" starting {date}. Please plan to return it in time.'**
  String nInvBookedBody(String who, String asset, String date);

  /// No description provided for @nInvDeliveryAckTitle.
  ///
  /// In en, this message translates to:
  /// **'📬 Delivery confirmed'**
  String get nInvDeliveryAckTitle;

  /// No description provided for @nInvDeliveryAckBody.
  ///
  /// In en, this message translates to:
  /// **'{who} confirmed receiving \"{asset}\".'**
  String nInvDeliveryAckBody(String who, String asset);

  /// No description provided for @nInvBookingCancelledMaintTitle.
  ///
  /// In en, this message translates to:
  /// **'🛠️ Booking cancelled — maintenance'**
  String get nInvBookingCancelledMaintTitle;

  /// No description provided for @nInvBookingCancelledMaintBody.
  ///
  /// In en, this message translates to:
  /// **'Your booked \"{asset}\" won\'t be available {start} – {end} because of planned maintenance ({reason}).'**
  String nInvBookingCancelledMaintBody(
    String asset,
    String start,
    String end,
    String reason,
  );

  /// No description provided for @nInvReturnForMaintTitle.
  ///
  /// In en, this message translates to:
  /// **'🛠️ Return needed for maintenance'**
  String get nInvReturnForMaintTitle;

  /// No description provided for @nInvReturnForMaintBody.
  ///
  /// In en, this message translates to:
  /// **'Please return \"{asset}\" by {date} — it\'s scheduled for maintenance ({reason}).'**
  String nInvReturnForMaintBody(String asset, String date, String reason);

  /// No description provided for @nInvReturnIncomingTitle.
  ///
  /// In en, this message translates to:
  /// **'📥 Return on the way'**
  String get nInvReturnIncomingTitle;

  /// No description provided for @nInvReturnIncomingBody.
  ///
  /// In en, this message translates to:
  /// **'{who} is returning \"{asset}\" — please record when it arrives.'**
  String nInvReturnIncomingBody(String who, String asset);

  /// No description provided for @nInvFabDiscrepancyTitle.
  ///
  /// In en, this message translates to:
  /// **'⚠️ Fabrication form: quantities don\'t match'**
  String get nInvFabDiscrepancyTitle;

  /// No description provided for @nInvFabReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'📄 Fabrication form ready to verify'**
  String get nInvFabReadyTitle;

  /// No description provided for @nInvFabUploadedDiscrepancyBody.
  ///
  /// In en, this message translates to:
  /// **'{who} uploaded the completed form for \"{material}\" — the quantities don\'t match, please review.'**
  String nInvFabUploadedDiscrepancyBody(String who, String material);

  /// No description provided for @nInvFabUploadedReadyBody.
  ///
  /// In en, this message translates to:
  /// **'{who} uploaded the completed form for \"{material}\" — ready to verify.'**
  String nInvFabUploadedReadyBody(String who, String material);

  /// No description provided for @nInvFabAwaitingReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'📄 Fabrication form waiting for review'**
  String get nInvFabAwaitingReviewTitle;

  /// No description provided for @nInvFabAwaitingReviewBody.
  ///
  /// In en, this message translates to:
  /// **'{who} uploaded the completed form for \"{material}\" — it needs an admin review.'**
  String nInvFabAwaitingReviewBody(String who, String material);

  /// No description provided for @nInvFabReviewedBody.
  ///
  /// In en, this message translates to:
  /// **'{who} reviewed the form for \"{material}\" — ready to verify.'**
  String nInvFabReviewedBody(String who, String material);

  /// No description provided for @invStatusAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get invStatusAvailable;

  /// No description provided for @invStatusCheckedOut.
  ///
  /// In en, this message translates to:
  /// **'Checked out'**
  String get invStatusCheckedOut;

  /// No description provided for @invStatusUnderMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Under maintenance'**
  String get invStatusUnderMaintenance;

  /// No description provided for @invStatusRetired.
  ///
  /// In en, this message translates to:
  /// **'Retired'**
  String get invStatusRetired;

  /// No description provided for @invConditionNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get invConditionNew;

  /// No description provided for @invConditionGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get invConditionGood;

  /// No description provided for @invConditionFair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get invConditionFair;

  /// No description provided for @invConditionDamaged.
  ///
  /// In en, this message translates to:
  /// **'Damaged'**
  String get invConditionDamaged;

  /// No description provided for @invConditionPartiallyDamaged.
  ///
  /// In en, this message translates to:
  /// **'Partially damaged'**
  String get invConditionPartiallyDamaged;

  /// No description provided for @invTypeAsset.
  ///
  /// In en, this message translates to:
  /// **'Asset'**
  String get invTypeAsset;

  /// No description provided for @invTypeTool.
  ///
  /// In en, this message translates to:
  /// **'Tool'**
  String get invTypeTool;

  /// No description provided for @invSourceLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get invSourceLocal;

  /// No description provided for @invSourceInternational.
  ///
  /// In en, this message translates to:
  /// **'International'**
  String get invSourceInternational;

  /// No description provided for @invCatHeavyEquipment.
  ///
  /// In en, this message translates to:
  /// **'Heavy equipment'**
  String get invCatHeavyEquipment;

  /// No description provided for @invCatVehicle.
  ///
  /// In en, this message translates to:
  /// **'Vehicle'**
  String get invCatVehicle;

  /// No description provided for @invCatItEquipment.
  ///
  /// In en, this message translates to:
  /// **'IT equipment / electronics'**
  String get invCatItEquipment;

  /// No description provided for @invCatOfficeEquipment.
  ///
  /// In en, this message translates to:
  /// **'Office equipment'**
  String get invCatOfficeEquipment;

  /// No description provided for @invCatFurniture.
  ///
  /// In en, this message translates to:
  /// **'Furniture'**
  String get invCatFurniture;

  /// No description provided for @invCatSafetyEquipment.
  ///
  /// In en, this message translates to:
  /// **'Safety equipment'**
  String get invCatSafetyEquipment;

  /// No description provided for @invCatPowerTool.
  ///
  /// In en, this message translates to:
  /// **'Power tool'**
  String get invCatPowerTool;

  /// No description provided for @invCatHandTool.
  ///
  /// In en, this message translates to:
  /// **'Hand tool'**
  String get invCatHandTool;

  /// No description provided for @invCatMeasuringTool.
  ///
  /// In en, this message translates to:
  /// **'Measuring tool'**
  String get invCatMeasuringTool;

  /// No description provided for @invCatSafetyTool.
  ///
  /// In en, this message translates to:
  /// **'Safety tool'**
  String get invCatSafetyTool;

  /// No description provided for @invCatCement.
  ///
  /// In en, this message translates to:
  /// **'Cement & aggregates'**
  String get invCatCement;

  /// No description provided for @invCatSteel.
  ///
  /// In en, this message translates to:
  /// **'Steel & metal'**
  String get invCatSteel;

  /// No description provided for @invCatElectrical.
  ///
  /// In en, this message translates to:
  /// **'Electrical'**
  String get invCatElectrical;

  /// No description provided for @invCatPlumbing.
  ///
  /// In en, this message translates to:
  /// **'Plumbing'**
  String get invCatPlumbing;

  /// No description provided for @invCatTimber.
  ///
  /// In en, this message translates to:
  /// **'Timber'**
  String get invCatTimber;

  /// No description provided for @invCatFinishes.
  ///
  /// In en, this message translates to:
  /// **'Finishes'**
  String get invCatFinishes;

  /// No description provided for @invCatOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get invCatOther;

  /// No description provided for @invBookingScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get invBookingScheduled;

  /// No description provided for @invBookingActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get invBookingActive;

  /// No description provided for @invBookingCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get invBookingCompleted;

  /// No description provided for @invBookingCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get invBookingCancelled;

  /// No description provided for @invRequestPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get invRequestPending;

  /// No description provided for @invRequestApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get invRequestApproved;

  /// No description provided for @invRequestRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get invRequestRejected;

  /// No description provided for @invFabIssued.
  ///
  /// In en, this message translates to:
  /// **'Issued'**
  String get invFabIssued;

  /// No description provided for @invFabPendingAdminReview.
  ///
  /// In en, this message translates to:
  /// **'Waiting for admin review'**
  String get invFabPendingAdminReview;

  /// No description provided for @invFabScanUploaded.
  ///
  /// In en, this message translates to:
  /// **'Ready to verify'**
  String get invFabScanUploaded;

  /// No description provided for @invFabVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get invFabVerified;

  /// No description provided for @invFabDiscrepancy.
  ///
  /// In en, this message translates to:
  /// **'Quantities don\'t match'**
  String get invFabDiscrepancy;

  /// No description provided for @invMovementReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get invMovementReceived;

  /// No description provided for @invDeliveryDirect.
  ///
  /// In en, this message translates to:
  /// **'Collected in person'**
  String get invDeliveryDirect;

  /// No description provided for @invDeliveryDriver.
  ///
  /// In en, this message translates to:
  /// **'Delivered by driver'**
  String get invDeliveryDriver;

  /// No description provided for @tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get tomorrow;

  /// No description provided for @inDays.
  ///
  /// In en, this message translates to:
  /// **'In {count} days'**
  String inDays(int count);

  /// No description provided for @daysAgoLong.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String daysAgoLong(int count);

  /// No description provided for @noUpcomingBookings.
  ///
  /// In en, this message translates to:
  /// **'No upcoming bookings or maintenance — free for the foreseeable future.'**
  String get noUpcomingBookings;

  /// No description provided for @maintenanceReason.
  ///
  /// In en, this message translates to:
  /// **'Maintenance: {reason}'**
  String maintenanceReason(String reason);

  /// No description provided for @checkedOutTo.
  ///
  /// In en, this message translates to:
  /// **'Checked out to {name}'**
  String checkedOutTo(String name);

  /// No description provided for @bookedFor.
  ///
  /// In en, this message translates to:
  /// **'Booked for {name}'**
  String bookedFor(String name);

  /// No description provided for @cancelMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Cancel maintenance'**
  String get cancelMaintenance;

  /// No description provided for @cancelBooking.
  ///
  /// In en, this message translates to:
  /// **'Cancel booking'**
  String get cancelBooking;

  /// No description provided for @noInventoryAccess.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have access to Inventory.'**
  String get noInventoryAccess;

  /// No description provided for @tabAssets.
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get tabAssets;

  /// No description provided for @tabTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get tabTools;

  /// No description provided for @tabMaterials.
  ///
  /// In en, this message translates to:
  /// **'Materials'**
  String get tabMaterials;

  /// No description provided for @noAssetsYet.
  ///
  /// In en, this message translates to:
  /// **'No assets yet'**
  String get noAssetsYet;

  /// No description provided for @noAssetsHint.
  ///
  /// In en, this message translates to:
  /// **'Assets you register will show up here.'**
  String get noAssetsHint;

  /// No description provided for @noToolsYet.
  ///
  /// In en, this message translates to:
  /// **'No tools yet'**
  String get noToolsYet;

  /// No description provided for @noToolsHint.
  ///
  /// In en, this message translates to:
  /// **'Tools you register will show up here.'**
  String get noToolsHint;

  /// No description provided for @addAsset.
  ///
  /// In en, this message translates to:
  /// **'Add asset'**
  String get addAsset;

  /// No description provided for @addTool.
  ///
  /// In en, this message translates to:
  /// **'Add tool'**
  String get addTool;

  /// No description provided for @addMaterial.
  ///
  /// In en, this message translates to:
  /// **'Add material'**
  String get addMaterial;

  /// No description provided for @fabricationOrders.
  ///
  /// In en, this message translates to:
  /// **'Fabrication orders'**
  String get fabricationOrders;

  /// No description provided for @pendingRequests.
  ///
  /// In en, this message translates to:
  /// **'Pending requests'**
  String get pendingRequests;

  /// No description provided for @accessStillSyncing.
  ///
  /// In en, this message translates to:
  /// **'Your access is still being set up'**
  String get accessStillSyncing;

  /// No description provided for @couldNotLoadItems.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this list'**
  String get couldNotLoadItems;

  /// No description provided for @accessStillSyncingHint.
  ///
  /// In en, this message translates to:
  /// **'This usually sorts itself out in a moment. Tap Try again.'**
  String get accessStillSyncingHint;

  /// No description provided for @searchAssets.
  ///
  /// In en, this message translates to:
  /// **'Search assets…'**
  String get searchAssets;

  /// No description provided for @searchTools.
  ///
  /// In en, this message translates to:
  /// **'Search tools…'**
  String get searchTools;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @requestPendingStatus.
  ///
  /// In en, this message translates to:
  /// **'Request pending'**
  String get requestPendingStatus;

  /// No description provided for @booked.
  ///
  /// In en, this message translates to:
  /// **'Booked'**
  String get booked;

  /// No description provided for @heldBy.
  ///
  /// In en, this message translates to:
  /// **'{category} • Held by {name}'**
  String heldBy(String category, String name);

  /// No description provided for @availableOfTotal.
  ///
  /// In en, this message translates to:
  /// **'{available} of {total} available'**
  String availableOfTotal(int available, int total);

  /// No description provided for @inStock.
  ///
  /// In en, this message translates to:
  /// **'In stock'**
  String get inStock;

  /// No description provided for @lowStock.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get lowStock;

  /// No description provided for @outOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get outOfStock;

  /// No description provided for @noMaterialsYet.
  ///
  /// In en, this message translates to:
  /// **'No materials yet'**
  String get noMaterialsYet;

  /// No description provided for @noMaterialsHint.
  ///
  /// In en, this message translates to:
  /// **'Materials you register will show up here.'**
  String get noMaterialsHint;

  /// No description provided for @searchMaterials.
  ///
  /// In en, this message translates to:
  /// **'Search materials…'**
  String get searchMaterials;

  /// No description provided for @source.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get source;

  /// No description provided for @stock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get stock;

  /// No description provided for @assetDetails.
  ///
  /// In en, this message translates to:
  /// **'Item details'**
  String get assetDetails;

  /// No description provided for @scheduleMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Schedule maintenance'**
  String get scheduleMaintenance;

  /// No description provided for @couldNotLoadAsset.
  ///
  /// In en, this message translates to:
  /// **'This item couldn\'t be loaded.'**
  String get couldNotLoadAsset;

  /// No description provided for @couldNotLoadBookings.
  ///
  /// In en, this message translates to:
  /// **'The bookings couldn\'t be loaded.'**
  String get couldNotLoadBookings;

  /// No description provided for @availability.
  ///
  /// In en, this message translates to:
  /// **'Availability'**
  String get availability;

  /// No description provided for @custodyHistory.
  ///
  /// In en, this message translates to:
  /// **'Custody history'**
  String get custodyHistory;

  /// No description provided for @couldNotLoadHistoryShort.
  ///
  /// In en, this message translates to:
  /// **'The history couldn\'t be loaded.'**
  String get couldNotLoadHistoryShort;

  /// No description provided for @noCustodyEvents.
  ///
  /// In en, this message translates to:
  /// **'No handovers recorded yet'**
  String get noCustodyEvents;

  /// No description provided for @serialNumber.
  ///
  /// In en, this message translates to:
  /// **'S/N: {serial}'**
  String serialNumber(String serial);

  /// No description provided for @conditionAtIntake.
  ///
  /// In en, this message translates to:
  /// **'Condition when registered: {condition}'**
  String conditionAtIntake(String condition);

  /// No description provided for @inMyPossession.
  ///
  /// In en, this message translates to:
  /// **'With me'**
  String get inMyPossession;

  /// No description provided for @heldByName.
  ///
  /// In en, this message translates to:
  /// **'Held by {name}'**
  String heldByName(String name);

  /// No description provided for @requestAwaitingReview.
  ///
  /// In en, this message translates to:
  /// **'A checkout request for this item is waiting for review.'**
  String get requestAwaitingReview;

  /// No description provided for @couldNotLoadRequest.
  ///
  /// In en, this message translates to:
  /// **'The request couldn\'t be loaded.'**
  String get couldNotLoadRequest;

  /// No description provided for @ownRequestAwaitingReview.
  ///
  /// In en, this message translates to:
  /// **'Your request is waiting for review by another Main Admin or System Admin.'**
  String get ownRequestAwaitingReview;

  /// No description provided for @reviewRequestFrom.
  ///
  /// In en, this message translates to:
  /// **'Review request from {name}'**
  String reviewRequestFrom(String name);

  /// No description provided for @recordCollectionFor.
  ///
  /// In en, this message translates to:
  /// **'Record collection — {name}'**
  String recordCollectionFor(String name);

  /// No description provided for @requestCheckout.
  ///
  /// In en, this message translates to:
  /// **'Request checkout'**
  String get requestCheckout;

  /// No description provided for @driverBringingToYou.
  ///
  /// In en, this message translates to:
  /// **'{driver} is bringing this to you.'**
  String driverBringingToYou(String driver);

  /// No description provided for @aDriver.
  ///
  /// In en, this message translates to:
  /// **'A driver'**
  String get aDriver;

  /// No description provided for @acknowledgeReceipt.
  ///
  /// In en, this message translates to:
  /// **'Confirm receipt'**
  String get acknowledgeReceipt;

  /// No description provided for @requestFutureDate.
  ///
  /// In en, this message translates to:
  /// **'Request a future date'**
  String get requestFutureDate;

  /// No description provided for @returnNotified.
  ///
  /// In en, this message translates to:
  /// **'Return notified — waiting for a Main Admin or System Admin to confirm it arrived.'**
  String get returnNotified;

  /// No description provided for @toolReturn.
  ///
  /// In en, this message translates to:
  /// **'Return tool'**
  String get toolReturn;

  /// No description provided for @assetReturn.
  ///
  /// In en, this message translates to:
  /// **'Return asset'**
  String get assetReturn;

  /// No description provided for @recordReturn.
  ///
  /// In en, this message translates to:
  /// **'Record return'**
  String get recordReturn;

  /// No description provided for @overrideRecordReturn.
  ///
  /// In en, this message translates to:
  /// **'Override & record return'**
  String get overrideRecordReturn;

  /// No description provided for @acknowledgeReceiptBody.
  ///
  /// In en, this message translates to:
  /// **'Confirm that \"{asset}\" has physically arrived with you. If you have the signed handover form, you can attach a photo of it too.'**
  String acknowledgeReceiptBody(String asset);

  /// No description provided for @attachFormPhoto.
  ///
  /// In en, this message translates to:
  /// **'Attach form photo'**
  String get attachFormPhoto;

  /// No description provided for @confirmReceipt.
  ///
  /// In en, this message translates to:
  /// **'Confirm receipt'**
  String get confirmReceipt;

  /// No description provided for @receiptAcknowledged.
  ///
  /// In en, this message translates to:
  /// **'Receipt confirmed.'**
  String get receiptAcknowledged;

  /// No description provided for @couldNotConfirmReceipt.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t confirm the receipt.'**
  String get couldNotConfirmReceipt;

  /// No description provided for @returnAssetTitle.
  ///
  /// In en, this message translates to:
  /// **'Return item'**
  String get returnAssetTitle;

  /// No description provided for @returnAssetMessage.
  ///
  /// In en, this message translates to:
  /// **'Let a Main Admin or System Admin know you\'re returning \"{asset}\"? They\'ll confirm it arrived and record its condition.'**
  String returnAssetMessage(String asset);

  /// No description provided for @notify.
  ///
  /// In en, this message translates to:
  /// **'Notify'**
  String get notify;

  /// No description provided for @returnNotifiedSnack.
  ///
  /// In en, this message translates to:
  /// **'An admin has been notified — they\'ll confirm the item arrived.'**
  String get returnNotifiedSnack;

  /// No description provided for @couldNotNotifyReturn.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the return notice.'**
  String get couldNotNotifyReturn;

  /// No description provided for @overrideReturnTitle.
  ///
  /// In en, this message translates to:
  /// **'Override return'**
  String get overrideReturnTitle;

  /// No description provided for @overrideReturnMessage.
  ///
  /// In en, this message translates to:
  /// **'{holder} hasn\'t said they\'re returning \"{asset}\" yet. Only continue if they can\'t be reached and you\'ve confirmed the item is physically back.'**
  String overrideReturnMessage(String holder, String asset);

  /// No description provided for @theCurrentHolder.
  ///
  /// In en, this message translates to:
  /// **'The current holder'**
  String get theCurrentHolder;

  /// No description provided for @overrideContinue.
  ///
  /// In en, this message translates to:
  /// **'Override & continue'**
  String get overrideContinue;

  /// No description provided for @cancelBookingMessage.
  ///
  /// In en, this message translates to:
  /// **'Cancel the booking for {name}?'**
  String cancelBookingMessage(String name);

  /// No description provided for @keep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get keep;

  /// No description provided for @couldNotCancelBooking.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t cancel the booking.'**
  String get couldNotCancelBooking;

  /// No description provided for @cancelMaintenanceMessage.
  ///
  /// In en, this message translates to:
  /// **'Cancel this maintenance window ({reason})?'**
  String cancelMaintenanceMessage(String reason);

  /// No description provided for @cancelWindow.
  ///
  /// In en, this message translates to:
  /// **'Cancel maintenance'**
  String get cancelWindow;

  /// No description provided for @couldNotCancelMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t cancel the maintenance.'**
  String get couldNotCancelMaintenance;

  /// No description provided for @checkedOutEvent.
  ///
  /// In en, this message translates to:
  /// **'Checked out'**
  String get checkedOutEvent;

  /// No description provided for @returnedEvent.
  ///
  /// In en, this message translates to:
  /// **'Returned'**
  String get returnedEvent;

  /// No description provided for @conditionLabel.
  ///
  /// In en, this message translates to:
  /// **'Condition: {condition}'**
  String conditionLabel(String condition);

  /// No description provided for @recordedBy.
  ///
  /// In en, this message translates to:
  /// **'Recorded by {name} ({role})'**
  String recordedBy(String name, String role);

  /// No description provided for @camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// No description provided for @editTool.
  ///
  /// In en, this message translates to:
  /// **'Edit tool'**
  String get editTool;

  /// No description provided for @editAsset.
  ///
  /// In en, this message translates to:
  /// **'Edit asset'**
  String get editAsset;

  /// No description provided for @confirmSaveAndAddUnits.
  ///
  /// In en, this message translates to:
  /// **'Save changes and register {count, plural, =1{1 more unit} other{{count} more units}} of \"{name}\"? Each new unit gets its own handover history.'**
  String confirmSaveAndAddUnits(int count, String name);

  /// No description provided for @confirmSaveChangesTo.
  ///
  /// In en, this message translates to:
  /// **'Save changes to \"{name}\"?'**
  String confirmSaveChangesTo(String name);

  /// No description provided for @confirmRegisterToolUnits.
  ///
  /// In en, this message translates to:
  /// **'Register {count} units of \"{name}\" ({category}) as new company tools? Each unit is tracked separately, with its own handover history.'**
  String confirmRegisterToolUnits(int count, String name, String category);

  /// No description provided for @confirmRegisterAssetUnits.
  ///
  /// In en, this message translates to:
  /// **'Register {count} units of \"{name}\" ({category}) as new company assets? Each unit is tracked separately, with its own handover history.'**
  String confirmRegisterAssetUnits(int count, String name, String category);

  /// No description provided for @confirmRegisterTool.
  ///
  /// In en, this message translates to:
  /// **'Register \"{name}\" ({category}) as a new company tool?'**
  String confirmRegisterTool(String name, String category);

  /// No description provided for @confirmRegisterAsset.
  ///
  /// In en, this message translates to:
  /// **'Register \"{name}\" ({category}) as a new company asset?'**
  String confirmRegisterAsset(String name, String category);

  /// No description provided for @changesSavedUnitsAdded.
  ///
  /// In en, this message translates to:
  /// **'Changes saved, {count, plural, =1{1 more unit} other{{count} more units}} added.'**
  String changesSavedUnitsAdded(int count);

  /// No description provided for @changesSaved.
  ///
  /// In en, this message translates to:
  /// **'Changes saved.'**
  String get changesSaved;

  /// No description provided for @unitsAdded.
  ///
  /// In en, this message translates to:
  /// **'{count} units added.'**
  String unitsAdded(int count);

  /// No description provided for @toolAdded.
  ///
  /// In en, this message translates to:
  /// **'Tool added.'**
  String get toolAdded;

  /// No description provided for @assetAdded.
  ///
  /// In en, this message translates to:
  /// **'Asset added.'**
  String get assetAdded;

  /// No description provided for @couldNotSaveItem.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save this item.'**
  String get couldNotSaveItem;

  /// No description provided for @photo.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photo;

  /// No description provided for @tapToAddPhoto.
  ///
  /// In en, this message translates to:
  /// **'Tap to add a photo (optional)'**
  String get tapToAddPhoto;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @toolName.
  ///
  /// In en, this message translates to:
  /// **'Tool name'**
  String get toolName;

  /// No description provided for @assetName.
  ///
  /// In en, this message translates to:
  /// **'Asset name'**
  String get assetName;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a name'**
  String get nameRequired;

  /// No description provided for @quantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantity;

  /// No description provided for @quantityUnitsHint.
  ///
  /// In en, this message translates to:
  /// **'Number of identical units to register'**
  String get quantityUnitsHint;

  /// No description provided for @wholeNumberOneOrMore.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number of 1 or more'**
  String get wholeNumberOneOrMore;

  /// No description provided for @addMoreUnitsOptional.
  ///
  /// In en, this message translates to:
  /// **'Add more units (optional)'**
  String get addMoreUnitsOptional;

  /// No description provided for @addMoreUnitsHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 2 more of this tool just arrived'**
  String get addMoreUnitsHint;

  /// No description provided for @zeroOrMore.
  ///
  /// In en, this message translates to:
  /// **'Enter 0 or more'**
  String get zeroOrMore;

  /// No description provided for @serialNumberOptional.
  ///
  /// In en, this message translates to:
  /// **'Serial number (optional)'**
  String get serialNumberOptional;

  /// No description provided for @descriptionOptional.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get descriptionOptional;

  /// No description provided for @conditionAtIntakeNewUnits.
  ///
  /// In en, this message translates to:
  /// **'Condition when registered (for new units)'**
  String get conditionAtIntakeNewUnits;

  /// No description provided for @conditionAtIntakeLabel.
  ///
  /// In en, this message translates to:
  /// **'Condition when registered'**
  String get conditionAtIntakeLabel;

  /// No description provided for @classification.
  ///
  /// In en, this message translates to:
  /// **'Classification'**
  String get classification;

  /// No description provided for @toolCategoryHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Power tool, IT equipment / electronics'**
  String get toolCategoryHint;

  /// No description provided for @assetCategoryHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Heavy equipment, Vehicle'**
  String get assetCategoryHint;

  /// No description provided for @categoryRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a category'**
  String get categoryRequired;

  /// No description provided for @unitBags.
  ///
  /// In en, this message translates to:
  /// **'bags'**
  String get unitBags;

  /// No description provided for @unitPieces.
  ///
  /// In en, this message translates to:
  /// **'pieces'**
  String get unitPieces;

  /// No description provided for @unitTonnes.
  ///
  /// In en, this message translates to:
  /// **'tonnes'**
  String get unitTonnes;

  /// No description provided for @unitLitres.
  ///
  /// In en, this message translates to:
  /// **'litres'**
  String get unitLitres;

  /// No description provided for @unitRolls.
  ///
  /// In en, this message translates to:
  /// **'rolls'**
  String get unitRolls;

  /// No description provided for @editMaterial.
  ///
  /// In en, this message translates to:
  /// **'Edit material'**
  String get editMaterial;

  /// No description provided for @confirmRegisterMaterial.
  ///
  /// In en, this message translates to:
  /// **'Register \"{name}\" ({category}) as a new material in the stock register?'**
  String confirmRegisterMaterial(String name, String category);

  /// No description provided for @materialAdded.
  ///
  /// In en, this message translates to:
  /// **'Material added.'**
  String get materialAdded;

  /// No description provided for @couldNotSaveMaterial.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save this material.'**
  String get couldNotSaveMaterial;

  /// No description provided for @materialName.
  ///
  /// In en, this message translates to:
  /// **'Material name'**
  String get materialName;

  /// No description provided for @materialCategoryHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Cement & aggregates, Steel & metal'**
  String get materialCategoryHint;

  /// No description provided for @unit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get unit;

  /// No description provided for @initialQuantity.
  ///
  /// In en, this message translates to:
  /// **'Starting quantity'**
  String get initialQuantity;

  /// No description provided for @reorderLevel.
  ///
  /// In en, this message translates to:
  /// **'Reorder level'**
  String get reorderLevel;

  /// No description provided for @reorderLevelHint.
  ///
  /// In en, this message translates to:
  /// **'Low-stock warning level'**
  String get reorderLevelHint;

  /// No description provided for @quantityEditNote.
  ///
  /// In en, this message translates to:
  /// **'The quantity in storage ({quantity} {unit}) can only change by recording a receipt or issue — not by editing.'**
  String quantityEditNote(String quantity, String unit);

  /// No description provided for @couldNotLoadUsers.
  ///
  /// In en, this message translates to:
  /// **'The list of people couldn\'t be loaded.'**
  String get couldNotLoadUsers;

  /// No description provided for @couldNotLoadProjects.
  ///
  /// In en, this message translates to:
  /// **'The list of projects couldn\'t be loaded.'**
  String get couldNotLoadProjects;

  /// No description provided for @selectWhoBookingFor.
  ///
  /// In en, this message translates to:
  /// **'Please choose who this booking is for.'**
  String get selectWhoBookingFor;

  /// No description provided for @checkOutNow.
  ///
  /// In en, this message translates to:
  /// **'Check out now'**
  String get checkOutNow;

  /// No description provided for @bookTool.
  ///
  /// In en, this message translates to:
  /// **'Book tool'**
  String get bookTool;

  /// No description provided for @bookAsset.
  ///
  /// In en, this message translates to:
  /// **'Book asset'**
  String get bookAsset;

  /// No description provided for @confirmCheckOutNow.
  ///
  /// In en, this message translates to:
  /// **'Check out \"{asset}\" to {who} now?'**
  String confirmCheckOutNow(String asset, String who);

  /// No description provided for @confirmCheckOutNowProject.
  ///
  /// In en, this message translates to:
  /// **'Check out \"{asset}\" to {who} now for project {project}?'**
  String confirmCheckOutNowProject(String asset, String who, String project);

  /// No description provided for @confirmBookFor.
  ///
  /// In en, this message translates to:
  /// **'Book \"{asset}\" for {who} from {start} to {end}?'**
  String confirmBookFor(String asset, String who, String start, String end);

  /// No description provided for @toolCheckedOut.
  ///
  /// In en, this message translates to:
  /// **'Tool checked out.'**
  String get toolCheckedOut;

  /// No description provided for @assetCheckedOut.
  ///
  /// In en, this message translates to:
  /// **'Asset checked out.'**
  String get assetCheckedOut;

  /// No description provided for @bookingCreated.
  ///
  /// In en, this message translates to:
  /// **'Booking created.'**
  String get bookingCreated;

  /// No description provided for @couldNotCreateBooking.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the booking.'**
  String get couldNotCreateBooking;

  /// No description provided for @handoverForm.
  ///
  /// In en, this message translates to:
  /// **'Handover form'**
  String get handoverForm;

  /// No description provided for @handoverFormBody.
  ///
  /// In en, this message translates to:
  /// **'Download the printable handover form for the driver to sign at pickup, and for {who} to sign on receipt.'**
  String handoverFormBody(String who);

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @downloadForm.
  ///
  /// In en, this message translates to:
  /// **'Download form'**
  String get downloadForm;

  /// No description provided for @bookingWindow.
  ///
  /// In en, this message translates to:
  /// **'Booking dates'**
  String get bookingWindow;

  /// No description provided for @startsTodayHint.
  ///
  /// In en, this message translates to:
  /// **'Starts today — the item is handed over right away'**
  String get startsTodayHint;

  /// No description provided for @futureWindowHint.
  ///
  /// In en, this message translates to:
  /// **'Future dates — the item stays available until it is collected on the day'**
  String get futureWindowHint;

  /// No description provided for @fromDate.
  ///
  /// In en, this message translates to:
  /// **'From {date}'**
  String fromDate(String date);

  /// No description provided for @toDate.
  ///
  /// In en, this message translates to:
  /// **'To {date}'**
  String toDate(String date);

  /// No description provided for @handover.
  ///
  /// In en, this message translates to:
  /// **'Handover'**
  String get handover;

  /// No description provided for @deliveryMethod.
  ///
  /// In en, this message translates to:
  /// **'Delivery method'**
  String get deliveryMethod;

  /// No description provided for @directHandoff.
  ///
  /// In en, this message translates to:
  /// **'Direct handoff'**
  String get directHandoff;

  /// No description provided for @viaDriver.
  ///
  /// In en, this message translates to:
  /// **'Via driver/transporter'**
  String get viaDriver;

  /// No description provided for @driverName.
  ///
  /// In en, this message translates to:
  /// **'Driver / transporter name'**
  String get driverName;

  /// No description provided for @driverNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. James, company driver'**
  String get driverNameHint;

  /// No description provided for @recipientMustAcknowledge.
  ///
  /// In en, this message translates to:
  /// **'The recipient will need to tap \"Confirm receipt\" once it arrives on site.'**
  String get recipientMustAcknowledge;

  /// No description provided for @conditionAndPhotos.
  ///
  /// In en, this message translates to:
  /// **'Condition & photos'**
  String get conditionAndPhotos;

  /// No description provided for @capturedAtCollection.
  ///
  /// In en, this message translates to:
  /// **'Recorded when the item is actually collected'**
  String get capturedAtCollection;

  /// No description provided for @conditionNotes.
  ///
  /// In en, this message translates to:
  /// **'Condition notes'**
  String get conditionNotes;

  /// No description provided for @conditionAtHandover.
  ///
  /// In en, this message translates to:
  /// **'Condition at handover'**
  String get conditionAtHandover;

  /// No description provided for @addPhotos.
  ///
  /// In en, this message translates to:
  /// **'Add photos'**
  String get addPhotos;

  /// No description provided for @checkOut.
  ///
  /// In en, this message translates to:
  /// **'Check out'**
  String get checkOut;

  /// No description provided for @bookFor.
  ///
  /// In en, this message translates to:
  /// **'Book for'**
  String get bookFor;

  /// No description provided for @bookForMyself.
  ///
  /// In en, this message translates to:
  /// **'Book for myself'**
  String get bookForMyself;

  /// No description provided for @projectOptionalStorage.
  ///
  /// In en, this message translates to:
  /// **'Project (optional — leave blank for company storage)'**
  String get projectOptionalStorage;

  /// No description provided for @overlapsBookingFor.
  ///
  /// In en, this message translates to:
  /// **'These dates overlap a booking for {who} ({start} – {end}).'**
  String overlapsBookingFor(String who, String start, String end);

  /// No description provided for @overlapsMaintenanceShort.
  ///
  /// In en, this message translates to:
  /// **'These dates overlap planned maintenance ({start} – {end}).'**
  String overlapsMaintenanceShort(String start, String end);

  /// No description provided for @confirmSendCheckoutRequest.
  ///
  /// In en, this message translates to:
  /// **'Send a checkout request for \"{asset}\" ({start} – {end}) to a Main Admin or System Admin for approval?'**
  String confirmSendCheckoutRequest(String asset, String start, String end);

  /// No description provided for @sendRequest.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get sendRequest;

  /// No description provided for @requestSentWaiting.
  ///
  /// In en, this message translates to:
  /// **'Request sent — waiting for a Main Admin or System Admin to approve it.'**
  String get requestSentWaiting;

  /// No description provided for @couldNotSendRequest.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the request.'**
  String get couldNotSendRequest;

  /// No description provided for @noPermissionRequestCheckout.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to request a checkout.'**
  String get noPermissionRequestCheckout;

  /// No description provided for @bookingWindowHint.
  ///
  /// In en, this message translates to:
  /// **'When you need it and when you\'ll return it'**
  String get bookingWindowHint;

  /// No description provided for @alreadyOnCalendar.
  ///
  /// In en, this message translates to:
  /// **'Already on the calendar'**
  String get alreadyOnCalendar;

  /// No description provided for @requestDetails.
  ///
  /// In en, this message translates to:
  /// **'Request details'**
  String get requestDetails;

  /// No description provided for @reasonForCheckout.
  ///
  /// In en, this message translates to:
  /// **'Reason for checkout'**
  String get reasonForCheckout;

  /// No description provided for @reasonForCheckoutHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Needed for site work at …'**
  String get reasonForCheckoutHint;

  /// No description provided for @reasonRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a reason'**
  String get reasonRequired;

  /// No description provided for @projectOptional.
  ///
  /// In en, this message translates to:
  /// **'Project (optional)'**
  String get projectOptional;

  /// No description provided for @approveAndCheckOut.
  ///
  /// In en, this message translates to:
  /// **'Approve & check out'**
  String get approveAndCheckOut;

  /// No description provided for @confirmApproveRequest.
  ///
  /// In en, this message translates to:
  /// **'Approve {who}\'s request for \"{asset}\"? This checks the item out to them straight away.'**
  String confirmApproveRequest(String who, String asset);

  /// No description provided for @approvedCheckedOut.
  ///
  /// In en, this message translates to:
  /// **'Approved — the item is checked out.'**
  String get approvedCheckedOut;

  /// No description provided for @couldNotApprove.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t approve the request.'**
  String get couldNotApprove;

  /// No description provided for @rejectRequest.
  ///
  /// In en, this message translates to:
  /// **'Reject request'**
  String get rejectRequest;

  /// No description provided for @reasonOptional.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get reasonOptional;

  /// No description provided for @requestRejected.
  ///
  /// In en, this message translates to:
  /// **'Request rejected.'**
  String get requestRejected;

  /// No description provided for @couldNotReject.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reject the request.'**
  String get couldNotReject;

  /// No description provided for @reviewRequest.
  ///
  /// In en, this message translates to:
  /// **'Review request'**
  String get reviewRequest;

  /// No description provided for @requestedBy.
  ///
  /// In en, this message translates to:
  /// **'Requested by'**
  String get requestedBy;

  /// No description provided for @project.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get project;

  /// No description provided for @reason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get reason;

  /// No description provided for @approveConditionAtHandover.
  ///
  /// In en, this message translates to:
  /// **'Approve — condition at handover'**
  String get approveConditionAtHandover;

  /// No description provided for @approveChecksOutNote.
  ///
  /// In en, this message translates to:
  /// **'Filling this in and tapping Approve checks the item out to {who} straight away.'**
  String approveChecksOutNote(String who);

  /// No description provided for @delivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get delivery;

  /// No description provided for @driverNameShort.
  ///
  /// In en, this message translates to:
  /// **'Driver name'**
  String get driverNameShort;

  /// No description provided for @recordCollection.
  ///
  /// In en, this message translates to:
  /// **'Record collection'**
  String get recordCollection;

  /// No description provided for @storage.
  ///
  /// In en, this message translates to:
  /// **'storage'**
  String get storage;

  /// No description provided for @confirmHandoverNow.
  ///
  /// In en, this message translates to:
  /// **'Confirm that \"{asset}\" is being handed over to {who} now?'**
  String confirmHandoverNow(String asset, String who);

  /// No description provided for @confirmRecordReturnFrom.
  ///
  /// In en, this message translates to:
  /// **'Record the return of \"{asset}\" from {who}?'**
  String confirmRecordReturnFrom(String asset, String who);

  /// No description provided for @collectionRecorded.
  ///
  /// In en, this message translates to:
  /// **'Collection recorded.'**
  String get collectionRecorded;

  /// No description provided for @returnRecorded.
  ///
  /// In en, this message translates to:
  /// **'Return recorded.'**
  String get returnRecorded;

  /// No description provided for @couldNotRecord.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save this record.'**
  String get couldNotRecord;

  /// No description provided for @noPermissionRecord.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to record this.'**
  String get noPermissionRecord;

  /// No description provided for @returnTitle.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get returnTitle;

  /// No description provided for @handingOverTo.
  ///
  /// In en, this message translates to:
  /// **'Handing over to'**
  String get handingOverTo;

  /// No description provided for @returningFrom.
  ///
  /// In en, this message translates to:
  /// **'Returning from'**
  String get returningFrom;

  /// No description provided for @conditionRating.
  ///
  /// In en, this message translates to:
  /// **'Condition'**
  String get conditionRating;

  /// No description provided for @conditionAtReturn.
  ///
  /// In en, this message translates to:
  /// **'Condition at return'**
  String get conditionAtReturn;

  /// No description provided for @confirmCollection.
  ///
  /// In en, this message translates to:
  /// **'Confirm collection'**
  String get confirmCollection;

  /// No description provided for @enterValidQuantity.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid quantity.'**
  String get enterValidQuantity;

  /// No description provided for @onlyRemainingInStorage.
  ///
  /// In en, this message translates to:
  /// **'Only {quantity} {unit} left in storage.'**
  String onlyRemainingInStorage(String quantity, String unit);

  /// No description provided for @recordReceipt.
  ///
  /// In en, this message translates to:
  /// **'Record receipt'**
  String get recordReceipt;

  /// No description provided for @recordIssue.
  ///
  /// In en, this message translates to:
  /// **'Record issue'**
  String get recordIssue;

  /// No description provided for @confirmRecordReceipt.
  ///
  /// In en, this message translates to:
  /// **'Record receipt of {quantity} {unit} of \"{material}\" into storage?'**
  String confirmRecordReceipt(String quantity, String unit, String material);

  /// No description provided for @confirmIssue.
  ///
  /// In en, this message translates to:
  /// **'Issue {quantity} {unit} of \"{material}\"?'**
  String confirmIssue(String quantity, String unit, String material);

  /// No description provided for @confirmIssueToProject.
  ///
  /// In en, this message translates to:
  /// **'Issue {quantity} {unit} of \"{material}\" to project {project}?'**
  String confirmIssueToProject(
    String quantity,
    String unit,
    String material,
    String project,
  );

  /// No description provided for @receiptRecorded.
  ///
  /// In en, this message translates to:
  /// **'Receipt recorded.'**
  String get receiptRecorded;

  /// No description provided for @issueRecorded.
  ///
  /// In en, this message translates to:
  /// **'Issue recorded.'**
  String get issueRecorded;

  /// No description provided for @noPermissionMaterialMovement.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to record material movements.'**
  String get noPermissionMaterialMovement;

  /// No description provided for @currentlyInStorage.
  ///
  /// In en, this message translates to:
  /// **'{quantity} {unit} currently in storage'**
  String currentlyInStorage(String quantity, String unit);

  /// No description provided for @receipt.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get receipt;

  /// No description provided for @issue.
  ///
  /// In en, this message translates to:
  /// **'Issue'**
  String get issue;

  /// No description provided for @quantityWithUnit.
  ///
  /// In en, this message translates to:
  /// **'Quantity ({unit})'**
  String quantityWithUnit(String unit);

  /// No description provided for @quantityRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a quantity'**
  String get quantityRequired;

  /// No description provided for @conditionOnReceipt.
  ///
  /// In en, this message translates to:
  /// **'Condition on receipt'**
  String get conditionOnReceipt;

  /// No description provided for @verifiedAtPortBy.
  ///
  /// In en, this message translates to:
  /// **'Checked at the port of arrival by'**
  String get verifiedAtPortBy;

  /// No description provided for @verifiedAtPortHint.
  ///
  /// In en, this message translates to:
  /// **'Name of the person who checked this shipment'**
  String get verifiedAtPortHint;

  /// No description provided for @receivedIntoStorageBy.
  ///
  /// In en, this message translates to:
  /// **'Received into storage by'**
  String get receivedIntoStorageBy;

  /// No description provided for @receivedIntoStorageHint.
  ///
  /// In en, this message translates to:
  /// **'Name of the person who signed for it'**
  String get receivedIntoStorageHint;

  /// No description provided for @notesAndPhotos.
  ///
  /// In en, this message translates to:
  /// **'Notes & photos'**
  String get notesAndPhotos;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @receiptNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Condition / state on receipt'**
  String get receiptNotesHint;

  /// No description provided for @issueNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Reason / extra notes'**
  String get issueNotesHint;

  /// No description provided for @destinationProject.
  ///
  /// In en, this message translates to:
  /// **'Destination project'**
  String get destinationProject;

  /// No description provided for @materialDetails.
  ///
  /// In en, this message translates to:
  /// **'Material details'**
  String get materialDetails;

  /// No description provided for @couldNotLoadMaterial.
  ///
  /// In en, this message translates to:
  /// **'This material couldn\'t be loaded.'**
  String get couldNotLoadMaterial;

  /// No description provided for @materialNotFound.
  ///
  /// In en, this message translates to:
  /// **'Material not found.'**
  String get materialNotFound;

  /// No description provided for @movementHistory.
  ///
  /// In en, this message translates to:
  /// **'Movement history'**
  String get movementHistory;

  /// No description provided for @noMovementsYet.
  ///
  /// In en, this message translates to:
  /// **'No movements yet'**
  String get noMovementsYet;

  /// No description provided for @inStorageQuantity.
  ///
  /// In en, this message translates to:
  /// **'{quantity} {unit} in storage'**
  String inStorageQuantity(String quantity, String unit);

  /// No description provided for @receivedQuantity.
  ///
  /// In en, this message translates to:
  /// **'Received: {quantity} {unit}'**
  String receivedQuantity(String quantity, String unit);

  /// No description provided for @issuedQuantity.
  ///
  /// In en, this message translates to:
  /// **'Issued: {quantity} {unit}'**
  String issuedQuantity(String quantity, String unit);

  /// No description provided for @toProject.
  ///
  /// In en, this message translates to:
  /// **'To project: {project}'**
  String toProject(String project);

  /// No description provided for @verifiedAtPortByName.
  ///
  /// In en, this message translates to:
  /// **'Checked at port by: {name}'**
  String verifiedAtPortByName(String name);

  /// No description provided for @receivedIntoStorageByName.
  ///
  /// In en, this message translates to:
  /// **'Received into storage by: {name}'**
  String receivedIntoStorageByName(String name);

  /// No description provided for @newOrder.
  ///
  /// In en, this message translates to:
  /// **'New order'**
  String get newOrder;

  /// No description provided for @couldNotLoadOrders.
  ///
  /// In en, this message translates to:
  /// **'The orders couldn\'t be loaded.'**
  String get couldNotLoadOrders;

  /// No description provided for @noFabricationOrdersFor.
  ///
  /// In en, this message translates to:
  /// **'No fabrication orders yet for \"{material}\"'**
  String noFabricationOrdersFor(String material);

  /// No description provided for @fabStatusWithDriver.
  ///
  /// In en, this message translates to:
  /// **'With driver — on the way to fabrication'**
  String get fabStatusWithDriver;

  /// No description provided for @quantityIssued.
  ///
  /// In en, this message translates to:
  /// **'{quantity} {unit} issued'**
  String quantityIssued(String quantity, String unit);

  /// No description provided for @formId.
  ///
  /// In en, this message translates to:
  /// **'Form ID: {id}'**
  String formId(String id);

  /// No description provided for @issuedByOn.
  ///
  /// In en, this message translates to:
  /// **'Issued by {name} on {date}'**
  String issuedByOn(String name, String date);

  /// No description provided for @destination.
  ///
  /// In en, this message translates to:
  /// **'Destination: {project}'**
  String destination(String project);

  /// No description provided for @fabricatorWithCondition.
  ///
  /// In en, this message translates to:
  /// **'Fabricator: {name} ({condition})'**
  String fabricatorWithCondition(String name, String condition);

  /// No description provided for @receivedByQuantity.
  ///
  /// In en, this message translates to:
  /// **'Received by {name}: {quantity} {unit}'**
  String receivedByQuantity(String name, String quantity, String unit);

  /// No description provided for @reviewedBy.
  ///
  /// In en, this message translates to:
  /// **'Reviewed by {name}'**
  String reviewedBy(String name);

  /// No description provided for @quantitiesDontReconcile.
  ///
  /// In en, this message translates to:
  /// **'⚠ The quantities don\'t fully match — check before verifying'**
  String get quantitiesDontReconcile;

  /// No description provided for @tapToUploadScan.
  ///
  /// In en, this message translates to:
  /// **'Tap to upload the completed scanned form'**
  String get tapToUploadScan;

  /// No description provided for @markReviewed.
  ///
  /// In en, this message translates to:
  /// **'Mark reviewed'**
  String get markReviewed;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @flagDiscrepancy.
  ///
  /// In en, this message translates to:
  /// **'Flag mismatch'**
  String get flagDiscrepancy;

  /// No description provided for @confirmMarkReviewed.
  ///
  /// In en, this message translates to:
  /// **'Confirm you\'ve checked the scanned form for \"{material}\"? It will then be ready for a System Admin to verify.'**
  String confirmMarkReviewed(String material);

  /// No description provided for @couldNotMarkReviewed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t mark it as reviewed.'**
  String get couldNotMarkReviewed;

  /// No description provided for @verifyOrder.
  ///
  /// In en, this message translates to:
  /// **'Verify order'**
  String get verifyOrder;

  /// No description provided for @confirmFlagDiscrepancy.
  ///
  /// In en, this message translates to:
  /// **'Flag \"{material}\" as a quantity mismatch for follow-up?'**
  String confirmFlagDiscrepancy(String material);

  /// No description provided for @confirmVerifyOrder.
  ///
  /// In en, this message translates to:
  /// **'Confirm \"{material}\" is verified and the quantities match?'**
  String confirmVerifyOrder(String material);

  /// No description provided for @couldNotVerify.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t verify the order.'**
  String get couldNotVerify;

  /// No description provided for @traceHandedToDriver.
  ///
  /// In en, this message translates to:
  /// **'Handed to the driver (movement recorded)'**
  String get traceHandedToDriver;

  /// No description provided for @traceReceivedBack.
  ///
  /// In en, this message translates to:
  /// **'Received back — form uploaded (movement recorded)'**
  String get traceReceivedBack;

  /// No description provided for @traceReceivedBackBy.
  ///
  /// In en, this message translates to:
  /// **'Received back — form uploaded by {name} (movement recorded)'**
  String traceReceivedBackBy(String name);

  /// No description provided for @traceDiscrepancyFlagged.
  ///
  /// In en, this message translates to:
  /// **'Mismatch flagged'**
  String get traceDiscrepancyFlagged;

  /// No description provided for @pendingFabricationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a scanned form, or flagged with a mismatch'**
  String get pendingFabricationSubtitle;

  /// No description provided for @nothingNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs attention'**
  String get nothingNeedsAttention;

  /// No description provided for @newFabricationOrdersHint.
  ///
  /// In en, this message translates to:
  /// **'New fabrication orders will show up here.'**
  String get newFabricationOrdersHint;

  /// No description provided for @issuedByName.
  ///
  /// In en, this message translates to:
  /// **'Issued by {name}'**
  String issuedByName(String name);

  /// No description provided for @materialNoLongerExists.
  ///
  /// In en, this message translates to:
  /// **'That material no longer exists.'**
  String get materialNoLongerExists;

  /// No description provided for @pendingRequestsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your approval before checkout'**
  String get pendingRequestsSubtitle;

  /// No description provided for @couldNotLoadRequests.
  ///
  /// In en, this message translates to:
  /// **'The requests couldn\'t be loaded.'**
  String get couldNotLoadRequests;

  /// No description provided for @noPendingRequests.
  ///
  /// In en, this message translates to:
  /// **'No pending requests'**
  String get noPendingRequests;

  /// No description provided for @newCheckoutRequestsHint.
  ///
  /// In en, this message translates to:
  /// **'New checkout requests will show up here.'**
  String get newCheckoutRequestsHint;

  /// No description provided for @requestedByName.
  ///
  /// In en, this message translates to:
  /// **'Requested by {name}'**
  String requestedByName(String name);

  /// No description provided for @confirmBlockForMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Block \"{asset}\" from being booked between {start} and {end}?'**
  String confirmBlockForMaintenance(String asset, String start, String end);

  /// No description provided for @schedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get schedule;

  /// No description provided for @maintenanceScheduled.
  ///
  /// In en, this message translates to:
  /// **'Maintenance scheduled.'**
  String get maintenanceScheduled;

  /// No description provided for @couldNotScheduleMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t schedule the maintenance.'**
  String get couldNotScheduleMaintenance;

  /// No description provided for @noPermissionScheduleMaintenance.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to schedule maintenance.'**
  String get noPermissionScheduleMaintenance;

  /// No description provided for @maintenanceDates.
  ///
  /// In en, this message translates to:
  /// **'Maintenance dates'**
  String get maintenanceDates;

  /// No description provided for @maintenanceReasonHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Scheduled servicing'**
  String get maintenanceReasonHint;

  /// No description provided for @issueForFabrication.
  ///
  /// In en, this message translates to:
  /// **'Issue for fabrication'**
  String get issueForFabrication;

  /// No description provided for @confirmIssueForFabrication.
  ///
  /// In en, this message translates to:
  /// **'Issue {quantity} {unit} of \"{material}\" for fabrication?'**
  String confirmIssueForFabrication(
    String quantity,
    String unit,
    String material,
  );

  /// No description provided for @issueAction.
  ///
  /// In en, this message translates to:
  /// **'Issue'**
  String get issueAction;

  /// No description provided for @couldNotIssue.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t issue the material.'**
  String get couldNotIssue;

  /// No description provided for @quantityToIssue.
  ///
  /// In en, this message translates to:
  /// **'Quantity to issue ({unit})'**
  String quantityToIssue(String unit);

  /// No description provided for @onlyAvailable.
  ///
  /// In en, this message translates to:
  /// **'Only {quantity} available'**
  String onlyAvailable(String quantity);

  /// No description provided for @destinationSite.
  ///
  /// In en, this message translates to:
  /// **'Destination site'**
  String get destinationSite;

  /// No description provided for @expectedFabricatorOptional.
  ///
  /// In en, this message translates to:
  /// **'Expected fabricator (optional)'**
  String get expectedFabricatorOptional;

  /// No description provided for @expectedFabricatorHint.
  ///
  /// In en, this message translates to:
  /// **'Best guess — corrected from the scanned form later'**
  String get expectedFabricatorHint;

  /// No description provided for @orderCreated.
  ///
  /// In en, this message translates to:
  /// **'Order created'**
  String get orderCreated;

  /// No description provided for @orderCreatedBody.
  ///
  /// In en, this message translates to:
  /// **'Download and print the handover form, then give it to the driver/transporter together with \"{material}\". The completed form is scanned back into the app once it reaches the technician.'**
  String orderCreatedBody(String material);

  /// No description provided for @couldNotOpenScanner.
  ///
  /// In en, this message translates to:
  /// **'The document scanner couldn\'t be opened.'**
  String get couldNotOpenScanner;

  /// No description provided for @couldNotOpenFile.
  ///
  /// In en, this message translates to:
  /// **'This file couldn\'t be opened. Please try another one.'**
  String get couldNotOpenFile;

  /// No description provided for @fillEveryFieldAndScan.
  ///
  /// In en, this message translates to:
  /// **'Please fill in every field and attach the scan before submitting.'**
  String get fillEveryFieldAndScan;

  /// No description provided for @submitVerifiedForm.
  ///
  /// In en, this message translates to:
  /// **'Submit checked form'**
  String get submitVerifiedForm;

  /// No description provided for @confirmSubmitVerifiedForm.
  ///
  /// In en, this message translates to:
  /// **'Confirm these values match the completed paper form for \"{material}\"? This becomes the permanent digital record.'**
  String confirmSubmitVerifiedForm(String material);

  /// No description provided for @attachScanFirst.
  ///
  /// In en, this message translates to:
  /// **'Please scan the form or upload a file before submitting.'**
  String get attachScanFirst;

  /// No description provided for @formSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Form submitted.'**
  String get formSubmitted;

  /// No description provided for @couldNotSubmitForm.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t submit the form.'**
  String get couldNotSubmitForm;

  /// No description provided for @uploadCompletedForm.
  ///
  /// In en, this message translates to:
  /// **'Upload completed form'**
  String get uploadCompletedForm;

  /// No description provided for @formIdIssued.
  ///
  /// In en, this message translates to:
  /// **'Form ID: {id} • Issued {quantity} {unit}'**
  String formIdIssued(String id, String quantity, String unit);

  /// No description provided for @scan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scan;

  /// No description provided for @scanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Scan the completed form (several pages are fine) or upload an existing document'**
  String get scanSubtitle;

  /// No description provided for @scanDocument.
  ///
  /// In en, this message translates to:
  /// **'Scan document'**
  String get scanDocument;

  /// No description provided for @uploadFile.
  ///
  /// In en, this message translates to:
  /// **'Upload file'**
  String get uploadFile;

  /// No description provided for @readingForm.
  ///
  /// In en, this message translates to:
  /// **'Reading the form (a starting point only — check everything below)…'**
  String get readingForm;

  /// No description provided for @pagesCaptured.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page captured} other{{count} pages captured}}'**
  String pagesCaptured(int count);

  /// No description provided for @verifyValues.
  ///
  /// In en, this message translates to:
  /// **'Check the values'**
  String get verifyValues;

  /// No description provided for @verifyValuesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every value below must match the paper form — correct anything that was read wrong'**
  String get verifyValuesSubtitle;

  /// No description provided for @driverPickupQuantity.
  ///
  /// In en, this message translates to:
  /// **'Driver pickup quantity (from office)'**
  String get driverPickupQuantity;

  /// No description provided for @fabricatorName.
  ///
  /// In en, this message translates to:
  /// **'Fabricator name'**
  String get fabricatorName;

  /// No description provided for @fabricatorQuantityReceived.
  ///
  /// In en, this message translates to:
  /// **'Fabricator: quantity received'**
  String get fabricatorQuantityReceived;

  /// No description provided for @fabricatorCondition.
  ///
  /// In en, this message translates to:
  /// **'Condition at fabricator'**
  String get fabricatorCondition;

  /// No description provided for @damageDescription.
  ///
  /// In en, this message translates to:
  /// **'Damage description'**
  String get damageDescription;

  /// No description provided for @fabricatorOutputQuantity.
  ///
  /// In en, this message translates to:
  /// **'Fabricator: finished quantity'**
  String get fabricatorOutputQuantity;

  /// No description provided for @driverCollectedQuantity.
  ///
  /// In en, this message translates to:
  /// **'Driver: quantity collected from fabricator'**
  String get driverCollectedQuantity;

  /// No description provided for @technicianReceivedQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity you received (technician)'**
  String get technicianReceivedQuantity;

  /// No description provided for @pdfUnit.
  ///
  /// In en, this message translates to:
  /// **'Unit: {unit}'**
  String pdfUnit(String unit);

  /// No description provided for @pdfPrintedName.
  ///
  /// In en, this message translates to:
  /// **'Printed name: '**
  String get pdfPrintedName;

  /// No description provided for @pdfSignature.
  ///
  /// In en, this message translates to:
  /// **'Signature: '**
  String get pdfSignature;

  /// No description provided for @pdfDate.
  ///
  /// In en, this message translates to:
  /// **'Date: '**
  String get pdfDate;

  /// No description provided for @pdfFormIdPage.
  ///
  /// In en, this message translates to:
  /// **'Form ID: {id}  •  Page {page} of {pages}'**
  String pdfFormIdPage(String id, int page, int pages);

  /// No description provided for @pdfFabricationTitle.
  ///
  /// In en, this message translates to:
  /// **'AlmaWorks — Material Fabrication Chain of Custody'**
  String get pdfFabricationTitle;

  /// No description provided for @pdfScanAndUploadNote.
  ///
  /// In en, this message translates to:
  /// **'Scan and upload this completed form in the AlmaWorks app after the technician section is signed.'**
  String get pdfScanAndUploadNote;

  /// No description provided for @pdfIssueDetails.
  ///
  /// In en, this message translates to:
  /// **'1. Issue details (filled in by the office)'**
  String get pdfIssueDetails;

  /// No description provided for @pdfMaterial.
  ///
  /// In en, this message translates to:
  /// **'Material'**
  String get pdfMaterial;

  /// No description provided for @pdfQuantityIssued.
  ///
  /// In en, this message translates to:
  /// **'Quantity issued'**
  String get pdfQuantityIssued;

  /// No description provided for @pdfDateIssued.
  ///
  /// In en, this message translates to:
  /// **'Date issued'**
  String get pdfDateIssued;

  /// No description provided for @pdfIssuedBy.
  ///
  /// In en, this message translates to:
  /// **'Issued by'**
  String get pdfIssuedBy;

  /// No description provided for @pdfExpectedFabricator.
  ///
  /// In en, this message translates to:
  /// **'Expected fabricator'**
  String get pdfExpectedFabricator;

  /// No description provided for @pdfDriverPickup.
  ///
  /// In en, this message translates to:
  /// **'2. Driver/transporter — pickup confirmation'**
  String get pdfDriverPickup;

  /// No description provided for @pdfQuantityTaken.
  ///
  /// In en, this message translates to:
  /// **'Quantity taken'**
  String get pdfQuantityTaken;

  /// No description provided for @pdfFabricatorReceipt.
  ///
  /// In en, this message translates to:
  /// **'3. Fabricator — receipt confirmation'**
  String get pdfFabricatorReceipt;

  /// No description provided for @pdfQuantityReceived.
  ///
  /// In en, this message translates to:
  /// **'Quantity received'**
  String get pdfQuantityReceived;

  /// No description provided for @pdfConditionGoodDamaged.
  ///
  /// In en, this message translates to:
  /// **'Condition:  [ ] Good   [ ] Damaged'**
  String get pdfConditionGoodDamaged;

  /// No description provided for @pdfIfDamagedDescribe.
  ///
  /// In en, this message translates to:
  /// **'If damaged, describe:'**
  String get pdfIfDamagedDescribe;

  /// No description provided for @pdfFabricatorName.
  ///
  /// In en, this message translates to:
  /// **'Fabricator name: '**
  String get pdfFabricatorName;

  /// No description provided for @pdfFabricatorOutput.
  ///
  /// In en, this message translates to:
  /// **'4. Finished material — driver/transporter confirmation'**
  String get pdfFabricatorOutput;

  /// No description provided for @pdfFabricatedCollected.
  ///
  /// In en, this message translates to:
  /// **'Fabricated quantity collected'**
  String get pdfFabricatedCollected;

  /// No description provided for @pdfTechnicianReceipt.
  ///
  /// In en, this message translates to:
  /// **'5. Technician — final receipt confirmation (on site)'**
  String get pdfTechnicianReceipt;

  /// No description provided for @formSavedToDownloads.
  ///
  /// In en, this message translates to:
  /// **'Form saved to Downloads: {file}'**
  String formSavedToDownloads(String file);

  /// No description provided for @pdfHandoverTitle.
  ///
  /// In en, this message translates to:
  /// **'AlmaWorks — {type} handover via driver/transporter'**
  String pdfHandoverTitle(String type);

  /// No description provided for @pdfHandoverScanNote.
  ///
  /// In en, this message translates to:
  /// **'Scan and upload this completed form in the AlmaWorks app after the recipient section is signed.'**
  String get pdfHandoverScanNote;

  /// No description provided for @pdfDispatchDetails.
  ///
  /// In en, this message translates to:
  /// **'1. Dispatch details (filled in by the office)'**
  String get pdfDispatchDetails;

  /// No description provided for @pdfDateDispatched.
  ///
  /// In en, this message translates to:
  /// **'Date dispatched'**
  String get pdfDateDispatched;

  /// No description provided for @pdfDispatchedBy.
  ///
  /// In en, this message translates to:
  /// **'Dispatched by'**
  String get pdfDispatchedBy;

  /// No description provided for @pdfDriverTransporter.
  ///
  /// In en, this message translates to:
  /// **'Driver / transporter'**
  String get pdfDriverTransporter;

  /// No description provided for @pdfRecipient.
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get pdfRecipient;

  /// No description provided for @pdfRecipientReceipt.
  ///
  /// In en, this message translates to:
  /// **'3. Recipient — receipt confirmation (on site)'**
  String get pdfRecipientReceipt;

  /// No description provided for @projectStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get projectStatusActive;

  /// No description provided for @projectStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get projectStatusCompleted;

  /// No description provided for @projectStatusUntracked.
  ///
  /// In en, this message translates to:
  /// **'Untracked'**
  String get projectStatusUntracked;

  /// No description provided for @allProjects.
  ///
  /// In en, this message translates to:
  /// **'All projects'**
  String get allProjects;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @couldNotLoadProjectsTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the projects'**
  String get couldNotLoadProjectsTitle;

  /// No description provided for @noProjectsAssigned.
  ///
  /// In en, this message translates to:
  /// **'No projects assigned to you yet'**
  String get noProjectsAssigned;

  /// No description provided for @noProjectsFound.
  ///
  /// In en, this message translates to:
  /// **'No projects found'**
  String get noProjectsFound;

  /// No description provided for @noActiveProjectsAssigned.
  ///
  /// In en, this message translates to:
  /// **'No active projects assigned to you'**
  String get noActiveProjectsAssigned;

  /// No description provided for @noCompletedProjectsAssigned.
  ///
  /// In en, this message translates to:
  /// **'No completed projects assigned to you'**
  String get noCompletedProjectsAssigned;

  /// No description provided for @noActiveProjects.
  ///
  /// In en, this message translates to:
  /// **'No active projects'**
  String get noActiveProjects;

  /// No description provided for @noCompletedProjects.
  ///
  /// In en, this message translates to:
  /// **'No completed projects'**
  String get noCompletedProjects;

  /// No description provided for @tapPlusToCreateProject.
  ///
  /// In en, this message translates to:
  /// **'Tap the + button to create your first project'**
  String get tapPlusToCreateProject;

  /// No description provided for @couldNotOpenProjectAction.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the project.'**
  String get couldNotOpenProjectAction;

  /// No description provided for @editProject.
  ///
  /// In en, this message translates to:
  /// **'Edit project'**
  String get editProject;

  /// No description provided for @deleteProject.
  ///
  /// In en, this message translates to:
  /// **'Delete project'**
  String get deleteProject;

  /// No description provided for @deleteProjectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"? This can\'t be undone.'**
  String deleteProjectConfirm(String name);

  /// No description provided for @projectDeleted.
  ///
  /// In en, this message translates to:
  /// **'Project \"{name}\" deleted.'**
  String projectDeleted(String name);

  /// No description provided for @couldNotDeleteProject.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the project.'**
  String get couldNotDeleteProject;

  /// No description provided for @addProject.
  ///
  /// In en, this message translates to:
  /// **'Add project'**
  String get addProject;

  /// No description provided for @addNewProject.
  ///
  /// In en, this message translates to:
  /// **'Add new project'**
  String get addNewProject;

  /// No description provided for @sectionComingSoon.
  ///
  /// In en, this message translates to:
  /// **'{section} is coming soon.'**
  String sectionComingSoon(String section);

  /// No description provided for @basicInformation.
  ///
  /// In en, this message translates to:
  /// **'Basic information'**
  String get basicInformation;

  /// No description provided for @projectName.
  ///
  /// In en, this message translates to:
  /// **'Project name'**
  String get projectName;

  /// No description provided for @enterProjectName.
  ///
  /// In en, this message translates to:
  /// **'Please enter a project name'**
  String get enterProjectName;

  /// No description provided for @descriptionOptionalCap.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get descriptionOptionalCap;

  /// No description provided for @contractNumberOptional.
  ///
  /// In en, this message translates to:
  /// **'Contract number (optional)'**
  String get contractNumberOptional;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// No description provided for @enterProjectLocation.
  ///
  /// In en, this message translates to:
  /// **'Please enter the project location'**
  String get enterProjectLocation;

  /// No description provided for @projectDetails.
  ///
  /// In en, this message translates to:
  /// **'Project details'**
  String get projectDetails;

  /// No description provided for @budgetUsd.
  ///
  /// In en, this message translates to:
  /// **'Budget (USD)'**
  String get budgetUsd;

  /// No description provided for @statusOptional.
  ///
  /// In en, this message translates to:
  /// **'Status (optional)'**
  String get statusOptional;

  /// No description provided for @projectManager.
  ///
  /// In en, this message translates to:
  /// **'Project manager'**
  String get projectManager;

  /// No description provided for @enterProjectManager.
  ///
  /// In en, this message translates to:
  /// **'Please enter the project manager'**
  String get enterProjectManager;

  /// No description provided for @timeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get timeline;

  /// No description provided for @startDate.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get startDate;

  /// No description provided for @endDateOptional.
  ///
  /// In en, this message translates to:
  /// **'End date (optional)'**
  String get endDateOptional;

  /// No description provided for @notSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// No description provided for @teamMembers.
  ///
  /// In en, this message translates to:
  /// **'Team members'**
  String get teamMembers;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @teamRoleSubcontractor.
  ///
  /// In en, this message translates to:
  /// **'Subcontractor'**
  String get teamRoleSubcontractor;

  /// No description provided for @teamRoleSupplier.
  ///
  /// In en, this message translates to:
  /// **'Supplier'**
  String get teamRoleSupplier;

  /// No description provided for @teamRoleTechnician.
  ///
  /// In en, this message translates to:
  /// **'Technician'**
  String get teamRoleTechnician;

  /// No description provided for @teamRoleManager.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get teamRoleManager;

  /// No description provided for @defineNew.
  ///
  /// In en, this message translates to:
  /// **'Define new'**
  String get defineNew;

  /// No description provided for @defineRoleName.
  ///
  /// In en, this message translates to:
  /// **'Role name *'**
  String get defineRoleName;

  /// No description provided for @defineRoleHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Site foreman, Safety officer'**
  String get defineRoleHint;

  /// No description provided for @teamMemberName.
  ///
  /// In en, this message translates to:
  /// **'Team member name'**
  String get teamMemberName;

  /// No description provided for @categoryOptional.
  ///
  /// In en, this message translates to:
  /// **'Category (optional)'**
  String get categoryOptional;

  /// No description provided for @teamMembersColon.
  ///
  /// In en, this message translates to:
  /// **'Team members:'**
  String get teamMembersColon;

  /// No description provided for @noTeamMembersYet.
  ///
  /// In en, this message translates to:
  /// **'No team members added yet'**
  String get noTeamMembersYet;

  /// No description provided for @creatingProject.
  ///
  /// In en, this message translates to:
  /// **'Creating project…'**
  String get creatingProject;

  /// No description provided for @createProject.
  ///
  /// In en, this message translates to:
  /// **'Create project'**
  String get createProject;

  /// No description provided for @selectRole.
  ///
  /// In en, this message translates to:
  /// **'Please choose a role.'**
  String get selectRole;

  /// No description provided for @enterCustomRole.
  ///
  /// In en, this message translates to:
  /// **'Please enter a name for the new role.'**
  String get enterCustomRole;

  /// No description provided for @enterTeamMemberName.
  ///
  /// In en, this message translates to:
  /// **'Please enter a team member name.'**
  String get enterTeamMemberName;

  /// No description provided for @teamMemberExists.
  ///
  /// In en, this message translates to:
  /// **'This team member is already on the list.'**
  String get teamMemberExists;

  /// No description provided for @projectCreated.
  ///
  /// In en, this message translates to:
  /// **'Project \"{name}\" created.'**
  String projectCreated(String name);

  /// No description provided for @couldNotCreateProject.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the project.'**
  String get couldNotCreateProject;

  /// No description provided for @editProjectName.
  ///
  /// In en, this message translates to:
  /// **'Edit {name}'**
  String editProjectName(String name);

  /// No description provided for @updating.
  ///
  /// In en, this message translates to:
  /// **'Updating…'**
  String get updating;

  /// No description provided for @updateProject.
  ///
  /// In en, this message translates to:
  /// **'Update project'**
  String get updateProject;

  /// No description provided for @linkedPmAccount.
  ///
  /// In en, this message translates to:
  /// **'Linked project manager account (optional)'**
  String get linkedPmAccount;

  /// No description provided for @linkedPmHelper.
  ///
  /// In en, this message translates to:
  /// **'Lets this person receive and approve task date-change requests'**
  String get linkedPmHelper;

  /// No description provided for @loadingAccounts.
  ///
  /// In en, this message translates to:
  /// **'Loading accounts…'**
  String get loadingAccounts;

  /// No description provided for @noLinkedAccount.
  ///
  /// In en, this message translates to:
  /// **'No linked account'**
  String get noLinkedAccount;

  /// No description provided for @teamMemberNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Team member name *'**
  String get teamMemberNameRequired;

  /// No description provided for @roleRequired.
  ///
  /// In en, this message translates to:
  /// **'Role *'**
  String get roleRequired;

  /// No description provided for @projectManagerRequired.
  ///
  /// In en, this message translates to:
  /// **'Project manager *'**
  String get projectManagerRequired;

  /// No description provided for @projectUpdated.
  ///
  /// In en, this message translates to:
  /// **'Project \"{name}\" updated.'**
  String projectUpdated(String name);

  /// No description provided for @couldNotUpdateProject.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update the project.'**
  String get couldNotUpdateProject;

  /// No description provided for @healthCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get healthCompleted;

  /// No description provided for @healthOnTrack.
  ///
  /// In en, this message translates to:
  /// **'On track'**
  String get healthOnTrack;

  /// No description provided for @healthInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get healthInProgress;

  /// No description provided for @healthEarlyStage.
  ///
  /// In en, this message translates to:
  /// **'Early stage'**
  String get healthEarlyStage;

  /// No description provided for @healthOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get healthOverdue;

  /// No description provided for @healthAhead.
  ///
  /// In en, this message translates to:
  /// **'Ahead of schedule'**
  String get healthAhead;

  /// No description provided for @healthSlightDelay.
  ///
  /// In en, this message translates to:
  /// **'Slight delay'**
  String get healthSlightDelay;

  /// No description provided for @healthAtRisk.
  ///
  /// In en, this message translates to:
  /// **'At risk'**
  String get healthAtRisk;

  /// No description provided for @projectUpdatedShort.
  ///
  /// In en, this message translates to:
  /// **'Project updated.'**
  String get projectUpdatedShort;

  /// No description provided for @projectOverview.
  ///
  /// In en, this message translates to:
  /// **'Project overview'**
  String get projectOverview;

  /// No description provided for @progress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get progress;

  /// No description provided for @progressLive.
  ///
  /// In en, this message translates to:
  /// **'Progress (live)'**
  String get progressLive;

  /// No description provided for @teamSize.
  ///
  /// In en, this message translates to:
  /// **'Team size'**
  String get teamSize;

  /// No description provided for @membersCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member} other{{count} members}}'**
  String membersCount(int count);

  /// No description provided for @endDate.
  ///
  /// In en, this message translates to:
  /// **'End date'**
  String get endDate;

  /// No description provided for @tbd.
  ///
  /// In en, this message translates to:
  /// **'TBD'**
  String get tbd;

  /// No description provided for @daysRemaining.
  ///
  /// In en, this message translates to:
  /// **'Days remaining'**
  String get daysRemaining;

  /// No description provided for @daysCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String daysCount(int count);

  /// No description provided for @dueToday.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get dueToday;

  /// No description provided for @daysOverdueShort.
  ///
  /// In en, this message translates to:
  /// **'{count}d overdue'**
  String daysOverdueShort(int count);

  /// No description provided for @overallProgress.
  ///
  /// In en, this message translates to:
  /// **'Overall progress'**
  String get overallProgress;

  /// No description provided for @healthStatus.
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get healthStatus;

  /// No description provided for @pmShort.
  ///
  /// In en, this message translates to:
  /// **'PM'**
  String get pmShort;

  /// No description provided for @taskTypeMain.
  ///
  /// In en, this message translates to:
  /// **'Main task'**
  String get taskTypeMain;

  /// No description provided for @taskTypeSub.
  ///
  /// In en, this message translates to:
  /// **'Subtask'**
  String get taskTypeSub;

  /// No description provided for @taskTypeTask.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get taskTypeTask;

  /// No description provided for @taskNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get taskNotStarted;

  /// No description provided for @taskStarted.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get taskStarted;

  /// No description provided for @taskCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get taskCompleted;

  /// No description provided for @monitorOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get monitorOverdue;

  /// No description provided for @monitorOngoing.
  ///
  /// In en, this message translates to:
  /// **'Ongoing'**
  String get monitorOngoing;

  /// No description provided for @monitorUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get monitorUpcoming;

  /// No description provided for @healthExcellent.
  ///
  /// In en, this message translates to:
  /// **'Excellent'**
  String get healthExcellent;

  /// No description provided for @healthGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get healthGood;

  /// No description provided for @healthFair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get healthFair;

  /// No description provided for @healthBehind.
  ///
  /// In en, this message translates to:
  /// **'Behind schedule'**
  String get healthBehind;

  /// No description provided for @storagePermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Storage access is turned off. Please allow it in your device settings and try again.'**
  String get storagePermissionDenied;

  /// No description provided for @downloadStartedWeb.
  ///
  /// In en, this message translates to:
  /// **'Download started. Check your browser downloads.'**
  String get downloadStartedWeb;

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t download the file. Please try again.'**
  String get downloadFailed;

  /// No description provided for @fileTooLarge100.
  ///
  /// In en, this message translates to:
  /// **'This file is larger than 100 MB. Please choose a smaller file.'**
  String get fileTooLarge100;

  /// No description provided for @drawingNotFound.
  ///
  /// In en, this message translates to:
  /// **'This drawing no longer exists. It may have been deleted.'**
  String get drawingNotFound;

  /// No description provided for @typeEmailOrName.
  ///
  /// In en, this message translates to:
  /// **'Type email or name…'**
  String get typeEmailOrName;

  /// No description provided for @addRecipientTo.
  ///
  /// In en, this message translates to:
  /// **'Please add at least one recipient in the To field.'**
  String get addRecipientTo;

  /// No description provided for @enterSubject.
  ///
  /// In en, this message translates to:
  /// **'Please enter a subject.'**
  String get enterSubject;

  /// No description provided for @messageSent.
  ///
  /// In en, this message translates to:
  /// **'Message sent!'**
  String get messageSent;

  /// No description provided for @couldNotSendMessage.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t send your message. Please try again.'**
  String get couldNotSendMessage;

  /// No description provided for @draftSaved.
  ///
  /// In en, this message translates to:
  /// **'Draft saved.'**
  String get draftSaved;

  /// No description provided for @discardMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard message?'**
  String get discardMessageTitle;

  /// No description provided for @discardMessageBody.
  ///
  /// In en, this message translates to:
  /// **'This message will not be saved.'**
  String get discardMessageBody;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @reply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get reply;

  /// No description provided for @replyAll.
  ///
  /// In en, this message translates to:
  /// **'Reply all'**
  String get replyAll;

  /// No description provided for @forward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forward;

  /// No description provided for @forwarded.
  ///
  /// In en, this message translates to:
  /// **'Forwarded'**
  String get forwarded;

  /// No description provided for @newMessage.
  ///
  /// In en, this message translates to:
  /// **'New message'**
  String get newMessage;

  /// No description provided for @msgTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get msgTo;

  /// No description provided for @msgFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get msgFrom;

  /// No description provided for @msgCc.
  ///
  /// In en, this message translates to:
  /// **'Cc'**
  String get msgCc;

  /// No description provided for @subject.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get subject;

  /// No description provided for @writeMessageHere.
  ///
  /// In en, this message translates to:
  /// **'Write your message here…'**
  String get writeMessageHere;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @attachFiles.
  ///
  /// In en, this message translates to:
  /// **'Attach files'**
  String get attachFiles;

  /// No description provided for @saveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save draft'**
  String get saveDraft;

  /// No description provided for @moveToTrashTitle.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash?'**
  String get moveToTrashTitle;

  /// No description provided for @moveToTrashBody.
  ///
  /// In en, this message translates to:
  /// **'This message will be moved to your Trash.'**
  String get moveToTrashBody;

  /// No description provided for @moveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get moveToTrash;

  /// No description provided for @attachmentsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 attachment} other{{count} attachments}}'**
  String attachmentsCount(int count);

  /// No description provided for @repliesInThread.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 reply in this thread} other{{count} replies in this thread}}'**
  String repliesInThread(int count);

  /// No description provided for @noContent.
  ///
  /// In en, this message translates to:
  /// **'(no content)'**
  String get noContent;

  /// No description provided for @noSubject.
  ///
  /// In en, this message translates to:
  /// **'(No subject)'**
  String get noSubject;

  /// No description provided for @newMessageFrom.
  ///
  /// In en, this message translates to:
  /// **'New message from {name}'**
  String newMessageFrom(String name);

  /// No description provided for @communication.
  ///
  /// In en, this message translates to:
  /// **'Communication'**
  String get communication;

  /// No description provided for @compose.
  ///
  /// In en, this message translates to:
  /// **'Compose'**
  String get compose;

  /// No description provided for @inbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get inbox;

  /// No description provided for @sentFolder.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sentFolder;

  /// No description provided for @drafts.
  ///
  /// In en, this message translates to:
  /// **'Drafts'**
  String get drafts;

  /// No description provided for @trash.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trash;

  /// No description provided for @searchMessages.
  ///
  /// In en, this message translates to:
  /// **'Search messages…'**
  String get searchMessages;

  /// No description provided for @inboxEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your inbox is empty'**
  String get inboxEmpty;

  /// No description provided for @noSentMessages.
  ///
  /// In en, this message translates to:
  /// **'No sent messages'**
  String get noSentMessages;

  /// No description provided for @trashEmpty.
  ///
  /// In en, this message translates to:
  /// **'Trash is empty'**
  String get trashEmpty;

  /// No description provided for @couldNotLoadMessages.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load your messages'**
  String get couldNotLoadMessages;

  /// No description provided for @noDraftsSaved.
  ///
  /// In en, this message translates to:
  /// **'No drafts saved'**
  String get noDraftsSaved;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @noRecipients.
  ///
  /// In en, this message translates to:
  /// **'No recipients'**
  String get noRecipients;

  /// No description provided for @toRecipient.
  ///
  /// In en, this message translates to:
  /// **'To: {name}'**
  String toRecipient(String name);

  /// No description provided for @toRecipientMore.
  ///
  /// In en, this message translates to:
  /// **'To: {name} +{count}'**
  String toRecipientMore(String name, int count);

  /// No description provided for @draft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get draft;

  /// No description provided for @deleteDraft.
  ///
  /// In en, this message translates to:
  /// **'Delete draft'**
  String get deleteDraft;

  /// No description provided for @downloadedTo.
  ///
  /// In en, this message translates to:
  /// **'Downloaded to {path}'**
  String downloadedTo(String path);

  /// No description provided for @couldNotDownload.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t download the file.'**
  String get couldNotDownload;

  /// No description provided for @projectSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'{project} - {section}'**
  String projectSectionTitle(String project, String section);

  /// No description provided for @documents.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get documents;

  /// No description provided for @docActivityHistory.
  ///
  /// In en, this message translates to:
  /// **'Document activity history'**
  String get docActivityHistory;

  /// No description provided for @selectRoleFirst.
  ///
  /// In en, this message translates to:
  /// **'Please select a {role} first'**
  String selectRoleFirst(String role);

  /// No description provided for @noDocsAskAdminSub.
  ///
  /// In en, this message translates to:
  /// **'No documents yet — ask your project admin to add you as a Sub-Contractor team member first.'**
  String get noDocsAskAdminSub;

  /// No description provided for @switchRole.
  ///
  /// In en, this message translates to:
  /// **'Switch role'**
  String get switchRole;

  /// No description provided for @docsForMember.
  ///
  /// In en, this message translates to:
  /// **'Documents for {name}'**
  String docsForMember(String name);

  /// No description provided for @noMembersOfRoleYet.
  ///
  /// In en, this message translates to:
  /// **'No {role} added to this project yet'**
  String noMembersOfRoleYet(String role);

  /// No description provided for @addMembersViaEdit.
  ///
  /// In en, this message translates to:
  /// **'Add team members via the Edit Project section.'**
  String get addMembersViaEdit;

  /// No description provided for @goToEditProject.
  ///
  /// In en, this message translates to:
  /// **'Go to Edit Project'**
  String get goToEditProject;

  /// No description provided for @couldNotLoadDocuments.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load the documents'**
  String get couldNotLoadDocuments;

  /// No description provided for @noDocumentsInSection.
  ///
  /// In en, this message translates to:
  /// **'No documents in this section'**
  String get noDocumentsInSection;

  /// No description provided for @fileUploadedOn.
  ///
  /// In en, this message translates to:
  /// **'{file} - Uploaded: {date}'**
  String fileUploadedOn(String file, String date);

  /// No description provided for @documentActivity.
  ///
  /// In en, this message translates to:
  /// **'Document activity'**
  String get documentActivity;

  /// No description provided for @couldNotLoadActivity.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load the activity'**
  String get couldNotLoadActivity;

  /// No description provided for @noActivityYet.
  ///
  /// In en, this message translates to:
  /// **'No activity recorded yet'**
  String get noActivityYet;

  /// No description provided for @auditUploaded.
  ///
  /// In en, this message translates to:
  /// **'{name} ({role}) uploaded \"{title}\"'**
  String auditUploaded(String name, String role, String title);

  /// No description provided for @auditDeleted.
  ///
  /// In en, this message translates to:
  /// **'{name} ({role}) deleted \"{title}\"'**
  String auditDeleted(String name, String role, String title);

  /// No description provided for @couldNotReadFile.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t read the file. Please try again.'**
  String get couldNotReadFile;

  /// No description provided for @documentAdded.
  ///
  /// In en, this message translates to:
  /// **'Document \"{title}\" added'**
  String documentAdded(String title);

  /// No description provided for @uploadCancelled.
  ///
  /// In en, this message translates to:
  /// **'Upload cancelled'**
  String get uploadCancelled;

  /// No description provided for @couldNotAddDocument.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add the document.'**
  String get couldNotAddDocument;

  /// No description provided for @enterDocumentTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter document title'**
  String get enterDocumentTitle;

  /// No description provided for @documentTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Title (e.g. RFI, close-out document)'**
  String get documentTitleHint;

  /// No description provided for @pleaseEnterTitle.
  ///
  /// In en, this message translates to:
  /// **'Please enter a title'**
  String get pleaseEnterTitle;

  /// No description provided for @couldNotOpenViewer.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t open the document viewer'**
  String get couldNotOpenViewer;

  /// No description provided for @couldNotOpenThisFile.
  ///
  /// In en, this message translates to:
  /// **'This file couldn\'t be opened on your device'**
  String get couldNotOpenThisFile;

  /// No description provided for @downloadInstead.
  ///
  /// In en, this message translates to:
  /// **'Download instead'**
  String get downloadInstead;

  /// No description provided for @offlineNoCopy.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline and this file hasn\'t been saved on this device yet'**
  String get offlineNoCopy;

  /// No description provided for @couldNotOpenDocument.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the document.'**
  String get couldNotOpenDocument;

  /// No description provided for @documentDeleted.
  ///
  /// In en, this message translates to:
  /// **'Document deleted'**
  String get documentDeleted;

  /// No description provided for @couldNotDeleteDocument.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the document.'**
  String get couldNotDeleteDocument;

  /// No description provided for @preparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get preparing;

  /// No description provided for @finalising.
  ///
  /// In en, this message translates to:
  /// **'Finalising…'**
  String get finalising;

  /// No description provided for @uploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get uploading;

  /// No description provided for @uploadingDocument.
  ///
  /// In en, this message translates to:
  /// **'Uploading document'**
  String get uploadingDocument;

  /// No description provided for @docSectionContract.
  ///
  /// In en, this message translates to:
  /// **'Contract'**
  String get docSectionContract;

  /// No description provided for @docSectionAccessRequests.
  ///
  /// In en, this message translates to:
  /// **'Access requests'**
  String get docSectionAccessRequests;

  /// No description provided for @subcontractorsPlural.
  ///
  /// In en, this message translates to:
  /// **'subcontractors'**
  String get subcontractorsPlural;

  /// No description provided for @suppliersPlural.
  ///
  /// In en, this message translates to:
  /// **'suppliers'**
  String get suppliersPlural;

  /// No description provided for @drawings.
  ///
  /// In en, this message translates to:
  /// **'Drawings'**
  String get drawings;

  /// No description provided for @tabContractDrawing.
  ///
  /// In en, this message translates to:
  /// **'Contract drawing'**
  String get tabContractDrawing;

  /// No description provided for @tabRevisions.
  ///
  /// In en, this message translates to:
  /// **'Revisions'**
  String get tabRevisions;

  /// No description provided for @tabAsBuilt.
  ///
  /// In en, this message translates to:
  /// **'As built'**
  String get tabAsBuilt;

  /// No description provided for @couldNotLoadContractDrawings.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load the contract drawings'**
  String get couldNotLoadContractDrawings;

  /// No description provided for @noContractDrawings.
  ///
  /// In en, this message translates to:
  /// **'No contract drawings uploaded yet'**
  String get noContractDrawings;

  /// No description provided for @tapUploadContractDrawings.
  ///
  /// In en, this message translates to:
  /// **'Tap the upload button to add contract drawings'**
  String get tapUploadContractDrawings;

  /// No description provided for @fileUploadedDot.
  ///
  /// In en, this message translates to:
  /// **'{file} • Uploaded {date}'**
  String fileUploadedDot(String file, String date);

  /// No description provided for @enterDrawingTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter drawing title'**
  String get enterDrawingTitle;

  /// No description provided for @enterContractDrawingTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter a title for this contract drawing:'**
  String get enterContractDrawingTitle;

  /// No description provided for @contractDrawingHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Main contract drawing'**
  String get contractDrawingHint;

  /// No description provided for @uploadingContractDrawing.
  ///
  /// In en, this message translates to:
  /// **'Uploading contract drawing'**
  String get uploadingContractDrawing;

  /// No description provided for @uploadingFile.
  ///
  /// In en, this message translates to:
  /// **'Uploading {file}…'**
  String uploadingFile(String file);

  /// No description provided for @contractDrawingUploaded.
  ///
  /// In en, this message translates to:
  /// **'Contract drawing \"{title}\" uploaded'**
  String contractDrawingUploaded(String title);

  /// No description provided for @couldNotUpload.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t upload the file.'**
  String get couldNotUpload;

  /// No description provided for @couldNotLoadDrawings.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load the drawings'**
  String get couldNotLoadDrawings;

  /// No description provided for @noDrawingsYet.
  ///
  /// In en, this message translates to:
  /// **'No drawings uploaded yet'**
  String get noDrawingsYet;

  /// No description provided for @tapUploadFirstDrawing.
  ///
  /// In en, this message translates to:
  /// **'Tap the upload button to add your first drawing'**
  String get tapUploadFirstDrawing;

  /// No description provided for @couldNotLoadAsBuilt.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load the as-built drawings'**
  String get couldNotLoadAsBuilt;

  /// No description provided for @noAsBuiltYet.
  ///
  /// In en, this message translates to:
  /// **'No as-built drawings yet'**
  String get noAsBuiltYet;

  /// No description provided for @tapUploadAsBuilt.
  ///
  /// In en, this message translates to:
  /// **'Tap the upload button to add as-built drawings'**
  String get tapUploadAsBuilt;

  /// No description provided for @latestRevisionSummary.
  ///
  /// In en, this message translates to:
  /// **'{file} (latest) • {count, plural, =1{1 revision} other{{count} revisions}}'**
  String latestRevisionSummary(String file, int count);

  /// No description provided for @revShort.
  ///
  /// In en, this message translates to:
  /// **'Rev{number}'**
  String revShort(String number);

  /// No description provided for @uploadedOn.
  ///
  /// In en, this message translates to:
  /// **'Uploaded {date}'**
  String uploadedOn(String date);

  /// No description provided for @latest.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get latest;

  /// No description provided for @finalLabel.
  ///
  /// In en, this message translates to:
  /// **'Final'**
  String get finalLabel;

  /// No description provided for @enterAsBuiltTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter as-built drawing title'**
  String get enterAsBuiltTitle;

  /// No description provided for @enterAsBuiltTitleBody.
  ///
  /// In en, this message translates to:
  /// **'Enter a title for this as-built drawing:'**
  String get enterAsBuiltTitleBody;

  /// No description provided for @asBuiltHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Final construction drawing'**
  String get asBuiltHint;

  /// No description provided for @uploadingAsBuilt.
  ///
  /// In en, this message translates to:
  /// **'Uploading as-built drawing'**
  String get uploadingAsBuilt;

  /// No description provided for @asBuiltUploaded.
  ///
  /// In en, this message translates to:
  /// **'As-built drawing \"{title}\" uploaded'**
  String asBuiltUploaded(String title);

  /// No description provided for @deleteAsBuiltTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete as-built drawing'**
  String get deleteAsBuiltTitle;

  /// No description provided for @deleteItemConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"? This can\'t be undone.'**
  String deleteItemConfirm(String name);

  /// No description provided for @asBuiltDeleted.
  ///
  /// In en, this message translates to:
  /// **'As-built drawing deleted'**
  String get asBuiltDeleted;

  /// No description provided for @couldNotDelete.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete it.'**
  String get couldNotDelete;

  /// No description provided for @enterDrawingCategory.
  ///
  /// In en, this message translates to:
  /// **'Enter drawing category'**
  String get enterDrawingCategory;

  /// No description provided for @enterDrawingCategoryBody.
  ///
  /// In en, this message translates to:
  /// **'Enter a name for the new drawing category:'**
  String get enterDrawingCategoryBody;

  /// No description provided for @drawingCategoryHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Floor plan level 1'**
  String get drawingCategoryHint;

  /// No description provided for @noCategoriesCreateNew.
  ///
  /// In en, this message translates to:
  /// **'There are no categories yet. Please create a new one.'**
  String get noCategoriesCreateNew;

  /// No description provided for @enterDrawingTitleBody.
  ///
  /// In en, this message translates to:
  /// **'Enter a title for this drawing:'**
  String get enterDrawingTitleBody;

  /// No description provided for @drawingTitleHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Floor plan level 1 - Rev 1'**
  String get drawingTitleHint;

  /// No description provided for @uploadingDrawing.
  ///
  /// In en, this message translates to:
  /// **'Uploading drawing'**
  String get uploadingDrawing;

  /// No description provided for @drawingUploaded.
  ///
  /// In en, this message translates to:
  /// **'Drawing \"{title}\" uploaded'**
  String drawingUploaded(String title);

  /// No description provided for @uploadType.
  ///
  /// In en, this message translates to:
  /// **'Upload type'**
  String get uploadType;

  /// No description provided for @chooseUploadType.
  ///
  /// In en, this message translates to:
  /// **'Choose how to upload the drawing:'**
  String get chooseUploadType;

  /// No description provided for @newCategoryDrawing.
  ///
  /// In en, this message translates to:
  /// **'New category drawing'**
  String get newCategoryDrawing;

  /// No description provided for @newCategoryDrawingHint.
  ///
  /// In en, this message translates to:
  /// **'Create a new drawing category and upload the first revision.'**
  String get newCategoryDrawingHint;

  /// No description provided for @revisionDrawing.
  ///
  /// In en, this message translates to:
  /// **'Revision drawing'**
  String get revisionDrawing;

  /// No description provided for @revisionDrawingHint.
  ///
  /// In en, this message translates to:
  /// **'Add a revision to an existing drawing category.'**
  String get revisionDrawingHint;

  /// No description provided for @selectDrawingCategory.
  ///
  /// In en, this message translates to:
  /// **'Select drawing category'**
  String get selectDrawingCategory;

  /// No description provided for @fileLabel.
  ///
  /// In en, this message translates to:
  /// **'File: {name}'**
  String fileLabel(String name);

  /// No description provided for @deleteDrawingTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete drawing'**
  String get deleteDrawingTitle;

  /// No description provided for @drawingDeleted.
  ///
  /// In en, this message translates to:
  /// **'Drawing deleted'**
  String get drawingDeleted;

  /// No description provided for @couldNotOpenDrawingViewer.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t open the drawing viewer'**
  String get couldNotOpenDrawingViewer;

  /// No description provided for @couldNotOpenDrawing.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the drawing.'**
  String get couldNotOpenDrawing;

  /// No description provided for @photoGallery.
  ///
  /// In en, this message translates to:
  /// **'Photo gallery'**
  String get photoGallery;

  /// No description provided for @viewPhotos.
  ///
  /// In en, this message translates to:
  /// **'View photos'**
  String get viewPhotos;

  /// No description provided for @uploadPhoto.
  ///
  /// In en, this message translates to:
  /// **'Upload photo'**
  String get uploadPhoto;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @moveToPhotos.
  ///
  /// In en, this message translates to:
  /// **'Move to Photos'**
  String get moveToPhotos;

  /// No description provided for @couldNotLoadPhotos.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load the photos'**
  String get couldNotLoadPhotos;

  /// No description provided for @noPhotosAddSome.
  ///
  /// In en, this message translates to:
  /// **'No photos yet. Add some!'**
  String get noPhotosAddSome;

  /// No description provided for @deactivateSelection.
  ///
  /// In en, this message translates to:
  /// **'Turn off selection'**
  String get deactivateSelection;

  /// No description provided for @activateSelection.
  ///
  /// In en, this message translates to:
  /// **'Select multiple'**
  String get activateSelection;

  /// No description provided for @movingPhotos.
  ///
  /// In en, this message translates to:
  /// **'Moving photos'**
  String get movingPhotos;

  /// No description provided for @photosProcessed.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} photos processed…'**
  String photosProcessed(int done, int total);

  /// No description provided for @photosMoved.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo moved to Photos.} other{{count} photos moved to Photos.}}'**
  String photosMoved(int count);

  /// No description provided for @photosAlreadyExisted.
  ///
  /// In en, this message translates to:
  /// **'{count} already existed.'**
  String photosAlreadyExisted(int count);

  /// No description provided for @photosFailedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} failed.'**
  String photosFailedCount(int count);

  /// No description provided for @noPhotosMoved.
  ///
  /// In en, this message translates to:
  /// **'No photos were moved.'**
  String get noPhotosMoved;

  /// No description provided for @moveResults.
  ///
  /// In en, this message translates to:
  /// **'Move results'**
  String get moveResults;

  /// No description provided for @moveResultsBody.
  ///
  /// In en, this message translates to:
  /// **'Moved: {moved}\nAlready there: {existing}\nFailed: {failed}\n\nPhotos that were \"already there\" are already in the Photos collection and were not copied again.'**
  String moveResultsBody(int moved, int existing, int failed);

  /// No description provided for @shareNotOnWeb.
  ///
  /// In en, this message translates to:
  /// **'Sharing files isn\'t available in the browser. Please use the mobile app.'**
  String get shareNotOnWeb;

  /// No description provided for @preparingPhotosToShare.
  ///
  /// In en, this message translates to:
  /// **'Preparing {count} photos for sharing…'**
  String preparingPhotosToShare(int count);

  /// No description provided for @couldNotPreparePhotos.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t prepare the photos for sharing.'**
  String get couldNotPreparePhotos;

  /// No description provided for @couldNotShare.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t share.'**
  String get couldNotShare;

  /// No description provided for @deletePhotosTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete photos'**
  String get deletePhotosTitle;

  /// No description provided for @deletePhotosConfirm.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete the selected photo?\n\nThis can\'t be undone.} other{Delete the {count} selected photos?\n\nThis can\'t be undone.}}'**
  String deletePhotosConfirm(int count);

  /// No description provided for @photosDeleted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo deleted.} other{{count} photos deleted.}}'**
  String photosDeleted(int count);

  /// No description provided for @photosDeletedSomeFailed.
  ///
  /// In en, this message translates to:
  /// **'{deleted} deleted, {failed} failed.'**
  String photosDeletedSomeFailed(int deleted, int failed);

  /// No description provided for @cannotDisplayImage.
  ///
  /// In en, this message translates to:
  /// **'This image can\'t be shown'**
  String get cannotDisplayImage;

  /// No description provided for @editPhotoDetails.
  ///
  /// In en, this message translates to:
  /// **'Edit photo details'**
  String get editPhotoDetails;

  /// No description provided for @titleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get titleLabel;

  /// No description provided for @phase.
  ///
  /// In en, this message translates to:
  /// **'Phase'**
  String get phase;

  /// No description provided for @noChangesMade.
  ///
  /// In en, this message translates to:
  /// **'No changes made.'**
  String get noChangesMade;

  /// No description provided for @photoDetailsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Photo details updated.'**
  String get photoDetailsUpdated;

  /// No description provided for @couldNotUpdate.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the changes.'**
  String get couldNotUpdate;

  /// No description provided for @preparingPhotoToShare.
  ///
  /// In en, this message translates to:
  /// **'Preparing photo for sharing…'**
  String get preparingPhotoToShare;

  /// No description provided for @deletePhotoTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete photo'**
  String get deletePhotoTitle;

  /// No description provided for @deletePhotoConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this photo? This can\'t be undone.'**
  String get deletePhotoConfirm;

  /// No description provided for @photoDeleted.
  ///
  /// In en, this message translates to:
  /// **'Photo deleted.'**
  String get photoDeleted;

  /// No description provided for @uploadPhotos.
  ///
  /// In en, this message translates to:
  /// **'Upload photos'**
  String get uploadPhotos;

  /// No description provided for @selectUploadType.
  ///
  /// In en, this message translates to:
  /// **'Choose what to upload'**
  String get selectUploadType;

  /// No description provided for @singlePhoto.
  ///
  /// In en, this message translates to:
  /// **'Single photo'**
  String get singlePhoto;

  /// No description provided for @multiplePhotos.
  ///
  /// In en, this message translates to:
  /// **'Multiple photos'**
  String get multiplePhotos;

  /// No description provided for @confirmUpload.
  ///
  /// In en, this message translates to:
  /// **'Confirm upload'**
  String get confirmUpload;

  /// No description provided for @uploadPhotosConfirm.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Upload 1 photo?} other{Upload {count} photos?}}'**
  String uploadPhotosConfirm(int count);

  /// No description provided for @photoDetails.
  ///
  /// In en, this message translates to:
  /// **'Photo details'**
  String get photoDetails;

  /// No description provided for @titleForPhotoN.
  ///
  /// In en, this message translates to:
  /// **'Title for photo {n} (optional)'**
  String titleForPhotoN(int n);

  /// No description provided for @titleOptional.
  ///
  /// In en, this message translates to:
  /// **'Title (optional)'**
  String get titleOptional;

  /// No description provided for @categoryOptionalField.
  ///
  /// In en, this message translates to:
  /// **'Category (optional)'**
  String get categoryOptionalField;

  /// No description provided for @phaseOptional.
  ///
  /// In en, this message translates to:
  /// **'Phase (optional)'**
  String get phaseOptional;

  /// No description provided for @uploadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Uploading'**
  String get uploadingTitle;

  /// No description provided for @uploadProgressPhotos.
  ///
  /// In en, this message translates to:
  /// **'{percent}%  ({done} of {total} photos)'**
  String uploadProgressPhotos(String percent, int done, int total);

  /// No description provided for @photosUploaded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo uploaded.} other{{count} photos uploaded.}}'**
  String photosUploaded(int count);

  /// No description provided for @photosUploadedSomeFailed.
  ///
  /// In en, this message translates to:
  /// **'{uploaded} uploaded, {failed} failed.'**
  String photosUploadedSomeFailed(int uploaded, int failed);

  /// No description provided for @couldNotUploadPhotos.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t upload the photos.'**
  String get couldNotUploadPhotos;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get unavailable;

  /// No description provided for @noPhotosAvailable.
  ///
  /// In en, this message translates to:
  /// **'No photos available yet.'**
  String get noPhotosAvailable;

  /// No description provided for @photosPromotedHint.
  ///
  /// In en, this message translates to:
  /// **'Photos shared by your project team will appear here.'**
  String get photosPromotedHint;

  /// No description provided for @financials.
  ///
  /// In en, this message translates to:
  /// **'Financials'**
  String get financials;

  /// No description provided for @financialDocsForMember.
  ///
  /// In en, this message translates to:
  /// **'Financial documents for {name}'**
  String financialDocsForMember(String name);

  /// No description provided for @indexBeingCreated.
  ///
  /// In en, this message translates to:
  /// **'This list is still being set up'**
  String get indexBeingCreated;

  /// No description provided for @indexBeingCreatedHint.
  ///
  /// In en, this message translates to:
  /// **'This usually takes a few minutes. Please try again shortly.'**
  String get indexBeingCreatedHint;

  /// No description provided for @couldNotLoadFinancialDocs.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load the financial documents'**
  String get couldNotLoadFinancialDocs;

  /// No description provided for @noFinancialDocsInSection.
  ///
  /// In en, this message translates to:
  /// **'No financial documents in this section'**
  String get noFinancialDocsInSection;

  /// No description provided for @selectSubcontractorFirst.
  ///
  /// In en, this message translates to:
  /// **'Please select a subcontractor first'**
  String get selectSubcontractorFirst;

  /// No description provided for @selectSupplierFirst.
  ///
  /// In en, this message translates to:
  /// **'Please select a supplier first'**
  String get selectSupplierFirst;

  /// No description provided for @uploadFileConfirm.
  ///
  /// In en, this message translates to:
  /// **'Upload {file}?'**
  String uploadFileConfirm(String file);

  /// No description provided for @fileSizeMb.
  ///
  /// In en, this message translates to:
  /// **'Size: {size} MB'**
  String fileSizeMb(String size);

  /// No description provided for @uploadingNamed.
  ///
  /// In en, this message translates to:
  /// **'Uploading {file}'**
  String uploadingNamed(String file);

  /// No description provided for @startingUpload.
  ///
  /// In en, this message translates to:
  /// **'Starting upload…'**
  String get startingUpload;

  /// No description provided for @financialDocAdded.
  ///
  /// In en, this message translates to:
  /// **'Financial document \"{title}\" added'**
  String financialDocAdded(String title);

  /// No description provided for @financialTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Title (e.g. invoice, receipt, payment)'**
  String get financialTitleHint;

  /// No description provided for @deleteDocumentTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete document'**
  String get deleteDocumentTitle;

  /// No description provided for @deleteFinancialDocConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this financial document? This can\'t be undone.'**
  String get deleteFinancialDocConfirm;

  /// No description provided for @financialDocDeleted.
  ///
  /// In en, this message translates to:
  /// **'Financial document deleted'**
  String get financialDocDeleted;

  /// No description provided for @qualitySafety.
  ///
  /// In en, this message translates to:
  /// **'Quality & Safety'**
  String get qualitySafety;

  /// No description provided for @quality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get quality;

  /// No description provided for @safety.
  ///
  /// In en, this message translates to:
  /// **'Safety'**
  String get safety;

  /// No description provided for @noDocumentsYet.
  ///
  /// In en, this message translates to:
  /// **'No documents added yet'**
  String get noDocumentsYet;

  /// No description provided for @qualityDocuments.
  ///
  /// In en, this message translates to:
  /// **'Quality documents'**
  String get qualityDocuments;

  /// No description provided for @safetyDocuments.
  ///
  /// In en, this message translates to:
  /// **'Safety documents'**
  String get safetyDocuments;

  /// No description provided for @uploadedColon.
  ///
  /// In en, this message translates to:
  /// **'Uploaded: {date}'**
  String uploadedColon(String date);

  /// No description provided for @documentUploaded.
  ///
  /// In en, this message translates to:
  /// **'Document uploaded'**
  String get documentUploaded;

  /// No description provided for @deleteNamedConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String deleteNamedConfirm(String name);

  /// No description provided for @scheduleTitle.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get scheduleTitle;

  /// No description provided for @generalSchedule.
  ///
  /// In en, this message translates to:
  /// **'General schedule'**
  String get generalSchedule;

  /// No description provided for @dynamicSchedule.
  ///
  /// In en, this message translates to:
  /// **'Dynamic schedule'**
  String get dynamicSchedule;

  /// No description provided for @ganttChart.
  ///
  /// In en, this message translates to:
  /// **'Gantt chart'**
  String get ganttChart;

  /// No description provided for @scheduleMonitor.
  ///
  /// In en, this message translates to:
  /// **'Schedule monitor'**
  String get scheduleMonitor;

  /// No description provided for @purchasingPlanResources.
  ///
  /// In en, this message translates to:
  /// **'Purchasing plan / resources'**
  String get purchasingPlanResources;

  /// No description provided for @couldNotLoadScheduleDocs.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load the schedule documents'**
  String get couldNotLoadScheduleDocs;

  /// No description provided for @noScheduleYet.
  ///
  /// In en, this message translates to:
  /// **'No schedule uploaded yet'**
  String get noScheduleYet;

  /// No description provided for @tapUploadSchedule.
  ///
  /// In en, this message translates to:
  /// **'Tap the upload button to add a schedule'**
  String get tapUploadSchedule;

  /// No description provided for @enterScheduleDocTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter schedule document title'**
  String get enterScheduleDocTitle;

  /// No description provided for @enterScheduleDocTitleBody.
  ///
  /// In en, this message translates to:
  /// **'Enter a title for this schedule document:'**
  String get enterScheduleDocTitleBody;

  /// No description provided for @scheduleDocHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Project master schedule Q1 2025'**
  String get scheduleDocHint;

  /// No description provided for @uploadingScheduleDoc.
  ///
  /// In en, this message translates to:
  /// **'Uploading schedule document'**
  String get uploadingScheduleDoc;

  /// No description provided for @scheduleDocUploaded.
  ///
  /// In en, this message translates to:
  /// **'Schedule document \"{title}\" uploaded'**
  String scheduleDocUploaded(String title);

  /// No description provided for @deleteScheduleDocTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete schedule document'**
  String get deleteScheduleDocTitle;

  /// No description provided for @scheduleDocDeleted.
  ///
  /// In en, this message translates to:
  /// **'Schedule document deleted'**
  String get scheduleDocDeleted;

  /// No description provided for @taskUpdated.
  ///
  /// In en, this message translates to:
  /// **'Task updated'**
  String get taskUpdated;

  /// No description provided for @taskMarkedStarted.
  ///
  /// In en, this message translates to:
  /// **'{task} marked as started'**
  String taskMarkedStarted(String task);

  /// No description provided for @taskMarkedCompleted.
  ///
  /// In en, this message translates to:
  /// **'{task} marked as completed'**
  String taskMarkedCompleted(String task);

  /// No description provided for @errorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorTitle;

  /// No description provided for @couldNotUpdateTaskStatus.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t update the task status. Please try again.'**
  String get couldNotUpdateTaskStatus;

  /// No description provided for @couldNotLoadData.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load the data'**
  String get couldNotLoadData;

  /// No description provided for @searchTasks.
  ///
  /// In en, this message translates to:
  /// **'Search tasks'**
  String get searchTasks;

  /// No description provided for @tabWithCount.
  ///
  /// In en, this message translates to:
  /// **'{label} ({count})'**
  String tabWithCount(String label, int count);

  /// No description provided for @startingSoonSection.
  ///
  /// In en, this message translates to:
  /// **'Starting soon (≤3 days)'**
  String get startingSoonSection;

  /// No description provided for @otherUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Other upcoming'**
  String get otherUpcoming;

  /// No description provided for @overdueToday.
  ///
  /// In en, this message translates to:
  /// **'Overdue today!'**
  String get overdueToday;

  /// No description provided for @overdueByDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Overdue by 1 day!} other{Overdue by {days} days!}}'**
  String overdueByDays(int days);

  /// No description provided for @startingToday.
  ///
  /// In en, this message translates to:
  /// **'Starting today!'**
  String get startingToday;

  /// No description provided for @dueInDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Due in 1 day} other{Due in {days} days}}'**
  String dueInDays(int days);

  /// No description provided for @markStarted.
  ///
  /// In en, this message translates to:
  /// **'Mark started'**
  String get markStarted;

  /// No description provided for @markCompleted.
  ///
  /// In en, this message translates to:
  /// **'Mark completed'**
  String get markCompleted;

  /// No description provided for @durationDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Duration: 1 day} other{Duration: {days} days}}'**
  String durationDays(int days);

  /// No description provided for @startedOn.
  ///
  /// In en, this message translates to:
  /// **'Started: {date}'**
  String startedOn(String date);

  /// No description provided for @completedOn.
  ///
  /// In en, this message translates to:
  /// **'Completed: {date}'**
  String completedOn(String date);

  /// No description provided for @noTasksMatchSearch.
  ///
  /// In en, this message translates to:
  /// **'No tasks match your search'**
  String get noTasksMatchSearch;

  /// No description provided for @noCategoryTasks.
  ///
  /// In en, this message translates to:
  /// **'No tasks here: {category}'**
  String noCategoryTasks(String category);

  /// No description provided for @noScheduleData.
  ///
  /// In en, this message translates to:
  /// **'No schedule data yet'**
  String get noScheduleData;

  /// No description provided for @noScheduleDataHint.
  ///
  /// In en, this message translates to:
  /// **'Add tasks in the Gantt chart to see schedule monitoring'**
  String get noScheduleDataHint;

  /// No description provided for @couldNotLoadResources.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load the resources'**
  String get couldNotLoadResources;

  /// No description provided for @noResourcesAdded.
  ///
  /// In en, this message translates to:
  /// **'No resources added'**
  String get noResourcesAdded;

  /// No description provided for @noResourcesHint.
  ///
  /// In en, this message translates to:
  /// **'Add resources to manage your purchasing plan'**
  String get noResourcesHint;

  /// No description provided for @addFirstResource.
  ///
  /// In en, this message translates to:
  /// **'Add first resource'**
  String get addFirstResource;

  /// No description provided for @totalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get totalLabel;

  /// No description provided for @resOnSite.
  ///
  /// In en, this message translates to:
  /// **'On site'**
  String get resOnSite;

  /// No description provided for @resInStorage.
  ///
  /// In en, this message translates to:
  /// **'In storage'**
  String get resInStorage;

  /// No description provided for @resNotOrdered.
  ///
  /// In en, this message translates to:
  /// **'Not ordered'**
  String get resNotOrdered;

  /// No description provided for @resOrdered.
  ///
  /// In en, this message translates to:
  /// **'Ordered'**
  String get resOrdered;

  /// No description provided for @resNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get resNotAvailable;

  /// No description provided for @resTypeMaterial.
  ///
  /// In en, this message translates to:
  /// **'Material'**
  String get resTypeMaterial;

  /// No description provided for @resTypeEquipment.
  ///
  /// In en, this message translates to:
  /// **'Equipment'**
  String get resTypeEquipment;

  /// No description provided for @resTypeLabor.
  ///
  /// In en, this message translates to:
  /// **'Labour'**
  String get resTypeLabor;

  /// No description provided for @resTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get resTypeOther;

  /// No description provided for @addResource.
  ///
  /// In en, this message translates to:
  /// **'Add resource'**
  String get addResource;

  /// No description provided for @editResource.
  ///
  /// In en, this message translates to:
  /// **'Edit resource'**
  String get editResource;

  /// No description provided for @deleteResource.
  ///
  /// In en, this message translates to:
  /// **'Delete resource'**
  String get deleteResource;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameLabel;

  /// No description provided for @quantityExampleHint.
  ///
  /// In en, this message translates to:
  /// **'Quantity (e.g. 500 kg)'**
  String get quantityExampleHint;

  /// No description provided for @typeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get typeLabel;

  /// No description provided for @searchResources.
  ///
  /// In en, this message translates to:
  /// **'Search resources…'**
  String get searchResources;

  /// No description provided for @resourceCleared.
  ///
  /// In en, this message translates to:
  /// **'Resource cleared'**
  String get resourceCleared;

  /// No description provided for @noneLabel.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get noneLabel;

  /// No description provided for @unknownResource.
  ///
  /// In en, this message translates to:
  /// **'Unknown resource'**
  String get unknownResource;

  /// No description provided for @projectDatesFallback.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load the project dates, so a default timeline is shown'**
  String get projectDatesFallback;

  /// No description provided for @workingOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline — changes will sync when the connection is back'**
  String get workingOffline;

  /// No description provided for @cannotDeleteSavedRow.
  ///
  /// In en, this message translates to:
  /// **'Saved rows in the default range can\'t be deleted'**
  String get cannotDeleteSavedRow;

  /// No description provided for @couldNotSaveTask.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the task.'**
  String get couldNotSaveTask;

  /// No description provided for @gCalcEndMainOutside.
  ///
  /// In en, this message translates to:
  /// **'The calculated end date would put this main task outside the project timeline. Please adjust the duration or start date.'**
  String get gCalcEndMainOutside;

  /// No description provided for @gCalcEndOutside.
  ///
  /// In en, this message translates to:
  /// **'The calculated end date would be outside the project timeline. Please adjust the duration or start date.'**
  String get gCalcEndOutside;

  /// No description provided for @gCalcEndAfterParent.
  ///
  /// In en, this message translates to:
  /// **'The calculated end date would be after the parent task ends'**
  String get gCalcEndAfterParent;

  /// No description provided for @gCalcEndBeforeParent.
  ///
  /// In en, this message translates to:
  /// **'The calculated end date would be before the parent task starts'**
  String get gCalcEndBeforeParent;

  /// No description provided for @gCalcStartMainOutside.
  ///
  /// In en, this message translates to:
  /// **'The calculated start date would put this main task outside the project timeline. Please adjust the duration or end date.'**
  String get gCalcStartMainOutside;

  /// No description provided for @gCalcStartOutside.
  ///
  /// In en, this message translates to:
  /// **'The calculated start date would be outside the project timeline. Please adjust the duration or end date.'**
  String get gCalcStartOutside;

  /// No description provided for @gCalcStartBeforeParent.
  ///
  /// In en, this message translates to:
  /// **'The calculated start date would be before the parent task starts'**
  String get gCalcStartBeforeParent;

  /// No description provided for @gCalcStartAfterParent.
  ///
  /// In en, this message translates to:
  /// **'The calculated start date would be after the parent task ends'**
  String get gCalcStartAfterParent;

  /// No description provided for @gMainStartInProject.
  ///
  /// In en, this message translates to:
  /// **'A main task\'s start date must be within the project timeline'**
  String get gMainStartInProject;

  /// No description provided for @gStartInProject.
  ///
  /// In en, this message translates to:
  /// **'The start date must be within the project timeline ({from} - {to})'**
  String gStartInProject(String from, String to);

  /// No description provided for @gStartBeforeParent.
  ///
  /// In en, this message translates to:
  /// **'The start date you chose is before the parent task starts'**
  String get gStartBeforeParent;

  /// No description provided for @gStartAfterParent.
  ///
  /// In en, this message translates to:
  /// **'The start date you chose is after the parent task ends'**
  String get gStartAfterParent;

  /// No description provided for @gMainEndInProject.
  ///
  /// In en, this message translates to:
  /// **'A main task\'s end date must be within the project timeline'**
  String get gMainEndInProject;

  /// No description provided for @gEndInProject.
  ///
  /// In en, this message translates to:
  /// **'The end date must be within the project timeline ({from} - {to})'**
  String gEndInProject(String from, String to);

  /// No description provided for @gEndAfterParent.
  ///
  /// In en, this message translates to:
  /// **'The end date you chose is after the parent task ends'**
  String get gEndAfterParent;

  /// No description provided for @gEndBeforeParent.
  ///
  /// In en, this message translates to:
  /// **'The end date you chose is before the parent task starts'**
  String get gEndBeforeParent;

  /// No description provided for @notSetLabel.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSetLabel;

  /// No description provided for @unnamed.
  ///
  /// In en, this message translates to:
  /// **'Unnamed'**
  String get unnamed;

  /// No description provided for @gAttemptedDate.
  ///
  /// In en, this message translates to:
  /// **'Date you chose: {date}'**
  String gAttemptedDate(String date);

  /// No description provided for @gParentTimeline.
  ///
  /// In en, this message translates to:
  /// **'Parent task \"{name}\" runs {from} - {to}'**
  String gParentTimeline(String name, String from, String to);

  /// No description provided for @gAdjustParentQuestion.
  ///
  /// In en, this message translates to:
  /// **'Would you like to adjust the parent task\'s dates to fit this change?'**
  String get gAdjustParentQuestion;

  /// No description provided for @gOutsideParentTitle.
  ///
  /// In en, this message translates to:
  /// **'Date outside the parent task'**
  String get gOutsideParentTitle;

  /// No description provided for @continueLabel2.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel2;

  /// No description provided for @gAdjustMainOutside.
  ///
  /// In en, this message translates to:
  /// **'Adjusting the main task would put it outside the project timeline'**
  String get gAdjustMainOutside;

  /// No description provided for @gAdjustParentOutside.
  ///
  /// In en, this message translates to:
  /// **'Adjusting the parent task would put it outside the project timeline'**
  String get gAdjustParentOutside;

  /// No description provided for @gParentAdjusted.
  ///
  /// In en, this message translates to:
  /// **'Parent task \"{name}\" dates were adjusted to fit the change'**
  String gParentAdjusted(String name);

  /// No description provided for @gStartAfterChild.
  ///
  /// In en, this message translates to:
  /// **'The start date can\'t be after sub-task \"{name}\" starts ({date})'**
  String gStartAfterChild(String name, String date);

  /// No description provided for @gEndBeforeChild.
  ///
  /// In en, this message translates to:
  /// **'The end date can\'t be before sub-task \"{name}\" ends ({date})'**
  String gEndBeforeChild(String name, String date);

  /// No description provided for @changesSavedLocally.
  ///
  /// In en, this message translates to:
  /// **'Changes saved on this device — they\'ll sync when you\'re online'**
  String get changesSavedLocally;

  /// No description provided for @allChangesSaved.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{All changes saved (1 row)} other{All changes saved ({count} rows)}}'**
  String allChangesSaved(int count);

  /// No description provided for @couldNotSaveSomeChanges.
  ///
  /// In en, this message translates to:
  /// **'Some changes couldn\'t be saved.'**
  String get couldNotSaveSomeChanges;

  /// No description provided for @addDates.
  ///
  /// In en, this message translates to:
  /// **'Add dates'**
  String get addDates;

  /// No description provided for @gProjectTimeline.
  ///
  /// In en, this message translates to:
  /// **'Project timeline: {from} - {to}'**
  String gProjectTimeline(String from, String to);

  /// No description provided for @gEditProjectQuestion.
  ///
  /// In en, this message translates to:
  /// **'Would you like to edit the project dates to fit this task?'**
  String get gEditProjectQuestion;

  /// No description provided for @gOutsideProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Date outside the project timeline'**
  String get gOutsideProjectTitle;

  /// No description provided for @editProjectDates.
  ///
  /// In en, this message translates to:
  /// **'Edit project dates'**
  String get editProjectDates;

  /// No description provided for @quantityOptional.
  ///
  /// In en, this message translates to:
  /// **'Quantity (optional)'**
  String get quantityOptional;

  /// No description provided for @quantityExamples.
  ///
  /// In en, this message translates to:
  /// **'e.g. 5, 10 kg, 2 hours'**
  String get quantityExamples;

  /// No description provided for @resourceAssignedQty.
  ///
  /// In en, this message translates to:
  /// **'Resource assigned: {name} ({qty})'**
  String resourceAssignedQty(String name, String qty);

  /// No description provided for @resourceAssigned.
  ///
  /// In en, this message translates to:
  /// **'Resource assigned: {name}'**
  String resourceAssigned(String name);

  /// No description provided for @noResourcesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No resources available'**
  String get noResourcesAvailable;

  /// No description provided for @addResourcesFirst.
  ///
  /// In en, this message translates to:
  /// **'Add resources to your project first'**
  String get addResourcesFirst;

  /// No description provided for @colNumber.
  ///
  /// In en, this message translates to:
  /// **'No.'**
  String get colNumber;

  /// No description provided for @colTaskName.
  ///
  /// In en, this message translates to:
  /// **'Task name'**
  String get colTaskName;

  /// No description provided for @colDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get colDuration;

  /// No description provided for @colStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get colStart;

  /// No description provided for @colFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get colFinish;

  /// No description provided for @colResources.
  ///
  /// In en, this message translates to:
  /// **'Resources'**
  String get colResources;

  /// No description provided for @colActualDates.
  ///
  /// In en, this message translates to:
  /// **'Actual dates'**
  String get colActualDates;

  /// No description provided for @enterTaskName.
  ///
  /// In en, this message translates to:
  /// **'Enter task name'**
  String get enterTaskName;

  /// No description provided for @addActualDates.
  ///
  /// In en, this message translates to:
  /// **'Add actual dates'**
  String get addActualDates;

  /// No description provided for @manageActualDates.
  ///
  /// In en, this message translates to:
  /// **'Manage actual dates'**
  String get manageActualDates;

  /// No description provided for @editActualDates.
  ///
  /// In en, this message translates to:
  /// **'Edit actual dates'**
  String get editActualDates;

  /// No description provided for @optActualStart.
  ///
  /// In en, this message translates to:
  /// **'Actual start date'**
  String get optActualStart;

  /// No description provided for @optActualFinish.
  ///
  /// In en, this message translates to:
  /// **'Actual finish date'**
  String get optActualFinish;

  /// No description provided for @optAddActualStart.
  ///
  /// In en, this message translates to:
  /// **'Add actual start date'**
  String get optAddActualStart;

  /// No description provided for @optAddActualFinish.
  ///
  /// In en, this message translates to:
  /// **'Add actual finish date'**
  String get optAddActualFinish;

  /// No description provided for @optEditActualStart.
  ///
  /// In en, this message translates to:
  /// **'Edit actual start date'**
  String get optEditActualStart;

  /// No description provided for @optEditActualFinish.
  ///
  /// In en, this message translates to:
  /// **'Edit actual finish date'**
  String get optEditActualFinish;

  /// No description provided for @optClearActual.
  ///
  /// In en, this message translates to:
  /// **'Clear all actual dates'**
  String get optClearActual;

  /// No description provided for @taskLabel.
  ///
  /// In en, this message translates to:
  /// **'Task: {name}'**
  String taskLabel(String name);

  /// No description provided for @unnamedTask.
  ///
  /// In en, this message translates to:
  /// **'Unnamed task'**
  String get unnamedTask;

  /// No description provided for @scheduledRange.
  ///
  /// In en, this message translates to:
  /// **'Scheduled: {from} - {to}'**
  String scheduledRange(String from, String to);

  /// No description provided for @currentActual.
  ///
  /// In en, this message translates to:
  /// **'Current actual: {dates}'**
  String currentActual(String dates);

  /// No description provided for @selectAction.
  ///
  /// In en, this message translates to:
  /// **'Choose an action:'**
  String get selectAction;

  /// No description provided for @gActStartAfterFinish.
  ///
  /// In en, this message translates to:
  /// **'The actual start date can\'t be after the actual finish date'**
  String get gActStartAfterFinish;

  /// No description provided for @gActStartBeforeProject.
  ///
  /// In en, this message translates to:
  /// **'The actual start date you chose is before the project starts'**
  String get gActStartBeforeProject;

  /// No description provided for @gActStartAfterProject.
  ///
  /// In en, this message translates to:
  /// **'The actual start date you chose is after the project ends'**
  String get gActStartAfterProject;

  /// No description provided for @gActStartBeforeParent.
  ///
  /// In en, this message translates to:
  /// **'The actual start date you chose is before the parent task starts'**
  String get gActStartBeforeParent;

  /// No description provided for @gActStartAfterParent.
  ///
  /// In en, this message translates to:
  /// **'The actual start date you chose is after the parent task ends'**
  String get gActStartAfterParent;

  /// No description provided for @gActStartBeforeScheduled.
  ///
  /// In en, this message translates to:
  /// **'The actual start date is before the scheduled start date'**
  String get gActStartBeforeScheduled;

  /// No description provided for @gActFinishBeforeStart.
  ///
  /// In en, this message translates to:
  /// **'The actual finish date can\'t be before the actual start date'**
  String get gActFinishBeforeStart;

  /// No description provided for @gActFinishBeforeProject.
  ///
  /// In en, this message translates to:
  /// **'The actual finish date you chose is before the project starts'**
  String get gActFinishBeforeProject;

  /// No description provided for @gActFinishAfterProject.
  ///
  /// In en, this message translates to:
  /// **'The actual finish date you chose is after the project ends'**
  String get gActFinishAfterProject;

  /// No description provided for @gActFinishBeforeParent.
  ///
  /// In en, this message translates to:
  /// **'The actual finish date you chose is before the parent task starts'**
  String get gActFinishBeforeParent;

  /// No description provided for @gActFinishAfterParent.
  ///
  /// In en, this message translates to:
  /// **'The actual finish date you chose is after the parent task ends'**
  String get gActFinishAfterParent;

  /// No description provided for @gActFinishAfterScheduled.
  ///
  /// In en, this message translates to:
  /// **'The actual finish date is after the scheduled finish date'**
  String get gActFinishAfterScheduled;

  /// No description provided for @actualStartSet.
  ///
  /// In en, this message translates to:
  /// **'Actual start date set to {date} — status: started'**
  String actualStartSet(String date);

  /// No description provided for @couldNotSaveChangesRetry.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t save your changes. Please try again.'**
  String get couldNotSaveChangesRetry;

  /// No description provided for @taskCompletedOn.
  ///
  /// In en, this message translates to:
  /// **'Task completed on {date}'**
  String taskCompletedOn(String date);

  /// No description provided for @taskCompletedOnWithStart.
  ///
  /// In en, this message translates to:
  /// **'Task completed on {date} (started {start})'**
  String taskCompletedOnWithStart(String date, String start);

  /// No description provided for @actualDatesCleared.
  ///
  /// In en, this message translates to:
  /// **'Actual dates cleared'**
  String get actualDatesCleared;

  /// No description provided for @couldNotClearDates.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t clear the dates. Please try again.'**
  String get couldNotClearDates;

  /// No description provided for @gBoundaryDate.
  ///
  /// In en, this message translates to:
  /// **'Limit date: {date}'**
  String gBoundaryDate(String date);

  /// No description provided for @gVarianceQuestion.
  ///
  /// In en, this message translates to:
  /// **'This may mean the schedule has slipped. Continue anyway?'**
  String get gVarianceQuestion;

  /// No description provided for @actualDateCheckTitle.
  ///
  /// In en, this message translates to:
  /// **'Check the actual date'**
  String get actualDateCheckTitle;

  /// No description provided for @continueAnyway.
  ///
  /// In en, this message translates to:
  /// **'Continue anyway'**
  String get continueAnyway;

  /// No description provided for @couldNotLoadProjectDates.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load project dates'**
  String get couldNotLoadProjectDates;

  /// No description provided for @offlineMode.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offlineMode;

  /// No description provided for @addRow.
  ///
  /// In en, this message translates to:
  /// **'Add row'**
  String get addRow;

  /// No description provided for @saveChangesTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChangesTooltip;

  /// No description provided for @makeMainTask.
  ///
  /// In en, this message translates to:
  /// **'Make main task'**
  String get makeMainTask;

  /// No description provided for @makeSubtask.
  ///
  /// In en, this message translates to:
  /// **'Make subtask'**
  String get makeSubtask;

  /// No description provided for @insertRowBelow.
  ///
  /// In en, this message translates to:
  /// **'Insert row below'**
  String get insertRowBelow;

  /// No description provided for @deleteRow.
  ///
  /// In en, this message translates to:
  /// **'Delete row'**
  String get deleteRow;

  /// No description provided for @dayDoneOngoing.
  ///
  /// In en, this message translates to:
  /// **'Work done – ongoing ✓'**
  String get dayDoneOngoing;

  /// No description provided for @dayDoneCompleted.
  ///
  /// In en, this message translates to:
  /// **'Work done – completed ✓'**
  String get dayDoneCompleted;

  /// No description provided for @dayHoliday.
  ///
  /// In en, this message translates to:
  /// **'Holiday (H)'**
  String get dayHoliday;

  /// No description provided for @dayBadWeather.
  ///
  /// In en, this message translates to:
  /// **'Bad weather (W)'**
  String get dayBadWeather;

  /// No description provided for @dayNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get dayNotSet;

  /// No description provided for @progressSaved.
  ///
  /// In en, this message translates to:
  /// **'Progress monitor saved'**
  String get progressSaved;

  /// No description provided for @couldNotSaveProgress.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the progress monitor.'**
  String get couldNotSaveProgress;

  /// No description provided for @importStepPick.
  ///
  /// In en, this message translates to:
  /// **'Opening file picker…'**
  String get importStepPick;

  /// No description provided for @importStepRead.
  ///
  /// In en, this message translates to:
  /// **'Reading the file…'**
  String get importStepRead;

  /// No description provided for @importStepParse.
  ///
  /// In en, this message translates to:
  /// **'Reading the Excel sheet…'**
  String get importStepParse;

  /// No description provided for @importStepProcess.
  ///
  /// In en, this message translates to:
  /// **'Processing rows…'**
  String get importStepProcess;

  /// No description provided for @importStepProcessN.
  ///
  /// In en, this message translates to:
  /// **'Processing {count} rows…'**
  String importStepProcessN(int count);

  /// No description provided for @importStepConfirm.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your confirmation…'**
  String get importStepConfirm;

  /// No description provided for @importStepConfirmN.
  ///
  /// In en, this message translates to:
  /// **'Found {count} rows — waiting for your confirmation…'**
  String importStepConfirmN(int count);

  /// No description provided for @importStepSave.
  ///
  /// In en, this message translates to:
  /// **'Saving rows…'**
  String get importStepSave;

  /// No description provided for @importStepSaveN.
  ///
  /// In en, this message translates to:
  /// **'Saving {count} rows…'**
  String importStepSaveN(int count);

  /// No description provided for @importStepWrite.
  ///
  /// In en, this message translates to:
  /// **'Uploading to the server…'**
  String get importStepWrite;

  /// No description provided for @noRowsInExcel.
  ///
  /// In en, this message translates to:
  /// **'No rows were found in the Excel file.'**
  String get noRowsInExcel;

  /// No description provided for @importFromExcel.
  ///
  /// In en, this message translates to:
  /// **'Import from Excel'**
  String get importFromExcel;

  /// No description provided for @importConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Found 1 row.} other{Found {count} rows.}}\nThis will replace the current table.\n\n{matched, plural, =0{No rows matched an existing task, so all rows start with no progress marks.} =1{1 row matched an existing task by name and will keep its recorded progress marks; any other row starts with no marks.} other{{matched} rows matched an existing task by name and will keep their recorded progress marks; any other row starts with no marks.}} Continue?'**
  String importConfirmBody(int count, int matched);

  /// No description provided for @importAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importAction;

  /// No description provided for @importedRows.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Imported 1 row} other{Imported {count} rows}}'**
  String importedRows(int count);

  /// No description provided for @couldNotImport.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t import the file.'**
  String get couldNotImport;

  /// No description provided for @newTask.
  ///
  /// In en, this message translates to:
  /// **'New task'**
  String get newTask;

  /// No description provided for @marksRetrying.
  ///
  /// In en, this message translates to:
  /// **'Some progress marks couldn\'t sync — retrying automatically…'**
  String get marksRetrying;

  /// No description provided for @clearNotSet.
  ///
  /// In en, this message translates to:
  /// **'Clear / not set'**
  String get clearNotSet;

  /// No description provided for @importingExcel.
  ///
  /// In en, this message translates to:
  /// **'Importing Excel'**
  String get importingExcel;

  /// No description provided for @pleaseWait.
  ///
  /// In en, this message translates to:
  /// **'Please wait…'**
  String get pleaseWait;

  /// No description provided for @taskProgressMonitorTitle.
  ///
  /// In en, this message translates to:
  /// **'{project} — Task progress monitor'**
  String taskProgressMonitorTitle(String project);

  /// No description provided for @projectDateExtensions.
  ///
  /// In en, this message translates to:
  /// **'Project date extensions'**
  String get projectDateExtensions;

  /// No description provided for @projectProgressPercent.
  ///
  /// In en, this message translates to:
  /// **'Project: {percent}%'**
  String projectProgressPercent(String percent);

  /// No description provided for @rowsToggle.
  ///
  /// In en, this message translates to:
  /// **'# Rows'**
  String get rowsToggle;

  /// No description provided for @removeLast.
  ///
  /// In en, this message translates to:
  /// **'Remove last'**
  String get removeLast;

  /// No description provided for @importExcel.
  ///
  /// In en, this message translates to:
  /// **'Import Excel'**
  String get importExcel;

  /// No description provided for @legendDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get legendDone;

  /// No description provided for @legendHoliday.
  ///
  /// In en, this message translates to:
  /// **'Holiday'**
  String get legendHoliday;

  /// No description provided for @legendBadWeather.
  ///
  /// In en, this message translates to:
  /// **'Bad weather'**
  String get legendBadWeather;

  /// No description provided for @startDateCol.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get startDateCol;

  /// No description provided for @finishDateCol.
  ///
  /// In en, this message translates to:
  /// **'Finish date'**
  String get finishDateCol;

  /// No description provided for @noPhasesWithDates.
  ///
  /// In en, this message translates to:
  /// **'No phases with start/end dates yet'**
  String get noPhasesWithDates;

  /// No description provided for @deleteTaskRowTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete task row?'**
  String get deleteTaskRowTitle;

  /// No description provided for @deleteTaskRowBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" and its recorded progress marks will be removed.'**
  String deleteTaskRowBody(String name);

  /// No description provided for @outsideProjectBounds.
  ///
  /// In en, this message translates to:
  /// **'Outside the project dates'**
  String get outsideProjectBounds;

  /// No description provided for @dateBeforeProjectStart.
  ///
  /// In en, this message translates to:
  /// **'That date is before the project\'s start date ({date}). Request a project date extension first — once approved, this and other tasks can use the new range.'**
  String dateBeforeProjectStart(String date);

  /// No description provided for @dateAfterProjectEnd.
  ///
  /// In en, this message translates to:
  /// **'That date is after the project\'s end date ({date}). Request a project date extension first — once approved, this and other tasks can use the new range.'**
  String dateAfterProjectEnd(String date);

  /// No description provided for @requestProjectExtension.
  ///
  /// In en, this message translates to:
  /// **'Request project extension'**
  String get requestProjectExtension;

  /// No description provided for @requestProjectDateExtension.
  ///
  /// In en, this message translates to:
  /// **'Request project date extension'**
  String get requestProjectDateExtension;

  /// No description provided for @extensionMainlyEnd.
  ///
  /// In en, this message translates to:
  /// **'This mainly affects the completion date, but the start date can be changed too if needed.'**
  String get extensionMainlyEnd;

  /// No description provided for @reasonForExtension.
  ///
  /// In en, this message translates to:
  /// **'Reason for extension *'**
  String get reasonForExtension;

  /// No description provided for @reasonForExtensionHint.
  ///
  /// In en, this message translates to:
  /// **'Why does the project timeline need to change?'**
  String get reasonForExtensionHint;

  /// No description provided for @extensionApprovalNote.
  ///
  /// In en, this message translates to:
  /// **'Once approved by the Project Manager or a MainAdmin: the project\'s dates update, any phase whose end matched the old project end date moves with it, and task dates can be edited freely within the new range.'**
  String get extensionApprovalNote;

  /// No description provided for @submitRequest.
  ///
  /// In en, this message translates to:
  /// **'Submit request'**
  String get submitRequest;

  /// No description provided for @nExtRequestedTitle.
  ///
  /// In en, this message translates to:
  /// **'Project date extension requested — {project}'**
  String nExtRequestedTitle(String project);

  /// No description provided for @nExtRequestedBody.
  ///
  /// In en, this message translates to:
  /// **'{name} requested new project dates: {from} – {to}.'**
  String nExtRequestedBody(String name, String from, String to);

  /// No description provided for @aUser.
  ///
  /// In en, this message translates to:
  /// **'A user'**
  String get aUser;

  /// No description provided for @extensionRequestedSnack.
  ///
  /// In en, this message translates to:
  /// **'Project extension requested — waiting for approval.'**
  String get extensionRequestedSnack;

  /// No description provided for @couldNotSubmitRequest.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t submit the request.'**
  String get couldNotSubmitRequest;

  /// No description provided for @nExtApprovedTitle.
  ///
  /// In en, this message translates to:
  /// **'Project date extension approved — {project}'**
  String nExtApprovedTitle(String project);

  /// No description provided for @nExtRejectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Project date extension rejected — {project}'**
  String nExtRejectedTitle(String project);

  /// No description provided for @nExtApprovedBody.
  ///
  /// In en, this message translates to:
  /// **'Project dates are now {from} – {to}.'**
  String nExtApprovedBody(String from, String to);

  /// No description provided for @nExtRejectedBody.
  ///
  /// In en, this message translates to:
  /// **'The project keeps its current dates.'**
  String get nExtRejectedBody;

  /// No description provided for @nExtRejectedBodyReason.
  ///
  /// In en, this message translates to:
  /// **'The project keeps its current dates. Reason: {reason}'**
  String nExtRejectedBodyReason(String reason);

  /// No description provided for @extensionApprovedSnack.
  ///
  /// In en, this message translates to:
  /// **'Extension approved.'**
  String get extensionApprovedSnack;

  /// No description provided for @extensionRejectedSnack.
  ///
  /// In en, this message translates to:
  /// **'Extension rejected.'**
  String get extensionRejectedSnack;

  /// No description provided for @couldNotRecordResponse.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t record your response.'**
  String get couldNotRecordResponse;

  /// No description provided for @requestedByNameRole.
  ///
  /// In en, this message translates to:
  /// **'Requested by {name} ({role})'**
  String requestedByNameRole(String name, String role);

  /// No description provided for @approvedByName.
  ///
  /// In en, this message translates to:
  /// **'Approved by {name}'**
  String approvedByName(String name);

  /// No description provided for @rejectedByName.
  ///
  /// In en, this message translates to:
  /// **'Rejected by {name}'**
  String rejectedByName(String name);

  /// No description provided for @reasonColon.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String reasonColon(String reason);

  /// No description provided for @rejectionReasonOptional.
  ///
  /// In en, this message translates to:
  /// **'Reason for rejection (optional)'**
  String get rejectionReasonOptional;

  /// No description provided for @confirmReject.
  ///
  /// In en, this message translates to:
  /// **'Confirm rejection'**
  String get confirmReject;

  /// No description provided for @awaitingPmApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval from the Project Manager or a MainAdmin.'**
  String get awaitingPmApproval;

  /// No description provided for @deadlinePassedRequest.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s deadline has passed — request a date extension to continue.'**
  String deadlinePassedRequest(String name);

  /// No description provided for @requestAction.
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get requestAction;

  /// No description provided for @alreadyCompletedTask.
  ///
  /// In en, this message translates to:
  /// **'{name} is already marked as completed.'**
  String alreadyCompletedTask(String name);

  /// No description provided for @workDaysCount.
  ///
  /// In en, this message translates to:
  /// **'{done} / {total} work days'**
  String workDaysCount(int done, int total);

  /// No description provided for @percentComplete.
  ///
  /// In en, this message translates to:
  /// **'{percent}% complete'**
  String percentComplete(String percent);

  /// No description provided for @noTasksDefined.
  ///
  /// In en, this message translates to:
  /// **'No tasks yet'**
  String get noTasksDefined;

  /// No description provided for @noTasksDefinedHint.
  ///
  /// In en, this message translates to:
  /// **'Use \"Import Excel\" to load from a file,\nor \"Add row\" to create tasks manually.'**
  String get noTasksDefinedHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
