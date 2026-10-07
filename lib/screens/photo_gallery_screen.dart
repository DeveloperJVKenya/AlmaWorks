import 'package:almaworks/models/photo_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:logger/logger.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:almaworks/screens/photos_screen.dart';

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
class PhotoGalleryScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;

  const PhotoGalleryScreen({
    super.key,
    required this.project,
    required this.logger,
  });

  @override
  State<PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen> {
  final _SelectionState _selection = _SelectionState();

  bool _isLoading = false;

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
        content: Text(message, style: TextStyle(color: Colors.white)),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        action: action,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) {
        return BaseLayout(
          title: '${widget.project.name} - Photo Gallery',
          project: widget.project,
          logger: widget.logger,
          selectedMenuItem: 'Photo Gallery',
          onMenuItemSelected: (_) {},
          floatingActionButton: !_selection.multiSelectMode
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // ── Navigate to Photos (curated collection) ──────────────
                    FloatingActionButton.extended(
                      heroTag: 'fab_view_photos',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => PhotosScreen(
                              project: widget.project,
                              logger: widget.logger,
                            ),
                          ),
                        );
                      },
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0A2E5A),
                      elevation: 4,
                      icon: const Icon(Icons.photo_album),
                      label: const Text('View Photos'),
                    ),
                    const SizedBox(height: 12),
                    // ── Upload new photo to PhotoGallery ─────────────────────
                    FloatingActionButton(
                      heroTag: 'fab_add_photo',
                      onPressed: _isLoading ? null : _startAddPhotoFlow,
                      backgroundColor: const Color(0xFF0A2E5A),
                      foregroundColor: Colors.white,
                      tooltip: 'Upload photo',
                      child: const Icon(Icons.add_photo_alternate),
                    ),
                  ],
                )
              : null,
          child: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    if (_selection.multiSelectMode)
                      SliverToBoxAdapter(child: _buildSelectionHeader()),
                    _buildPhotoGallerySlivers(),
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
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF0A2E5A),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              widget.logger.i('🔄 Exiting multi-select mode');
              _selection.exitMultiSelect();
            },
            icon: const Icon(Icons.close, color: Color(0xFF0A2E5A)),
            label: Text(
              'Cancel',
              style: TextStyle(color: const Color(0xFF0A2E5A)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Multi-select action bar ──────────────────────────────────────────────────
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
                icon: Icons.drive_file_move,
                label: 'Move to Photos',
                onPressed: hasSelection ? _moveToPhotosCollection : null,
              ),
              _buildActionButton(
                icon: Icons.share,
                label: 'Share',
                onPressed: hasSelection ? _handleMultiShare : null,
              ),
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
          label: Text(label, style: TextStyle(fontSize: 12)),
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

  // ── Main gallery sliver ──────────────────────────────────────────────────────
  Widget _buildPhotoGallerySlivers() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('PhotoGallery')
          .where('projectId', isEqualTo: widget.project.id)
          .where('isDeleted', isEqualTo: false)
          .orderBy('uploadedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          widget.logger.e(
            'Firestore error: ${snapshot.error}',
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
                    style: TextStyle(
                        color: Colors.red[600], fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${snapshot.error}',
                    style:
                        TextStyle(color: Colors.grey, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh),
                    label: Text('Retry', style: TextStyle()),
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
        final List<PhotoModel> photos = docs
            .map((doc) =>
                PhotoModel.fromMap(doc.id, doc.data() as Map<String, dynamic>))
            .toList();

        widget.logger.i(
            '📸 Loaded ${photos.length} photos for project: ${widget.project.name}');

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
                    'No photos yet. Add some!',
                    style: TextStyle(
                        color: Colors.grey[600], fontSize: 16),
                  ),
                ],
              ),
            ),
          );
        }

        // Group photos by date
        final Map<String, List<PhotoModel>> dateGroups = {};
        for (final PhotoModel photo in photos) {
          final String dateKey =
              DateFormat('yyyy-MM-dd').format(photo.uploadedAt);
          dateGroups.update(dateKey, (list) => list..add(photo),
              ifAbsent: () => [photo]);
        }
        final List<String> sortedDates = dateGroups.keys.toList()
          ..sort((a, b) => b.compareTo(a));

        widget.logger.d(
            '📅 ${sortedDates.length} date groups: ${sortedDates.join(', ')}');

        final List<Widget> slivers = [];
        for (final String dateKey in sortedDates) {
          final List<PhotoModel> groupPhotos = dateGroups[dateKey]!;
          slivers.add(SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                _formatDate(DateTime.parse(dateKey)),
                style: TextStyle(
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
  Widget _buildDateGroupSliver(List<PhotoModel> photos) {
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

  Widget _buildPhotoTile(PhotoModel photo) {
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
        widget.logger.e('⛔  Image load error for ${photo.id}: $error');
      },
    );
  }

  // ── Right-click context menu ─────────────────────────────────────────────────
  void _showContextMenu(Offset position, PhotoModel photo) {
    widget.logger.i('🖱️ Context menu at $position for photo: ${photo.id}');

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
              style: TextStyle(fontSize: 14),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (!_selection.multiSelectMode) ...[
          const PopupMenuDivider(),
          PopupMenuItem<void>(
            onTap: () => WidgetsBinding.instance
                .addPostFrameCallback((_) => _viewPhotoFullScreen(photo)),
            child: ListTile(
              leading:
                  const Icon(Icons.visibility, color: Color(0xFF0A2E5A)),
              title: Text('View', style: TextStyle(fontSize: 14)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem<void>(
            onTap: () => WidgetsBinding.instance
                .addPostFrameCallback((_) => _editPhotoDetails(photo)),
            child: ListTile(
              leading: const Icon(Icons.edit, color: Color(0xFF0A2E5A)),
              title: Text('Edit', style: TextStyle(fontSize: 14)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem<void>(
            onTap: () => WidgetsBinding.instance
                .addPostFrameCallback((_) => _sharePhoto(photo)),
            child: ListTile(
              leading: const Icon(Icons.share, color: Color(0xFF0A2E5A)),
              title: Text('Share', style: TextStyle(fontSize: 14)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem<void>(
            onTap: () => WidgetsBinding.instance
                .addPostFrameCallback((_) => _deletePhoto(photo)),
            child: ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text('Delete',
                  style:
                      TextStyle(fontSize: 14, color: Colors.red)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ],
    );
  }

  // ── Move selected photos to Photos collection ────────────────────────────────
  Future<void> _moveToPhotosCollection() async {
    final List<String> idsToMove = _selection.snapshot();
    widget.logger.i('📦 Moving ${idsToMove.length} photos to Photos');
    if (idsToMove.isEmpty) return;

    _selection.exitMultiSelect();
    if (mounted) setState(() => _isLoading = true);

    int successCount = 0;
    int alreadyExistsCount = 0;
    int failCount = 0;
    double progress = 0;

    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    // Progress dialog
    final ValueNotifier<double> progressNotifier = ValueNotifier(0);
    navigator.push(
      DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (ctx, value, _) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                const Icon(Icons.drive_file_move, color: Color(0xFF0A2E5A)),
                const SizedBox(width: 8),
                Text('Moving Photos', style: TextStyle()),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: value,
                  backgroundColor: Colors.grey[200],
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF0A2E5A)),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 12),
                Text(
                  '${(value * idsToMove.length).round()} of '
                  '${idsToMove.length} photos processed…',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    for (int i = 0; i < idsToMove.length; i++) {
      final String photoId = idsToMove[i];
      try {
        final DocumentSnapshot photoDoc = await FirebaseFirestore.instance
            .collection('PhotoGallery')
            .doc(photoId)
            .get();

        if (!photoDoc.exists) {
          widget.logger.w('⚠️ Photo $photoId not found');
          failCount++;
        } else {
          final PhotoModel photo = PhotoModel.fromMap(
              photoId, photoDoc.data() as Map<String, dynamic>);

          final QuerySnapshot existing = await FirebaseFirestore.instance
              .collection('Photos')
              .where('url', isEqualTo: photo.url)
              .where('projectId', isEqualTo: widget.project.id)
              .limit(1)
              .get();

          if (existing.docs.isNotEmpty) {
            widget.logger.w('⚠️ ${photo.name} already in Photos collection');
            alreadyExistsCount++;
          } else {
            await FirebaseFirestore.instance.collection('Photos').add({
              'name': photo.name,
              'url': photo.url,
              'category': photo.category,
              'phase': photo.phase,
              'uploadedAt': Timestamp.fromDate(photo.uploadedAt),
              'movedAt': FieldValue.serverTimestamp(),
              'isDeleted': false,
              'projectId': widget.project.id,
              'sourceCollection': 'PhotoGallery',
              'sourceDocId': photoId,
            });
            successCount++;
            widget.logger.i('✅ Moved $photoId → Photos');
          }
        }
      } catch (e) {
        widget.logger.e('❌ Error moving $photoId: $e');
        failCount++;
      }

      progress = (i + 1) / idsToMove.length;
      progressNotifier.value = progress;
    }

    progressNotifier.dispose();

    // Close dialog via the captured navigator (no async gap after this point)
    navigator.pop();

    if (!mounted) return;
    setState(() => _isLoading = false);

    final StringBuffer msg = StringBuffer();
    if (successCount > 0) {
      msg.write(
          '✅ $successCount photo${successCount > 1 ? 's' : ''} moved to Photos.');
    }
    if (alreadyExistsCount > 0) {
      if (msg.isNotEmpty) msg.write('  ');
      msg.write('⚠️ $alreadyExistsCount already existed.');
    }
    if (failCount > 0) {
      if (msg.isNotEmpty) msg.write('  ');
      msg.write('❌ $failCount failed.');
    }
    if (msg.isEmpty) msg.write('No photos were moved.');

    final Color bgColor = failCount > 0
        ? Colors.orange[800]!
        : successCount > 0
            ? Colors.green[700]!
            : Colors.grey[700]!;

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content:
            Text(msg.toString(), style: TextStyle(color: Colors.white)),
        backgroundColor: bgColor,
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        action: (failCount > 0 || alreadyExistsCount > 0)
            ? SnackBarAction(
                label: 'Details',
                textColor: Colors.white,
                onPressed: () {
                  if (!mounted) return;
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('Move Results', style: TextStyle()),
                      content: Text(
                        'Moved successfully: $successCount\n'
                        'Already existed: $alreadyExistsCount\n'
                        'Failed: $failCount\n\n'
                        'Photos that "already existed" are already present in '
                        'the Photos collection and were not duplicated.',
                        style: TextStyle(),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('OK', style: TextStyle()),
                        ),
                      ],
                    ),
                  );
                },
              )
            : null,
      ),
    );
  }

  // ── Multi-share ──────────────────────────────────────────────────────────────
  Future<void> _handleMultiShare() async {
    final List<String> idsToShare = _selection.snapshot();
    widget.logger.i('📤 Multi-share: ${idsToShare.length} photos');

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
            .collection('PhotoGallery')
            .doc(id)
            .get();
        if (doc.exists) {
          final PhotoModel photo =
              PhotoModel.fromMap(id, doc.data() as Map<String, dynamic>);
          final String path = '${tempDir.path}/${photo.name}';
          await FirebaseStorage.instance
              .refFromURL(photo.url)
              .writeToFile(File(path));
          files.add(XFile(path));
        }
      } catch (e) {
        widget.logger.e('📤 Error preparing $id for share: $e');
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
      widget.logger.i('✅ Multi-share completed');
    } catch (e) {
      widget.logger.e('📤 Share failed: $e');
      if (!mounted) return;
      _showSnackBar('❌ Share failed: $e', backgroundColor: Colors.red[700]!);
    }
  }

  // ── Multi-delete ─────────────────────────────────────────────────────────────
  Future<void> _handleMultiDelete() async {
    final List<String> idsToDelete = _selection.snapshot();
    widget.logger.i('🗑️ Multi-delete: ${idsToDelete.length} photos');

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever, color: Colors.red),
            const SizedBox(width: 8),
            Text('Delete Photos', style: TextStyle()),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${idsToDelete.length} '
          'selected photo${idsToDelete.length > 1 ? 's' : ''}?\n\n'
          'This action cannot be undone.',
          style: TextStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete',
                style: TextStyle(color: Colors.white)),
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
            .collection('PhotoGallery')
            .doc(id)
            .update({'isDeleted': true});
        deleted++;
        widget.logger.i('🗑️ Deleted $id');
      } catch (e) {
        widget.logger.e('🗑️ Failed to delete $id: $e');
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
  void _viewPhotoFullScreen(PhotoModel photo) {
    widget.logger.i('🖼️ Full-screen: ${photo.id}');
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(photo.name, style: TextStyle()),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _editPhotoDetails(photo),
              ),
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: () => _sharePhoto(photo),
              ),
              IconButton(
                icon: const Icon(Icons.delete),
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
                      style: TextStyle(color: Colors.white54)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Edit photo metadata ──────────────────────────────────────────────────────
  Future<void> _editPhotoDetails(PhotoModel photo) async {
    final TextEditingController titleController =
        TextEditingController(text: photo.name);
    final TextEditingController categoryController =
        TextEditingController(text: photo.category);
    final TextEditingController phaseController =
        TextEditingController(text: photo.phase);

    final bool? updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Edit Photo Details', style: TextStyle()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                  labelText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: categoryController,
              decoration: const InputDecoration(
                  labelText: 'Category', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phaseController,
              decoration: const InputDecoration(
                  labelText: 'Phase', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2E5A)),
            child: Text('Save',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (updated == true && mounted) {
      final Map<String, dynamic> updates = {};
      final String newName = titleController.text.trim();
      final String newCategory = categoryController.text.trim();
      final String newPhase = phaseController.text.trim();

      if (newName.isNotEmpty) updates['name'] = newName;
      if (newCategory.isNotEmpty) updates['category'] = newCategory;
      if (newPhase.isNotEmpty) updates['phase'] = newPhase;

      if (updates.isEmpty) {
        _showSnackBar('No changes made.', backgroundColor: Colors.grey[700]!);
        return;
      }

      try {
        await FirebaseFirestore.instance
            .collection('PhotoGallery')
            .doc(photo.id)
            .update(updates);
        widget.logger.i('✏️ Updated ${photo.id}');
        if (!mounted) return;
        _showSnackBar('✅ Photo details updated.',
            backgroundColor: Colors.green[700]!);
      } catch (e) {
        widget.logger.e('✏️ Update failed: $e');
        if (!mounted) return;
        _showSnackBar('❌ Update failed: $e',
            backgroundColor: Colors.red[700]!);
      }
    }
  }

  // ── Share single photo ───────────────────────────────────────────────────────
  Future<void> _sharePhoto(PhotoModel photo) async {
    widget.logger.i('📤 Share: ${photo.id}');

    if (kIsWeb) {
      _showSnackBar(
        '⚠️ File sharing is not supported in the browser.',
        backgroundColor: Colors.orange[800]!,
      );
      return;
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Preparing photo for sharing…',
              style: TextStyle(color: Colors.white)),
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
      widget.logger.i('✅ Share completed for ${photo.id}');
    } catch (e, st) {
      widget.logger.e('📤 Share error: $e', stackTrace: st);
      messenger.clearSnackBars();
      if (!mounted) return;
      _showSnackBar('❌ Share failed: $e', backgroundColor: Colors.red[700]!);
    }
  }

  // ── Delete single photo ──────────────────────────────────────────────────────
  Future<void> _deletePhoto(PhotoModel photo) async {
    widget.logger.i('🗑️ Delete: ${photo.id}');

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.delete, color: Colors.red),
            const SizedBox(width: 8),
            Text('Delete Photo', style: TextStyle()),
          ],
        ),
        content: Text('Delete this photo? This cannot be undone.',
            style: TextStyle()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('PhotoGallery')
            .doc(photo.id)
            .update({'isDeleted': true});
        widget.logger.i('🗑️ Deleted ${photo.id}');

        if (!mounted) return;
        if (Navigator.canPop(context)) Navigator.pop(context);
        _showSnackBar('🗑️ Photo deleted.',
            backgroundColor: Colors.grey[700]!);
      } catch (e) {
        widget.logger.e('🗑️ Delete failed: $e');
        if (!mounted) return;
        _showSnackBar('❌ Delete failed: $e',
            backgroundColor: Colors.red[700]!);
      }
    }
  }

  // ── Add photo upload flow ────────────────────────────────────────────────────
  Future<void> _startAddPhotoFlow() async {
    widget.logger.i('📸 Upload flow started');

    final String? uploadType = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Upload Photos', style: TextStyle()),
        content: Text('Select upload type', style: TextStyle()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'single'),
            child: Text('Single Photo', style: TextStyle()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'multiple'),
            child: Text('Multiple Photos', style: TextStyle()),
          ),
        ],
      ),
    );

    if (uploadType == null || !mounted) return;

    List<XFile> selectedFiles = [];

    if (uploadType == 'single') {
      final String? source = await showModalBottomSheet<String>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text('Camera', style: TextStyle()),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text('Gallery', style: TextStyle()),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final ImagePicker picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source:
            source == 'camera' ? ImageSource.camera : ImageSource.gallery,
      );
      if (file != null) selectedFiles.add(file);
    } else {
      final ImagePicker picker = ImagePicker();
      selectedFiles = await picker.pickMultiImage();
    }

    if (selectedFiles.isEmpty || !mounted) {
      widget.logger.d('📸 No photos selected');
      return;
    }

    final bool? confirmUpload = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Confirm Upload', style: TextStyle()),
        content: Text(
          'Upload ${selectedFiles.length} '
          'photo${selectedFiles.length > 1 ? 's' : ''}?',
          style: TextStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2E5A)),
            child: Text('Confirm',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmUpload != true || !mounted) return;

    List<String> titles =
        selectedFiles.map((file) => file.name).toList();
    String category = '';
    String phase = '';

    final bool? detailsConfirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Photo Details', style: TextStyle()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selectedFiles.length > 1)
                ...List.generate(
                  selectedFiles.length,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: TextField(
                      onChanged: (value) {
                        titles[index] = value.trim().isEmpty
                            ? selectedFiles[index].name
                            : value.trim();
                      },
                      decoration: InputDecoration(
                        labelText: 'Title for Photo ${index + 1} (optional)',
                        hintText: selectedFiles[index].name,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
              if (selectedFiles.length == 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    onChanged: (value) {
                      titles[0] = value.trim().isEmpty
                          ? selectedFiles[0].name
                          : value.trim();
                    },
                    decoration: InputDecoration(
                      labelText: 'Title (optional)',
                      hintText: selectedFiles[0].name,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              TextField(
                onChanged: (value) => category = value.trim(),
                decoration: const InputDecoration(
                    labelText: 'Category (optional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (value) => phase = value.trim(),
                decoration: const InputDecoration(
                    labelText: 'Phase (optional)',
                    border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2E5A)),
            child: Text('OK',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (detailsConfirmed != true || !mounted) return;

    setState(() => _isLoading = true);

    // Upload progress via ValueNotifier – no markNeedsBuild hacks
    final ValueNotifier<double> uploadProgressNotifier = ValueNotifier(0.0);
    final NavigatorState uploadNavigator = Navigator.of(context);

    uploadNavigator.push(
      DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ValueListenableBuilder<double>(
          valueListenable: uploadProgressNotifier,
          builder: (ctx, value, _) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                const Icon(Icons.cloud_upload, color: Color(0xFF0A2E5A)),
                const SizedBox(width: 8),
                Text('Uploading', style: TextStyle()),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: value,
                  backgroundColor: Colors.grey[200],
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF0A2E5A)),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 12),
                Text(
                  '${(value * 100).toStringAsFixed(0)}%  '
                  '(${(value * selectedFiles.length).floor()}'
                  ' of ${selectedFiles.length} photos)',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    int uploadedCount = 0;
    int uploadFailed = 0;

    try {
      for (int i = 0; i < selectedFiles.length; i++) {
        final XFile file = selectedFiles[i];
        final String title = titles[i];
        late Uint8List bytes;

        try {
          if (!kIsWeb) {
            bytes = await File(file.path).readAsBytes();
          } else {
            bytes = await file.readAsBytes();
          }

          String mimeType = 'image/jpeg';
          final String extension =
              file.name.toLowerCase().split('.').last;
          if (extension == 'png') {
            mimeType = 'image/png';
          } else if (extension == 'webp') {
            mimeType = 'image/webp';
          } else if (extension == 'heic' || extension == 'heif') {
            widget.logger.w(
                '⚠️ HEIC/HEIF image detected: ${file.name}. '
                'May not display in browser.');
          }

          final int timestamp = DateTime.now().millisecondsSinceEpoch + i;
          final String fileName = title.contains('.')
              ? title
              : '${title}_$timestamp.$extension';

          final Reference storageRef = FirebaseStorage.instance
              .ref()
              .child(widget.project.id)
              .child('PhotoGallery')
              .child(fileName);

          final UploadTask uploadTask = storageRef.putData(
            bytes,
            SettableMetadata(
              contentType: mimeType,
              cacheControl: 'public, max-age=31536000',
            ),
          );

          uploadTask.snapshotEvents.listen((TaskSnapshot snap) {
            final double fileProgress =
                snap.bytesTransferred / snap.totalBytes;
            final double overall =
                (i + fileProgress) / selectedFiles.length;
            if ((overall - uploadProgressNotifier.value).abs() >= 0.05 ||
                fileProgress >= 1.0) {
              uploadProgressNotifier.value = overall;
            }
          });

          await uploadTask;
          final String url = await storageRef.getDownloadURL();

          await FirebaseFirestore.instance
              .collection('PhotoGallery')
              .add(PhotoModel(
                id: '',
                name: fileName,
                url: url,
                category: category,
                phase: phase,
                uploadedAt: DateTime.now(),
                projectId: widget.project.id,
              ).toMap());

          uploadedCount++;
          widget.logger.i('✅ Uploaded: $fileName');
        } catch (e) {
          widget.logger.e('❌ Failed to upload ${file.name}: $e');
          uploadFailed++;
        }
      }

      uploadProgressNotifier.dispose();
      uploadNavigator.pop();

      if (!mounted) return;
      _showSnackBar(
        uploadFailed == 0
            ? '✅ $uploadedCount photo${uploadedCount > 1 ? 's' : ''} '
                'uploaded successfully!'
            : '⚠️ $uploadedCount uploaded, $uploadFailed failed.',
        backgroundColor:
            uploadFailed > 0 ? Colors.orange[800]! : Colors.green[700]!,
        duration: const Duration(seconds: 5),
      );
    } catch (e, stackTrace) {
      widget.logger.e('📤 Upload error: $e', stackTrace: stackTrace);
      uploadProgressNotifier.dispose();
      uploadNavigator.pop();
      if (!mounted) return;
      _showSnackBar(
        '❌ Upload error: $e',
        backgroundColor: Colors.red[700]!,
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: _startAddPhotoFlow,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Utility ──────────────────────────────────────────────────────────────────
  String _formatDate(DateTime date) =>
      DateFormat('MMMM dd, yyyy').format(date);
}

class _PhotoTile extends StatefulWidget {
  final PhotoModel photo;
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
    // If the selection object itself changes (shouldn't normally happen but
    // guard against it), re-hook the listener.
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

              // Checkbox (multi-select mode only)
              if (_multiSelectMode)
                Positioned(
                  top: 6,
                  right: 6,
                  child: AnimatedScale(
                    scale: _multiSelectMode ? 1.0 : 0.0,
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
// MultiSliver – wraps a list of slivers into a SliverMainAxisGroup.
// ─────────────────────────────────────────────────────────────────────────────
class _MultiSliverRaw extends StatelessWidget {
  final List<Widget> slivers;
  const _MultiSliverRaw({required this.slivers});

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(slivers: slivers);
  }
}