// communication_service.dart
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'communication_models.dart';

class CommunicationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Logger _log = Logger();
  final Uuid _uuid = const Uuid();

  // ─── Collection refs ──────────────────────────────────────────────────────
  CollectionReference get _commsCol => _db.collection('Communication');
  CollectionReference get _draftsCol => _db.collection('CommunicationDrafts');

  // ─── Current user helper ──────────────────────────────────────────────────
  User? get _currentUser => _auth.currentUser;
  String get _currentUid => _currentUser?.uid ?? '';

  // ─────────────────────────────────────────────────────────────────────────
  //  USER DIRECTORY — fetch users who can access a given project
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns all users that share the given project (for recipient autocomplete).
  /// Admins / MainAdmins have access to every project.
  /// Clients are included only if explicitly granted access.
  Future<List<MessageParticipant>> getProjectUsers(String projectId) async {
    try {
      // All admin-level users
      final adminSnap = await _db
          .collection('Users')
          .where('role', whereIn: ['Admin', 'MainAdmin'])
          .get();

      // Client / Technician accounts explicitly granted this project.
      // Access grants live directly on the user doc as `grantedProjects`
      // (written by ClientRequestService on approval) — NOT in a
      // `ClientAccessRequests` collection, which nothing in the app ever
      // writes to. Querying that dead collection was silently excluding
      // every Client and Technician from the recipient list regardless of
      // their actual project access.
      final grantedSnap = await _db
          .collection('Users')
          .where('grantedProjects', arrayContains: projectId)
          .get();

      final List<MessageParticipant> participants = [];
      final String myUid = _currentUid;

      for (final doc in adminSnap.docs) {
        final data = doc.data();
        final uid = data['uid'] as String? ?? doc.id;
        if (uid == myUid) continue; // exclude self
        participants.add(
          MessageParticipant(
            uid: uid,
            email: data['email'] as String? ?? '',
            username:
                data['username'] as String? ?? data['email'] as String? ?? '',
          ),
        );
      }

      for (final doc in grantedSnap.docs) {
        final data = doc.data();
        final uid = data['uid'] as String? ?? doc.id;
        if (uid == myUid) continue;
        if (participants.any((p) => p.uid == uid)) continue; // dedupe

        participants.add(
          MessageParticipant(
            uid: uid,
            email: data['email'] as String? ?? '',
            username:
                data['username'] as String? ?? data['email'] as String? ?? '',
          ),
        );
      }

      _log.i(
        '✅ CommunicationService: ${participants.length} users found for project $projectId',
      );
      return participants;
    } catch (e) {
      _log.e('❌ CommunicationService.getProjectUsers: $e');
      return [];
    }
  }

  /// Fetches current user's profile as a [MessageParticipant]
  Future<MessageParticipant?> getCurrentUserParticipant() async {
    try {
      final user = _currentUser;
      if (user == null) return null;

      final snap = await _db
          .collection('Users')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) return null;
      final data = snap.docs.first.data();

      return MessageParticipant(
        uid: user.uid,
        email: data['email'] as String? ?? user.email ?? '',
        username: data['username'] as String? ?? user.email ?? '',
      );
    } catch (e) {
      _log.e('❌ CommunicationService.getCurrentUserParticipant: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  SEND MESSAGE
  // ─────────────────────────────────────────────────────────────────────────

  Future<String?> sendMessage({
    required String projectId,
    required MessageParticipant from,
    required List<MessageParticipant> to,
    required List<MessageParticipant> cc,
    required String subject,
    required String bodyDelta,
    required String bodyPlainText,
    required List<MessageAttachment> attachments,
    String? parentId,
    String? threadId,
    MessageType type = MessageType.original,
  }) async {
    try {
      final id = _uuid.v4();
      final resolvedThreadId = threadId ?? id; // root message uses its own id

      final msg = CommunicationMessage(
        id: id,
        projectId: projectId,
        threadId: resolvedThreadId,
        parentId: parentId,
        subject: subject,
        bodyDelta: bodyDelta,
        bodyPlainText: bodyPlainText,
        from: from,
        to: to,
        cc: cc,
        attachments: attachments,
        sentAt: DateTime.now(),
        type: type,
        readByUids: [from.uid], // sender has "read" their own message
        deletedByUids: [],
      );

      await _commsCol.doc(id).set(msg.toMap());
      _log.i(
        '✅ CommunicationService: Message $id sent to ${to.length} recipient(s)',
      );
      return id;
    } catch (e) {
      _log.e('❌ CommunicationService.sendMessage: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  STREAMS — INBOX / SENT / TRASH
  // ─────────────────────────────────────────────────────────────────────────

  // NOTE on every query below: Firestore security rules for a *list* query
  // (as opposed to a single get()) must be provable directly from the
  // query's own filters — Firestore checks whether the query's potential
  // result set could ever include a document the rule would reject, and if
  // it can't prove otherwise, it denies the ENTIRE query server-side rather
  // than silently filtering. Our Communication read rule is
  // `request.auth.uid in resource.data.participantUids`, so every query here
  // must explicitly filter `participantUids array-contains uid` for
  // Firestore to accept it — filtering by `to`/`cc`/`from.uid` client-side
  // alone is not enough, even though it's logically equivalent. Without this,
  // the local optimistic cache briefly shows results (cache isn't
  // rule-checked) and then the live listener gets rejected by the server and
  // the list appears to "flash and disappear".

  /// Messages where current user is a recipient (to OR cc) and hasn't deleted
  Stream<List<CommunicationMessage>> inboxStream(String projectId) {
    final uid = _currentUid;
    return _commsCol
        .where('projectId', isEqualTo: projectId)
        .where('participantUids', arrayContains: uid)
        .orderBy('sentAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => CommunicationMessage.fromDoc(d))
              .where(
                (m) =>
                    !m.isDeletedBy(uid) &&
                    (m.to.any((p) => p.uid == uid) ||
                        m.cc.any((p) => p.uid == uid)),
              )
              .toList(),
        );
  }

  /// Messages sent by the current user that haven't been deleted
  Stream<List<CommunicationMessage>> sentStream(String projectId) {
    final uid = _currentUid;
    return _commsCol
        .where('projectId', isEqualTo: projectId)
        .where('from.uid', isEqualTo: uid)
        .where('participantUids', arrayContains: uid)
        .orderBy('sentAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => CommunicationMessage.fromDoc(d))
              .where((m) => !m.isDeletedBy(uid))
              .toList(),
        );
  }

  /// Messages soft-deleted by the current user
  Stream<List<CommunicationMessage>> trashStream(String projectId) {
    final uid = _currentUid;
    return _commsCol
        .where('projectId', isEqualTo: projectId)
        .where('participantUids', arrayContains: uid)
        .orderBy('sentAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => CommunicationMessage.fromDoc(d))
              .where(
                (m) =>
                    m.isDeletedBy(uid) &&
                    (m.from.uid == uid ||
                        m.to.any((p) => p.uid == uid) ||
                        m.cc.any((p) => p.uid == uid)),
              )
              .toList(),
        );
  }

  /// Thread: all messages sharing the same threadId, ordered oldest first.
  /// Scoped to messages the current user actually participated in — also
  /// the behavior you want anyway: someone not CC'd on a given reply
  /// shouldn't see it just because they were on an earlier message in the
  /// same thread.
  Stream<List<CommunicationMessage>> threadStream(String threadId) {
    final uid = _currentUid;
    return _commsCol
        .where('threadId', isEqualTo: threadId)
        .where('participantUids', arrayContains: uid)
        .orderBy('sentAt')
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => CommunicationMessage.fromDoc(d)).toList(),
        );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  READ / UNREAD
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> markAsRead(String messageId) async {
    try {
      await _commsCol.doc(messageId).update({
        'readByUids': FieldValue.arrayUnion([_currentUid]),
      });
    } catch (e) {
      _log.e('❌ markAsRead: $e');
    }
  }

  Future<void> markAsUnread(String messageId) async {
    try {
      await _commsCol.doc(messageId).update({
        'readByUids': FieldValue.arrayRemove([_currentUid]),
      });
    } catch (e) {
      _log.e('❌ markAsUnread: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  SOFT DELETE / RESTORE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> softDelete(String messageId) async {
    try {
      await _commsCol.doc(messageId).update({
        'deletedByUids': FieldValue.arrayUnion([_currentUid]),
      });
    } catch (e) {
      _log.e('❌ softDelete: $e');
    }
  }

  Future<void> restoreFromTrash(String messageId) async {
    try {
      await _commsCol.doc(messageId).update({
        'deletedByUids': FieldValue.arrayRemove([_currentUid]),
      });
    } catch (e) {
      _log.e('❌ restoreFromTrash: $e');
    }
  }

  Future<void> permanentlyDelete(String messageId) async {
    try {
      await _commsCol.doc(messageId).delete();
    } catch (e) {
      _log.e('❌ permanentlyDelete: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  DRAFTS
  // ─────────────────────────────────────────────────────────────────────────

  Future<String?> saveDraft(DraftMessage draft) async {
    try {
      await _draftsCol.doc(draft.id).set(draft.toMap());
      return draft.id;
    } catch (e) {
      _log.e('❌ saveDraft: $e');
      return null;
    }
  }

  Future<void> deleteDraft(String draftId) async {
    try {
      await _draftsCol.doc(draftId).delete();
    } catch (e) {
      _log.e('❌ deleteDraft: $e');
    }
  }

  Stream<List<DraftMessage>> draftsStream(String projectId) {
    return _draftsCol
        .where('projectId', isEqualTo: projectId)
        .where('ownerUid', isEqualTo: _currentUid)
        .orderBy('savedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => DraftMessage.fromDoc(d)).toList());
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  ATTACHMENT UPLOAD
  // ─────────────────────────────────────────────────────────────────────────

  Future<MessageAttachment?> uploadAttachment({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String projectId,
  }) async {
    try {
      final path = 'communication/$projectId/${_uuid.v4()}_$fileName';
      final ref = _storage.ref().child(path);
      final task = await ref.putData(
        bytes,
        SettableMetadata(contentType: mimeType),
      );
      final url = await task.ref.getDownloadURL();

      return MessageAttachment(
        name: fileName,
        url: url,
        mimeType: mimeType,
        sizeBytes: bytes.length,
      );
    } catch (e) {
      _log.e('❌ uploadAttachment: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  UNREAD COUNT HELPER
  // ─────────────────────────────────────────────────────────────────────────

  Stream<int> unreadCountStream(String projectId) {
    final uid = _currentUid;
    return _commsCol
        .where('projectId', isEqualTo: projectId)
        .where('participantUids', arrayContains: uid)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => CommunicationMessage.fromDoc(d))
              .where(
                (m) =>
                    !m.isDeletedBy(uid) &&
                    !m.isReadBy(uid) &&
                    (m.to.any((p) => p.uid == uid) ||
                        m.cc.any((p) => p.uid == uid)),
              )
              .length,
        );
  }
}
