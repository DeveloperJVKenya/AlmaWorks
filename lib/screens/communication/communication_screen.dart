// communication_screen.dart
import 'package:almaworks/widgets/base_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

import 'package:almaworks/models/project_model.dart';

import 'communication_compose_dialog.dart';
import 'communication_message_detail_screen.dart';
import 'communication_models.dart';
import 'communication_service.dart';

// ─── Folder / View types ──────────────────────────────────────────────────────
enum _Folder { inbox, sent, drafts, trash }

class CommunicationScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;

  const CommunicationScreen({
    super.key,
    required this.project,
    required this.logger,
  });

  @override
  State<CommunicationScreen> createState() => _CommunicationScreenState();
}

class _CommunicationScreenState extends State<CommunicationScreen> {
  final CommunicationService _service = CommunicationService();

  _Folder _activeFolder = _Folder.inbox;
  MessageParticipant? _currentUser;
  List<MessageParticipant> _projectUsers = [];
  bool _isLoadingUsers = true;

  Stream<List<CommunicationMessage>>? _inboxStream;
  Stream<List<CommunicationMessage>>? _sentStream;
  Stream<List<DraftMessage>>? _draftsStream;
  Stream<List<CommunicationMessage>>? _trashStream;
  Stream<int>? _unreadStream;

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initData();
    _searchCtrl.addListener(
        () => setState(() => _searchQuery = _searchCtrl.text.toLowerCase()));
  }

  Future<void> _initData() async {
    final me = await _service.getCurrentUserParticipant();
    final users = await _service.getProjectUsers(widget.project.id);

    if (mounted) {
      setState(() {
        _currentUser = me;
        _projectUsers = users;
        _isLoadingUsers = false;
        _inboxStream = _service.inboxStream(widget.project.id);
        _sentStream = _service.sentStream(widget.project.id);
        _draftsStream = _service.draftsStream(widget.project.id);
        _trashStream = _service.trashStream(widget.project.id);
        _unreadStream = _service.unreadCountStream(widget.project.id);
      });
    }
  }

  void _openCompose({
    List<MessageParticipant>? initialTo,
    List<MessageParticipant>? initialCc,
    String? initialSubject,
    String? replyToId,
    String? threadId,
    MessageType type = MessageType.original,
  }) {
    if (_currentUser == null) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CommunicationComposeDialog(
        projectId: widget.project.id,
        service: _service,
        currentUser: _currentUser!,
        projectUsers: _projectUsers,
        initialTo: initialTo,
        initialCc: initialCc,
        initialSubject: initialSubject,
        replyToMessageId: replyToId,
        threadId: threadId,
        messageType: type,
        onSent: () => setState(() => _activeFolder = _Folder.sent),
      ),
    );
  }

  void _openMessage(CommunicationMessage msg) {
    if (_currentUser == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommunicationMessageDetailScreen(
          message: msg,
          service: _service,
          currentUser: _currentUser!,
          projectUsers: _projectUsers,
          projectId: widget.project.id,
          onActionDone: () => setState(() {}),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return BaseLayout(
      title: 'Communication',
      project: widget.project,
      logger: widget.logger,
      selectedMenuItem: 'Communication',
      onMenuItemSelected: (_) {},
      floatingActionButton: isMobile ? _buildFab() : null,
      child: _isLoadingUsers
          ? const Center(child: CircularProgressIndicator())
          : isMobile
              ? _buildMobileLayout()
              : _buildDesktopLayout(),
    );
  }

  // ─── Desktop layout ───────────────────────────────────────────────────────
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        _buildSidebar(),
        const VerticalDivider(width: 1),
        Expanded(child: _buildMessagePane()),
      ],
    );
  }

  // ─── Mobile layout ────────────────────────────────────────────────────────
  Widget _buildMobileLayout() {
    return Column(
      children: [
        Expanded(child: _buildMessagePane()),
        _buildMobileBottomBar(),
      ],
    );
  }

  // ─── Sidebar (desktop) ────────────────────────────────────────────────────
  Widget _buildSidebar() {
    return Container(
      width: 220,
      color: Colors.white,
      child: Column(
        children: [
          const SizedBox(height: 16),

          // Compose button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ElevatedButton.icon(
              onPressed: _openCompose,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text('Compose',
                  style: GoogleFonts.poppins(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2E5A),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                elevation: 2,
              ),
            ),
          ),
          const SizedBox(height: 20),

          _folderTile(
            icon: Icons.inbox_outlined,
            label: 'Inbox',
            folder: _Folder.inbox,
            badge: _unreadStream,
          ),
          _folderTile(
            icon: Icons.send_outlined,
            label: 'Sent',
            folder: _Folder.sent,
          ),
          _folderTile(
            icon: Icons.drafts_outlined,
            label: 'Drafts',
            folder: _Folder.drafts,
          ),
          _folderTile(
            icon: Icons.delete_outline,
            label: 'Trash',
            folder: _Folder.trash,
          ),

          const Divider(height: 32),

          // Project label
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PROJECT',
                  style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: Colors.grey[400],
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.project.name,
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: const Color(0xFF0A2E5A),
                      fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const Spacer(),

          // Current user info footer
          if (_currentUser != null)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFF0A2E5A),
                    child: Text(
                      _currentUser!.username.isNotEmpty
                          ? _currentUser!.username[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _currentUser!.username,
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _currentUser!.email,
                          style: GoogleFonts.poppins(
                              fontSize: 10, color: Colors.grey[500]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ─── Folder tile ──────────────────────────────────────────────────────────
  Widget _folderTile({
    required IconData icon,
    required String label,
    required _Folder folder,
    Stream<int>? badge,
  }) {
    final isSelected = _activeFolder == folder;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        dense: true,
        leading: Icon(
          icon,
          size: 20,
          color: isSelected ? const Color(0xFF0A2E5A) : Colors.grey[600],
        ),
        title: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight:
                isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? const Color(0xFF0A2E5A)
                : Colors.grey[700],
          ),
        ),
        selected: isSelected,
        selectedTileColor:
            const Color(0xFF0A2E5A).withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        onTap: () => setState(() => _activeFolder = folder),
        trailing: badge != null
            ? StreamBuilder<int>(
                stream: badge,
                builder: (_, snap) {
                  final count = snap.data ?? 0;
                  if (count == 0) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A2E5A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11),
                    ),
                  );
                },
              )
            : null,
      ),
    );
  }

  // ─── Message pane ─────────────────────────────────────────────────────────
  Widget _buildMessagePane() {
    return Column(
      children: [
        _buildSearchBar(),
        Expanded(child: _buildMessageList()),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.grey[50],
      child: TextField(
        controller: _searchCtrl,
        style: GoogleFonts.poppins(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search messages…',
          hintStyle:
              GoogleFonts.poppins(fontSize: 13, color: Colors.grey[400]),
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  })
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF0A2E5A)),
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          isDense: true,
        ),
      ),
    );
  }

  // ─── Message list ─────────────────────────────────────────────────────────
  Widget _buildMessageList() {
    switch (_activeFolder) {
      case _Folder.inbox:
        return _streamList<CommunicationMessage>(
          stream: _inboxStream,
          itemBuilder: (msg) => _MessageTile(
            message: msg,
            currentUid: _currentUser?.uid ?? '',
            onTap: () => _openMessage(msg),
            onDelete: () => _service.softDelete(msg.id),
          ),
          filter: _matchSearch,
          emptyLabel: 'Your inbox is empty',
          emptyIcon: Icons.inbox_outlined,
        );
      case _Folder.sent:
        return _streamList<CommunicationMessage>(
          stream: _sentStream,
          itemBuilder: (msg) => _MessageTile(
            message: msg,
            currentUid: _currentUser?.uid ?? '',
            onTap: () => _openMessage(msg),
            onDelete: () => _service.softDelete(msg.id),
            isSent: true,
          ),
          filter: _matchSearch,
          emptyLabel: 'No sent messages',
          emptyIcon: Icons.send_outlined,
        );
      case _Folder.drafts:
        return _draftList();
      case _Folder.trash:
        return _streamList<CommunicationMessage>(
          stream: _trashStream,
          itemBuilder: (msg) => _MessageTile(
            message: msg,
            currentUid: _currentUser?.uid ?? '',
            onTap: () => _openMessage(msg),
            onDelete: () => _service.permanentlyDelete(msg.id),
            onRestore: () => _service.restoreFromTrash(msg.id),
            isTrash: true,
          ),
          filter: _matchSearch,
          emptyLabel: 'Trash is empty',
          emptyIcon: Icons.delete_outline,
        );
    }
  }

  bool _matchSearch(CommunicationMessage msg) {
    if (_searchQuery.isEmpty) return true;
    return msg.subject.toLowerCase().contains(_searchQuery) ||
        msg.bodyPlainText.toLowerCase().contains(_searchQuery) ||
        msg.from.email.toLowerCase().contains(_searchQuery) ||
        msg.from.username.toLowerCase().contains(_searchQuery) ||
        msg.to.any((p) =>
            p.email.toLowerCase().contains(_searchQuery) ||
            p.username.toLowerCase().contains(_searchQuery));
  }

  Widget _streamList<T>({
    required Stream<List<T>>? stream,
    required Widget Function(T) itemBuilder,
    required bool Function(T) filter,
    required String emptyLabel,
    required IconData emptyIcon,
  }) {
    if (stream == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return StreamBuilder<List<T>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = (snap.data ?? []).where(filter).toList();
        if (items.isEmpty) {
          return _emptyState(emptyLabel, emptyIcon);
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: items.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: Colors.grey.shade200),
          itemBuilder: (_, i) => itemBuilder(items[i]),
        );
      },
    );
  }

  Widget _draftList() {
    if (_draftsStream == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return StreamBuilder<List<DraftMessage>>(
      stream: _draftsStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final drafts = snap.data ?? [];
        if (drafts.isEmpty) {
          return _emptyState('No drafts saved', Icons.drafts_outlined);
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: drafts.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: Colors.grey.shade200),
          itemBuilder: (_, i) {
            final d = drafts[i];
            return _DraftTile(
              draft: d,
              onOpen: () {
                _openCompose(
                  initialTo: d.to,
                  initialCc: d.cc,
                  initialSubject: d.subject,
                );
                _service.deleteDraft(d.id);
              },
              onDelete: () => _service.deleteDraft(d.id),
            );
          },
        );
      },
    );
  }

  Widget _emptyState(String label, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            label,
            style: GoogleFonts.poppins(
                fontSize: 15, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  // ─── Mobile bottom bar ────────────────────────────────────────────────────
  Widget _buildMobileBottomBar() {
    return BottomNavigationBar(
      currentIndex: _Folder.values.indexOf(_activeFolder),
      onTap: (i) =>
          setState(() => _activeFolder = _Folder.values[i]),
      selectedLabelStyle: GoogleFonts.poppins(fontSize: 11),
      unselectedLabelStyle: GoogleFonts.poppins(fontSize: 11),
      selectedItemColor: const Color(0xFF0A2E5A),
      unselectedItemColor: Colors.grey[500],
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(
            icon: Icon(Icons.inbox_outlined), label: 'Inbox'),
        BottomNavigationBarItem(
            icon: Icon(Icons.send_outlined), label: 'Sent'),
        BottomNavigationBarItem(
            icon: Icon(Icons.drafts_outlined), label: 'Drafts'),
        BottomNavigationBarItem(
            icon: Icon(Icons.delete_outline), label: 'Trash'),
      ],
    );
  }

  // ─── FAB (mobile compose) ─────────────────────────────────────────────────
  Widget _buildFab() {
    return FloatingActionButton.extended(
      onPressed: _openCompose,
      backgroundColor: const Color(0xFF0A2E5A),
      foregroundColor: Colors.white,
      icon: const Icon(Icons.edit_outlined),
      label: Text('Compose', style: GoogleFonts.poppins()),
    );
  }
}

