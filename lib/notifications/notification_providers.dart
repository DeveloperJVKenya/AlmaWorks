import 'package:almaworks/notifications/app_notification.dart';
import 'package:almaworks/rbacsystem/client_request_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The signed-in user as the notification center needs them: uid for the
/// targeted queues, role for the role-broadcast queue (writers target the
/// role stored on the Users doc), username for display.
class NotificationUser {
  final String uid;
  final String role;
  final String username;
  const NotificationUser({required this.uid, required this.role, required this.username});
}

final _firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final authUidProvider = StreamProvider<String?>((ref) {
  return FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);
});

/// Live, so a role change (or sign-out/in) re-targets every query below.
final notificationUserProvider = StreamProvider<NotificationUser?>((ref) {
  final uid = ref.watch(authUidProvider).valueOrNull;
  if (uid == null) return Stream.value(null);
  return ref.watch(_firestoreProvider).collection('Users').where('uid', isEqualTo: uid).limit(1).snapshots().map((
    snap,
  ) {
    final doc = snap.docs.isEmpty ? null : snap.docs.first;
    return NotificationUser(uid: uid, role: doc?.data()['role'] as String? ?? 'Client', username: doc?.id ?? '');
  });
});

/// How many of each source to keep live — the inbox is a recent-activity
/// view, not an archive.
const _perSourceLimit = 150;

final _userQueueProvider = StreamProvider<List<AppNotification>>((ref) {
  final user = ref.watch(notificationUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref
      .watch(_firestoreProvider)
      .collection(NotificationSources.user)
      .where('targetUid', isEqualTo: user.uid)
      .orderBy('createdAt', descending: true)
      .limit(_perSourceLimit)
      .snapshots()
      .map((snap) => [for (final d in snap.docs) ?AppNotification.fromQueueDoc(d, NotificationSources.user, user.uid)]);
});

final _adminQueueProvider = StreamProvider<List<AppNotification>>((ref) {
  final user = ref.watch(notificationUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref
      .watch(_firestoreProvider)
      .collection(NotificationSources.admin)
      .where('targetRoles', arrayContains: user.role)
      .orderBy('createdAt', descending: true)
      .limit(_perSourceLimit)
      .snapshots()
      .map(
        (snap) => [for (final d in snap.docs) ?AppNotification.fromQueueDoc(d, NotificationSources.admin, user.uid)],
      );
});

final _scheduleQueueProvider = StreamProvider<List<AppNotification>>((ref) {
  final user = ref.watch(notificationUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref
      .watch(_firestoreProvider)
      .collection(NotificationSources.schedule)
      .where('userId', isEqualTo: user.uid)
      .orderBy('createdAt', descending: true)
      .limit(_perSourceLimit)
      .snapshots()
      .map((snap) => snap.docs.map(AppNotification.fromScheduleDoc).toList());
});

/// Every notification for the signed-in user, newest first. Loading until
/// all three sources have reported; an error in one source surfaces only
/// if every source failed (the rest still show).
final notificationsProvider = Provider<AsyncValue<List<AppNotification>>>((ref) {
  final sources = [ref.watch(_userQueueProvider), ref.watch(_adminQueueProvider), ref.watch(_scheduleQueueProvider)];
  if (sources.any((s) => s.isLoading && !s.hasValue)) return const AsyncLoading();
  final ok = sources.where((s) => s.hasValue).toList();
  if (ok.isEmpty) {
    final failed = sources.firstWhere((s) => s.hasError);
    return AsyncError(failed.error!, failed.stackTrace ?? StackTrace.current);
  }
  final all = [for (final s in ok) ...s.value!]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return AsyncData(all);
});

/// Sources that failed to load (shown as a warning above the list).
final notificationSourceErrorsProvider = Provider<int>((ref) {
  return [
    ref.watch(_userQueueProvider),
    ref.watch(_adminQueueProvider),
    ref.watch(_scheduleQueueProvider),
  ].where((s) => s.hasError).length;
});

final unreadNotificationCountProvider = Provider<int>((ref) {
  final all = ref.watch(notificationsProvider).valueOrNull ?? const <AppNotification>[];
  return all.where((n) => !n.isRead).length;
});

/// The list filter: everything, unread only, or one category.
sealed class NotificationFilter {
  const NotificationFilter();
  bool matches(AppNotification n);
  String get label;
}

class AllNotifications extends NotificationFilter {
  const AllNotifications();
  @override
  bool matches(AppNotification n) => true;
  @override
  String get label => 'All';
  @override
  bool operator ==(Object other) => other is AllNotifications;
  @override
  int get hashCode => 0;
}

class UnreadNotifications extends NotificationFilter {
  const UnreadNotifications();
  @override
  bool matches(AppNotification n) => !n.isRead;
  @override
  String get label => 'Unread';
  @override
  bool operator ==(Object other) => other is UnreadNotifications;
  @override
  int get hashCode => 1;
}

class CategoryNotifications extends NotificationFilter {
  const CategoryNotifications(this.category);
  final NotificationCategory category;
  @override
  bool matches(AppNotification n) => n.category == category;
  @override
  String get label => category.label;
  @override
  bool operator ==(Object other) => other is CategoryNotifications && other.category == category;
  @override
  int get hashCode => category.hashCode;
}

final notificationFilterProvider = StateProvider.autoDispose<NotificationFilter>((ref) => const AllNotifications());

/// The live state of an access request a notification is about, so admins
/// see "Approved by … as Technician" (or denied) on every copy of the
/// request alert — whichever admin acted, and however long after it was
/// sent — instead of a stale "new request" forever.
final accessRequestProvider = StreamProvider.autoDispose.family<ClientRequest?, String>((ref, requestId) {
  return ref
      .watch(_firestoreProvider)
      .collection('ClientRequests')
      .doc(requestId)
      .snapshots()
      .map((snap) => snap.exists ? ClientRequest.fromFirestore(snap) : null);
});

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(_firestoreProvider));
});

