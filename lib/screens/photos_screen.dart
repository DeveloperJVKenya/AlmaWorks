import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PhotosScreen
//
// Reads from the top-level "Photos" Firestore collection — the promoted/curated
// set that admins push photos into from the PhotoGallery.
//
// Access model:
//   • Clients  → sidebar menu item "Photos" (only visible to them)
//   • Admins   → FAB inside PhotoGalleryScreen ("View Photos →")
//
// Actions available per photo: View full-screen, Edit metadata, Share, Delete.
// No "Move" action — this is the destination collection, not the source.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Selection state (same pattern as PhotoGalleryScreen)
// ─────────────────────────────────────────────────────────────────────────────
class _SelectionState extends ChangeNotifier {
  bool _multiSelectMode = false;
  final Set<String> _selected = {};

  bool get multiSelectMode => _multiSelectMode;
  Set<String> get selected => Set.unmodifiable(_selected);
  int get count => _selected.length;
  bool isSelected(String id) => _selected.contains(id);

  void startMultiSelect(String photoId) {
    _multiSelectMode = true;
    _selected.add(photoId);
    notifyListeners();
  }

  void toggle(String photoId) {
    if (_selected.contains(photoId)) {
      _selected.remove(photoId);
      if (_selected.isEmpty) _multiSelectMode = false;
    } else {
      _selected.add(photoId);
    }
    notifyListeners();
  }

  void exitMultiSelect() {
    _multiSelectMode = false;
    _selected.clear();
    notifyListeners();
  }

  List<String> snapshot() => List<String>.from(_selected);
}

// ─────────────────────────────────────────────────────────────────────────────
// Data model for a Photos collection document
// ─────────────────────────────────────────────────────────────────────────────
class _PhotoItem {
  final String id;
  final String name;
  final String url;
  final String category;
  final String phase;
  final DateTime uploadedAt;
  final String projectId;

  const _PhotoItem({
    required this.id,
    required this.name,
    required this.url,
    required this.category,
    required this.phase,
    required this.uploadedAt,
    required this.projectId,
  });

