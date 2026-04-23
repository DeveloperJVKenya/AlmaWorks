// communication_compose_dialog.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import 'communication_models.dart';
import 'communication_notification_service.dart';
import 'communication_service.dart';

// ─── Module-level logger (mirrors the pattern used in BaseLayout) ─────────────
final _log = Logger(
  printer: PrettyPrinter(
    methodCount: 1,
    errorMethodCount: 5,
    lineLength: 100,
    colors: true,
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
);

// ══════════════════════════════════════════════════════════════════════════════
//  RECIPIENT CHIP FIELD
// ══════════════════════════════════════════════════════════════════════════════
class _RecipientField extends StatefulWidget {
  final String label;
  final List<MessageParticipant> selected;
  final List<MessageParticipant> suggestions;
  final ValueChanged<List<MessageParticipant>> onChanged;

  const _RecipientField({
    required this.label,
    required this.selected,
    required this.suggestions,
    required this.onChanged,
  });

  @override
  State<_RecipientField> createState() => _RecipientFieldState();
}

class _RecipientFieldState extends State<_RecipientField> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<MessageParticipant> _filtered = [];
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  // ── Guard flag ──────────────────────────────────────────────────────────────
  // onTapDown on an overlay item sets this to true BEFORE the TextField's
  // focus-lost event fires. The focus listener checks this flag and skips
  // _hideOverlay() while a selection gesture is in progress. Without this
  // guard the overlay is removed before onTap can deliver the selection.
  bool _isSelectingFromOverlay = false;

  @override
  void initState() {
    super.initState();
    _log.i('📬 RecipientField[${widget.label}]: initState');
    _ctrl.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    _log.d(
      '🔍 RecipientField[${widget.label}]: '
      'hasFocus=${_focusNode.hasFocus} '
      'isSelecting=$_isSelectingFromOverlay',
    );
    if (!_focusNode.hasFocus) {
      // Flutter delivers focus-loss events synchronously, several milliseconds
      // BEFORE the gesture recognizer on the overlay item fires onTapDown.
      // Hiding immediately tears the overlay down before the tap can land,
      // which cancels the gesture. Deferring by 250 ms gives onTapDown and
      // onTap time to run first; the guard flag is then checked here to
      // decide whether to actually dismiss the overlay.
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        if (!_isSelectingFromOverlay) {
          _log.d('🔍 RecipientField[${widget.label}]: focus lost → hiding overlay');
          _hideOverlay();
        } else {
          _log.d(
            '🔍 RecipientField[${widget.label}]: focus lost but selection '
            'in progress → overlay kept alive',
          );
        }
      });
    }
  }

  void _onTextChanged() {
    final query = _ctrl.text.trim().toLowerCase();
    _log.d(
      '⌨️ RecipientField[${widget.label}]: query="$query" '
      'suggestions=${widget.suggestions.length}',
    );

    if (query.isEmpty) {
      _hideOverlay();
      return;
    }

    final selectedUids = widget.selected.map((p) => p.uid).toSet();
    _filtered = widget.suggestions
        .where((p) =>
            !selectedUids.contains(p.uid) &&
            (p.email.toLowerCase().contains(query) ||
                p.username.toLowerCase().contains(query)))
        .take(8)
        .toList();

    _log.i(
      '🔎 RecipientField[${widget.label}]: '
      '${_filtered.length} match(es) for "$query" → '
      '${_filtered.map((p) => p.email).join(', ')}',
    );

    if (_filtered.isEmpty) {
      _hideOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    _hideOverlay();
    _overlayEntry = _buildOverlay();
    Overlay.of(context).insert(_overlayEntry!);
    _log.d(
      '📋 RecipientField[${widget.label}]: '
      'overlay shown (${_filtered.length} items)',
    );
  }

  void _hideOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
      _log.d('📋 RecipientField[${widget.label}]: overlay hidden');
    }
  }

  OverlayEntry _buildOverlay() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    return OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 2),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final p = _filtered[i];
                  return GestureDetector(
                    // onTapDown fires BEFORE TextField loses focus.
                    // Raising the flag here ensures _onFocusChanged()
                    // does NOT call _hideOverlay().
                    onTapDown: (_) {
                      _log.d(
                        '👆 RecipientField[${widget.label}]: '
                        'onTapDown "${p.email}" — guard raised',
                      );
                      _isSelectingFromOverlay = true;
                    },
                    // onTap fires after focus changes; overlay is still
                    // alive because the guard was set in onTapDown.
                    onTap: () {
                      _log.i(
                        '✅ RecipientField[${widget.label}]: '
                        'selected "${p.email}" uid=${p.uid}',
                      );
                      _isSelectingFromOverlay = false;
                      _selectParticipant(p);
                    },
                    // Reset guard if gesture is interrupted (scroll, etc.)
                    onTapCancel: () {
                      _log.d(
                        '⚠️ RecipientField[${widget.label}]: '
                        'tap cancelled on "${p.email}" — guard reset',
                      );
                      _isSelectingFromOverlay = false;
                    },
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFF0A2E5A),
                        child: Text(
                          p.username.isNotEmpty
                              ? p.username[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                      ),
                      title: Text(p.username,
                          style: GoogleFonts.poppins(fontSize: 13)),
                      subtitle: Text(p.email,
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: Colors.grey[600])),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectParticipant(MessageParticipant p) {
    _hideOverlay();
    _ctrl.clear();
    final updated = [...widget.selected, p];
    _log.i(
      '📌 RecipientField[${widget.label}]: notifying parent — '
      '${updated.length} recipient(s): '
      '${updated.map((x) => x.email).join(', ')}',
    );
    widget.onChanged(updated);
  }

  void _removeParticipant(MessageParticipant p) {
    final updated = widget.selected.where((x) => x.uid != p.uid).toList();
    _log.i(
      '🗑️ RecipientField[${widget.label}]: removed "${p.email}" — '
      '${updated.length} remaining',
    );
    widget.onChanged(updated);
  }

  @override
  void dispose() {
    _log.i('📬 RecipientField[${widget.label}]: dispose');
    _hideOverlay();
    _ctrl.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          border:
              Border(bottom: BorderSide(color: Colors.grey.shade300)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 60,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  widget.label,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ...widget.selected.map((p) => Chip(
                        label: Text(p.email,
                            style: GoogleFonts.poppins(fontSize: 12)),
                        backgroundColor: const Color(0xFF0A2E5A)
                            .withValues(alpha: 0.08),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () => _removeParticipant(p),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      )),
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focusNode,
                      style: GoogleFonts.poppins(fontSize: 13),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: widget.selected.isEmpty
                            ? 'Type email or name…'
                            : '',
                        hintStyle: GoogleFonts.poppins(
                            fontSize: 13, color: Colors.grey[400]),
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  COMPOSE DIALOG
// ══════════════════════════════════════════════════════════════════════════════
class CommunicationComposeDialog extends StatefulWidget {
  final String projectId;
  final CommunicationService service;
  final MessageParticipant currentUser;
  final List<MessageParticipant> projectUsers;

  final List<MessageParticipant>? initialTo;
  final List<MessageParticipant>? initialCc;
  final String? initialSubject;
  final String? initialBodyDelta;
  final String? replyToMessageId;
  final String? threadId;
  final MessageType messageType;

  final VoidCallback? onSent;

  const CommunicationComposeDialog({
    super.key,
    required this.projectId,
    required this.service,
    required this.currentUser,
    required this.projectUsers,
    this.initialTo,
    this.initialCc,
    this.initialSubject,
    this.initialBodyDelta,
    this.replyToMessageId,
    this.threadId,
    this.messageType = MessageType.original,
    this.onSent,
  });

  @override
  State<CommunicationComposeDialog> createState() =>
      _CommunicationComposeDialogState();
}

class _CommunicationComposeDialogState
    extends State<CommunicationComposeDialog> {
  final TextEditingController _subjectCtrl = TextEditingController();
  late quill.QuillController _quillCtrl;
  final FocusNode _quillFocus = FocusNode();
  final ScrollController _quillScroll = ScrollController();
  final Uuid _uuid = const Uuid();

  List<MessageParticipant> _toList = [];
  List<MessageParticipant> _ccList = [];
  bool _showCcField = false;

  final List<MessageAttachment> _attachments = [];
  final List<_PendingAttachment> _pendingAttachments = [];

  bool _isSending = false;

  @override
  void initState() {
    super.initState();

    _toList = List<MessageParticipant>.from(widget.initialTo ?? []);
    _ccList = List<MessageParticipant>.from(widget.initialCc ?? []);
    _showCcField = _ccList.isNotEmpty;

    if (widget.initialSubject != null) {
      _subjectCtrl.text = widget.initialSubject!;
    }

    if (widget.initialBodyDelta != null &&
        widget.initialBodyDelta!.isNotEmpty) {
      try {
        final ops = parseDeltaJson(widget.initialBodyDelta!);
        if (ops.isNotEmpty) {
          final doc = quill.Document.fromJson(ops);
          _quillCtrl = quill.QuillController(
            document: doc,
            selection: const TextSelection.collapsed(offset: 0),
          );
        } else {
          _quillCtrl = quill.QuillController.basic();
        }
      } catch (_) {
        _quillCtrl = quill.QuillController.basic();
      }
    } else {
      _quillCtrl = quill.QuillController.basic();
    }

    _log.i(
      '📝 ComposeDialog: initState — '
      'type=${widget.messageType.value} '
      'projectId=${widget.projectId} '
      'projectUsers=${widget.projectUsers.length} '
      'initialTo=${_toList.map((p) => p.email).join(', ')} '
      'initialCc=${_ccList.map((p) => p.email).join(', ')}',
    );
  }

  // ── Recipient callbacks ───────────────────────────────────────────────────────
  void _onToChanged(List<MessageParticipant> updated) {
    _log.i(
      '📨 ComposeDialog: To updated — '
      '${updated.length} recipient(s): '
      '${updated.map((p) => p.email).join(', ')}',
    );
    setState(() => _toList = updated);
    _log.d('📨 ComposeDialog: _toList after setState = ${_toList.length}');
  }

  void _onCcChanged(List<MessageParticipant> updated) {
    _log.i(
      '📨 ComposeDialog: Cc updated — '
      '${updated.length} recipient(s): '
      '${updated.map((p) => p.email).join(', ')}',
    );
    setState(() => _ccList = updated);
  }

  // ── Serialisation ─────────────────────────────────────────────────────────────
  String _buildDeltaJson() {
    try {
      return jsonEncode(_quillCtrl.document.toDelta().toJson());
    } catch (_) {
      return '[]';
    }
  }

  String _buildPlainText() => _quillCtrl.document.toPlainText().trim();

  // ── Attachment picking ────────────────────────────────────────────────────────
  Future<void> _pickAttachment() async {
    _log.i('📎 ComposeDialog: opening file picker');
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'pdf', 'doc', 'docx', 'xls', 'xlsx', 'csv',
        'png', 'jpg', 'jpeg', 'gif', 'webp',
      ],
      withData: true,
    );
    if (result == null) {
      _log.i('📎 ComposeDialog: file picker cancelled');
      return;
    }
    _log.i('📎 ComposeDialog: ${result.files.length} file(s) picked');
    for (final file in result.files) {
      if (file.bytes == null) {
        _log.w('📎 ComposeDialog: skipping "${file.name}" — no bytes');
        continue;
      }
      _log.i('📎 ComposeDialog: queuing "${file.name}" (${file.bytes!.length} bytes)');
      setState(() {
        _pendingAttachments.add(_PendingAttachment(
          id: _uuid.v4(),
          name: file.name,
          bytes: file.bytes!,
          mimeType: _mimeFromExtension(file.extension ?? ''),
        ));
      });
    }
  }

  String _mimeFromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument'
            '.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument'
            '.spreadsheetml.sheet';
      case 'csv':
        return 'text/csv';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  // ── Send ──────────────────────────────────────────────────────────────────────
  Future<void> _send() async {
    _log.i(
      '🚀 ComposeDialog._send: called — '
      '_toList=${_toList.length} '
      'emails=${_toList.map((p) => p.email).join(', ')} '
      'subject="${_subjectCtrl.text.trim()}" '
      'pendingAttachments=${_pendingAttachments.length}',
    );

    if (_toList.isEmpty) {
      _log.w('🚀 ComposeDialog._send: BLOCKED — _toList is empty');
      _snack('Please add at least one recipient in the To field.');
      return;
    }
    if (_subjectCtrl.text.trim().isEmpty) {
      _log.w('🚀 ComposeDialog._send: BLOCKED — subject is empty');
      _snack('Please enter a subject.');
      return;
    }

    _log.i(
      '🚀 ComposeDialog._send: validation passed — '
      'proceeding to send to ${_toList.map((p) => p.email).join(', ')}',
    );
    setState(() => _isSending = true);

    try {
      final List<MessageAttachment> uploaded = [];
      for (final pending in _pendingAttachments) {
        _log.i('⬆️ ComposeDialog: uploading "${pending.name}"');
        final att = await widget.service.uploadAttachment(
          bytes: pending.bytes,
          fileName: pending.name,
          mimeType: pending.mimeType,
          projectId: widget.projectId,
        );
        if (att != null) {
          uploaded.add(att);
          _log.i('⬆️ ComposeDialog: "${pending.name}" → ${att.url}');
        } else {
          _log.w('⬆️ ComposeDialog: upload failed for "${pending.name}"');
        }
      }
      uploaded.addAll(_attachments);

      final bodyDelta = _buildDeltaJson();
      final bodyPlain = _buildPlainText();
      final preview = bodyPlain.length > 80
          ? '${bodyPlain.substring(0, 80)}…'
          : bodyPlain;
      _log.d('🚀 ComposeDialog._send: bodyPreview="$preview"');

      _log.i('🚀 ComposeDialog._send: calling CommunicationService.sendMessage');
      final messageId = await widget.service.sendMessage(
        projectId: widget.projectId,
        from: widget.currentUser,
        to: _toList,
        cc: _ccList,
        subject: _subjectCtrl.text.trim(),
        bodyDelta: bodyDelta,
        bodyPlainText: bodyPlain,
        attachments: uploaded,
        parentId: widget.replyToMessageId,
        threadId: widget.threadId,
        type: widget.messageType,
      );

      if (messageId != null) {
        _log.i('✅ ComposeDialog._send: Firestore write succeeded — id=$messageId');
        final msg = CommunicationMessage(
          id: messageId,
          projectId: widget.projectId,
          threadId: widget.threadId ?? messageId,
          parentId: widget.replyToMessageId,
          subject: _subjectCtrl.text.trim(),
          bodyDelta: bodyDelta,
          bodyPlainText: bodyPlain,
          from: widget.currentUser,
          to: _toList,
          cc: _ccList,
          attachments: uploaded,
          sentAt: DateTime.now(),
          type: widget.messageType,
          readByUids: [widget.currentUser.uid],
          deletedByUids: [],
        );
        await CommunicationNotificationService()
            .enqueueNotificationsForMessage(msg);
        _log.i('🔔 ComposeDialog._send: notifications enqueued');

        if (mounted) {
          Navigator.of(context).pop();
          widget.onSent?.call();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Message sent!', style: GoogleFonts.poppins()),
            backgroundColor: const Color(0xFF0A2E5A),
          ));
        }
      } else {
        _log.e('❌ ComposeDialog._send: sendMessage returned null — Firestore write may have failed');
        _snack('Failed to send. Please try again.');
      }
    } catch (e, stack) {
      _log.e('❌ ComposeDialog._send: exception', error: e, stackTrace: stack);
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ── Save Draft ────────────────────────────────────────────────────────────────
  Future<void> _saveDraftAndClose() async {
    _log.i('💾 ComposeDialog: saving draft');
    final draft = DraftMessage(
      id: _uuid.v4(),
      projectId: widget.projectId,
      to: _toList,
      cc: _ccList,
      subject: _subjectCtrl.text,
      bodyDelta: _buildDeltaJson(),
      attachments: _attachments,
      savedAt: DateTime.now(),
    );
    await widget.service.saveDraft(draft);
    _log.i('💾 ComposeDialog: draft saved id=${draft.id}');
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Draft saved.', style: GoogleFonts.poppins()),
        backgroundColor: Colors.grey[700],
      ));
    }
  }

  // ── Discard ───────────────────────────────────────────────────────────────────
  void _discard() {
    _log.i('🗑️ ComposeDialog: discard tapped');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Discard message?', style: GoogleFonts.poppins()),
        content:
            Text('This message will not be saved.', style: GoogleFonts.poppins()),
        actions: [
          TextButton(
            onPressed: () {
              _log.i('🗑️ ComposeDialog: discard cancelled');
              Navigator.pop(context);
            },
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () {
              _log.i('🗑️ ComposeDialog: discard confirmed');
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child:
                Text('Discard', style: GoogleFonts.poppins(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg, style: GoogleFonts.poppins())));
  }

  @override
  void dispose() {
    _log.i('📝 ComposeDialog: dispose');
    _subjectCtrl.dispose();
    _quillCtrl.dispose();
    _quillFocus.dispose();
    _quillScroll.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: isMobile
          ? const EdgeInsets.all(8)
          : const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: screenHeight * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTitleBar(),
            Flexible(child: _buildBody()),
            _buildToolbar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0A2E5A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _composeTitle(),
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: _discard,
            tooltip: 'Discard',
          ),
        ],
      ),
    );
  }

  String _composeTitle() {
    switch (widget.messageType) {
      case MessageType.reply:
        return 'Reply';
      case MessageType.replyAll:
        return 'Reply All';
      case MessageType.forward:
        return 'Forward';
      default:
        return 'New Message';
    }
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RecipientField(
            label: 'To',
            selected: _toList,
            suggestions: widget.projectUsers,
            onChanged: _onToChanged,
          ),
          if (!_showCcField)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  _log.i('📝 ComposeDialog: Cc field shown');
                  setState(() => _showCcField = true);
                },
                child: Text('Cc',
                    style: GoogleFonts.poppins(
                        color: Colors.grey[600], fontSize: 13)),
              ),
            )
          else
            _RecipientField(
              label: 'Cc',
              selected: _ccList,
              suggestions: widget.projectUsers,
              onChanged: _onCcChanged,
            ),
          Container(
            decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300))),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 60,
                  child: Text('Subject',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500)),
                ),
                Expanded(
                  child: TextField(
                    controller: _subjectCtrl,
                    style: GoogleFonts.poppins(fontSize: 13),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Subject',
                      hintStyle: GoogleFonts.poppins(
                          fontSize: 13, color: Colors.grey[400]),
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200))),
            child: quill.QuillSimpleToolbar(
              controller: _quillCtrl,
              config: const quill.QuillSimpleToolbarConfig(
                showFontFamily: false,
                showFontSize: false,
                showCodeBlock: false,
                showInlineCode: false,
                showSubscript: false,
                showSuperscript: false,
                showClearFormat: true,
                showSearchButton: false,
              ),
            ),
          ),
          Container(
            constraints: const BoxConstraints(minHeight: 220),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: quill.QuillEditor(
              controller: _quillCtrl,
              focusNode: _quillFocus,
              scrollController: _quillScroll,
              config: quill.QuillEditorConfig(
                placeholder: 'Write your message here…',
                scrollable: true,
                expands: false,
                padding: EdgeInsets.zero,
                customStyles: quill.DefaultStyles(
                  paragraph: quill.DefaultTextBlockStyle(
                    GoogleFonts.poppins(
                        fontSize: 13, color: Colors.grey[800]),
                    const quill.HorizontalSpacing(0, 0),
                    const quill.VerticalSpacing(0, 0),
                    const quill.VerticalSpacing(0, 0),
                    null,
                  ),
                ),
              ),
            ),
          ),
          if (_pendingAttachments.isNotEmpty) _buildAttachmentPreview(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildAttachmentPreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.grey[50],
          border: Border(top: BorderSide(color: Colors.grey.shade200))),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: _pendingAttachments.map((pa) {
          return Chip(
            avatar: Icon(_iconForMime(pa.mimeType),
                size: 16, color: const Color(0xFF0A2E5A)),
            label: Text(pa.name,
                style: GoogleFonts.poppins(fontSize: 11),
                overflow: TextOverflow.ellipsis),
            deleteIcon: const Icon(Icons.close, size: 14),
            onDeleted: () {
              _log.i('📎 ComposeDialog: removed attachment "${pa.name}"');
              setState(() => _pendingAttachments.remove(pa));
            },
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: Colors.grey.shade300),
            ),
          );
        }).toList(),
      ),
    );
  }

  IconData _iconForMime(String mime) {
    if (mime.startsWith('image/')) return Icons.image;
    if (mime == 'application/pdf') return Icons.picture_as_pdf;
    if (mime.contains('word') || mime.contains('document')) {
      return Icons.description;
    }
    if (mime.contains('sheet') ||
        mime.contains('excel') ||
        mime.contains('csv')) {
      return Icons.table_chart;
    }
    return Icons.attach_file;
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey.shade200))),
      child: Row(
        children: [
          ElevatedButton.icon(
            onPressed: _isSending ? null : _send,
            icon: _isSending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send, size: 16),
            label: Text(
              _isSending ? 'Sending…' : 'Send',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0A2E5A),
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 8),
          _ToolbarAction(
            icon: Icons.attach_file,
            tooltip: 'Attach files',
            onTap: _pickAttachment,
          ),
          const Spacer(),
          _ToolbarAction(
            icon: Icons.save_outlined,
            tooltip: 'Save draft',
            onTap: _saveDraftAndClose,
          ),
          _ToolbarAction(
            icon: Icons.delete_outline,
            tooltip: 'Discard',
            onTap: _discard,
            color: Colors.red[400]!,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TOOLBAR ICON BUTTON
// ══════════════════════════════════════════════════════════════════════════════
class _ToolbarAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  const _ToolbarAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = const Color(0xFF555555),
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  PENDING ATTACHMENT  (local, before upload)
// ══════════════════════════════════════════════════════════════════════════════
class _PendingAttachment {
  final String id;
  final String name;
  final Uint8List bytes;
  final String mimeType;

  const _PendingAttachment({
    required this.id,
    required this.name,
    required this.bytes,
    required this.mimeType,
  });
}