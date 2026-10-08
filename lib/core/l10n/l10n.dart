import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

export '../../l10n/app_localizations.dart';

/// The languages AlmaWorks is fully translated into.
enum AppLanguage {
  english('en', 'English', '🇬🇧'),
  italian('it', 'Italiano', '🇮🇹');

  const AppLanguage(this.code, this.nativeName, this.flag);

  final String code;

  /// Always shown in the language itself, so anyone can find their own.
  final String nativeName;
  final String flag;

  Locale get locale => Locale(code);

  static List<Locale> get supportedLocales => [for (final l in values) l.locale];

  /// Accepts both the enum name (stored by the old LocaleProvider, e.g.
  /// "italian") and the language code. Anything else — including the
  /// retired "swahili" — returns null so the caller falls back to a default.
  static AppLanguage? fromStored(String? raw) {
    for (final l in values) {
      if (l.name == raw || l.code == raw) return l;
    }
    return null;
  }

  static AppLanguage fromCode(String? code) => fromStored(code) ?? english;
}

/// `context.l10n.someText` — the translations for the language on screen.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

AppLocalizations? _current;

/// The current translations for code with no BuildContext (services,
/// models, notification builders). Kept up to date by AppearanceScope.
AppLocalizations get l10nNow => _current ?? lookupAppLocalizations(const Locale('en'));

/// The language currently on screen.
AppLanguage get currentLanguage => AppLanguage.fromCode(l10nNow.localeName);

void setCurrentL10n(AppLocalizations l10n) => _current = l10n;

/// Translations for a specific language (e.g. to write text that someone
/// else, who may use a different language, will read).
AppLocalizations l10nFor(AppLanguage language) => lookupAppLocalizations(language.locale);

/// Display name for a stored role value ('MainAdmin', 'Client', …). The
/// stored values never change — only what's shown.
String roleLabel(String role, [AppLocalizations? l]) {
  final t = l ?? l10nNow;
  return switch (role) {
    'MainAdmin' => t.roleMainAdmin,
    'SystemAdmin' => t.roleSystemAdmin,
    'Admin' => t.roleAdmin,
    'Client' => t.roleClient,
    'Technician' => t.roleTechnician,
    'SubContractor' => t.roleSubContractor,
    'Manager' => t.roleManager,
    '' => t.roleMember,
    _ => role,
  };
}

/// Display name for a stored project status ('active' / 'completed' /
/// anything else = untracked).
String projectStatusLabel(String? status, [AppLocalizations? l]) {
  final t = l ?? l10nNow;
  return switch (status) {
    'active' => t.projectStatusActive,
    'completed' => t.projectStatusCompleted,
    _ => t.projectStatusUntracked,
  };
}

// ── Text stored in Firestore for other people to read ─────────────────────────
//
// Notifications are written by one person's device and read by someone
// else, whose language may differ. So they're stored in every language:
// `title`/`body` hold English (what older app versions and anything else
// reading the doc expect) and `i18n.<code>.title/body` hold the others.
// The app shows the reader's language ([localizedField]) and the push
// Cloud Functions pick the recipient's (Users.language).

/// `{'title': …, 'body': …, 'i18n': {'it': {'title': …, 'body': …}}}`
Map<String, dynamic> notificationText({
  required String Function(AppLocalizations l) title,
  required String Function(AppLocalizations l) body,
}) {
  final en = l10nFor(AppLanguage.english);
  return {
    'title': title(en),
    'body': body(en),
    'i18n': {
      for (final lang in AppLanguage.values)
        if (lang != AppLanguage.english) lang.code: {'title': title(l10nFor(lang)), 'body': body(l10nFor(lang))},
    },
  };
}

/// One text in every language: `{'en': …, 'it': …}`.
Map<String, String> inAllLanguages(String Function(AppLocalizations l) text) => {
  for (final lang in AppLanguage.values) lang.code: text(l10nFor(lang)),
};

/// Reads [field] from a doc written with [notificationText], in the
/// language on screen; falls back to the English top-level field.
String? localizedField(Map<String, dynamic> data, String field, {AppLanguage? language}) {
  final lang = language ?? currentLanguage;
  final i18n = data['i18n'];
  if (lang != AppLanguage.english && i18n is Map) {
    final forLang = i18n[lang.code];
    if (forLang is Map && forLang[field] is String) return forLang[field] as String;
  }
  return data[field] as String?;
}
