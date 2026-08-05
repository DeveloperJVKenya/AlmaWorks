/// Derives a stable, deterministic notification id from a Firestore document
/// id. Using the same id everywhere a given `AdminNotificationQueue` doc is
/// displayed (the live Firestore listener path AND the FCM push path added
/// for terminated-app delivery) means the two can never show as two separate
/// entries in the system tray — whichever fires second just silently
/// updates/replaces the first instead of duplicating it.
int stableNotificationId(String docId) {
  return docId.hashCode & 0x7FFFFFFF;
}