  factory _PhotoItem.fromMap(String id, Map<String, dynamic> data) {
    DateTime uploadedAt = DateTime.now();
    final raw = data['uploadedAt'];
    if (raw is Timestamp) {
      uploadedAt = raw.toDate();
    } else if (raw is String) {
      uploadedAt = DateTime.tryParse(raw) ?? DateTime.now();
    }
    return _PhotoItem(
      id: id,
      name: data['name'] as String? ?? '',
      url: data['url'] as String? ?? '',
      category: data['category'] as String? ?? '',
      phase: data['phase'] as String? ?? '',
      uploadedAt: uploadedAt,
      projectId: data['projectId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toUpdateMap({
    String? name,
    String? category,
    String? phase,
  }) =>
      {
        if (name != null) 'name': name,
        if (category != null) 'category': category,
        if (phase != null) 'phase': phase,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen widget
// ─────────────────────────────────────────────────────────────────────────────
class PhotosScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;

  const PhotosScreen({
    super.key,
    required this.project,
    required this.logger,
  });

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  final _SelectionState _selection = _SelectionState();
  String? _userRole = 'Client'; // default to most restrictive until loaded

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        widget.logger.e('❌ PhotosScreen: No authenticated user found');
        return;
      }
      final querySnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        final role =
            querySnapshot.docs.first.data()['role'] as String? ?? 'Client';
        if (mounted) setState(() => _userRole = role);
        widget.logger.i('✅ PhotosScreen: User role fetched: $role');
      }
    } catch (e) {
      widget.logger.e('❌ PhotosScreen: Error fetching user role: $e');
    }
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  // ── Snackbar helper ──────────────────────────────────────────────────────────
  void _showSnackBar(
    String message, {
    Color backgroundColor = Colors.black87,
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        action: action,
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) {
        return BaseLayout(
          title: '${widget.project.name} - Photos',
          project: widget.project,
          logger: widget.logger,
          selectedMenuItem: 'Photos',
          onMenuItemSelected: (_) {},
          // No FAB — clients cannot upload; admins upload via PhotoGallery
          floatingActionButton: null,
          child: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    if (_selection.multiSelectMode)
                      SliverToBoxAdapter(child: _buildSelectionHeader()),
                    _buildPhotosSlivers(),
                  ],
                ),
              ),
              _buildFooter(context),
              if (_selection.multiSelectMode) _buildMultiSelectActionBar(),
            ],
          ),
        );
      },
    );
  }

  // ── Selection header ─────────────────────────────────────────────────────────
  Widget _buildSelectionHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF0A2E5A).withValues(alpha: 0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_selection.count} selected',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF0A2E5A),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              widget.logger.i('🔄 PhotosScreen: Exiting multi-select mode');
              _selection.exitMultiSelect();
            },
            icon: const Icon(Icons.close, color: Color(0xFF0A2E5A)),
            label: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: const Color(0xFF0A2E5A)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Multi-select action bar (Share + Delete only — no Move) ──────────────────
  Widget _buildMultiSelectActionBar() {
    final bool hasSelection = _selection.count > 0;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A2E5A),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildActionButton(
                icon: Icons.share,
                label: 'Share',
                onPressed: hasSelection ? _handleMultiShare : null,
              ),
              if (_userRole != 'Client')
                _buildActionButton(
                  icon: Icons.delete,
                  label: 'Delete',
                  onPressed: hasSelection ? _handleMultiDelete : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final bool isEnabled = onPressed != null;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          label: Text(label, style: GoogleFonts.poppins(fontSize: 12)),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isEnabled ? Colors.white : Colors.white.withValues(alpha: 0.3),
            foregroundColor:
                isEnabled ? const Color(0xFF0A2E5A) : Colors.grey,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }

  // ── Footer ───────────────────────────────────────────────────────────────────
  Widget _buildFooter(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      color: const Color(0xFF0A2E5A),
      child: Text(
        '© 2026 JV Alma C.I.S Site Management System',
        style: TextStyle(
          color: Colors.white,
          fontSize: isMobile ? 12 : 14,
          fontWeight: FontWeight.w400,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ── Main gallery sliver (reads from "Photos" collection) ─────────────────────
  Widget _buildPhotosSlivers() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Photos')
          .where('projectId', isEqualTo: widget.project.id)
          .where('isDeleted', isEqualTo: false)
          .orderBy('uploadedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          widget.logger.e(
            '❌ PhotosScreen: Firestore error: ${snapshot.error}',
            stackTrace: snapshot.stackTrace,
          );
          return SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off, size: 48, color: Colors.red[300]),
                  const SizedBox(height: 12),
                  Text(
                    'Error loading photos',
                    style: GoogleFonts.poppins(
                        color: Colors.red[600], fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${snapshot.error}',
                    style:
                        GoogleFonts.poppins(color: Colors.grey, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh),
                    label: Text('Retry', style: GoogleFonts.poppins()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0A2E5A),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final List<DocumentSnapshot> docs = snapshot.data!.docs;
        final List<_PhotoItem> photos = docs
            .map((doc) => _PhotoItem.fromMap(
                doc.id, doc.data() as Map<String, dynamic>))
            .toList();

        widget.logger.i(
            '📸 PhotosScreen: Loaded ${photos.length} photos for project: ${widget.project.name}');

        if (photos.isEmpty) {
          return SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library_outlined,
                      size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No photos available yet.',
                    style: GoogleFonts.poppins(
                        color: Colors.grey[600], fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Photos promoted by your project team will appear here.',
                    style: GoogleFonts.poppins(
                        color: Colors.grey[500], fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        // Group by date
        final Map<String, List<_PhotoItem>> dateGroups = {};
        for (final _PhotoItem photo in photos) {
          final String dateKey =
              DateFormat('yyyy-MM-dd').format(photo.uploadedAt);
          dateGroups.update(dateKey, (list) => list..add(photo),
              ifAbsent: () => [photo]);
        }
        final List<String> sortedDates = dateGroups.keys.toList()
          ..sort((a, b) => b.compareTo(a));

        widget.logger.d(
            '📅 PhotosScreen: ${sortedDates.length} date groups: ${sortedDates.join(', ')}');

        final List<Widget> slivers = [];
        for (final String dateKey in sortedDates) {
          final List<_PhotoItem> groupPhotos = dateGroups[dateKey]!;
          slivers.add(SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                _formatDate(DateTime.parse(dateKey)),
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, fontSize: 18),
              ),
            ),
          ));
          slivers.add(_buildDateGroupSliver(groupPhotos));
        }

        return _MultiSliverRaw(slivers: slivers);
      },
    );
  }

  // ── Sliver grid for one date group ──────────────────────────────────────────
  Widget _buildDateGroupSliver(List<_PhotoItem> photos) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final double width = constraints.crossAxisExtent;
          final int crossAxisCount =
              width < 600 ? 2 : width < 1200 ? 4 : 6;
          final double spacing = width < 600 ? 8.0 : 16.0;

          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 1,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, idx) => _buildPhotoTile(photos[idx]),
              childCount: photos.length,
              addRepaintBoundaries: true,
            ),
          );
        },
      ),
    );
  }

  // ── Individual photo tile ────────────────────────────────────────────────────
  Widget _buildPhotoTile(_PhotoItem photo) {
    return _PhotoTile(
      key: ValueKey(photo.id),
      photo: photo,
      selection: _selection,
      onContextMenu: (position) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showContextMenu(position, photo);
        });
      },
      onTap: () {
        if (_selection.multiSelectMode) {
          _selection.toggle(photo.id);
        } else {
          _viewPhotoFullScreen(photo);
        }
      },
      onLongPress: () {
        if (!_selection.multiSelectMode) {
          _selection.startMultiSelect(photo.id);
        }
      },
      onImageError: (error) {
        widget.logger
            .e('⛔ PhotosScreen: Image load error for ${photo.id}: $error');
      },
    );
  }

  // ── Right-click / long-press context menu ────────────────────────────────────
  void _showContextMenu(Offset position, _PhotoItem photo) {
    widget.logger
        .i('🖱️ PhotosScreen: Context menu at $position for photo: ${photo.id}');

    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    showMenu<void>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        // ── Toggle multi-select ──────────────────────────────────────────────
        PopupMenuItem<void>(
          onTap: () {
            if (_selection.multiSelectMode) {
              _selection.exitMultiSelect();
            } else {
              _selection.startMultiSelect(photo.id);
            }
          },
          child: ListTile(
            leading: Icon(
              _selection.multiSelectMode
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
              color: const Color(0xFF0A2E5A),
            ),
            title: Text(
              _selection.multiSelectMode
                  ? 'Deactivate Selection'
                  : 'Activate Selection',
              style: GoogleFonts.poppins(fontSize: 14),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (!_selection.multiSelectMode) ...[
          const PopupMenuDivider(),
          // ── View ────────────────────────────────────────────────────────────
          PopupMenuItem<void>(
            onTap: () => WidgetsBinding.instance
                .addPostFrameCallback((_) => _viewPhotoFullScreen(photo)),
            child: ListTile(
              leading:
                  const Icon(Icons.visibility, color: Color(0xFF0A2E5A)),
              title: Text('View', style: GoogleFonts.poppins(fontSize: 14)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          // ── Edit ────────────────────────────────────────────────────────────
          PopupMenuItem<void>(
            onTap: () => WidgetsBinding.instance
                .addPostFrameCallback((_) => _editPhotoDetails(photo)),
            child: ListTile(
              leading: const Icon(Icons.edit, color: Color(0xFF0A2E5A)),
              title: Text('Edit', style: GoogleFonts.poppins(fontSize: 14)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          // ── Share ────────────────────────────────────────────────────────────
          PopupMenuItem<void>(
            onTap: () => WidgetsBinding.instance
                .addPostFrameCallback((_) => _sharePhoto(photo)),
            child: ListTile(
              leading: const Icon(Icons.share, color: Color(0xFF0A2E5A)),
              title: Text('Share', style: GoogleFonts.poppins(fontSize: 14)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          // ── Delete ───────────────────────────────────────────────────────────
          if (_userRole != 'Client')
            PopupMenuItem<void>(
              onTap: () => WidgetsBinding.instance
                  .addPostFrameCallback((_) => _deletePhoto(photo)),
              child: ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text('Delete',
                    style:
                        GoogleFonts.poppins(fontSize: 14, color: Colors.red)),
                contentPadding: EdgeInsets.zero,
              ),
            ),
        ],
      ],
    );
  }

  // ── Multi-share ──────────────────────────────────────────────────────────────
  Future<void> _handleMultiShare() async {
    final List<String> idsToShare = _selection.snapshot();
    widget.logger.i('📤 PhotosScreen: Multi-share: ${idsToShare.length} photos');

    _selection.exitMultiSelect();

    if (kIsWeb) {
      _showSnackBar(
        '⚠️ File sharing is not supported in the browser. '
        'Please use the mobile app.',
        backgroundColor: Colors.orange[800]!,
        duration: const Duration(seconds: 5),
      );
      return;
    }

    _showSnackBar(
      'Preparing ${idsToShare.length} photos for sharing…',
      backgroundColor: const Color(0xFF0A2E5A),
      duration: const Duration(seconds: 30),
    );

    final List<XFile> files = [];
    final Directory tempDir = await getTemporaryDirectory();

    for (final String id in idsToShare) {
      try {
        final DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('Photos')
            .doc(id)
            .get();
        if (doc.exists) {
          final _PhotoItem photo = _PhotoItem.fromMap(
              id, doc.data() as Map<String, dynamic>);
          final String path = '${tempDir.path}/${photo.name}';
          await FirebaseStorage.instance
              .refFromURL(photo.url)
              .writeToFile(File(path));
          files.add(XFile(path));
        }
      } catch (e) {
        widget.logger.e('📤 PhotosScreen: Error preparing $id for share: $e');
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();

    if (files.isEmpty) {
      _showSnackBar(
        '❌ Could not prepare any photos for sharing.',
        backgroundColor: Colors.red[700]!,
      );
      return;
    }

    try {
      await SharePlus.instance.share(ShareParams(files: files));
      widget.logger.i('✅ PhotosScreen: Multi-share completed');
    } catch (e) {
      widget.logger.e('📤 PhotosScreen: Share failed: $e');
      if (!mounted) return;
      _showSnackBar('❌ Share failed: $e', backgroundColor: Colors.red[700]!);
    }
  }

  // ── Multi-delete ─────────────────────────────────────────────────────────────
  Future<void> _handleMultiDelete() async {
    final List<String> idsToDelete = _selection.snapshot();
    widget.logger
        .i('🗑️ PhotosScreen: Multi-delete: ${idsToDelete.length} photos');

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever, color: Colors.red),
            const SizedBox(width: 8),
            Text('Delete Photos', style: GoogleFonts.poppins()),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${idsToDelete.length} '
          'selected photo${idsToDelete.length > 1 ? 's' : ''}?\n\n'
          'This action cannot be undone.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete',
                style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    _selection.exitMultiSelect();

    int deleted = 0;
    int failed = 0;
    for (final String id in idsToDelete) {
      try {
        await FirebaseFirestore.instance
            .collection('Photos')
            .doc(id)
            .update({'isDeleted': true});
        deleted++;
        widget.logger.i('🗑️ PhotosScreen: Soft-deleted $id');
      } catch (e) {
        widget.logger.e('🗑️ PhotosScreen: Failed to delete $id: $e');
        failed++;
      }
    }

    if (!mounted) return;
    _showSnackBar(
      failed == 0
          ? '🗑️ $deleted photo${deleted > 1 ? 's' : ''} deleted.'
          : '🗑️ $deleted deleted, $failed failed.',
      backgroundColor: failed > 0 ? Colors.orange[800]! : Colors.grey[700]!,
    );
  }

  // ── Full-screen viewer ───────────────────────────────────────────────────────
  void _viewPhotoFullScreen(_PhotoItem photo) {
    widget.logger.i('🖼️ PhotosScreen: Full-screen: ${photo.id}');
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(photo.name, style: GoogleFonts.poppins()),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit',
                onPressed: () => _editPhotoDetails(photo),
              ),
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: 'Share',
                onPressed: () => _sharePhoto(photo),
              ),
              if (_userRole != 'Client')
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: 'Delete',
                  onPressed: () => _deletePhoto(photo),
                ),
            ],
          ),
          body: PhotoView(
            imageProvider: CachedNetworkImageProvider(photo.url),
            loadingBuilder: (context, event) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            errorBuilder: (context, error, trace) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.broken_image,
                      color: Colors.white54, size: 64),
                  const SizedBox(height: 12),
                  Text('Cannot display image',
                      style: GoogleFonts.poppins(color: Colors.white54)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Edit photo metadata ──────────────────────────────────────────────────────
  Future<void> _editPhotoDetails(_PhotoItem photo) async {
    final TextEditingController titleCtrl =
        TextEditingController(text: photo.name);
    final TextEditingController categoryCtrl =
        TextEditingController(text: photo.category);
    final TextEditingController phaseCtrl =
        TextEditingController(text: photo.phase);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Edit Photo Details', style: GoogleFonts.poppins()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                  labelText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: categoryCtrl,
              decoration: const InputDecoration(
                  labelText: 'Category', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phaseCtrl,
              decoration: const InputDecoration(
                  labelText: 'Phase', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2E5A)),
            child: Text('Save',
                style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final Map<String, dynamic> updates = {};
      final String newName = titleCtrl.text.trim();
      final String newCategory = categoryCtrl.text.trim();
      final String newPhase = phaseCtrl.text.trim();

      if (newName.isNotEmpty) updates['name'] = newName;
      if (newCategory.isNotEmpty) updates['category'] = newCategory;
      if (newPhase.isNotEmpty) updates['phase'] = newPhase;

      if (updates.isEmpty) {
        _showSnackBar('No changes made.', backgroundColor: Colors.grey[700]!);
        return;
      }

      try {
        await FirebaseFirestore.instance
            .collection('Photos')
            .doc(photo.id)
            .update(updates);
        widget.logger.i('✏️ PhotosScreen: Updated ${photo.id}');
        if (!mounted) return;
        _showSnackBar('✅ Photo details updated.',
            backgroundColor: Colors.green[700]!);
      } catch (e) {
        widget.logger.e('✏️ PhotosScreen: Update failed: $e');
        if (!mounted) return;
        _showSnackBar('❌ Update failed: $e',
            backgroundColor: Colors.red[700]!);
      }
    }
  }

  // ── Share single photo ───────────────────────────────────────────────────────
  Future<void> _sharePhoto(_PhotoItem photo) async {
    widget.logger.i('📤 PhotosScreen: Share: ${photo.id}');

    if (kIsWeb) {
      _showSnackBar(
        '⚠️ File sharing is not supported in the browser.',
        backgroundColor: Colors.orange[800]!,
      );
      return;
    }

    // Capture messenger before the first await (use_build_context_synchronously)
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Preparing photo for sharing…',
              style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: const Color(0xFF0A2E5A),
          duration: const Duration(seconds: 30),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );

      final Directory tempDir = await getTemporaryDirectory();
      final String path = '${tempDir.path}/${photo.name}';
      await FirebaseStorage.instance
          .refFromURL(photo.url)
          .writeToFile(File(path));

      messenger.clearSnackBars();

      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
      widget.logger.i('✅ PhotosScreen: Share completed for ${photo.id}');
    } catch (e, st) {
      widget.logger.e('📤 PhotosScreen: Share error: $e', stackTrace: st);
      messenger.clearSnackBars();
      if (!mounted) return;
      _showSnackBar('❌ Share failed: $e', backgroundColor: Colors.red[700]!);
    }
  }

  // ── Delete single photo ──────────────────────────────────────────────────────
  Future<void> _deletePhoto(_PhotoItem photo) async {
    widget.logger.i('🗑️ PhotosScreen: Delete: ${photo.id}');

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.delete, color: Colors.red),
            const SizedBox(width: 8),
            Text('Delete Photo', style: GoogleFonts.poppins()),
          ],
        ),
        content: Text('Delete this photo? This cannot be undone.',
            style: GoogleFonts.poppins()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete',
                style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('Photos')
            .doc(photo.id)
            .update({'isDeleted': true});
        widget.logger.i('🗑️ PhotosScreen: Soft-deleted ${photo.id}');

        if (!mounted) return;
        if (Navigator.canPop(context)) Navigator.pop(context);
        _showSnackBar('🗑️ Photo deleted.',
            backgroundColor: Colors.grey[700]!);
      } catch (e) {
        widget.logger.e('🗑️ PhotosScreen: Delete failed: $e');
        if (!mounted) return;
        _showSnackBar('❌ Delete failed: $e',
            backgroundColor: Colors.red[700]!);
      }
    }
  }

  // ── Utility ──────────────────────────────────────────────────────────────────
  String _formatDate(DateTime date) =>
      DateFormat('MMMM dd, yyyy').format(date);
}

