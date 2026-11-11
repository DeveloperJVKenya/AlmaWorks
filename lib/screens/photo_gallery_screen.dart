import 'dart:typed_data';

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
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:universal_html/html.dart' as html;
import 'package:almaworks/screens/photos_screen.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/errors/friendly_error.dart';
import 'package:almaworks/core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Selection state
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

  void selectAll(List<String> ids) {
    _multiSelectMode = true;
    _selected.addAll(ids);
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
// Download progress helper
// ─────────────────────────────────────────────────────────────────────────────
class _DownloadProgress {
  final int done;
  final int total;
  const _DownloadProgress(this.done, this.total);
  double get fraction => total == 0 ? 0 : done / total;
}

// ─────────────────────────────────────────────────────────────────────────────
// PhotoGalleryScreen
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

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen>
    with SingleTickerProviderStateMixin {
  final _SelectionState _selection = _SelectionState();
  bool _isLoading = false;

  // Tab: 0 = Photos, 1 = Collections
  late final TabController _tabController;

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _searchActive = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() {
      final q = _searchController.text.trim().toLowerCase();
      if (q != _searchQuery) setState(() => _searchQuery = q);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
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
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        action: action,
      ),
    );
  }

  // ── Filter photos by search query ────────────────────────────────────────────
  List<PhotoModel> _filterPhotos(List<PhotoModel> all) {
    if (_searchQuery.isEmpty) return all;
    final q = _searchQuery;
    return all.where((p) =>
        p.name.toLowerCase().contains(q) ||
        p.category.toLowerCase().contains(q) ||
        p.phase.toLowerCase().contains(q) ||
        DateFormat('yyyy').format(p.uploadedAt).contains(q) ||
        DateFormat('MMMM').format(p.uploadedAt).toLowerCase().contains(q) ||
        DateFormat('MMM yyyy').format(p.uploadedAt).toLowerCase().contains(q) ||
        DateFormat('yyyy-MM-dd').format(p.uploadedAt).contains(q)).toList();
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) {
        return BaseLayout(
          title: context.l10n.projectSectionTitle(
              widget.project.name, context.l10n.photoGallery),
          project: widget.project,
          logger: widget.logger,
          selectedMenuItem: 'Photo Gallery',
          onMenuItemSelected: (_) {},
          floatingActionButton:
              !_selection.multiSelectMode ? _buildFABs() : null,
          child: Column(
            children: [
              _buildSearchBar(),
              _buildTabBar(),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
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
                      return _buildErrorState(snapshot);
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final List<PhotoModel> allPhotos = snapshot.data!.docs
                        .map((d) => PhotoModel.fromMap(
                            d.id, d.data() as Map<String, dynamic>))
                        .toList();

                    widget.logger.i(
                        '📸 Loaded ${allPhotos.length} photos for project: ${widget.project.name}');

                    final List<PhotoModel> filtered = _filterPhotos(allPhotos);

                    return TabBarView(
                      controller: _tabController,
                      children: [
                        _buildPhotosTab(filtered, allPhotos),
                        _buildCollectionsTab(allPhotos),
                      ],
                    );
                  },
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

  // ── FABs ─────────────────────────────────────────────────────────────────────
  Widget _buildFABs() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
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
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.brandInk,
          elevation: 4,
          icon: const Icon(Icons.photo_album),
          label: Text(context.l10n.viewPhotos),
        ),
        const SizedBox(height: 12),
        FloatingActionButton(
          heroTag: 'fab_add_photo',
          onPressed: _isLoading ? null : _startAddPhotoFlow,
          backgroundColor: const Color(0xFF0A2E5A),
          foregroundColor: Colors.white,
          tooltip: context.l10n.uploadPhoto,
          child: const Icon(Icons.add_photo_alternate),
        ),
      ],
    );
  }

  // ── Search bar ───────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: _searchActive ? 56 : 0,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: _searchActive
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: context.l10n.searchPhotosHint,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: _searchController.clear,
                        )
                      : null,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24)),
                  filled: true,
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  // ── Tab bar with search toggle ───────────────────────────────────────────────
  Widget _buildTabBar() {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      elevation: 1,
      child: Row(
        children: [
          Expanded(
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.brandInk,
              unselectedLabelColor: Colors.grey[600],
              indicatorColor: AppColors.brandInk,
              indicatorWeight: 3,
              tabs: [
                Tab(text: context.l10n.galleryTabPhotos),
                Tab(text: context.l10n.galleryTabCollections),
              ],
            ),
          ),
          if (!_selection.multiSelectMode)
            IconButton(
              icon: Icon(_searchActive ? Icons.search_off : Icons.search),
              tooltip: context.l10n.search,
              onPressed: () {
                setState(() {
                  _searchActive = !_searchActive;
                  if (!_searchActive) _searchController.clear();
                });
              },
            ),
        ],
      ),
    );
  }

  // ── Photos tab ───────────────────────────────────────────────────────────────
  Widget _buildPhotosTab(
      List<PhotoModel> filtered, List<PhotoModel> allPhotos) {
    if (filtered.isEmpty && _searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(context.l10n.noResultsForSearch,
                style:
                    TextStyle(color: AppColors.inkMuted, fontSize: 15)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _searchController.clear,
              child: Text(context.l10n.clear),
            ),
          ],
        ),
      );
    }

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined,
                size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(context.l10n.noPhotosAddSome,
                style:
                    TextStyle(color: AppColors.inkMuted, fontSize: 16)),
          ],
        ),
      );
    }

    // Date-grouped grid
    final Map<String, List<PhotoModel>> dateGroups = {};
    for (final PhotoModel photo in filtered) {
      final String dateKey =
          DateFormat('yyyy-MM-dd').format(photo.uploadedAt);
      dateGroups.update(dateKey, (list) => list..add(photo),
          ifAbsent: () => [photo]);
    }
    final List<String> sortedDates = dateGroups.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return CustomScrollView(
      slivers: [
        if (_selection.multiSelectMode)
          SliverToBoxAdapter(
              child: _buildSelectionHeader(allPhotos: filtered)),
        for (final String dateKey in sortedDates) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
              child: Text(
                _formatDate(DateTime.parse(dateKey)).toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  color: Colors.grey[600],
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          _buildDateGroupSliver(dateGroups[dateKey]!),
        ],
      ],
    );
  }

  // ── Collections tab ──────────────────────────────────────────────────────────
  Widget _buildCollectionsTab(List<PhotoModel> allPhotos) {
    final Map<String, List<PhotoModel>> collections = {};
    for (final p in allPhotos) {
      final String key =
          p.category.isEmpty ? context.l10n.uncategorized : p.category;
      collections.update(key, (l) => l..add(p), ifAbsent: () => [p]);
    }

    if (collections.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.collections_outlined,
                size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(context.l10n.noCollectionsYet,
                style:
                    TextStyle(color: AppColors.inkMuted, fontSize: 16)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(context.l10n.collectionsHint,
                  style:
                      TextStyle(color: Colors.grey[500], fontSize: 13),
                  textAlign: TextAlign.center),
            ),
          ],
        ),
      );
    }

    final List<MapEntry<String, List<PhotoModel>>> entries =
        collections.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    return LayoutBuilder(builder: (context, constraints) {
      final int cols = constraints.maxWidth < 600
          ? 2
          : constraints.maxWidth < 1200
              ? 3
              : 4;
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          childAspectRatio: 1,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: entries.length,
        itemBuilder: (context, i) =>
            _buildCollectionCard(entries[i].key, entries[i].value),
      );
    });
  }

  Widget _buildCollectionCard(
      String category, List<PhotoModel> photos) {
    return GestureDetector(
      onTap: () => _openCollection(category, photos),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: photos.first.url,
              fit: BoxFit.cover,
              cacheKey: 'col_${photos.first.id}',
              placeholder: (_, __) =>
                  Container(color: AppColors.surfaceMuted),
              errorWidget: (_, __, ___) =>
                  Container(color: AppColors.surfaceMuted,
                      child: Icon(Icons.broken_image, color: Colors.grey[400])),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65)
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    category,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    context.l10n.photosCount(photos.length),
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCollection(String category, List<PhotoModel> photos) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _CollectionDetailPage(
          category: category,
          photos: photos,
          onViewFullScreen: _viewPhotoFullScreen,
        ),
      ),
    );
  }

  // ── Selection header ─────────────────────────────────────────────────────────
  Widget _buildSelectionHeader({List<PhotoModel>? allPhotos}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF0A2E5A).withValues(alpha: 0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            context.l10n.selectedCount(_selection.count),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.brandInk,
            ),
          ),
          Row(
            children: [
              if (allPhotos != null && allPhotos.isNotEmpty)
                TextButton(
                  onPressed: () {
                    if (_selection.count == allPhotos.length) {
                      _selection.exitMultiSelect();
                    } else {
                      _selection
                          .selectAll(allPhotos.map((p) => p.id).toList());
                    }
                  },
                  child: Text(
                    _selection.count == (allPhotos.length)
                        ? context.l10n.deselectAll
                        : context.l10n.selectAll,
                    style: TextStyle(color: AppColors.brandInk),
                  ),
                ),
              TextButton.icon(
                onPressed: () {
                  widget.logger.i('🔄 Exiting multi-select mode');
                  _selection.exitMultiSelect();
                },
                icon: Icon(Icons.close, color: AppColors.brandInk),
                label: Text(
                  context.l10n.cancel,
                  style: TextStyle(color: AppColors.brandInk),
                ),
              ),
            ],
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: LayoutBuilder(builder: (context, constraints) {
            final bool narrow = constraints.maxWidth < 420;
            return Row(
              children: [
                _buildActionButton(
                  icon: Icons.drive_file_move,
                  label: narrow ? '' : context.l10n.moveToPhotos,
                  onPressed:
                      hasSelection ? _moveToPhotosCollection : null,
                ),
                _buildActionButton(
                  icon: Icons.share,
                  label: narrow ? '' : context.l10n.share,
                  onPressed: hasSelection ? _handleMultiShare : null,
                ),
                _buildActionButton(
                  icon: Icons.download,
                  label: narrow ? '' : context.l10n.download,
                  onPressed:
                      hasSelection ? _handleMultiDownload : null,
                ),
                _buildActionButton(
                  icon: Icons.delete,
                  label: narrow ? '' : context.l10n.delete,
                  onPressed: hasSelection ? _handleMultiDelete : null,
                ),
              ],
            );
          }),
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
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: label.isEmpty
            ? IconButton(
                onPressed: onPressed,
                icon: Icon(icon, size: 22),
                color: isEnabled ? Colors.white : Colors.white38,
              )
            : ElevatedButton.icon(
                onPressed: onPressed,
                icon: Icon(icon, size: 18),
                label: Text(label,
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isEnabled
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.3),
                  foregroundColor:
                      isEnabled ? const Color(0xFF0A2E5A) : Colors.grey,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
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
        context.l10n.copyrightFooter,
        style: TextStyle(
          color: Colors.white,
          fontSize: isMobile ? 12 : 14,
          fontWeight: FontWeight.w400,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ── Error state ──────────────────────────────────────────────────────────────
  Widget _buildErrorState(AsyncSnapshot<QuerySnapshot> snapshot) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 48, color: Colors.red[300]),
          const SizedBox(height: 12),
          Text(context.l10n.couldNotLoadPhotos,
              style: TextStyle(
                  color: Colors.red[600], fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(friendlyError(snapshot.error!),
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
            label: Text(context.l10n.retry),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0A2E5A),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
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

  // ── Context menu ─────────────────────────────────────────────────────────────
  void _showContextMenu(Offset position, PhotoModel photo) {
    widget.logger
        .i('🖱️ Context menu at $position for photo: ${photo.id}');

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
              color: AppColors.brandInk,
            ),
            title: Text(
              _selection.multiSelectMode
                  ? context.l10n.deactivateSelection
                  : context.l10n.activateSelection,
              style: const TextStyle(fontSize: 14),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (!_selection.multiSelectMode) ...[
          const PopupMenuDivider(),
          PopupMenuItem<void>(
            onTap: () => WidgetsBinding.instance.addPostFrameCallback(
                (_) => _viewPhotoFullScreen(photo)),
            child: ListTile(
              leading: Icon(Icons.visibility, color: AppColors.brandInk),
              title: Text(context.l10n.view,
                  style: const TextStyle(fontSize: 14)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem<void>(
            onTap: () => WidgetsBinding.instance.addPostFrameCallback(
                (_) => _editPhotoDetails(photo)),
            child: ListTile(
              leading: Icon(Icons.edit, color: AppColors.brandInk),
              title: Text(context.l10n.edit,
                  style: const TextStyle(fontSize: 14)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem<void>(
            onTap: () => WidgetsBinding.instance.addPostFrameCallback(
                (_) => _sharePhoto(photo)),
            child: ListTile(
              leading: Icon(Icons.share, color: AppColors.brandInk),
              title: Text(context.l10n.share,
                  style: const TextStyle(fontSize: 14)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem<void>(
            onTap: () => WidgetsBinding.instance.addPostFrameCallback(
                (_) => _downloadPhoto(photo)),
            child: ListTile(
              leading: Icon(Icons.download, color: AppColors.brandInk),
              title: Text(context.l10n.download,
                  style: const TextStyle(fontSize: 14)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem<void>(
            onTap: () => WidgetsBinding.instance.addPostFrameCallback(
                (_) => _deletePhoto(photo)),
            child: ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(context.l10n.delete,
                  style:
                      const TextStyle(fontSize: 14, color: Colors.red)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ],
    );
  }

  // ── Full-screen viewer ───────────────────────────────────────────────────────
  void _viewPhotoFullScreen(PhotoModel photo) {
    widget.logger.i('🖼️ Full-screen: ${photo.id}');
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _FullScreenViewerPage(
          photo: photo,
          onEdit: (p) => _editPhotoDetails(p),
          onShare: (p) => _sharePhoto(p),
          onDownload: (p) => _downloadPhoto(p),
          onDelete: (p) => _deletePhoto(p),
        ),
      ),
    );
  }

  // ── Download single photo ────────────────────────────────────────────────────
  Future<void> _downloadPhoto(PhotoModel photo) async {
    if (kIsWeb) {
      await _downloadPhotoWeb(photo);
    } else {
      await _downloadPhotoMobile(photo);
    }
  }

  Future<void> _downloadPhotoWeb(PhotoModel photo) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text(context.l10n.downloadingPhoto,
          style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFF0A2E5A),
      duration: const Duration(seconds: 60),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
    try {
      final Response<List<int>> response = await Dio().get<List<int>>(
        photo.url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.data == null) throw Exception('empty response');
      final blob =
          html.Blob([Uint8List.fromList(response.data!)]);
      final blobUrl = html.Url.createObjectUrlFromBlob(blob);
      (html.AnchorElement(href: blobUrl)
            ..setAttribute('download', photo.name))
          .click();
      html.Url.revokeObjectUrl(blobUrl);
      messenger.clearSnackBars();
      if (!mounted) return;
      _showSnackBar('✅ ${context.l10n.download}',
          backgroundColor: Colors.green[700]!);
    } catch (e) {
      widget.logger.e('⬇️ Web download error: $e');
      messenger.clearSnackBars();
      if (!mounted) return;
      _showSnackBar('❌ ${context.l10n.couldNotDownloadPhoto}',
          backgroundColor: Colors.red[700]!);
    }
  }

  Future<void> _downloadPhotoMobile(PhotoModel photo) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text(context.l10n.downloadingPhoto,
          style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFF0A2E5A),
      duration: const Duration(seconds: 60),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
    try {
      final Uint8List? bytes = await FirebaseStorage.instance
          .refFromURL(photo.url)
          .getData(10 * 1024 * 1024);
      if (bytes == null) throw Exception('no data returned');
      await Gal.putImageBytes(bytes, name: photo.name);
      messenger.clearSnackBars();
      if (!mounted) return;
      _showSnackBar('✅ ${context.l10n.photoSavedToGallery}',
          backgroundColor: Colors.green[700]!);
    } catch (e, st) {
      widget.logger.e('⬇️ Mobile download error: $e', stackTrace: st);
      messenger.clearSnackBars();
      if (!mounted) return;
      _showSnackBar(
          '❌ ${friendlyError(e, action: context.l10n.couldNotDownloadPhoto)}',
          backgroundColor: Colors.red[700]!);
    }
  }

  // ── Multi-download ───────────────────────────────────────────────────────────
  Future<void> _handleMultiDownload() async {
    final List<String> ids = _selection.snapshot();
    widget.logger.i('⬇️ Multi-download: ${ids.length} photos');
    _selection.exitMultiSelect();

    final ValueNotifier<_DownloadProgress> progressNotifier =
        ValueNotifier(_DownloadProgress(0, ids.length));
    final NavigatorState nav = Navigator.of(context);

    nav.push(DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ValueListenableBuilder<_DownloadProgress>(
        valueListenable: progressNotifier,
        builder: (ctx, progress, _) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(children: [
            Icon(Icons.download, color: AppColors.brandInk),
            const SizedBox(width: 8),
            Text(context.l10n.download, style: const TextStyle()),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: progress.fraction,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF0A2E5A)),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.downloadingPhotos(progress.done, progress.total),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    ));

    int downloaded = 0;
    int failed = 0;

    for (int i = 0; i < ids.length; i++) {
      try {
        final DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('PhotoGallery')
            .doc(ids[i])
            .get();
        if (doc.exists) {
          final PhotoModel photo =
              PhotoModel.fromMap(ids[i], doc.data() as Map<String, dynamic>);
          if (kIsWeb) {
            await _downloadPhotoWebQuiet(photo);
          } else {
            final Uint8List? bytes = await FirebaseStorage.instance
                .refFromURL(photo.url)
                .getData(10 * 1024 * 1024);
            if (bytes != null) await Gal.putImageBytes(bytes, name: photo.name);
          }
          downloaded++;
        } else {
          failed++;
        }
      } catch (e) {
        widget.logger.e('⬇️ Bulk download failed for ${ids[i]}: $e');
        failed++;
      }
      progressNotifier.value = _DownloadProgress(i + 1, ids.length);
    }

    progressNotifier.dispose();
    nav.pop();

    if (!mounted) return;
    _showSnackBar(
      failed == 0
          ? '✅ ${context.l10n.photosDownloaded(downloaded)}'
          : '⚠️ ${context.l10n.photosDownloadSomeFailed(downloaded, failed)}',
      backgroundColor:
          failed > 0 ? Colors.orange[800]! : Colors.green[700]!,
    );
  }

  Future<void> _downloadPhotoWebQuiet(PhotoModel photo) async {
    final Response<List<int>> response = await Dio().get<List<int>>(
      photo.url,
      options: Options(responseType: ResponseType.bytes),
    );
    if (response.data == null) throw Exception('empty response');
    final blob = html.Blob([Uint8List.fromList(response.data!)]);
    final blobUrl = html.Url.createObjectUrlFromBlob(blob);
    (html.AnchorElement(href: blobUrl)
          ..setAttribute('download', photo.name))
        .click();
    html.Url.revokeObjectUrl(blobUrl);
  }

  // ── Share single photo (web: copy URL) ──────────────────────────────────────
  Future<void> _sharePhoto(PhotoModel photo) async {
    widget.logger.i('📤 Share: ${photo.id}');

    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: photo.url));
      if (!mounted) return;
      _showSnackBar('🔗 ${context.l10n.shareWebCopied}',
          backgroundColor: Colors.green[700]!);
      return;
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(
        content: Text(context.l10n.preparingPhotoToShare,
            style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0A2E5A),
        duration: const Duration(seconds: 30),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));

      final Directory tempDir = await getTemporaryDirectory();
      final String path = '${tempDir.path}/${photo.name}';
      await FirebaseStorage.instance
          .refFromURL(photo.url)
          .writeToFile(File(path));

      messenger.clearSnackBars();
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
      widget.logger
          .i('✅ Share completed for ${photo.id}');
    } catch (e, st) {
      widget.logger.e('📤 Share error: $e', stackTrace: st);
      messenger.clearSnackBars();
      if (!mounted) return;
      _showSnackBar(
          '❌ ${friendlyError(e, action: context.l10n.couldNotShare)}',
          backgroundColor: Colors.red[700]!);
    }
  }

  // ── Multi-share ──────────────────────────────────────────────────────────────
  Future<void> _handleMultiShare() async {
    final List<String> idsToShare = _selection.snapshot();
    widget.logger.i('📤 Multi-share: ${idsToShare.length} photos');
    _selection.exitMultiSelect();

    if (kIsWeb) {
      final List<String> urls = [];
      for (final String id in idsToShare) {
        try {
          final DocumentSnapshot doc = await FirebaseFirestore.instance
              .collection('PhotoGallery')
              .doc(id)
              .get();
          if (doc.exists) {
            final PhotoModel photo =
                PhotoModel.fromMap(id, doc.data() as Map<String, dynamic>);
            urls.add(photo.url);
          }
        } catch (_) {}
      }
      await Clipboard.setData(ClipboardData(text: urls.join('\n')));
      if (!mounted) return;
      _showSnackBar('🔗 ${context.l10n.shareWebMultiCopied}',
          backgroundColor: Colors.green[700]!);
      return;
    }

    _showSnackBar(
      context.l10n.preparingPhotosToShare(idsToShare.length),
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
      _showSnackBar('❌ ${context.l10n.couldNotPreparePhotos}',
          backgroundColor: Colors.red[700]!);
      return;
    }

    try {
      await SharePlus.instance.share(ShareParams(files: files));
      widget.logger.i('✅ Multi-share completed');
    } catch (e) {
      widget.logger.e('📤 Share failed: $e');
      if (!mounted) return;
      _showSnackBar(
          '❌ ${friendlyError(e, action: context.l10n.couldNotShare)}',
          backgroundColor: Colors.red[700]!);
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
            Text(context.l10n.deletePhotosTitle,
                style: const TextStyle()),
          ],
        ),
        content: Text(
          context.l10n.deletePhotosConfirm(idsToDelete.length),
          style: const TextStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel,
                style: const TextStyle()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red),
            child: Text(context.l10n.delete,
                style: const TextStyle(color: Colors.white)),
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
          ? '🗑️ ${context.l10n.photosDeleted(deleted)}'
          : '🗑️ ${context.l10n.photosDeletedSomeFailed(deleted, failed)}',
      backgroundColor:
          failed > 0 ? Colors.orange[800]! : Colors.grey[700]!,
    );
  }

  // ── Move selected to Photos collection ───────────────────────────────────────
  Future<void> _moveToPhotosCollection() async {
    final List<String> idsToMove = _selection.snapshot();
    widget.logger.i('📦 Moving ${idsToMove.length} photos to Photos');
    if (idsToMove.isEmpty) return;

    _selection.exitMultiSelect();
    if (mounted) setState(() => _isLoading = true);

    int successCount = 0;
    int alreadyExistsCount = 0;
    int failCount = 0;

    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final ValueNotifier<double> progressNotifier = ValueNotifier(0);
    navigator.push(DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ValueListenableBuilder<double>(
        valueListenable: progressNotifier,
        builder: (ctx, value, _) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(children: [
            Icon(Icons.drive_file_move, color: AppColors.brandInk),
            const SizedBox(width: 8),
            Text(context.l10n.movingPhotos, style: const TextStyle()),
          ]),
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
                context.l10n.photosProcessed(
                    (value * idsToMove.length).round(),
                    idsToMove.length),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    ));

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
            widget.logger
                .w('⚠️ ${photo.name} already in Photos collection');
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
      progressNotifier.value = (i + 1) / idsToMove.length;
    }

    progressNotifier.dispose();
    navigator.pop();

    if (!mounted) return;
    setState(() => _isLoading = false);

    final StringBuffer msg = StringBuffer();
    if (successCount > 0) {
      msg.write('✅ ${l10nNow.photosMoved(successCount)}');
    }
    if (alreadyExistsCount > 0) {
      if (msg.isNotEmpty) msg.write('  ');
      msg.write('⚠️ ${l10nNow.photosAlreadyExisted(alreadyExistsCount)}');
    }
    if (failCount > 0) {
      if (msg.isNotEmpty) msg.write('  ');
      msg.write('❌ ${l10nNow.photosFailedCount(failCount)}');
    }
    if (msg.isEmpty) msg.write(l10nNow.noPhotosMoved);

    final Color bgColor = failCount > 0
        ? Colors.orange[800]!
        : successCount > 0
            ? Colors.green[700]!
            : Colors.grey[700]!;

    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content:
          Text(msg.toString(), style: const TextStyle(color: Colors.white)),
      backgroundColor: bgColor,
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      action: (failCount > 0 || alreadyExistsCount > 0)
          ? SnackBarAction(
              label: l10nNow.details,
              textColor: Colors.white,
              onPressed: () {
                if (!mounted) return;
                showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(context.l10n.moveResults,
                        style: const TextStyle()),
                    content: Text(
                      context.l10n.moveResultsBody(
                          successCount, alreadyExistsCount, failCount),
                      style: const TextStyle(),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(context.l10n.ok,
                            style: const TextStyle()),
                      ),
                    ],
                  ),
                );
              },
            )
          : null,
    ));
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
        title: Text(context.l10n.editPhotoDetails,
            style: const TextStyle()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                  labelText: context.l10n.titleLabel,
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: categoryController,
              decoration: InputDecoration(
                  labelText: context.l10n.category,
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phaseController,
              decoration: InputDecoration(
                  labelText: context.l10n.phase,
                  border: const OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel, style: const TextStyle()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2E5A)),
            child: Text(context.l10n.save,
                style: const TextStyle(color: Colors.white)),
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
        _showSnackBar(context.l10n.noChangesMade,
            backgroundColor: Colors.grey[700]!);
        return;
      }

      try {
        await FirebaseFirestore.instance
            .collection('PhotoGallery')
            .doc(photo.id)
            .update(updates);
        widget.logger.i('✏️ Updated ${photo.id}');
        if (!mounted) return;
        _showSnackBar('✅ ${context.l10n.photoDetailsUpdated}',
            backgroundColor: Colors.green[700]!);
      } catch (e) {
        widget.logger.e('✏️ Update failed: $e');
        if (!mounted) return;
        _showSnackBar(
            '❌ ${friendlyError(e, action: context.l10n.couldNotUpdate)}',
            backgroundColor: Colors.red[700]!);
      }
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
            Text(context.l10n.deletePhotoTitle,
                style: const TextStyle()),
          ],
        ),
        content: Text(context.l10n.deletePhotoConfirm,
            style: const TextStyle()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel, style: const TextStyle()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(context.l10n.delete,
                style: const TextStyle(color: Colors.white)),
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
        _showSnackBar('🗑️ ${context.l10n.photoDeleted}',
            backgroundColor: Colors.grey[700]!);
      } catch (e) {
        widget.logger.e('🗑️ Delete failed: $e');
        if (!mounted) return;
        _showSnackBar(
            '❌ ${friendlyError(e, action: context.l10n.couldNotDelete)}',
            backgroundColor: Colors.red[700]!);
      }
    }
  }

  // ── Upload flow ──────────────────────────────────────────────────────────────
  Future<void> _startAddPhotoFlow() async {
    widget.logger.i('📸 Upload flow started');

    final String? uploadType = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(context.l10n.uploadPhotos,
            style: const TextStyle()),
        content:
            Text(context.l10n.selectUploadType, style: const TextStyle()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'single'),
            child:
                Text(context.l10n.singlePhoto, style: const TextStyle()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'multiple'),
            child: Text(context.l10n.multiplePhotos,
                style: const TextStyle()),
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
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(16))),
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title:
                    Text(context.l10n.camera, style: const TextStyle()),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(context.l10n.gallery,
                    style: const TextStyle()),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final ImagePicker picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source == 'camera'
            ? ImageSource.camera
            : ImageSource.gallery,
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
        title: Text(context.l10n.confirmUpload,
            style: const TextStyle()),
        content: Text(
          context.l10n.uploadPhotosConfirm(selectedFiles.length),
          style: const TextStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                Text(context.l10n.cancel, style: const TextStyle()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2E5A)),
            child: Text(context.l10n.confirm,
                style: const TextStyle(color: Colors.white)),
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
        title: Text(context.l10n.photoDetails,
            style: const TextStyle()),
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
                        labelText:
                            context.l10n.titleForPhotoN(index + 1),
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
                      labelText: context.l10n.titleOptional,
                      hintText: selectedFiles[0].name,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              TextField(
                onChanged: (value) => category = value.trim(),
                decoration: InputDecoration(
                    labelText: context.l10n.categoryOptionalField,
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (value) => phase = value.trim(),
                decoration: InputDecoration(
                    labelText: context.l10n.phaseOptional,
                    border: const OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text(context.l10n.cancel, style: const TextStyle()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2E5A)),
            child: Text(context.l10n.ok,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (detailsConfirmed != true || !mounted) return;

    setState(() => _isLoading = true);

    final ValueNotifier<double> uploadProgressNotifier =
        ValueNotifier(0.0);
    final NavigatorState uploadNavigator = Navigator.of(context);

    uploadNavigator.push(DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ValueListenableBuilder<double>(
        valueListenable: uploadProgressNotifier,
        builder: (ctx, value, _) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          title: Row(children: [
            Icon(Icons.cloud_upload, color: AppColors.brandInk),
            const SizedBox(width: 8),
            Text(context.l10n.uploadingTitle, style: const TextStyle()),
          ]),
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
                context.l10n.uploadProgressPhotos(
                    (value * 100).toStringAsFixed(0),
                    (value * selectedFiles.length).floor(),
                    selectedFiles.length),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    ));

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
                '⚠️ HEIC/HEIF image detected: ${file.name}.');
          }

          final int timestamp =
              DateTime.now().millisecondsSinceEpoch + i;
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
            if ((overall - uploadProgressNotifier.value).abs() >=
                    0.05 ||
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
            ? '✅ ${context.l10n.photosUploaded(uploadedCount)}'
            : '⚠️ ${context.l10n.photosUploadedSomeFailed(uploadedCount, uploadFailed)}',
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
        '❌ ${friendlyError(e, action: context.l10n.couldNotUploadPhotos)}',
        backgroundColor: Colors.red[700]!,
        action: SnackBarAction(
          label: context.l10n.retry,
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

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen viewer with explicit zoom controls
// ─────────────────────────────────────────────────────────────────────────────
class _FullScreenViewerPage extends StatefulWidget {
  final PhotoModel photo;
  final void Function(PhotoModel) onEdit;
  final void Function(PhotoModel) onShare;
  final void Function(PhotoModel) onDownload;
  final void Function(PhotoModel) onDelete;

  const _FullScreenViewerPage({
    required this.photo,
    required this.onEdit,
    required this.onShare,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  State<_FullScreenViewerPage> createState() =>
      _FullScreenViewerPageState();
}

class _FullScreenViewerPageState extends State<_FullScreenViewerPage> {
  final PhotoViewController _ctrl = PhotoViewController();
  final PhotoViewScaleStateController _scaleCtrl =
      PhotoViewScaleStateController();

  void _zoomIn() {
    final double scale = _ctrl.scale ?? 1.0;
    _ctrl.scale = (scale * 1.5).clamp(0.25, 8.0);
  }

  void _zoomOut() {
    final double scale = _ctrl.scale ?? 1.0;
    _ctrl.scale = (scale / 1.5).clamp(0.25, 8.0);
  }

  void _resetZoom() =>
      _scaleCtrl.scaleState = PhotoViewScaleState.initial;

  @override
  void dispose() {
    _ctrl.dispose();
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.photo.name, style: const TextStyle()),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: context.l10n.edit,
            onPressed: () => widget.onEdit(widget.photo),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: context.l10n.share,
            onPressed: () => widget.onShare(widget.photo),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: context.l10n.download,
            onPressed: () => widget.onDownload(widget.photo),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: context.l10n.delete,
            onPressed: () => widget.onDelete(widget.photo),
          ),
        ],
      ),
      body: Stack(
        children: [
          PhotoView(
            imageProvider:
                CachedNetworkImageProvider(widget.photo.url),
            controller: _ctrl,
            scaleStateController: _scaleCtrl,
            minScale: PhotoViewComputedScale.contained * 0.5,
            maxScale: PhotoViewComputedScale.covered * 4.0,
            loadingBuilder: (context, event) => const Center(
              child:
                  CircularProgressIndicator(color: Colors.white),
            ),
            errorBuilder: (context, error, trace) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.broken_image,
                      color: Colors.white54, size: 64),
                  const SizedBox(height: 12),
                  Text(context.l10n.cannotDisplayImage,
                      style:
                          const TextStyle(color: Colors.white54)),
                ],
              ),
            ),
          ),
          // Zoom control overlay
          Positioned(
            bottom: 24,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(28),
              ),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white),
                    tooltip: context.l10n.zoomIn,
                    onPressed: _zoomIn,
                  ),
                  const Divider(
                      height: 1, color: Colors.white24, indent: 10, endIndent: 10),
                  IconButton(
                    icon: const Icon(Icons.remove, color: Colors.white),
                    tooltip: context.l10n.zoomOut,
                    onPressed: _zoomOut,
                  ),
                  const Divider(
                      height: 1, color: Colors.white24, indent: 10, endIndent: 10),
                  IconButton(
                    icon: const Icon(Icons.zoom_out_map,
                        color: Colors.white),
                    tooltip: context.l10n.resetZoom,
                    onPressed: _resetZoom,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Collection detail page
// ─────────────────────────────────────────────────────────────────────────────
class _CollectionDetailPage extends StatelessWidget {
  final String category;
  final List<PhotoModel> photos;
  final void Function(PhotoModel) onViewFullScreen;

  const _CollectionDetailPage({
    required this.category,
    required this.photos,
    required this.onViewFullScreen,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(category),
        backgroundColor: const Color(0xFF0A2E5A),
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final int cols = constraints.maxWidth < 600
            ? 2
            : constraints.maxWidth < 1200
                ? 4
                : 6;
        final double spacing = constraints.maxWidth < 600 ? 8.0 : 16.0;
        return GridView.builder(
          padding: EdgeInsets.all(spacing),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 1,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
          ),
          itemCount: photos.length,
          itemBuilder: (context, i) => GestureDetector(
            onTap: () => onViewFullScreen(photos[i]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: photos[i].url,
                fit: BoxFit.cover,
                cacheKey: photos[i].id,
                memCacheWidth: 400,
                memCacheHeight: 400,
                placeholder: (_, __) =>
                    Container(color: AppColors.surfaceMuted),
                errorWidget: (_, __, ___) => Container(
                  color: AppColors.surfaceMuted,
                  child: Icon(Icons.broken_image,
                      color: Colors.grey[400]),
                ),
                fadeInDuration: const Duration(milliseconds: 200),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PhotoTile – StatefulWidget with proper listener lifecycle
// ─────────────────────────────────────────────────────────────────────────────
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
    final bool nowSelected =
        widget.selection.isSelected(widget.photo.id);
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
            borderRadius: BorderRadius.circular(8),
            border: _isSelected
                ? Border.all(
                    color: const Color(0xFF0A2E5A), width: 3)
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
                _isSelected ? 5 : 8),
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
                    color: AppColors.surfaceMuted,
                    child: const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF0A2E5A),
                          strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, url, error) {
                    widget.onImageError(error);
                    return _buildErrorWidget();
                  },
                  fadeInDuration:
                      const Duration(milliseconds: 200),
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
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),

                // Checkbox (multi-select)
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
                              : AppColors.surface,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  Colors.black.withValues(alpha: 0.25),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: Checkbox(
                            value: _isSelected,
                            onChanged: (_) => widget.selection
                                .toggle(widget.photo.id),
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
                      color: const Color(0xFF0A2E5A)
                          .withValues(alpha: 0.18),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      color: AppColors.surfaceMuted,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image,
              color: Colors.grey[500], size: 28),
          const SizedBox(height: 4),
          Text(
            l10nNow.unavailable,
            style: TextStyle(
                color: AppColors.inkMuted, fontSize: 10),
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
