import 'package:shared_preferences/shared_preferences.dart';

/// Persisted "Notifications" toggle from the Account screen. Every local
/// notification call site (AwesomeNotifications().createNotification) should
/// check [isEnabled] before firing, so the toggle actually suppresses
/// notifications instead of just flipping cosmetic UI state that resets on
/// next visit.
class NotificationPreferences {
  NotificationPreferences._();

  static const _key = 'notificationsEnabled';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}