// ─────────────────────────────────────────────────────────────────────────────
// _PhotoTile – StatefulWidget with proper listener lifecycle.
// Same pattern as PhotoGalleryScreen to prevent window.dart:99 assertions.
// ─────────────────────────────────────────────────────────────────────────────
class _PhotoTile extends StatefulWidget {
  final _PhotoItem photo;
  final _SelectionState selection;
  final void Function(Offset position) onContextMenu;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final void Function(dynamic error) onImageError;

  const _PhotoTile({
    super.key,
    required this.photo,
    required this.selection,
    required this.onContextMenu,
    required this.onTap,
    required this.onLongPress,
    required this.onImageError,
  });

  @override
  State<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends State<_PhotoTile> {
  late bool _isSelected;
  late bool _multiSelectMode;

  @override
  void initState() {
    super.initState();
    _isSelected = widget.selection.isSelected(widget.photo.id);
    _multiSelectMode = widget.selection.multiSelectMode;
    widget.selection.addListener(_onSelectionChanged);
  }

  void _onSelectionChanged() {
    final bool nowSelected = widget.selection.isSelected(widget.photo.id);
    final bool nowMulti = widget.selection.multiSelectMode;
    if (nowSelected != _isSelected || nowMulti != _multiSelectMode) {
      setState(() {
        _isSelected = nowSelected;
        _multiSelectMode = nowMulti;
      });
    }
  }

  @override
  void didUpdateWidget(_PhotoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection) {
      oldWidget.selection.removeListener(_onSelectionChanged);
      widget.selection.addListener(_onSelectionChanged);
      _isSelected = widget.selection.isSelected(widget.photo.id);
      _multiSelectMode = widget.selection.multiSelectMode;
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onSelectionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons == kSecondaryMouseButton) {
          widget.onContextMenu(event.position);
        }
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            border: _isSelected
                ? Border.all(color: const Color(0xFF0A2E5A), width: 3)
                : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: widget.photo.url,
                fit: BoxFit.cover,
                cacheKey: widget.photo.id,
                memCacheWidth: 400,
                memCacheHeight: 400,
                maxHeightDiskCache: 600,
                maxWidthDiskCache: 600,
                placeholder: (context, url) => Container(
                  color: Colors.grey[200],
                  child: const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF0A2E5A), strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) {
                  widget.onImageError(error);
                  return _buildErrorWidget();
                },
                fadeInDuration: const Duration(milliseconds: 200),
              ),

              // Category / phase label
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  color: Colors.black.withValues(alpha: 0.5),
                  child: Text(
                    '${widget.photo.category} - ${widget.photo.phase}',
                    style:
                        const TextStyle(color: Colors.white, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),

              // Checkbox overlay (multi-select mode only)
              if (_multiSelectMode)
                Positioned(
                  top: 6,
                  right: 6,
                  child: AnimatedScale(
                    scale: 1.0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _isSelected
                            ? const Color(0xFF0A2E5A)
                            : Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: Checkbox(
                          value: _isSelected,
                          onChanged: (_) =>
                              widget.selection.toggle(widget.photo.id),
                          activeColor: Colors.transparent,
                          checkColor: Colors.white,
                          side: BorderSide.none,
                          shape: const CircleBorder(),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ),
                ),

              // Selected tint overlay
              if (_isSelected)
                Positioned.fill(
                  child: Container(
                    color:
                        const Color(0xFF0A2E5A).withValues(alpha: 0.18),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      color: Colors.grey[200],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image, color: Colors.grey[500], size: 28),
          const SizedBox(height: 4),
          Text(
            'Unavailable',
            style: TextStyle(color: Colors.grey[600], fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MultiSliver helper
// ─────────────────────────────────────────────────────────────────────────────
class _MultiSliverRaw extends StatelessWidget {
  final List<Widget> slivers;
  const _MultiSliverRaw({required this.slivers});

  @override
  Widget build(BuildContext context) =>
      SliverMainAxisGroup(slivers: slivers);
}