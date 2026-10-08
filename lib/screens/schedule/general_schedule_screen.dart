import 'dart:io';
import 'dart:typed_data';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/schedule/schedule_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:logger/logger.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:almaworks/helpers/download_helper.dart';
import 'package:almaworks/helpers/download_feedback.dart';
import 'package:intl/intl.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/errors/friendly_error.dart';

class GeneralScheduleScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final bool isClient;
  final bool isTechnician;

  const GeneralScheduleScreen({
    super.key,
    required this.project,
    required this.logger,
    this.isClient = false,
    this.isTechnician = false,
  });

  @override
  State<GeneralScheduleScreen> createState() => _GeneralScheduleScreenState();
}

class _GeneralScheduleScreenState extends State<GeneralScheduleScreen> {
  final ScheduleService _scheduleService = ScheduleService();
  bool _isUploading = false;

  // Client and Technician are view-only here — no upload, download, or
  // delete; every other role keeps full manage access.
  bool get _canManage => !widget.isClient && !widget.isTechnician;

  @override
  void initState() {
    super.initState();
    widget.logger.i(
      '📅 GeneralScheduleScreen: Initialized for project: ${widget.project.name} (ID: ${widget.project.id})',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: StreamBuilder<List<ScheduleDocument>>(
        stream: _scheduleService.getGeneralScheduleDocuments(widget.project.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            widget.logger.e(
              '❌ GeneralScheduleScreen: Error loading documents',
              error: snapshot.error,
            );
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.couldNotLoadScheduleDocs,
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

          final documents = snapshot.data!;
          documents.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));

          if (documents.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.calendar_today, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.noScheduleYet,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_canManage)
                    Text(
                      context.l10n.tapUploadSchedule,
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
            itemCount: documents.length,
            itemBuilder: (context, index) {
              final document = documents[index];
              return _buildDocumentCard(document);
            },
          );
        },
      ),
      floatingActionButton: !_canManage
          ? null
          : FloatingActionButton(
              onPressed: _isUploading ? null : _uploadScheduleDocument,
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
    );
  }

  Widget _buildDocumentCard(ScheduleDocument document) {
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
            _getDocumentIcon(document.fileExtension),
            color: _getDocumentIconColor(document.fileExtension),
          ),
        ),
        title: Text(
          document.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          context.l10n.fileUploadedDot(document.fileName, _formatDate(document.uploadedAt)),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleDocumentAction(value, document),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'view',
              child: Row(
                children: [
                  Icon(Icons.visibility, size: 16, color: Colors.blue[600]),
                  const SizedBox(width: 8),
                  Text(context.l10n.view),
                ],
              ),
            ),
            if (!widget.isTechnician)
              PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(Icons.download, size: 16, color: Colors.green[600]),
                    const SizedBox(width: 8),
                    Text(context.l10n.download),
                  ],
                ),
              ),
            if (_canManage)
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 16, color: Colors.red[600]),
                    const SizedBox(width: 8),
                    Text(context.l10n.delete, style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadScheduleDocument() async {
    try {
      // Step 1: Pick file
      // withData: true ensures PlatformFile.bytes is populated on web.
      // Without this flag, bytes is null on web and the null-check
      // operator below throws "Unexpected null value".
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'mpp', 'jpg', 'jpeg', 'png'],
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        widget.logger.d('📤 GeneralScheduleScreen: File selection cancelled');
        return;
      }

      final pickedFile = result.files.first;
      final originalFileName = pickedFile.name;
      final fileExtension = originalFileName.split('.').last.toLowerCase();
      widget.logger.i('📤 GeneralScheduleScreen: File selected: $originalFileName');

      // Step 2: Input document title
      if (!mounted) return;
      final documentTitle = await _showTextInputDialog(
        dialogTitle: context.l10n.enterScheduleDocTitle,
        contentText: context.l10n.enterScheduleDocTitleBody,
        hintText: context.l10n.scheduleDocHint,
        prefill: originalFileName.split('.').first,
        fileName: originalFileName,
        showFileName: true,
      );

      if (documentTitle == null || documentTitle.trim().isEmpty) {
        widget.logger.d('📤 GeneralScheduleScreen: Document title input cancelled');
        return;
      }

      final finalFileName = '$documentTitle.$fileExtension';
      widget.logger.i('📤 GeneralScheduleScreen: Final file name: $finalFileName');

      // Step 3: Get file bytes
      List<int> fileBytes;
      if (kIsWeb) {
        if (pickedFile.bytes == null) {
          widget.logger.e('❌ GeneralScheduleScreen: File bytes are null on web — withData may not have worked');
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
          widget.logger.e('❌ GeneralScheduleScreen: File path is null on native');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.couldNotReadFile, style: TextStyle())),
            );
          }
          return;
        }
        fileBytes = await File(pickedFile.path!).readAsBytes();
      }

      widget.logger.i('📤 GeneralScheduleScreen: File bytes loaded (size: ${fileBytes.length})');

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
              context.l10n.uploadingScheduleDoc,
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

      // Step 5: Upload document
      _scheduleService
          .uploadGeneralScheduleDocument(
        projectId: widget.project.id,
        title: documentTitle.trim(),
        fileName: finalFileName,
        fileBytes: fileBytes,
        fileExtension: fileExtension,
      )
          .then((_) {
        if (mounted) {
          Navigator.pop(context); // Close progress dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.scheduleDocUploaded(documentTitle),
                style: TextStyle(),
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
        widget.logger.i(
          '✅ GeneralScheduleScreen: Document uploaded successfully: $documentTitle',
        );
      }).catchError((e) {
        widget.logger.e('❌ GeneralScheduleScreen: Upload failed', error: e);
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
      widget.logger.e('❌ GeneralScheduleScreen: Upload failed', error: e);

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

  Future<String?> _showTextInputDialog({
    required String dialogTitle,
    required String contentText,
    required String hintText,
    String? prefill,
    String? fileName,
    bool showFileName = true,
  }) async {
    final controller = TextEditingController(text: prefill ?? '');

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          dialogTitle,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0A2E5A),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              contentText,
              style: TextStyle(color: Colors.grey[700]),
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
              context.l10n.cancel,
              style: TextStyle(color: const Color(0xFF800000)),
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

  void _handleDocumentAction(String action, ScheduleDocument document) async {
    switch (action) {
      case 'view':
        await _viewDocument(document.url, document.fileExtension, document.fileName);
        break;
      case 'download':
        await _downloadDocument(document.url, document.fileName);
        break;
      case 'delete':
        await _deleteDocument(document);
        break;
    }
  }

  Future<void> _viewDocument(String url, String type, String name) async {
    widget.logger.i('👀 GeneralScheduleScreen: Viewing document: $name ($type)');
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
        if (kIsWeb) {
          // On web, always use launchUrl
          final viewerUrl = _getViewerUrl(url, type);
          final uri = Uri.parse(viewerUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            if (mounted) {
              widget.logger.e('Could not launch $viewerUrl');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    context.l10n.couldNotOpenViewer,
                    style: TextStyle(),
                  ),
                ),
              );
            }
          }
        } else {
          // On native, open local file with system viewer
          final result = await OpenFile.open(localPath);
          if (result.type != ResultType.done && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n.couldNotOpenThisFile,
                  style: TextStyle(),
                ),
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
              content: Text(
                context.l10n.offlineNoCopy,
                style: TextStyle(),
              ),
            ),
          );
        }
      }
    } catch (e) {
      widget.logger.e('Error viewing document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(e, action: context.l10n.couldNotOpenDocument),
              style: TextStyle(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _downloadDocument(String url, String name) async {
    widget.logger.i('⬇️ Downloading: $name');
    try {
      final response = await Dio().get(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final Uint8List bytes = response.data;

      final result = await platformDownloadFile(bytes, name);

      if (!mounted) return;

      if (result != null) {
        showDownloadSuccess(context, result);
      } else {
        widget.logger.d('Download cancelled by user');
      }
    } catch (e) {
      widget.logger.e('❌ Error downloading', error: e);
      if (mounted) {
        showDownloadError(context, e);
      }
    }
  }

  Future<void> _deleteDocument(ScheduleDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.l10n.deleteScheduleDocTitle,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        content: Text(
          context.l10n.deleteItemConfirm(document.title),
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
        await _scheduleService.deleteScheduleDocument(document.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.scheduleDocDeleted,
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

  IconData _getDocumentIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'mpp':
        return Icons.calendar_today;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getDocumentIconColor(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Colors.red[600]!;
      case 'doc':
      case 'docx':
        return Colors.blue[600]!;
      case 'xls':
      case 'xlsx':
        return Colors.green[600]!;
      case 'mpp':
        return Colors.purple[600]!;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Colors.orange[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  String _formatDate(dynamic date) {
    try {
      DateTime dateTime;
      if (date is Timestamp) {
        dateTime = date.toDate();
      } else if (date is DateTime) {
        dateTime = date;
      } else {
        return l10nNow.justNow;
      }
      return DateFormat.yMd().format(dateTime);
    } catch (e) {
      return l10nNow.justNow;
    }
  }

  String _getViewerUrl(String url, String type) {
    final encodedUrl = Uri.encodeComponent(url);
    if (type.toLowerCase() == 'pdf' ||
        type.toLowerCase() == 'jpg' ||
        type.toLowerCase() == 'jpeg' ||
        type.toLowerCase() == 'png') {
      return url;
    } else {
      return 'https://view.officeapps.live.com/op/view.aspx?src=$encodedUrl';
    }
  }
}