/// Read/unread/delete — shared role-broadcast docs are updated per person
/// (readBy / hiddenFor) so one admin's actions don't change another's inbox.
class NotificationRepository {
  NotificationRepository(this._db);
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _ref(AppNotification n) => _db.collection(n.collection).doc(n.id);

  Map<String, dynamic> _readUpdate(AppNotification n, String uid, bool read) =>
      n.collection == NotificationSources.admin
      ? {
          'readBy': read ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid]),
        }
      : {'isRead': read, if (read) 'readAt': FieldValue.serverTimestamp()};

  Future<void> setRead(AppNotification n, String uid, {bool read = true}) => _ref(n).update(_readUpdate(n, uid, read));

  Future<void> markAllRead(Iterable<AppNotification> items, String uid) async {
    final unread = items.where((n) => !n.isRead).toList();
    for (var i = 0; i < unread.length; i += 400) {
      final batch = _db.batch();
      for (final n in unread.skip(i).take(400)) {
        batch.update(_ref(n), _readUpdate(n, uid, true));
      }
      await batch.commit();
    }
  }

  /// Removes it from this user's inbox: deletes a personal notification,
  /// hides a shared one for this user only.
  Future<void> remove(AppNotification n, String uid) => n.collection == NotificationSources.admin
      ? _ref(n).update({
          'hiddenFor': FieldValue.arrayUnion([uid]),
        })
      : _ref(n).delete();

  /// Marks a notification read given only its source and id (e.g. a tap on
  /// the OS tray, which carries those in its payload).
  Future<void> markReadById(String collection, String id, String uid) => _db
      .collection(collection)
      .doc(id)
      .update(
        collection == NotificationSources.admin
            ? {
                'readBy': FieldValue.arrayUnion([uid]),
              }
            : {'isRead': true, 'readAt': FieldValue.serverTimestamp()},
      );
}
