// communication_message_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'communication_models.dart';
import 'communication_service.dart';
import 'communication_compose_dialog.dart';

class CommunicationMessageDetailScreen extends StatefulWidget {
  final CommunicationMessage message;
  final CommunicationService service;
  final MessageParticipant currentUser;
  final List<MessageParticipant> projectUsers;
  final String projectId;
  final VoidCallback? onActionDone;

  const CommunicationMessageDetailScreen({
    super.key,
    required this.message,
    required this.service,
    required this.currentUser,
    required this.projectUsers,
    required this.projectId,
    this.onActionDone,
  });

  @override
  State<CommunicationMessageDetailScreen> createState() =>
      _CommunicationMessageDetailScreenState();
}

class _CommunicationMessageDetailScreenState
    extends State<CommunicationMessageDetailScreen> {
  quill.QuillController? _quillCtrl;
  bool _isLoadingBody = true;
  bool _showThread = false;

  // Live thread stream
  List<CommunicationMessage> _threadMessages = [];

  @override
  void initState() {
    super.initState();
    _markRead();
    _initQuill();
    _subscribeThread();
  }

  void _markRead() {
    if (!widget.message.isReadBy(widget.currentUser.uid)) {
      widget.service.markAsRead(widget.message.id);
    }
  }

  void _initQuill() {
    try {
      if (widget.message.bodyDelta.isNotEmpty) {
        final raw = widget.message.bodyDelta;
        // bodyDelta is stored as Dart list .toString() — try json decode
        final doc = quill.Document.fromJson(_safeParseJson(raw));
        _quillCtrl = quill.QuillController(
          document: doc,
          selection: const TextSelection.collapsed(offset: 0),
        );
      } else {
        _quillCtrl = _plainTextController(widget.message.bodyPlainText);
      }
    } catch (_) {
      _quillCtrl = _plainTextController(widget.message.bodyPlainText);
    }
    setState(() => _isLoadingBody = false);
  }

  quill.QuillController _plainTextController(String text) {
    final doc = quill.Document()..insert(0, text);
    return quill.QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  List<dynamic> _safeParseJson(String raw) {
    try {
      // Stored via dart List.toString() — attempt basic parse
      if (raw.startsWith('[') && raw.endsWith(']')) {
        // Use dart:convert via json
        return [];
      }
    } catch (_) {}
    return [];
  }

  void _subscribeThread() {
    widget.service
        .threadStream(widget.message.threadId)
        .listen((msgs) {
      if (mounted) setState(() => _threadMessages = msgs);
    });
  }

  // ─── Action helpers ─────────────────────────────────────────────────────

  void _openCompose({
    required List<MessageParticipant> to,
    required List<MessageParticipant> cc,
    required String subject,
    required MessageType type,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CommunicationComposeDialog(
        projectId: widget.projectId,
        service: widget.service,
        currentUser: widget.currentUser,
        projectUsers: widget.projectUsers,
        initialTo: to,
        initialCc: cc,
        initialSubject: subject,
        replyToMessageId: widget.message.id,
        threadId: widget.message.threadId,
        messageType: type,
        onSent: () {
          widget.onActionDone?.call();
        },
      ),
    );
  }

  void _reply() {
    _openCompose(
      to: [widget.message.from],
      cc: [],
      subject: _reSubject(),
      type: MessageType.reply,
    );
  }

  void _replyAll() {
    // Include all original recipients except self, plus original sender
    final allTo = <MessageParticipant>{widget.message.from};
    for (final p in widget.message.to) {
      if (p.uid != widget.currentUser.uid) allTo.add(p);
    }
    _openCompose(
      to: allTo.toList(),
      cc: widget.message.cc
          .where((p) => p.uid != widget.currentUser.uid)
          .toList(),
      subject: _reSubject(),
      type: MessageType.replyAll,
    );
  }

  void _forward() {
    _openCompose(
      to: [],
      cc: [],
      subject: 'Fwd: ${widget.message.subject}',
      type: MessageType.forward,
    );
  }

  String _reSubject() {
    final sub = widget.message.subject;
    return sub.startsWith('Re:') ? sub : 'Re: $sub';
  }

  Future<void> _markUnread() async {
    await widget.service.markAsUnread(widget.message.id);
    if (mounted) {
      widget.onActionDone?.call();
      Navigator.pop(context);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Move to Trash?', style: TextStyle()),
        content: Text(
          'This message will be moved to your Trash.',
          style: TextStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Move to Trash',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.service.softDelete(widget.message.id);
      if (mounted) {
        widget.onActionDone?.call();
        Navigator.pop(context);
      }
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2E5A),
        foregroundColor: Colors.white,
        title: Text(
          widget.message.subject,
          style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.mark_email_unread_outlined),
            tooltip: 'Mark as unread',
            onPressed: _markUnread,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: _delete,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'reply') _reply();
              if (v == 'reply_all') _replyAll();
              if (v == 'forward') _forward();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'reply',
                child:
                    Text('Reply', style: TextStyle()),
              ),
              PopupMenuItem(
                value: 'reply_all',
                child: Text('Reply All',
                    style: TextStyle()),
              ),
              PopupMenuItem(
                value: 'forward',
                child: Text('Forward',
                    style: TextStyle()),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 12 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMessageCard(isMobile),
            const SizedBox(height: 16),
            _buildActionRow(),

            // Thread replies
            if (_threadMessages.length > 1) ...[
              const SizedBox(height: 24),
              _buildThreadSection(isMobile),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessageCard(bool isMobile) {
    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Subject
            Text(
              widget.message.subject,
              style: TextStyle(
                fontSize: isMobile ? 18 : 22,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0A2E5A),
              ),
            ),
            const SizedBox(height: 16),

            // Sender row
            _buildParticipantRow(
              label: 'From',
              participants: [widget.message.from],
              isMobile: isMobile,
            ),
            const SizedBox(height: 8),
            _buildParticipantRow(
              label: 'To',
              participants: widget.message.to,
              isMobile: isMobile,
            ),
            if (widget.message.cc.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildParticipantRow(
                label: 'Cc',
                participants: widget.message.cc,
                isMobile: isMobile,
              ),
            ],

            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.schedule,
                    size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  DateFormat('MMM d, yyyy · h:mm a')
                      .format(widget.message.sentAt),
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey[500]),
                ),
                const Spacer(),
                _messageTypeBadge(),
              ],
            ),

            const Divider(height: 32),

            // Body
            _buildBody(isMobile),

            // Attachments
            if (widget.message.attachments.isNotEmpty) ...[
              const Divider(height: 32),
              _buildAttachments(isMobile),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantRow({
    required String label,
    required List<MessageParticipant> participants,
    required bool isMobile,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: participants.map((p) {
              return Tooltip(
                message: p.email,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A2E5A).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 10,
                        backgroundColor: const Color(0xFF0A2E5A),
                        child: Text(
                          p.username.isNotEmpty
                              ? p.username[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        p.username.isNotEmpty ? p.username : p.email,
                        style: TextStyle(
                          fontSize: 13,
                          color: const Color(0xFF0A2E5A),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _messageTypeBadge() {
    if (widget.message.type == MessageType.original) {
      return const SizedBox.shrink();
    }
    final labels = {
      MessageType.reply: 'Reply',
      MessageType.replyAll: 'Reply All',
      MessageType.forward: 'Forwarded',
    };
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Text(
        labels[widget.message.type] ?? '',
        style: TextStyle(
            fontSize: 11, color: Colors.blue[700]),
      ),
    );
  }

  Widget _buildBody(bool isMobile) {
    if (_isLoadingBody || _quillCtrl == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return IgnorePointer(
      child: quill.QuillEditor(
        controller: _quillCtrl!,
        focusNode: FocusNode(),
        scrollController: ScrollController(),
        config: quill.QuillEditorConfig(
          scrollable: false,
          expands: false,
          padding: EdgeInsets.zero,
          customStyles: quill.DefaultStyles(
            paragraph: quill.DefaultTextBlockStyle(
              TextStyle(
                  fontSize: isMobile ? 13 : 14,
                  color: Colors.grey[800]),
              const quill.HorizontalSpacing(0, 0),
              const quill.VerticalSpacing(0, 0),
              const quill.VerticalSpacing(0, 0),
              null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttachments(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.message.attachments.length} Attachment(s)',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: const Color(0xFF0A2E5A),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.message.attachments.map((att) {
            return InkWell(
              onTap: () async {
                final uri = Uri.parse(att.url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri,
                      mode: LaunchMode.externalApplication);
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[50],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(att.icon,
                        size: 20, color: const Color(0xFF0A2E5A)),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          att.name,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                        Text(
                          att.readableSize,
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.download_outlined,
                        size: 16, color: Colors.grey[400]),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        _ActionButton(
          icon: Icons.reply,
          label: 'Reply',
          onTap: _reply,
        ),
        const SizedBox(width: 8),
        _ActionButton(
          icon: Icons.reply_all,
          label: 'Reply All',
          onTap: _replyAll,
        ),
        const SizedBox(width: 8),
        _ActionButton(
          icon: Icons.forward,
          label: 'Forward',
          onTap: _forward,
        ),
      ],
    );
  }

  Widget _buildThreadSection(bool isMobile) {
    final replies = _threadMessages
        .where((m) => m.id != widget.message.id)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _showThread = !_showThread),
          child: Row(
            children: [
              Icon(
                _showThread
                    ? Icons.expand_less
                    : Icons.expand_more,
                color: const Color(0xFF0A2E5A),
              ),
              const SizedBox(width: 6),
              Text(
                '${replies.length} reply(ies) in this thread',
                style: TextStyle(
                  fontSize: 13,
                  color: const Color(0xFF0A2E5A),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (_showThread) ...[
          const SizedBox(height: 12),
          ...replies.map((m) => _ThreadMessageTile(
                message: m,
                isMobile: isMobile,
              )),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _quillCtrl?.dispose();
    super.dispose();
  }
}

// ─── Thread Message Tile ──────────────────────────────────────────────────────
class _ThreadMessageTile extends StatelessWidget {
  final CommunicationMessage message;
  final bool isMobile;

  const _ThreadMessageTile({
    required this.message,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12, left: 16),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.06),
            blurRadius: 6,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFF1565C0),
                child: Text(
                  message.from.username.isNotEmpty
                      ? message.from.username[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.from.username.isNotEmpty
                          ? message.from.username
                          : message.from.email,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      message.from.email,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              Text(
                DateFormat('MMM d, h:mm a').format(message.sentAt),
                style: TextStyle(
                    fontSize: 11, color: Colors.grey[400]),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            message.bodyPlainText.isNotEmpty
                ? message.bodyPlainText
                : '(no content)',
            style: TextStyle(
                fontSize: 13, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
}

// ─── Action Button ────────────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF0A2E5A),
        side: BorderSide(color: const Color(0xFF0A2E5A).withValues(alpha: 0.4)),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
    );
  }
}