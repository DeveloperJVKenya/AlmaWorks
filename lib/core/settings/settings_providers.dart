import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import 'app_font.dart';

/// Overridden in `main.dart` with an instance loaded before `runApp`, so
/// every setting below is read synchronously on the first frame — no flash
/// of the wrong theme, font or language.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden in main() before runApp');
});

// Keys. `darkModeEnabled` and `appLanguage` predate this file (the old
// ThemeProvider / LocaleProvider) and are migrated on read.
const _themeModeKey = 'settings.themeMode';
const _legacyDarkModeKey = 'darkModeEnabled';
const _fontKey = 'settings.font';
const _textScaleKey = 'settings.textScale';
const _boldTextKey = 'settings.boldText';
const _highContrastKey = 'settings.highContrast';
const _reduceMotionKey = 'settings.reduceMotion';
const _languageKey = 'appLanguage';
const _notificationsKey = 'notificationsEnabled';

abstract class _PrefNotifier<T> extends Notifier<T> {
  SharedPreferences get prefs => ref.read(sharedPreferencesProvider);
}

// ── Appearance ───────────────────────────────────────────────────────────────

class ThemeModeController extends _PrefNotifier<ThemeMode> {
  @override
  ThemeMode build() {
    final raw = prefs.getString(_themeModeKey);
    if (raw == null) {
      // Before System/Light/Dark existed there was only a dark-mode switch.
      final legacyDark = prefs.getBool(_legacyDarkModeKey);
      if (legacyDark != null) return legacyDark ? ThemeMode.dark : ThemeMode.light;
      return ThemeMode.light;
    }
    return ThemeMode.values.firstWhere((m) => m.name == raw, orElse: () => ThemeMode.light);
  }

  void set(ThemeMode mode) {
    state = mode;
    prefs.setString(_themeModeKey, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class AppFontController extends _PrefNotifier<AppFont> {
  @override
  AppFont build() => AppFont.fromName(prefs.getString(_fontKey));

  void set(AppFont font) {
    state = font;
    prefs.setString(_fontKey, font.name);
  }
}

final appFontProvider = NotifierProvider<AppFontController, AppFont>(AppFontController.new);

// ── Accessibility ────────────────────────────────────────────────────────────

/// Text size multiplier, applied on top of the device's own text-size
/// setting at the app root (see AppearanceScope).
class TextScaleController extends _PrefNotifier<double> {
  static const double min = 0.85;
  static const double max = 1.4;
  static const double standard = 1.0;

  @override
  double build() => (prefs.getDouble(_textScaleKey) ?? standard).clamp(min, max);

  void set(double scale) {
    state = scale.clamp(min, max);
    prefs.setDouble(_textScaleKey, state);
  }
}

final textScaleProvider = NotifierProvider<TextScaleController, double>(TextScaleController.new);

class _BoolSetting extends _PrefNotifier<bool> {
  _BoolSetting(this._key, this._default);
  final String _key;
  final bool _default;

  @override
  bool build() => prefs.getBool(_key) ?? _default;

  void set(bool value) {
    state = value;
    prefs.setBool(_key, value);
  }
}

/// Draws all text in bold (Flutter's `MediaQuery.boldText`).
final boldTextProvider = NotifierProvider<_BoolSetting, bool>(() => _BoolSetting(_boldTextKey, false));

/// Stronger text and border colors (see AppColors / AppTheme).
final highContrastProvider = NotifierProvider<_BoolSetting, bool>(() => _BoolSetting(_highContrastKey, false));

/// Turns off page transitions and decorative animations.
final reduceMotionProvider = NotifierProvider<_BoolSetting, bool>(() => _BoolSetting(_reduceMotionKey, false));

/// On-device (system tray) notifications. Read without Riverpod by
/// NotificationPreferences, which shares the same key.
final deviceNotificationsProvider =
    NotifierProvider<_BoolSetting, bool>(() => _BoolSetting(_notificationsKey, true));

// ── Language ─────────────────────────────────────────────────────────────────

class LanguageController extends _PrefNotifier<AppLanguage> {
  @override
  AppLanguage build() {
    final saved = AppLanguage.fromStored(prefs.getString(_languageKey));
    if (saved != null) return saved;
    // First run: follow the device if it's set to Italian.
    final device = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return device == 'it' ? AppLanguage.italian : AppLanguage.english;
  }

  void set(AppLanguage language) {
    state = language;
    prefs.setString(_languageKey, language.name);
  }
}

final languageProvider = NotifierProvider<LanguageController, AppLanguage>(LanguageController.new);

/// Puts every appearance, accessibility and language setting back to its
/// default (notifications are left alone — they're not an appearance).
void resetDisplaySettings(WidgetRef ref) {
  ref.read(themeModeProvider.notifier).set(ThemeMode.light);
  ref.read(appFontProvider.notifier).set(AppFont.fallback);
  ref.read(textScaleProvider.notifier).set(TextScaleController.standard);
  ref.read(boldTextProvider.notifier).set(false);
  ref.read(highContrastProvider.notifier).set(false);
  ref.read(reduceMotionProvider.notifier).set(false);
}
