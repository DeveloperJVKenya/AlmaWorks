import 'package:intl/intl.dart';
import 'package:almaworks/core/l10n/l10n.dart';

/// "Today" / "Tomorrow" / "In N days" for a date within the next week,
/// falling back to an absolute `d MMM yyyy` date beyond that — makes a
/// booking/request date picker feel live instead of showing only a raw
/// calendar date. Modeled on the day-bucket phrasing already used in
/// lib/models/schedule_monitor_model.dart, extracted here since Inventory
/// had no shared date-label helper of its own.
String relativeDayLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final daysDiff = target.difference(today).inDays;

  final l = l10nNow;
  if (daysDiff == 0) return l.today;
  if (daysDiff == 1) return l.tomorrow;
  if (daysDiff == -1) return l.yesterday;
  if (daysDiff > 1 && daysDiff <= 7) return l.inDays(daysDiff);
  if (daysDiff < -1 && daysDiff >= -7) return l.daysAgoLong(-daysDiff);
  return DateFormat('d MMM yyyy').format(date);
}

/// Combines the relative label with the absolute date for clarity, e.g.
/// "Tomorrow (26 Aug 2026)" — falls back to just the absolute date once
/// [relativeDayLabel] itself is already an absolute date.
String relativeDayLabelWithDate(DateTime date) {
  final relative = relativeDayLabel(date);
  final absolute = DateFormat('d MMM yyyy').format(date);
  return relative == absolute ? absolute : '$relative ($absolute)';
}
