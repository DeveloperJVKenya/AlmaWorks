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
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:almaworks/helpers/download_helper.dart';

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
      title: '${widget.project.name} - Drawings',
      project: widget.project,
      logger: widget.logger,
      selectedMenuItem: 'Drawings',
      onMenuItemSelected: (_) {}, // Empty callback as navigation is handled by BaseLayout
          floatingActionButton: FloatingActionButton(
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
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withValues(alpha: 0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TabBar(
                          controller: _tabController,
                          labelColor: const Color(0xFF0A2E5A),
                          unselectedLabelColor: Colors.grey[600],
                          indicatorColor: const Color(0xFF0A2E5A),
                          indicatorWeight: 3,
                          labelStyle: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                          unselectedLabelStyle: GoogleFonts.poppins(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                          tabs: const [
                            Tab(text: 'Contract Drawing'),
                            Tab(text: 'Revisions'),
                            Tab(text: 'As Built'),
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
                  'Error loading contract drawings',
                  style: GoogleFonts.poppins(
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
                  'No contract drawings uploaded yet',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap the upload button to add contract drawings',
                  style: GoogleFonts.poppins(
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
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          '${drawing.fileName} • Uploaded ${_formatDate(drawing.uploadedAt)}',
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.grey[600],
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
                  Text('View'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'download',
              child: Row(
                children: [
                  Icon(Icons.download, size: 16, color: Colors.green[600]),
                  SizedBox(width: 8),
                  Text('Download'),
                ],
              ),
            ),
            if (_userRole != 'Client')
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 16, color: Colors.red[600]),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Colors.red)),
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
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'dwg', 'dxf', 'jpg', 'jpeg', 'png'],
        allowMultiple: false,
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
      final drawingTitle = await _showTextInputDialog(
        dialogTitle: 'Enter Drawing Title',
        contentText: 'Enter a title for this contract drawing:',
        hintText: 'e.g., Main Contract Drawing',
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
        fileBytes = pickedFile.bytes!;
      } else {
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
              'Uploading Contract Drawing',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Uploading $finalFileName...',
                  style: GoogleFonts.poppins(),
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
                'Contract drawing "$drawingTitle" uploaded successfully!',
                style: GoogleFonts.poppins(),
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
                'Upload failed: ${e.toString()}',
                style: GoogleFonts.poppins(),
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
              'Upload failed: ${e.toString()}',
              style: GoogleFonts.poppins(),
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
                  'Error loading drawings',
                  style: GoogleFonts.poppins(
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
                  'No drawings uploaded yet',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap the upload button to add your first drawing',
                  style: GoogleFonts.poppins(
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
                  'Error loading as-built drawings',
                  style: GoogleFonts.poppins(
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
                  'No as-built drawings yet',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap the upload button to add as-built drawings', 
                  style: GoogleFonts.poppins(
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
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          '${group.latestRevision?.fileName ?? ''} (Latest) • ${group.revisions.length} revision${group.revisions.length != 1 ? 's' : ''}',
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.grey[600],
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
            'Rev${drawing.revisionNumber}',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isLatest ? Colors.green[700] : Colors.grey[600],
            ),
          ),
        ),
      ),
      title: Text(
        drawing.fileName,
        style: GoogleFonts.poppins(fontSize: 14),
      ),
      subtitle: Text(
        'Uploaded ${_formatDate(drawing.uploadedAt)}',
        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
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
                'Latest',
                style: GoogleFonts.poppins(
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
                'Final',
                style: GoogleFonts.poppins(
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
                    Text('View'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(Icons.download, size: 16, color: Colors.green[600]),
                    SizedBox(width: 8),
                    Text('Download'),
                  ],
                ),
              ),
              if (_userRole != 'Client')
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 16, color: Colors.red[600]),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
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
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          '${drawing.fileName} • Uploaded ${_formatDate(drawing.uploadedAt)}',
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.grey[600],
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
                  Text('View'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'download',
              child: Row(
                children: [
                  Icon(Icons.download, size: 16, color: Colors.green[600]),
                  SizedBox(width: 8),
                  Text('Download'),
                ],
              ),
            ),
            // REMOVED "Update" option
            if (_userRole != 'Client')
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 16, color: Colors.red[600]),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Colors.red)),
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
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'dwg', 'dxf', 'jpg', 'jpeg', 'png'],
        allowMultiple: false,
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
      final drawingTitle = await _showTextInputDialog(
        dialogTitle: 'Enter As-Built Drawing Title',
        contentText: 'Enter a title for this as-built drawing:',
        hintText: 'e.g., Final Construction Drawing',
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
        fileBytes = pickedFile.bytes!;
      } else {
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
              'Uploading As-Built Drawing',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Uploading $finalFileName...',
                  style: GoogleFonts.poppins(),
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
                'As-Built drawing "$drawingTitle" uploaded successfully!',
                style: GoogleFonts.poppins(),
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
                'Upload failed: ${e.toString()}',
                style: GoogleFonts.poppins(),
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
              'Upload failed: ${e.toString()}',
              style: GoogleFonts.poppins(),
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
          'Delete As-Built Drawing',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to delete "${drawing.title}"? This action cannot be undone.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Delete', style: GoogleFonts.poppins()),
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
                'As-Built drawing deleted successfully',
                style: GoogleFonts.poppins(),
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
                'Failed to delete: ${e.toString()}',
                style: GoogleFonts.poppins(),
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
        final categoryName = await _showTextInputDialog(
          dialogTitle: 'Enter Drawing Category',
          contentText: 'Enter a name for the new drawing category:',
          hintText: 'e.g., Floor Plan Level 1',
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
                  'No existing categories. Please create a new one.',
                  style: GoogleFonts.poppins(),
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
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'dwg', 'dxf', 'jpg', 'jpeg', 'png'],
        allowMultiple: false,
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
      final drawingTitle = await _showTextInputDialog(
        dialogTitle: 'Enter Drawing Title',
        contentText: 'Enter a title for this drawing:',
        hintText: 'e.g., Floor Plan Level 1 - Rev 1',
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
        fileBytes = pickedFile.bytes!;
      } else {
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
              'Uploading Drawing',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Uploading $finalFileName...',
                  style: GoogleFonts.poppins(),
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
                'Drawing "$drawingTitle" uploaded successfully!',
                style: GoogleFonts.poppins(),
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
                'Upload failed: ${e.toString()}',
                style: GoogleFonts.poppins(),
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
              'Upload failed: ${e.toString()}',
              style: GoogleFonts.poppins(),
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
        backgroundColor: Colors.white,
        title: Text(
          'Upload Type',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: const Color(0xFF0A2E5A)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose how to upload the drawing:',
              style: GoogleFonts.poppins(color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                title: Text('New Category Drawing', style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: Colors.green[800])),
                subtitle: Text('Create a new drawing category and upload the first revision.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
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
                title: Text('Revision Drawing', style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: const Color(0xFF0A2E5A))),
                subtitle: Text('Add a revision to an existing drawing category.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                leading: const Icon(Icons.edit, color: Color(0xFF0A2E5A)),
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
              'Cancel',
              style: GoogleFonts.poppins(color: Color(0xFF800000)),
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
        backgroundColor: Colors.white,
        title: Text(
          'Select Drawing Category',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: const Color(0xFF0A2E5A)),
        ),
        content: SizedBox(
          width: min(400, MediaQuery.of(context).size.width * 0.8),
          height: 300,
          child: ListView.separated(
            itemCount: titles.length,
            separatorBuilder: (context, index) => Divider(color: Colors.grey[300]),
            itemBuilder: (context, index) {
              final title = titles[index];
              return Card(
                elevation: 1,
                color: index % 2 == 0 ? Colors.white : Colors.grey[50],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: Text(title, style: GoogleFonts.poppins(color: Colors.grey[800])),
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
              'Cancel',
              style: GoogleFonts.poppins(color: Color(0xFF800000)),
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
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: const Color(0xFF0A2E5A)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              contentText,
              style: GoogleFonts.poppins(color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hintText,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                hintStyle: GoogleFonts.poppins(color: Colors.grey[500]),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0xFF0A2E5A)),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              style: GoogleFonts.poppins(),
              autofocus: true,
            ),
            if (showFileName && fileName != null) ...[
              const SizedBox(height: 8),
              Text(
                'File: $fileName',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: Color(0xFF800000)),
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
              'Confirm',
              style: GoogleFonts.poppins(),
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
          'Delete Drawing',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to delete "${drawing.fileName}"? This action cannot be undone.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Delete', style: GoogleFonts.poppins()),
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
                'Drawing deleted successfully',
                style: GoogleFonts.poppins(),
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
                'Failed to delete: ${e.toString()}',
                style: GoogleFonts.poppins(),
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
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
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
                title: Text(name, style: GoogleFonts.poppins()),
                content: SingleChildScrollView(
                  child: SelectableText(content, style: GoogleFonts.poppins()),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Close', style: GoogleFonts.poppins()),
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
                  content: Text('Could not open drawing viewer', style: GoogleFonts.poppins()),
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
                content: Text('Could not open file: ${result.message}', style: GoogleFonts.poppins()),
                action: SnackBarAction(
                  label: 'Download instead',
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
              content: Text('No internet and no cache available', style: GoogleFonts.poppins()),
            ),
          );
        }
      }
    } catch (e) {
      widget.logger.e('Error viewing drawing: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error viewing drawing: $e', style: GoogleFonts.poppins()),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kIsWeb 
                ? result  // Web: "Download started. Check your browser downloads."
                : 'Downloaded successfully!\nLocation: $result',  // Mobile: Full path
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Open',
              textColor: Colors.white,
              onPressed: () async {
                if (!kIsWeb) {
                  await OpenFile.open(result);
                }
              },
            ),
          ),
        );
      } else {
        // User cancelled (shouldn't happen with new implementation)
        widget.logger.d('Download cancelled by user');
      }
    } catch (e) {
      widget.logger.e('❌ Error downloading', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains('permission')
                ? 'Storage permission denied. Please enable it in Settings.'
                : 'Error downloading: $e',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: e.toString().contains('permission')
              ? SnackBarAction(
                  label: 'Settings',
                  textColor: Colors.white,
                  onPressed: () => openAppSettings(),
                )
              : null,
          ),
        );
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