// ─── Message Tile ─────────────────────────────────────────────────────────────
class _MessageTile extends StatelessWidget {
  final CommunicationMessage message;
  final String currentUid;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onRestore;
  final bool isSent;
  final bool isTrash;

  const _MessageTile({
    required this.message,
    required this.currentUid,
    required this.onTap,
    required this.onDelete,
    this.onRestore,
    this.isSent = false,
    this.isTrash = false,
  });

  bool get _isUnread => !message.isReadBy(currentUid);

  /// True when the current user was looped in via Cc rather than addressed
  /// directly via To — mirrors email's "you were CC'd" distinction.
  bool get _isCcOnly =>
      !isSent &&
      message.cc.any((p) => p.uid == currentUid) &&
      !message.to.any((p) => p.uid == currentUid);

  @override
  Widget build(BuildContext context) {
    final displayName = isSent ? _recipientLabel() : _senderName();

    return Dismissible(
      key: Key(message.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: isTrash ? Colors.red : Colors.red[400],
        child: Icon(
          isTrash ? Icons.delete_forever : Icons.delete_outline,
          color: Colors.white,
        ),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false; // we handle removal ourselves via stream
      },
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: _isUnread && !isSent
              ? const Color(0xFF0A2E5A).withValues(alpha: 0.03)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: _avatarColor(),
                child: Text(
                  displayName.isNotEmpty
                      ? displayName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15),
                ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: _isUnread && !isSent
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: const Color(0xFF0A2E5A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _formatDate(message.sentAt),
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: _isUnread && !isSent
                                ? const Color(0xFF0A2E5A)
                                : Colors.grey[400],
                            fontWeight: _isUnread && !isSent
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            message.subject,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: _isUnread && !isSent
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: Colors.grey[800],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_isCcOnly)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Cc',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        if (message.attachments.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(Icons.attach_file,
                                size: 14, color: Colors.grey[400]),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message.bodyPlainText,
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.grey[500]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Unread dot
              if (_isUnread && !isSent)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(left: 6),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0A2E5A),
                    shape: BoxShape.circle,
                  ),
                ),

              // Restore button (trash folder only)
              if (isTrash && onRestore != null)
                IconButton(
                  icon: const Icon(
                      Icons.restore_from_trash_outlined,
                      size: 18),
                  color: Colors.grey[500],
                  onPressed: onRestore,
                  tooltip: 'Restore',
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _senderName() => message.from.username.isNotEmpty
      ? message.from.username
      : message.from.email;

  String _recipientLabel() {
    final names = message.to
        .map((p) =>
            p.username.isNotEmpty ? p.username : p.email)
        .toList();
    if (names.isEmpty) return 'No recipients';
    if (names.length == 1) return 'To: ${names.first}';
    return 'To: ${names.first} +${names.length - 1}';
  }

  Color _avatarColor() {
    const colors = [
      Color(0xFF0A2E5A),
      Color(0xFF1565C0),
      Color(0xFF1976D2),
      Color(0xFF0288D1),
      Color(0xFF0097A7),
    ];
    final idx = (message.from.uid.isNotEmpty
            ? message.from.uid.codeUnitAt(0)
            : 0) %
        colors.length;
    return colors[idx];
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day) {
      return DateFormat.jm().format(dt);
    }
    if (dt.year == now.year) {
      return DateFormat('MMM d').format(dt);
    }
    return DateFormat('MM/dd/yy').format(dt);
  }
}

// ─── Draft Tile ───────────────────────────────────────────────────────────────
class _DraftTile extends StatelessWidget {
  final DraftMessage draft;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _DraftTile({
    required this.draft,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final toLabel = draft.to.isEmpty
        ? '(No recipients)'
        : draft.to.map((p) => p.email).join(', ');

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 20,
              backgroundColor: Colors.grey,
              child: Icon(Icons.drafts_outlined,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Draft',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange[700],
                          ),
                        ),
                      ),
                      Text(
                        DateFormat.MMMd().format(draft.savedAt),
                        style: GoogleFonts.poppins(
                            fontSize: 11, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                  Text(
                    draft.subject.isNotEmpty
                        ? draft.subject
                        : '(No subject)',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: Colors.grey[700]),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'To: $toLabel',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey[500]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 18, color: Colors.grey[400]),
              onPressed: onDelete,
              tooltip: 'Delete draft',
            ),
          ],
        ),
      ),
    );
  }
}