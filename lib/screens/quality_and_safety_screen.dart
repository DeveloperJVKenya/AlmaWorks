import 'package:almaworks/models/document_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:open_file/open_file.dart';
import 'dart:typed_data';
import 'package:almaworks/helpers/download_feedback.dart';
import 'package:almaworks/helpers/download_helper.dart'; // Assuming this is available as per DocumentsScreen
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/errors/friendly_error.dart';
import 'package:almaworks/core/theme/app_colors.dart';

class QualityAndSafetyScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;

  const QualityAndSafetyScreen({
    super.key,
    required this.project,
    required this.logger,
  });

  @override
  State<QualityAndSafetyScreen> createState() => _QualityAndSafetyScreenState();
}

class _QualityAndSafetyScreenState extends State<QualityAndSafetyScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateFormat get _dateFormat => DateFormat.yMd().add_Hm();
  bool _isLoading = false;
  String? _userRole = 'Client'; // default to most restrictive until loaded

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    widget.logger.i('📄 QualityAndSafetyScreen: Initialized for project: ${widget.project.name} (ID: ${widget.project.id})');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final width = MediaQuery.of(context).size.width;
      widget.logger.d('📄 QualityAndSafetyScreen: Screen width: $width, isMobile: ${width < 600}');
    });
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        widget.logger.e('❌ QualityAndSafetyScreen: No authenticated user found');
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
        widget.logger.i('✅ QualityAndSafetyScreen: User role fetched: $role');
      }
    } catch (e) {
      widget.logger.e('❌ QualityAndSafetyScreen: Error fetching user role: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    widget.logger.d('📄 QualityAndSafetyScreen: Building UI, isMobile: $isMobile');
    return BaseLayout(
      title: context.l10n.projectSectionTitle(widget.project.name, context.l10n.qualitySafety),
      project: widget.project,
      logger: widget.logger,
      selectedMenuItem: 'Quality & Safety',
      onMenuItemSelected: (_) {},
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : () => _uploadDocument(_tabController.index == 0 ? 'QualityDocuments' : 'SafetyDocuments'),
        backgroundColor: const Color(0xFF0A2E5A),
        foregroundColor: Colors.white,
        child: const Icon(Icons.file_upload),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
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
                          controller: _tabController,
                          labelColor: AppColors.brandInk,
                          unselectedLabelColor: Colors.grey[600],
                          indicatorColor: AppColors.brandInk,
                          labelStyle: TextStyle(fontWeight: FontWeight.w600),
                          tabs: [
                            Tab(text: context.l10n.quality),
                            Tab(text: context.l10n.safety),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: constraints.maxHeight - 48 - (isMobile ? 12 : 16) * 2,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildQualityTab(),
                            _buildSafetyTab(),
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

  Widget _buildQualityTab() {
    widget.logger.d('📄 QualityAndSafetyScreen: Fetching QualityDocuments (projectId: ${widget.project.id})');
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('QualityDocuments')
          .where('projectId', isEqualTo: widget.project.id)
          .orderBy('uploadedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          widget.logger.e(
            '❌ QualityAndSafetyScreen: Error loading QualityDocuments',
            error: snapshot.error,
            stackTrace: snapshot.stackTrace,
          );
          return Center(
            child: Text(
              context.l10n.couldNotLoadDocuments,
              style: TextStyle(color: Colors.red[600]),
            ),
          );
        }
        if (!snapshot.hasData) {
          widget.logger.d('📄 QualityAndSafetyScreen: Waiting for QualityDocuments data');
          return const Center(child: CircularProgressIndicator());
        }
        final documents = snapshot.data!.docs;
        widget.logger.i('📄 QualityAndSafetyScreen: Loaded ${documents.length} QualityDocuments');
        widget.logger.d('📄 QualityAndSafetyScreen: Rendering Quality tab');
        if (documents.isEmpty) {
          return Center(
            child: Text(context.l10n.noDocumentsYet, style: TextStyle(color: AppColors.inkMuted)),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border, width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      context.l10n.qualityDocuments,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...documents.map((doc) {
              try {
                final data = doc.data() as Map<String, dynamic>;
                final document = DocumentModel.fromMap(doc.id, data);
                return _buildDocumentItem(
                  document.id,
                  document.name,
                  document.url,
                  document.uploadedAt,
                  'QualityDocuments',
                  data['type'] as String? ?? 'pdf', // Assume type is stored, default to pdf
                );
              } catch (e, stackTrace) {
                widget.logger.e(
                  '❌ QualityAndSafetyScreen: Error parsing QualityDocuments document ${doc.id}',
                  error: e,
                  stackTrace: stackTrace,
                );
                return const SizedBox.shrink();
              }
            }),
          ],
        );
      },
    );
  }

  Widget _buildSafetyTab() {
    widget.logger.d('📄 QualityAndSafetyScreen: Fetching SafetyDocuments (projectId: ${widget.project.id})');
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('SafetyDocuments')
          .where('projectId', isEqualTo: widget.project.id)
          .orderBy('uploadedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          widget.logger.e(
            '❌ QualityAndSafetyScreen: Error loading SafetyDocuments',
            error: snapshot.error,
            stackTrace: snapshot.stackTrace,
          );
          return Center(
            child: Text(
              context.l10n.couldNotLoadDocuments,
              style: TextStyle(color: Colors.red[600]),
            ),
          );
        }
        if (!snapshot.hasData) {
          widget.logger.d('📄 QualityAndSafetyScreen: Waiting for SafetyDocuments data');
          return const Center(child: CircularProgressIndicator());
        }
        final documents = snapshot.data!.docs;
        widget.logger.i('📄 QualityAndSafetyScreen: Loaded ${documents.length} SafetyDocuments');
        widget.logger.d('📄 QualityAndSafetyScreen: Rendering Safety tab');
        if (documents.isEmpty) {
          return Center(
            child: Text(context.l10n.noDocumentsYet, style: TextStyle(color: AppColors.inkMuted)),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border, width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      context.l10n.safetyDocuments,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...documents.map((doc) {
              try {
                final data = doc.data() as Map<String, dynamic>;
                final document = DocumentModel.fromMap(doc.id, data);
                return _buildDocumentItem(
                  document.id,
                  document.name,
                  document.url,
                  document.uploadedAt,
                  'SafetyDocuments',
                  data['type'] as String? ?? 'pdf', // Assume type is stored, default to pdf
                );
              } catch (e, stackTrace) {
                widget.logger.e(
                  '❌ QualityAndSafetyScreen: Error parsing SafetyDocuments document ${doc.id}',
                  error: e,
                  stackTrace: stackTrace,
                );
                return const SizedBox.shrink();
              }
            }),
          ],
        );
      },
    );
  }

  Widget _buildDocumentItem(String id, String name, String url, DateTime uploadedAt, String collection, String type) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(_getDocumentIcon(type), color: _getFileIconColor(type)),
        title: Text(name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        subtitle: Text(
          context.l10n.uploadedColon(_dateFormat.format(uploadedAt)),
          style: TextStyle(color: AppColors.inkMuted, fontSize: 14),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleDocumentAction(value, id, name, url, collection, type),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'view',
              child: Row(
                children: [
                  Icon(Icons.visibility, color: Colors.blue[600]),
                  const SizedBox(width: 8),
                  Text(context.l10n.view, style: TextStyle()),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'download',
              child: Row(
                children: [
                  Icon(Icons.download, color: Colors.green[600]),
                  const SizedBox(width: 8),
                  Text(context.l10n.download, style: TextStyle()),
                ],
              ),
            ),
            if (_userRole != 'Client')
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red[600]),
                    const SizedBox(width: 8),
                    Text(context.l10n.delete, style: TextStyle()),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadDocument(String collection) async {
    widget.logger.d('📄 QualityAndSafetyScreen: Opening file picker for $collection');
    try {
      setState(() {
        _isLoading = true;
      });

      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'pptx', 'txt', 'doc', 'ppt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        widget.logger.d('📄 QualityAndSafetyScreen: File picker cancelled');
        return;
      }

      final platformFile = result.files.single;
      final fileName = platformFile.name;
      final extension = fileName.split('.').last.toLowerCase();
      Uint8List? fileBytes;

      if (platformFile.bytes != null) {
        fileBytes = platformFile.bytes!;
        widget.logger.d('📄 QualityAndSafetyScreen: File bytes available (web)');
      } else if (platformFile.path != null) {
        final file = File(platformFile.path!);
        fileBytes = await file.readAsBytes();
        widget.logger.d('📄 QualityAndSafetyScreen: File read from path (mobile/desktop)');
      }

      if (fileBytes == null) {
        throw UserFacingException(l10nNow.couldNotReadFile);
      }

      final title = await _getDocumentTitle(fileName);
      if (title == null) {
        widget.logger.d('📄 QualityAndSafetyScreen: Upload cancelled - no title provided');
        return;
      }

      final storageRef = FirebaseStorage.instance
          .ref()
          .child(widget.project.id)
          .child(collection)
          .child(fileName);

      final uploadTask = storageRef.putData(
        fileBytes,
        SettableMetadata(contentType: _getContentType(extension)),
      );

      await uploadTask.whenComplete(() => null);

      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection(collection).add({
        'name': title,
        'url': downloadUrl,
        'projectId': widget.project.id,
        'projectName': widget.project.name,
        'uploadedAt': Timestamp.now(),
        'type': extension,
      });

      widget.logger.i('✅ QualityAndSafetyScreen: Document uploaded successfully: $fileName');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.documentUploaded, style: TextStyle())),
        );
      }
    } catch (e, stackTrace) {
      widget.logger.e('❌ QualityAndSafetyScreen: Error uploading document', error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e, action: context.l10n.couldNotUpload), style: TextStyle())),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<String?> _getDocumentTitle(String prefilledName) async {
    String? title = prefilledName;
    final controller = TextEditingController(text: prefilledName);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(context.l10n.enterDocumentTitle, style: TextStyle()),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: context.l10n.documentTitleHint,
              border: const OutlineInputBorder(),
              labelStyle: TextStyle(),
            ),
            style: TextStyle(),
            onChanged: (val) => title = val.trim(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel, style: TextStyle()),
            ),
            TextButton(
              onPressed: () {
                if (title != null && title!.isNotEmpty) {
                  Navigator.pop(ctx, true);
                } else {
                  if (!mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(context.l10n.pleaseEnterTitle, style: TextStyle())),
                  );
                }
              },
              child: Text('OK', style: TextStyle()),
            ),
          ],
        );
      },
    );
    return result == true ? title : null;
  }

  String _getContentType(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'doc':
        return 'application/msword';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  IconData _getDocumentIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'docx':
      case 'doc':
        return Icons.description;
      case 'pptx':
      case 'ppt':
        return Icons.slideshow;
      case 'txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileIconColor(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Colors.red[600]!;
      case 'docx':
      case 'doc':
        return Colors.blueGrey[600]!;
      case 'pptx':
      case 'ppt':
        return Colors.orange[600]!;
      case 'txt':
        return Colors.grey[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  String _getViewerUrl(String url, String type) {
    final encodedUrl = Uri.encodeComponent(url);
    if (type.toLowerCase() == 'pdf') {
      return url;
    } else {
      return 'https://view.officeapps.live.com/op/view.aspx?src=$encodedUrl';
    }
  }

  Future<void> _viewDocument(String url, String type, String name) async {
    widget.logger.i('👀 QualityAndSafetyScreen: Viewing document: $name ($type)');
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
                  content: Text(context.l10n.couldNotOpenViewer, style: TextStyle()),
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
                  onPressed: () => _downloadDocument(url, name),
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
      widget.logger.e('Error viewing document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, action: context.l10n.couldNotOpenDocument), style: TextStyle()),
          ),
        );
      }
    }
  }

  Future<void> _downloadDocument(String url, String name) async {
    widget.logger.i('⬇️ QualityAndSafetyScreen: Downloading: $name');
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

  Future<void> _deleteDocument(String docId, String url, String collection) async {
    widget.logger.i('🗑️ QualityAndSafetyScreen: Deleting document: $docId');
    try {
      widget.logger.d('🗑️ QualityAndSafetyScreen: Deleting from storage');
      final ref = FirebaseStorage.instance.refFromURL(url);
      await ref.delete();
      widget.logger.d('🗑️ QualityAndSafetyScreen: Deleting from Firestore');
      await FirebaseFirestore.instance.collection(collection).doc(docId).delete();
      if (mounted) {
        widget.logger.i('✅ QualityAndSafetyScreen: Document deleted successfully');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.documentDeleted, style: TextStyle()),
          ),
        );
      }
    } catch (e) {
      widget.logger.e('❌ QualityAndSafetyScreen: Error deleting document', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, action: context.l10n.couldNotDeleteDocument), style: TextStyle()),
          ),
        );
      }
    }
  }

  Future<void> _handleDocumentAction(String action, String id, String name, String url, String collection, String type) async {
    if (action == 'view') {
      await _viewDocument(url, type, name);
    } else if (action == 'download') {
      await _downloadDocument(url, name);
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.deleteDocumentTitle, style: TextStyle(fontWeight: FontWeight.w600)),
          content: Text(context.l10n.deleteNamedConfirm(name), style: TextStyle()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel, style: TextStyle()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: Text(context.l10n.delete, style: TextStyle()),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await _deleteDocument(id, url, collection);
      }
    }
  }
}