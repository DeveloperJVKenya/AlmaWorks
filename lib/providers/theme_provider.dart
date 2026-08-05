import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A [ChangeNotifier] that holds the app's dark-mode preference, persisted
/// to SharedPreferences so it survives restarts — same pattern as
/// [LocaleProvider]. Wrap [MaterialApp] with a [ListenableBuilder] and pass
/// [themeProvider.themeMode] to [MaterialApp.themeMode].
///
/// Scope note: most existing screens paint with hardcoded colors (the navy
/// `0xFF0A2E5A` brand color, white cards, black text) rather than reading
/// from [Theme.of(context)], so toggling this will correctly switch
/// Flutter's own default surfaces (dialogs, switches, default text/icon
/// colors, scaffold background where not overridden) but will NOT re-theme
/// every custom-colored widget across the app — that would require an
/// app-wide theming pass beyond this toggle's scope.
class ThemeProvider extends ChangeNotifier {
  static const _prefsKey = 'darkModeEnabled';

  bool _isDarkMode = false;
  bool _isLoaded = false;

  bool get isDarkMode => _isDarkMode;
  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  /// Loads the persisted preference. Call once at app startup before the
  /// first frame that depends on it, same as other one-time init steps.
  Future<void> load() async {
    if (_isLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool(_prefsKey) ?? false;
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setDarkMode(bool enabled) async {
    if (_isDarkMode == enabled) return;
    _isDarkMode = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
  }
}
