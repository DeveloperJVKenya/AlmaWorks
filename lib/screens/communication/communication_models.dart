// communication_models.dart
import 'dart:convert';                             // ← required for parseDeltaJson

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';            // ← moved to top (was line 91)

// ─── Participant (sender / recipient) ────────────────────────────────────────
class MessageParticipant {
  final String uid;
  final String email;
  final String username;

  const MessageParticipant({
    required this.uid,
    required this.email,
    required this.username,
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email,
        'username': username,
      };

  factory MessageParticipant.fromMap(Map<String, dynamic> m) =>
      MessageParticipant(
        uid: m['uid'] as String? ?? '',
        email: m['email'] as String? ?? '',
        username: m['username'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is MessageParticipant && other.uid == uid;

  @override
  int get hashCode => uid.hashCode;
}

// ─── Attachment ───────────────────────────────────────────────────────────────
class MessageAttachment {
  final String name;
  final String url;
  final String mimeType;
  final int sizeBytes;

  const MessageAttachment({
    required this.name,
    required this.url,
    required this.mimeType,
    required this.sizeBytes,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'url': url,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
      };

  factory MessageAttachment.fromMap(Map<String, dynamic> m) =>
      MessageAttachment(
        name: m['name'] as String? ?? '',
        url: m['url'] as String? ?? '',
        mimeType: m['mimeType'] as String? ?? '',
        sizeBytes: m['sizeBytes'] as int? ?? 0,
      );

  /// Returns a user-friendly size string
  String get readableSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Icon appropriate for the file type
  IconData get icon {
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType == 'application/pdf') return Icons.picture_as_pdf;
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return Icons.description;
    }
    if (mimeType.contains('sheet') ||
        mimeType.contains('excel') ||
        mimeType.contains('csv')) {
      return Icons.table_chart;
    }
    return Icons.attach_file;
  }
}

// ─── Message Type ─────────────────────────────────────────────────────────────
enum MessageType { original, reply, replyAll, forward }

extension MessageTypeExt on MessageType {
  String get value {
    switch (this) {
      case MessageType.original:
        return 'original';
      case MessageType.reply:
        return 'reply';
      case MessageType.replyAll:
        return 'replyAll';
      case MessageType.forward:
        return 'forward';
    }
  }

  static MessageType fromString(String s) {
    switch (s) {
      case 'reply':
        return MessageType.reply;
      case 'replyAll':
        return MessageType.replyAll;
      case 'forward':
        return MessageType.forward;
      default:
        return MessageType.original;
    }
  }
}

// ─── Core Message Model ───────────────────────────────────────────────────────
class CommunicationMessage {
  final String id;
  final String projectId;

  /// The root message id — shared by all messages in a thread.
  final String threadId;

  /// The direct parent message id for nested replies (null on root messages).
  final String? parentId;

  final String subject;

  /// flutter_quill Delta stored as a JSON array string via [dart:convert].
  final String bodyDelta;

  /// Plain-text fallback used for search and notification previews.
  final String bodyPlainText;

  final MessageParticipant from;
  final List<MessageParticipant> to;
  final List<MessageParticipant> cc;
  final List<MessageAttachment> attachments;

  final DateTime sentAt;
  final MessageType type;

  /// UIDs of users who have opened this message.
  final List<String> readByUids;

  /// UIDs of users who soft-deleted this message from their view.
  final List<String> deletedByUids;

  /// Flat uid list — {from.uid, ...to.uid, ...cc.uid} — kept in sync at
  /// construction so Firestore security rules can check membership without
  /// having to reach into the `to`/`cc` map arrays (rules can't query map
  /// fields inside an array element directly).
  final List<String> participantUids;

  CommunicationMessage({
    required this.id,
    required this.projectId,
    required this.threadId,
    this.parentId,
    required this.subject,
    required this.bodyDelta,
    required this.bodyPlainText,
    required this.from,
    required this.to,
    required this.cc,
    required this.attachments,
    required this.sentAt,
    required this.type,
    required this.readByUids,
    required this.deletedByUids,
    List<String>? participantUids,
  }) : participantUids = participantUids ??
            <String>{from.uid, ...to.map((p) => p.uid), ...cc.map((p) => p.uid)}
                .toList();

  bool isReadBy(String uid) => readByUids.contains(uid);
  bool isDeletedBy(String uid) => deletedByUids.contains(uid);

  /// All unique recipients across To and Cc fields.
  List<dynamic> get allRecipients =>
      <dynamic>{...to, ...cc}.toList();

  Map<String, dynamic> toMap() => {
        'id': id,
        'projectId': projectId,
        'threadId': threadId,
        'parentId': parentId,
        'subject': subject,
        'bodyDelta': bodyDelta,
        'bodyPlainText': bodyPlainText,
        'from': from.toMap(),
        'to': to.map((p) => p.toMap()).toList(),
        'cc': cc.map((p) => p.toMap()).toList(),
        'attachments': attachments.map((a) => a.toMap()).toList(),
        'sentAt': Timestamp.fromDate(sentAt),
        'type': type.value,
        'readByUids': readByUids,
        'deletedByUids': deletedByUids,
        'participantUids': participantUids,
      };

  factory CommunicationMessage.fromDoc(DocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    return CommunicationMessage(
      id: m['id'] as String? ?? doc.id,
      projectId: m['projectId'] as String? ?? '',
      threadId: m['threadId'] as String? ?? doc.id,
      parentId: m['parentId'] as String?,
      subject: m['subject'] as String? ?? '(no subject)',
      bodyDelta: m['bodyDelta'] as String? ?? '',
      bodyPlainText: m['bodyPlainText'] as String? ?? '',
      from: MessageParticipant.fromMap(
          (m['from'] as Map<String, dynamic>?) ?? {}),
      to: ((m['to'] as List?) ?? [])
          .map((e) => MessageParticipant.fromMap(e as Map<String, dynamic>))
          .toList(),
      cc: ((m['cc'] as List?) ?? [])
          .map((e) => MessageParticipant.fromMap(e as Map<String, dynamic>))
          .toList(),
      attachments: ((m['attachments'] as List?) ?? [])
          .map((e) => MessageAttachment.fromMap(e as Map<String, dynamic>))
          .toList(),
      sentAt: m['sentAt'] != null
          ? (m['sentAt'] as Timestamp).toDate()
          : DateTime.now(),
      type: MessageTypeExt.fromString(m['type'] as String? ?? 'original'),
      readByUids: List<String>.from(m['readByUids'] ?? []),
      deletedByUids: List<String>.from(m['deletedByUids'] ?? []),
      participantUids: (m['participantUids'] as List?)?.cast<String>(),
    );
  }

  CommunicationMessage copyWith({
    List<String>? readByUids,
    List<String>? deletedByUids,
  }) =>
      CommunicationMessage(
        id: id,
        projectId: projectId,
        threadId: threadId,
        parentId: parentId,
        subject: subject,
        bodyDelta: bodyDelta,
        bodyPlainText: bodyPlainText,
        from: from,
        to: to,
        cc: cc,
        attachments: attachments,
        sentAt: sentAt,
        type: type,
        readByUids: readByUids ?? this.readByUids,
        deletedByUids: deletedByUids ?? this.deletedByUids,
        participantUids: participantUids,
      );
}

// ─── Delta JSON helper ────────────────────────────────────────────────────────
/// Safely decodes a stored bodyDelta JSON string back to a Dart list
/// that [flutter_quill] Document.fromJson() accepts.
/// Returns an empty list — not an exception — on any parse failure.
List<dynamic> parseDeltaJson(String raw) {
  try {
    if (raw.isEmpty || !raw.startsWith('[')) return [];
    return jsonDecode(raw) as List<dynamic>;
  } catch (_) {
    return [];
  }
}

// ─── Draft Model ──────────────────────────────────────────────────────────────
class DraftMessage {
  final String id;
  final String projectId;
  final String ownerUid;
  final List<MessageParticipant> to;
  final List<MessageParticipant> cc;
  final String subject;
  final String bodyDelta;
  final List<MessageAttachment> attachments;
  final DateTime savedAt;

  const DraftMessage({
    required this.id,
    required this.projectId,
    required this.ownerUid,
    required this.to,
    required this.cc,
    required this.subject,
    required this.bodyDelta,
    required this.attachments,
    required this.savedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'projectId': projectId,
        'ownerUid': ownerUid,
        'to': to.map((p) => p.toMap()).toList(),
        'cc': cc.map((p) => p.toMap()).toList(),
        'subject': subject,
        'bodyDelta': bodyDelta,
        'attachments': attachments.map((a) => a.toMap()).toList(),
        'savedAt': Timestamp.fromDate(savedAt),
      };

  factory DraftMessage.fromDoc(DocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    return DraftMessage(
      id: m['id'] as String? ?? doc.id,
      projectId: m['projectId'] as String? ?? '',
      ownerUid: m['ownerUid'] as String? ?? '',
      to: ((m['to'] as List?) ?? [])
          .map((e) => MessageParticipant.fromMap(e as Map<String, dynamic>))
          .toList(),
      cc: ((m['cc'] as List?) ?? [])
          .map((e) => MessageParticipant.fromMap(e as Map<String, dynamic>))
          .toList(),
      subject: m['subject'] as String? ?? '',
      bodyDelta: m['bodyDelta'] as String? ?? '',
      attachments: ((m['attachments'] as List?) ?? [])
          .map((e) => MessageAttachment.fromMap(e as Map<String, dynamic>))
          .toList(),
      savedAt: m['savedAt'] != null
          ? (m['savedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}