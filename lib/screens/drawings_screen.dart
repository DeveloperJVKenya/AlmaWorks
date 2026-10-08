import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:almaworks/models/drawing_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/services/drawing_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:logger/logger.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:almaworks/helpers/download_helper.dart';
import 'package:almaworks/helpers/download_feedback.dart';
import 'package:intl/intl.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/errors/friendly_error.dart';
import 'package:almaworks/core/theme/app_colors.dart';

class DrawingsScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;

  const DrawingsScreen({
    super.key,
    required this.project,
    required this.logger,
  });

  @override
  State<DrawingsScreen> createState() => _DrawingsScreenState();
}

class _DrawingsScreenState extends State<DrawingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DrawingService _drawingService = DrawingService();
  bool _isUploading = false;
  String? _userRole = 'Client'; // default to most restrictive until loaded

  // Client and Technician are view-only here — no upload, download, or
  // delete; every other role keeps full manage access.
  bool get _canManageDrawings => _userRole != 'Client' && _userRole != 'Technician';
  bool get _isTechnician => _userRole == 'Technician';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this); // Changed from 2 to 3
    widget.logger.i('🏗️ DrawingsScreen: Initialized for project: ${widget.project.name}');
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        widget.logger.e('❌ DrawingsScreen: No authenticated user found');
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
        widget.logger.i('✅ DrawingsScreen: User role fetched: $role');
      }
    } catch (e) {
      widget.logger.e('❌ DrawingsScreen: Error fetching user role: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BaseLayout(
      title: context.l10n.projectSectionTitle(widget.project.name, context.l10n.drawings),
      project: widget.project,
      logger: widget.logger,
      selectedMenuItem: 'Drawings',
      onMenuItemSelected: (_) {}, // Empty callback as navigation is handled by BaseLayout
          floatingActionButton: !_canManageDrawings ? null : FloatingActionButton(
            onPressed: _isUploading ? null : () {
              if (_tabController.index == 0) {
                _uploadContractDrawing();
              } else if (_tabController.index == 1) {
                _uploadDrawing();
              } else if (_tabController.index == 2) {
                _uploadAsBuiltDrawing();
              }
            },
            backgroundColor: const Color(0xFF0A2E5A),
            foregroundColor: Colors.white,
            child: _isUploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.upload_file),
          ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withValues(alpha: 0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TabBar(
                          // swipeable on phones so longer labels (e.g. Italian) never get cut off
                          isScrollable: MediaQuery.sizeOf(context).width < 600,
                          tabAlignment: MediaQuery.sizeOf(context).width < 600 ? TabAlignment.start : TabAlignment.fill,
                          controller: _tabController,
                          labelColor: AppColors.brandInk,
                          unselectedLabelColor: Colors.grey[600],
                          indicatorColor: AppColors.brandInk,
                          indicatorWeight: 3,
                          labelStyle: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                          unselectedLabelStyle: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                          tabs: [
                            Tab(text: context.l10n.tabContractDrawing),
                            Tab(text: context.l10n.tabRevisions),
                            Tab(text: context.l10n.tabAsBuilt),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: constraints.maxHeight - 48 - 48, // Subtract TabBar and footer height
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildContractDrawingTab(),
                            _buildRevisionsTab(),
                            _buildAsBuiltTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
                  _buildFooter(context),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // New method: Build Contract Drawing tab
  Widget _buildContractDrawingTab() {
    return StreamBuilder<List<DrawingModel>>(
      stream: _drawingService.getContractDrawings(widget.project.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          widget.logger.e('❌ DrawingsScreen: Error loading contract drawings', error: snapshot.error);
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
                const SizedBox(height: 16),
                Text(
                  context.l10n.couldNotLoadContractDrawings,
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.red[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final drawings = snapshot.data!;
        drawings.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));

        if (drawings.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.description, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  context.l10n.noContractDrawings,
                  style: TextStyle(
                    fontSize: 18,
                    color: AppColors.inkMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.tapUploadContractDrawings,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: drawings.length,
          itemBuilder: (context, index) {
            final drawing = drawings[index];
            return _buildContractDrawingCard(drawing);
          },
        );
      },
    );
  }

  // Updated method: Build Contract Drawing card (Fixed deprecated withOpacity)
  Widget _buildContractDrawingCard(DrawingModel drawing) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0A2E5A).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getDrawingIcon(drawing.type),
            color: _getDrawingIconColor(drawing.type),
          ),
        ),
        title: Text(
          drawing.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          context.l10n.fileUploadedDot(drawing.fileName, _formatDate(drawing.uploadedAt)),
          style: TextStyle(
            fontSize: 12,
            color: AppColors.inkMuted,
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleContractDrawingAction(value, drawing),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'view',
              child: Row(
                children: [
                  Icon(Icons.visibility, size: 16, color: Colors.blue[600]),
                  SizedBox(width: 8),
                  Text(context.l10n.view),
                ],
              ),
            ),
            if (!_isTechnician)
              PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(Icons.download, size: 16, color: Colors.green[600]),
                    SizedBox(width: 8),
                    Text(context.l10n.download),
                  ],
                ),
              ),
            if (_canManageDrawings)
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 16, color: Colors.red[600]),
                    SizedBox(width: 8),
                    Text(context.l10n.delete, style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // New method: Upload Contract Drawing
  Future<void> _uploadContractDrawing() async {
    try {
      // Step 1: Pick file first
      // withData: true ensures PlatformFile.bytes is populated on web.
      // Without this flag, bytes is null on web and the null-check
      // operator below throws "Unexpected null value".
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'dwg', 'dxf', 'jpg', 'jpeg', 'png'],
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        widget.logger.d('📤 DrawingsScreen: File selection cancelled');
        return;
      }

      final pickedFile = result.files.first;
      final originalFileName = pickedFile.name;
      final fileExtension = originalFileName.split('.').last.toLowerCase();
      widget.logger.i('📤 DrawingsScreen: Contract file selected: $originalFileName');

      // Step 2: Input drawing title (prefilled with file name without extension)
      if (!mounted) return;
      final drawingTitle = await _showTextInputDialog(
        dialogTitle: context.l10n.enterDrawingTitle,
        contentText: context.l10n.enterContractDrawingTitle,
        hintText: context.l10n.contractDrawingHint,
        prefill: originalFileName.split('.').first,
        fileName: originalFileName,
        showFileName: true,
      );

      if (drawingTitle == null || drawingTitle.trim().isEmpty) {
        widget.logger.d('📤 DrawingsScreen: Drawing title input cancelled');
        return;
      }

      final finalFileName = '$drawingTitle.$fileExtension';
      widget.logger.i('📤 DrawingsScreen: Final contract file name: $finalFileName');

      // Step 3: Get file bytes
      List<int> fileBytes;
      if (kIsWeb) {
        if (pickedFile.bytes == null) {
          widget.logger.e('❌ DrawingsScreen: File bytes are null on web — withData may not have worked');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.couldNotReadFile, style: TextStyle())),
            );
          }
          return;
        }
        fileBytes = pickedFile.bytes!;
      } else {
        if (pickedFile.path == null) {
          widget.logger.e('❌ DrawingsScreen: File path is null on native');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.couldNotReadFile, style: TextStyle())),
            );
          }
          return;
        }
        fileBytes = await File(pickedFile.path!).readAsBytes();
      }

      widget.logger.i('📤 DrawingsScreen: File bytes loaded (size: ${fileBytes.length})');

      setState(() {
        _isUploading = true;
      });

      // Step 4: Show upload progress dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(
              context.l10n.uploadingContractDrawing,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  context.l10n.uploadingFile(finalFileName),
                  style: TextStyle(),
                ),
              ],
            ),
          ),
        );
      }

      // Step 5: Upload contract drawing
      _drawingService.uploadContractDrawing(
        projectId: widget.project.id,
        title: drawingTitle.trim(),
        fileName: finalFileName,
        fileBytes: fileBytes,
        fileExtension: fileExtension,
      ).then((_) {
        if (mounted) {
          Navigator.pop(context); // Close progress dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.contractDrawingUploaded(drawingTitle),
                style: TextStyle(),
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
        widget.logger.i('✅ DrawingsScreen: Contract drawing uploaded successfully: $drawingTitle');
      }).catchError((e) {
        widget.logger.e('❌ DrawingsScreen: Contract upload failed', error: e);
        if (mounted) {
          if (Navigator.canPop(context)) {
            Navigator.pop(context); // Close progress dialog if open
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                friendlyError(e, action: context.l10n.couldNotUpload),
                style: TextStyle(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      });

    } catch (e) {
      widget.logger.e('❌ DrawingsScreen: Contract upload failed', error: e);

      if (mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context); // Close progress dialog if open
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(e, action: context.l10n.couldNotUpload),
              style: TextStyle(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  // Updated method: Handle Contract Drawing actions
  void _handleContractDrawingAction(String action, DrawingModel drawing) async {
    switch (action) {
      case 'view':
        await _viewDrawing(drawing.url, drawing.type, drawing.fileName);
        break;
      case 'download':
        await _downloadDrawing(drawing.url, drawing.fileName);
        break;
      case 'delete':
        await _deleteDrawing(drawing);
        break;
    }
  }

  Widget _buildFooter(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
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

  Widget _buildRevisionsTab() {
    return StreamBuilder<List<DrawingModel>>(
      stream: _drawingService.getProjectDrawings(widget.project.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          widget.logger.e('❌ DrawingsScreen: Error loading revisions', error: snapshot.error);
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
                const SizedBox(height: 16),
                Text(
                  context.l10n.couldNotLoadDrawings,
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.red[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final drawings = snapshot.data!;
        final groupedDrawings = _drawingService.groupDrawingsByTitle(drawings);

        if (groupedDrawings.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.architecture, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  context.l10n.noDrawingsYet,
                  style: TextStyle(
                    fontSize: 18,
                    color: AppColors.inkMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.tapUploadFirstDrawing,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: groupedDrawings.length,
          itemBuilder: (context, index) {
            final group = groupedDrawings[index];
            return _buildDrawingGroup(group);
          },
        );
      },
    );
  }

  Widget _buildAsBuiltTab() {
    return StreamBuilder<List<DrawingModel>>(
      stream: _drawingService.getAsBuiltDrawings(widget.project.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
                const SizedBox(height: 16),
                Text(
                  context.l10n.couldNotLoadAsBuilt,
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.red[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final drawings = snapshot.data!;
        drawings.sort((a, b) => a.title.compareTo(b.title));

        if (drawings.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  context.l10n.noAsBuiltYet,
                  style: TextStyle(
                    fontSize: 18,
                    color: AppColors.inkMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.tapUploadAsBuilt,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: drawings.length,
          itemBuilder: (context, index) {
            final drawing = drawings[index];
            return _buildAsBuiltDrawingCard(drawing);
          },
        );
      },
    );
  }

  Widget _buildDrawingGroup(DrawingGroup group) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text(
          group.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          context.l10n.latestRevisionSummary(group.latestRevision?.fileName ?? '', group.revisions.length),
          style: TextStyle(
            fontSize: 12,
            color: AppColors.inkMuted,
          ),
        ),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 100, 157, 122).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.architecture,
            color: Color.fromARGB(255, 3, 71, 13),
          ),
        ),
        children: group.revisions.map((drawing) => _buildRevisionTile(drawing, group)).toList(),
      ),
    );
  }

  Widget _buildRevisionTile(DrawingModel drawing, DrawingGroup group) {
    final isLatest = drawing.revisionNumber == group.latestRevision?.revisionNumber;
    final isFinal = drawing.isFinal;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isLatest
              ? Colors.green.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            context.l10n.revShort('${drawing.revisionNumber}'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isLatest ? Colors.green[700] : AppColors.inkMuted,
            ),
          ),
        ),
      ),
      title: Text(
        drawing.fileName,
        style: TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        context.l10n.uploadedOn(_formatDate(drawing.uploadedAt)),
        style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLatest) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                context.l10n.latest,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (isFinal) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                context.l10n.finalLabel,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          PopupMenuButton<String>(
            onSelected: (value) => _handleRevisionAction(value, drawing),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'view',
                child: Row(
                  children: [
                    Icon(Icons.visibility, size: 16, color: Colors.blue[600]),
                    SizedBox(width: 8),
                    Text(context.l10n.view),
                  ],
                ),
              ),
              if (!_isTechnician)
                PopupMenuItem(
                  value: 'download',
                  child: Row(
                    children: [
                      Icon(Icons.download, size: 16, color: Colors.green[600]),
                      SizedBox(width: 8),
                      Text(context.l10n.download),
                    ],
                  ),
                ),
              if (_canManageDrawings)
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 16, color: Colors.red[600]),
                      SizedBox(width: 8),
                      Text(context.l10n.delete, style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAsBuiltDrawingCard(DrawingModel drawing) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0A2E5A).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getDrawingIcon(drawing.type),
            color: _getDrawingIconColor(drawing.type),
          ),
        ),
        title: Text(
          drawing.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          context.l10n.fileUploadedDot(drawing.fileName, _formatDate(drawing.uploadedAt)),
          style: TextStyle(
            fontSize: 12,
            color: AppColors.inkMuted,
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleAsBuiltAction(value, drawing),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'view',
              child: Row(
                children: [
                  Icon(Icons.visibility, size: 16, color: Colors.blue[600]),
                  SizedBox(width: 8),
                  Text(context.l10n.view),
                ],
              ),
            ),
            if (!_isTechnician)
              PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(Icons.download, size: 16, color: Colors.green[600]),
                    SizedBox(width: 8),
                    Text(context.l10n.download),
                  ],
                ),
              ),
            // REMOVED "Update" option
            if (_canManageDrawings)
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 16, color: Colors.red[600]),
                    SizedBox(width: 8),
                    Text(context.l10n.delete, style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // New method: Upload As-Built Drawing
  Future<void> _uploadAsBuiltDrawing() async {
    try {
      // Step 1: Pick file first
      // withData: true ensures PlatformFile.bytes is populated on web.
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'dwg', 'dxf', 'jpg', 'jpeg', 'png'],
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        widget.logger.d('📤 DrawingsScreen: File selection cancelled');
        return;
      }

      final pickedFile = result.files.first;
      final originalFileName = pickedFile.name;
      final fileExtension = originalFileName.split('.').last.toLowerCase();
      widget.logger.i('📤 DrawingsScreen: As-Built file selected: $originalFileName');

      // Step 2: Input drawing title (prefilled with file name without extension)
      if (!mounted) return;
      final drawingTitle = await _showTextInputDialog(
        dialogTitle: context.l10n.enterAsBuiltTitle,
        contentText: context.l10n.enterAsBuiltTitleBody,
        hintText: context.l10n.asBuiltHint,
        prefill: originalFileName.split('.').first,
        fileName: originalFileName,
        showFileName: true,
      );

      if (drawingTitle == null || drawingTitle.trim().isEmpty) {
        widget.logger.d('📤 DrawingsScreen: Drawing title input cancelled');
        return;
      }

      final finalFileName = '$drawingTitle.$fileExtension';
      widget.logger.i('📤 DrawingsScreen: Final as-built file name: $finalFileName');

      // Step 3: Get file bytes
      List<int> fileBytes;
      if (kIsWeb) {
        if (pickedFile.bytes == null) {
          widget.logger.e('❌ DrawingsScreen: File bytes are null on web — withData may not have worked');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.couldNotReadFile, style: TextStyle())),
            );
          }
          return;
        }
        fileBytes = pickedFile.bytes!;
      } else {
        if (pickedFile.path == null) {
          widget.logger.e('❌ DrawingsScreen: File path is null on native');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.couldNotReadFile, style: TextStyle())),
            );
          }
          return;
        }
        fileBytes = await File(pickedFile.path!).readAsBytes();
      }

      widget.logger.i('📤 DrawingsScreen: File bytes loaded (size: ${fileBytes.length})');

      setState(() {
        _isUploading = true;
      });

      // Step 4: Show upload progress dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(
              context.l10n.uploadingAsBuilt,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  context.l10n.uploadingFile(finalFileName),
                  style: TextStyle(),
                ),
              ],
            ),
          ),
        );
      }

      // Step 5: Upload as-built drawing
      _drawingService.uploadAsBuiltDrawing(
        projectId: widget.project.id,
        title: drawingTitle.trim(),
        fileName: finalFileName,
        fileBytes: fileBytes,
        fileExtension: fileExtension,
      ).then((_) {
        if (mounted) {
          Navigator.pop(context); // Close progress dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.asBuiltUploaded(drawingTitle),
                style: TextStyle(),
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
        widget.logger.i('✅ DrawingsScreen: As-Built drawing uploaded successfully: $drawingTitle');
      }).catchError((e) {
        widget.logger.e('❌ DrawingsScreen: As-Built upload failed', error: e);
        if (mounted) {
          if (Navigator.canPop(context)) {
            Navigator.pop(context); // Close progress dialog if open
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                friendlyError(e, action: context.l10n.couldNotUpload),
                style: TextStyle(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      });

    } catch (e) {
      widget.logger.e('❌ DrawingsScreen: As-Built upload failed', error: e);

      if (mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context); // Close progress dialog if open
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(e, action: context.l10n.couldNotUpload),
              style: TextStyle(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _deleteAsBuiltDrawing(DrawingModel drawing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.l10n.deleteAsBuiltTitle,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        content: Text(
          context.l10n.deleteItemConfirm(drawing.title),
          style: TextStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel, style: TextStyle()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(context.l10n.delete, style: TextStyle()),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmed == true) {
      try {
        await _drawingService.deleteDrawing(drawing.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.asBuiltDeleted,
                style: TextStyle(),
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                friendlyError(e, action: context.l10n.couldNotDelete),
                style: TextStyle(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _uploadDrawing() async {
    try {
      final uploadType = await _showUploadTypeDialog();
      if (uploadType == null) {
        widget.logger.d('📤 DrawingsScreen: Upload type selection cancelled');
        return;
      }

      String drawingCategory;
      if (uploadType == 'new') {
        // For new category: Input category name first
        if (!mounted) return;
        final categoryName = await _showTextInputDialog(
          dialogTitle: context.l10n.enterDrawingCategory,
          contentText: context.l10n.enterDrawingCategoryBody,
          hintText: context.l10n.drawingCategoryHint,
          prefill: '',
          showFileName: false,
        );
        if (categoryName == null || categoryName.trim().isEmpty) {
          widget.logger.d('📤 DrawingsScreen: Category name input cancelled for new');
          return;
        }
        drawingCategory = categoryName.trim();
        widget.logger.i('📤 DrawingsScreen: New category name: $drawingCategory');
      } else {
        // For revision: Select existing category
        final titles = await _getUniqueTitles();
        if (titles.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n.noCategoriesCreateNew,
                  style: TextStyle(),
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        final selectedCategory = await _showTitleSelectionDialog(titles);
        if (selectedCategory == null) {
          widget.logger.d('📤 DrawingsScreen: Category selection cancelled for revision');
          return;
        }
        drawingCategory = selectedCategory;
        widget.logger.i('📤 DrawingsScreen: Selected category for revision: $drawingCategory');
      }

      // Pick file (common for both)
      // withData: true ensures PlatformFile.bytes is populated on web.
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'dwg', 'dxf', 'jpg', 'jpeg', 'png'],
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        widget.logger.d('📤 DrawingsScreen: File selection cancelled');
        return;
      }

      final pickedFile = result.files.first;
      final originalFileName = pickedFile.name;
      final fileExtension = originalFileName.split('.').last.toLowerCase();
      widget.logger.i('📤 DrawingsScreen: File selected: $originalFileName');

      // Input drawing title (file name without extension, editable)
      if (!mounted) return;
      final drawingTitle = await _showTextInputDialog(
        dialogTitle: context.l10n.enterDrawingTitle,
        contentText: context.l10n.enterDrawingTitleBody,
        hintText: context.l10n.drawingTitleHint,
        prefill: originalFileName.split('.').first,
        fileName: originalFileName,
        showFileName: true,
      );
      if (drawingTitle == null || drawingTitle.trim().isEmpty) {
        widget.logger.d('📤 DrawingsScreen: Drawing title input cancelled');
        return;
      }

      final finalFileName = '$drawingTitle.$fileExtension';
      widget.logger.i('📤 DrawingsScreen: Final file name: $finalFileName');

      // Get file bytes
      List<int> fileBytes;
      if (kIsWeb) {
        if (pickedFile.bytes == null) {
          widget.logger.e('❌ DrawingsScreen: File bytes are null on web — withData may not have worked');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.couldNotReadFile, style: TextStyle())),
            );
          }
          return;
        }
        fileBytes = pickedFile.bytes!;
      } else {
        if (pickedFile.path == null) {
          widget.logger.e('❌ DrawingsScreen: File path is null on native');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.couldNotReadFile, style: TextStyle())),
            );
          }
          return;
        }
        fileBytes = await File(pickedFile.path!).readAsBytes();
      }

      widget.logger.i('📤 DrawingsScreen: File bytes loaded (size: ${fileBytes.length})');

      setState(() {
        _isUploading = true;
      });

      // Show upload progress dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(
              context.l10n.uploadingDrawing,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  context.l10n.uploadingFile(finalFileName),
                  style: TextStyle(),
                ),
              ],
            ),
          ),
        );
      }

      // Upload drawing in background for faster feel
      _drawingService.uploadDrawing(
        projectId: widget.project.id,
        title: drawingCategory,
        fileName: finalFileName,
        fileBytes: fileBytes,
        fileExtension: fileExtension,
      ).then((_) {
        if (mounted) {
          Navigator.pop(context); // Close progress dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.drawingUploaded(drawingTitle),
                style: TextStyle(),
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
        widget.logger.i('✅ DrawingsScreen: Drawing uploaded successfully: $drawingTitle');
      }).catchError((e) {
        widget.logger.e('❌ DrawingsScreen: Upload failed', error: e);
        if (mounted) {
          if (Navigator.canPop(context)) {
            Navigator.pop(context); // Close progress dialog if open
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                friendlyError(e, action: context.l10n.couldNotUpload),
                style: TextStyle(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      });

    } catch (e) {
      widget.logger.e('❌ DrawingsScreen: Upload failed', error: e);

      if (mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context); // Close progress dialog if open
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(e, action: context.l10n.couldNotUpload),
              style: TextStyle(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<String?> _showUploadTypeDialog() async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppColors.surface,
        title: Text(
          context.l10n.uploadType,
          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.brandInk),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.chooseUploadType,
              style: TextStyle(color: AppColors.inkMuted),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                title: Text(context.l10n.newCategoryDrawing, style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.success)),
                subtitle: Text(context.l10n.newCategoryDrawingHint, style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                leading: const Icon(Icons.add, color: Colors.green),
                onTap: () => Navigator.pop(context, 'new'),
                tileColor: Colors.green.withValues(alpha: 0.05),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                title: Text(context.l10n.revisionDrawing, style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.brandInk)),
                subtitle: Text(context.l10n.revisionDrawingHint, style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                leading: Icon(Icons.edit, color: AppColors.brandInk),
                onTap: () => Navigator.pop(context, 'revision'),
                tileColor: const Color(0xFF0A2E5A).withValues(alpha: 0.05),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              context.l10n.cancel,
              style: TextStyle(color: Color(0xFF800000)),
            ),
          ),
        ],
      ),
    );
  }

  Future<List<String>> _getUniqueTitles() async {
    try {
      final drawings = await _drawingService.getProjectDrawings(widget.project.id).first;
      final titles = drawings.map((d) => d.title).toSet().toList()..sort();
      widget.logger.d('📤 DrawingsScreen: Fetched ${titles.length} unique titles');
      return titles;
    } catch (e) {
      widget.logger.e('❌ DrawingsScreen: Failed to fetch unique titles', error: e);
      return [];
    }
  }

  Future<String?> _showTitleSelectionDialog(List<String> titles) async {
    String? selectedTitle;
    await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppColors.surface,
        title: Text(
          context.l10n.selectDrawingCategory,
          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.brandInk),
        ),
        content: SizedBox(
          width: min(400, MediaQuery.of(context).size.width * 0.8),
          height: 300,
          child: ListView.separated(
            itemCount: titles.length,
            separatorBuilder: (context, index) => Divider(color: AppColors.border),
            itemBuilder: (context, index) {
              final title = titles[index];
              return Card(
                elevation: 1,
                color: index % 2 == 0 ? Colors.white : Colors.grey[50],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: Text(title, style: TextStyle(color: AppColors.ink)),
                  onTap: () {
                    selectedTitle = title;
                    Navigator.pop(context);
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              context.l10n.cancel,
              style: TextStyle(color: Color(0xFF800000)),
            ),
          ),
        ],
      ),
    );
    return selectedTitle;
  }

  Future<String?> _showTextInputDialog({
    required String dialogTitle,
    required String contentText,
    required String hintText,
    String? prefill,
    String? fileName,
    bool showFileName = true,
  }) async {
    final controller = TextEditingController(
      text: prefill ?? '',
    );

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          dialogTitle,
          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.brandInk),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              contentText,
              style: TextStyle(color: AppColors.inkMuted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hintText,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                hintStyle: TextStyle(color: Colors.grey[500]),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0xFF0A2E5A)),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              style: TextStyle(),
              autofocus: true,
            ),
            if (showFileName && fileName != null) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.fileLabel(fileName),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.inkMuted,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              context.l10n.cancel,
              style: TextStyle(color: Color(0xFF800000)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0A2E5A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              context.l10n.confirm,
              style: TextStyle(),
            ),
          ),
        ],
      ),
    );
  }

  void _handleRevisionAction(String action, DrawingModel drawing) async {
    switch (action) {
      case 'view':
        await _viewDrawing(drawing.url, drawing.type, drawing.fileName);
        break;
      case 'download':
        await _downloadDrawing(drawing.url, drawing.fileName);
        break;
      case 'delete':
        await _deleteDrawing(drawing);
        break;
      // REMOVED 'mark_final' case
    }
  }

  void _handleAsBuiltAction(String action, DrawingModel drawing) async {
    switch (action) {
      case 'view':
        await _viewDrawing(drawing.url, drawing.type, drawing.fileName);
        break;
      case 'download':
        await _downloadDrawing(drawing.url, drawing.fileName);
        break;
      case 'delete':
        await _deleteAsBuiltDrawing(drawing);
        break;
      // REMOVED 'update' case
    }
  }

  Future<void> _deleteDrawing(DrawingModel drawing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.l10n.deleteDrawingTitle,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        content: Text(
          context.l10n.deleteItemConfirm(drawing.fileName),
          style: TextStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel, style: TextStyle()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(context.l10n.delete, style: TextStyle()),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmed == true) {
      try {
        await _drawingService.deleteDrawing(drawing.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.drawingDeleted,
                style: TextStyle(),
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                friendlyError(e, action: context.l10n.couldNotDelete),
                style: TextStyle(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  IconData _getDrawingIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'dwg':
      case 'dxf':
        return Icons.architecture;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      default:
        return Icons.description;
    }
  }

  Color _getDrawingIconColor(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Colors.red[600]!;
      case 'dwg':
      case 'dxf':
        return Colors.blueGrey[600]!;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Colors.orange[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  String _formatDate(dynamic date) {
    DateTime dateTime;
    if (date is Timestamp) {
      dateTime = date.toDate();
    } else if (date is DateTime) {
      dateTime = date;
    } else {
      return '';
    }
    return DateFormat.yMd().format(dateTime);
  }

  Future<void> _viewDrawing(String url, String type, String name) async {
    widget.logger.i('👀 DrawingsScreen: Viewing drawing: $name ($type)');
    final connectivityResult = await Connectivity().checkConnectivity();
    final isOnline = connectivityResult.any((r) => r != ConnectivityResult.none);

    try {
      final cacheManager = DefaultCacheManager();
      FileInfo? cachedFile;
      if (isOnline) {
        cachedFile = await cacheManager.downloadFile(url);
      } else {
        cachedFile = await cacheManager.getFileFromCache(url);
      }

      if (cachedFile != null) {
        final localPath = cachedFile.file.path;
        if (type.toLowerCase() == 'txt') {
          // For TXT, read and show in dialog (works offline)
          final content = await File(localPath).readAsString();
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(name, style: TextStyle()),
                content: SingleChildScrollView(
                  child: SelectableText(content, style: TextStyle()),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10n.close, style: TextStyle()),
                  ),
                ],
              ),
            );
          }
        } else if (kIsWeb) {
          // On web, always use launchUrl (can't open local files directly)
          final viewerUrl = _getViewerUrl(url, type);
          final uri = Uri.parse(viewerUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            if (mounted) {
              widget.logger.e('Could not launch $viewerUrl');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.l10n.couldNotOpenDrawingViewer, style: TextStyle()),
                ),
              );
            }
          }
        } else {
          // On native, open local file with system viewer (prompts if multiple apps)
          final result = await OpenFile.open(localPath);
          if (result.type != ResultType.done && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.l10n.couldNotOpenThisFile, style: TextStyle()),
                action: SnackBarAction(
                  label: context.l10n.downloadInstead,
                  onPressed: () => _downloadDrawing(url, name),
                ),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.offlineNoCopy, style: TextStyle()),
            ),
          );
        }
      }
    } catch (e) {
      widget.logger.e('Error viewing drawing: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, action: context.l10n.couldNotOpenDrawing), style: TextStyle()),
          ),
        );
      }
    }
  }

  Future<void> _downloadDrawing(String url, String name) async {
    widget.logger.i('⬇️ Downloading: $name');
    try {
      // Fetch file bytes from URL
      final response = await Dio().get(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final Uint8List bytes = response.data;

      // Use platform-specific download helper
      final result = await platformDownloadFile(bytes, name);

      if (!mounted) return;

      if (result != null) {
        // Success: result is either a path (mobile) or message (web)
        showDownloadSuccess(context, result);
      } else {
        // User cancelled (shouldn't happen with new implementation)
        widget.logger.d('Download cancelled by user');
      }
    } catch (e) {
      widget.logger.e('❌ Error downloading', error: e);
      if (mounted) {
        showDownloadError(context, e);
      }
    }
  }

  String _getViewerUrl(String url, String type) {
    final encodedUrl = Uri.encodeComponent(url);
    if (type.toLowerCase() == 'pdf' || type.toLowerCase() == 'jpg' || type.toLowerCase() == 'jpeg' || type.toLowerCase() == 'png') {
      return url;
    } else {
      return 'https://view.officeapps.live.com/op/view.aspx?src=$encodedUrl';
    }
  }
}