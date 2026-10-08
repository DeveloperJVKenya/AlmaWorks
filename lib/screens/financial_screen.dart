import 'package:almaworks/models/project_model.dart';
//import 'package:almaworks/models/financial_document_model.dart';
import 'package:almaworks/screens/projects/edit_project_screen.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:open_file/open_file.dart';
import 'package:almaworks/helpers/download_helper.dart';
import 'package:almaworks/helpers/download_feedback.dart';
import 'package:almaworks/screens/documents_screen.dart' show docTabLabel;
import 'package:almaworks/screens/projects/add_project_screen.dart' show teamRoleLabel;
import 'package:intl/intl.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/errors/friendly_error.dart';
import 'package:almaworks/core/theme/app_colors.dart';

class FinancialScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;

  const FinancialScreen({
    super.key,
    required this.project,
    required this.logger,
  });

  @override
  State<FinancialScreen> createState() => _FinancialScreenState();
}

class _FinancialScreenState extends State<FinancialScreen> with TickerProviderStateMixin {
  late TabController _mainTabController;
  bool _isLoading = false;
  double? _uploadProgress;
  late ProjectModel _currentProject;
  String? _selectedSubcontractor;
  String? _selectedSupplier;
  String? _userRole;
  bool _isLoadingUserData = true;

  final List<String> _mainTabs = ['Client', 'Subcontractor', 'Supplier'];

  @override
  void initState() {
    super.initState();
    _currentProject = widget.project;

    // Initialize tab controller immediately with default values
    _mainTabController = TabController(length: _mainTabs.length, vsync: this);

    widget.logger.i('💰 FinancialScreen: Initialized for project: ${_currentProject.name}');

    // Fetch user role asynchronously
    _fetchUserRole();
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    super.dispose();
  }

  void _navigateToEditProject() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditProjectScreen(
          project: _currentProject,
          logger: widget.logger,
        ),
      ),
    ).then((_) async {
      final doc = await FirebaseFirestore.instance.collection('Projects').doc(_currentProject.id).get();
      if (doc.exists) {
        setState(() {
          _currentProject = ProjectModel.fromFirestore(doc);
          _selectedSubcontractor = null;
          _selectedSupplier = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    widget.logger.d('🎨 FinancialScreen: Building UI');

    // Show loading indicator while fetching user data
    if (_isLoadingUserData) {
      return BaseLayout(
        title: context.l10n.projectSectionTitle(_currentProject.name, context.l10n.financials),
        project: _currentProject,
        logger: widget.logger,
        selectedMenuItem: 'Financials',
        onMenuItemSelected: (_) {},
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Determine if user is a client
    final bool isClient = _userRole == 'Client';

    return BaseLayout(
      title: context.l10n.projectSectionTitle(_currentProject.name, context.l10n.financials),
      project: _currentProject,
      logger: widget.logger,
      selectedMenuItem: 'Financials',
      onMenuItemSelected: (_) {},
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : _addFinancialDocument,
        backgroundColor: const Color(0xFF0A2E5A),
        foregroundColor: Colors.white,
        child: const Icon(Icons.upload_file),
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
                      // Show TabBar only for Admin/MainAdmin users
                      if (!isClient)
                        TabBar(
                          controller: _mainTabController,
                          tabs: _mainTabs.map((tab) => Tab(text: docTabLabel(tab))).toList(),
                          labelColor: AppColors.brandInk,
                          unselectedLabelColor: Colors.grey,
                          labelStyle: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      SizedBox(
                        height: constraints.maxHeight - (isClient ? 0 : 48) - 48,
                        child: isClient
                            ? _buildFinancialList('Client', memberName: null)
                            : TabBarView(
                                controller: _mainTabController,
                                children: [
                                  _buildFinancialList('Client', memberName: null),
                                  _buildSubcontractorContent(),
                                  _buildSupplierContent(),
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

  Widget _buildSubcontractorContent() {
    final subs = _currentProject.teamMembers.where((m) => m.role == 'subcontractor').toList();
    if (subs.isEmpty) {
      return Center(
        child: _buildEmptyMemberSection(context.l10n.subcontractorsPlural, _navigateToEditProject),
      );
    }
    if (_selectedSubcontractor == null) {
      return _buildMembersList(subs, (name) => setState(() => _selectedSubcontractor = name));
    } else {
      return _buildSelectedMemberSection(
        'Subcontractor',
        _selectedSubcontractor!,
        () => setState(() => _selectedSubcontractor = null),
      );
    }
  }

  Widget _buildSupplierContent() {
    final suppliers = _currentProject.teamMembers.where((m) => m.role == 'supplier').toList();
    if (suppliers.isEmpty) {
      return Center(
        child: _buildEmptyMemberSection(context.l10n.suppliersPlural, _navigateToEditProject),
      );
    }
    if (_selectedSupplier == null) {
      return _buildMembersList(suppliers, (name) => setState(() => _selectedSupplier = name));
    } else {
      return _buildSelectedMemberSection(
        'Supplier',
        _selectedSupplier!,
        () => setState(() => _selectedSupplier = null),
      );
    }
  }

  Widget _buildMembersList(List<TeamMember> members, Function(String) onSelected) {
    return ListView.separated(
      itemCount: members.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final member = members[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF0A2E5A),
            child: Text(
              member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(member.name, style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${teamRoleLabel(member.role)}${member.category != null ? ' - ${member.category}' : ''}',
            style: TextStyle(color: AppColors.inkMuted),
          ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () => onSelected(member.name),
        );
      },
    );
  }

  Widget _buildSelectedMemberSection(String role, String memberName, VoidCallback onBack) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.surfaceMuted,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
              ),
              Expanded(
                child: Text(
                  context.l10n.financialDocsForMember(memberName),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildFinancialList(role, memberName: memberName),
        ),
      ],
    );
  }

  Widget _buildEmptyMemberSection(String title, VoidCallback onEdit) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            context.l10n.noMembersOfRoleYet(title),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.addMembersViaEdit,
            style: TextStyle(color: AppColors.inkMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit),
            label: Text(context.l10n.goToEditProject),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0A2E5A),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

Widget _buildFinancialList(String role, {String? memberName}) {
  Query query = FirebaseFirestore.instance
      .collection('Financials')
      .where('projectId', isEqualTo: _currentProject.id)
      .where('role', isEqualTo: role)
      .orderBy('uploadedAt', descending: true);

    if (memberName != null) {
      query = query.where('teamMemberName', isEqualTo: memberName);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          widget.logger.e('Firestore error: ${snapshot.error}');

          // Check if it's an index error
          if (snapshot.error.toString().contains('index')) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_sync, size: 64, color: const Color.fromARGB(255, 5, 135, 68)),
                    const SizedBox(height: 16),
                    Text(
                      context.l10n.indexBeingCreated,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.indexBeingCreatedHint,
                      style: TextStyle(color: AppColors.inkMuted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return Center(
            child: Text(
              context.l10n.couldNotLoadFinancialDocs,
              style: TextStyle(color: Colors.red[600]),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        return ListView(
          children: [
            if (docs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Text(
                    context.l10n.noFinancialDocsInSection,
                    style: TextStyle(color: AppColors.inkMuted),
                  ),
                ),
              )
            else
              ...docs.map((doc) {
                final docData = doc.data() as Map<String, dynamic>;
                final docId = doc.id;
                final title = docData['title'] as String;
                final fileName = docData['fileName'] as String;
                final url = docData['url'] as String;
                final type = path.extension(fileName).substring(1).toLowerCase();

                return ListTile(
                  leading: Icon(_getDocumentIcon(type), color: _getFileIconColor(type)),
                  title: Text(title, style: TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    context.l10n.fileUploadedOn(fileName, _formatDate(docData['uploadedAt'] as Timestamp)),
                    style: TextStyle(color: AppColors.inkMuted),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'view') {
                        _viewDocument(url, type, title);
                      } else if (value == 'download') {
                        _downloadDocument(url, fileName);
                      } else if (value == 'delete') {
                        _deleteDocument(docId, url);
                      }
                    },
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
                );
              }),
          ],
        );
      },
    );
  }

  Future<void> _fetchUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        widget.logger.e('❌ FinancialScreen: No authenticated user found');
        setState(() {
          _userRole = 'Client';
          _isLoadingUserData = false;
        });
        return;
      }

      final querySnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final userData = querySnapshot.docs.first.data();
        final role = userData['role'] as String? ?? 'Client';

        if (mounted) {
          setState(() {
            _userRole = role;
            _isLoadingUserData = false;
          });
        }

        widget.logger.i('✅ FinancialScreen: User role fetched: $role');
      } else {
        widget.logger.w('⚠️ FinancialScreen: User document not found');
        if (mounted) {
          setState(() {
            _userRole = 'Client';
            _isLoadingUserData = false;
          });
        }
      }
    } catch (e) {
      widget.logger.e('❌ FinancialScreen: Error fetching user role: $e');
      if (mounted) {
        setState(() {
          _userRole = 'Client';
          _isLoadingUserData = false;
        });
      }
    }
  }

  Future<void> _addFinancialDocument() async {
    // Determine if user is a client
    final bool isClient = _userRole == 'Client';

    String role;
    String? teamMemberName;

    if (isClient) {
      // Clients can only upload to Client tab
      role = 'Client';
      teamMemberName = null;
    } else {
      // Admins can upload to any tab
      final roleIndex = _mainTabController.index;
      role = _mainTabs[roleIndex];

      if (role == 'Client') {
        teamMemberName = null;
      } else if (role == 'Subcontractor') {
        if (_selectedSubcontractor == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.selectSubcontractorFirst)),
            );
          }
          return;
        }
        teamMemberName = _selectedSubcontractor;
      } else { // Supplier
        if (_selectedSupplier == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.selectSupplierFirst)),
            );
          }
          return;
        }
        teamMemberName = _selectedSupplier;
      }
    }

    widget.logger.i('📤 FinancialScreen: Initiating add document to $role${teamMemberName != null ? ' - $teamMemberName' : ''}');

    widget.logger.d('📤 FinancialScreen: Picking file...');
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'pptx', 'txt', 'doc', 'ppt', 'xlsx', 'xls'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      widget.logger.w('📤 FinancialScreen: No document selected');
      return;
    }

    final platformFile = result.files.single;
    final fileName = platformFile.name;
    final extension = path.extension(fileName).substring(1).toLowerCase();
    Uint8List? fileBytes;

    if (platformFile.bytes != null) {
      fileBytes = platformFile.bytes!;
      widget.logger.d('📤 FinancialScreen: File bytes available (web)');
    } else if (!kIsWeb && platformFile.path != null) {
      final file = File(platformFile.path!);
      fileBytes = await file.readAsBytes();
      widget.logger.d('📤 FinancialScreen: File read from path (mobile/desktop)');
    }

    if (fileBytes == null) {
      throw UserFacingException(l10nNow.couldNotReadFile);
    }

    final title = await _getDocumentTitle(fileName);
    if (title == null) {
      widget.logger.d('📤 FinancialScreen: Add document cancelled - no title provided');
      return;
    }

    if (!mounted) return;
    final bool? confirmUpload = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.confirmUpload, style: TextStyle()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getDocumentIcon(extension),
              size: 48,
              color: _getFileIconColor(extension),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.uploadFileConfirm(fileName),
              style: TextStyle(),
              textAlign: TextAlign.center,
            ),
            Text(
              context.l10n.fileSizeMb((fileBytes!.length / 1024 / 1024).toStringAsFixed(2)),
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel, style: TextStyle()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.upload, style: TextStyle()),
          ),
        ],
      ),
    );

    if (confirmUpload != true) {
      widget.logger.d('📤 FinancialScreen: Upload cancelled by user');
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    UploadTask? uploadTask;
    final GlobalKey<State> dialogKey = GlobalKey<State>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        key: dialogKey,
        title: Text(context.l10n.uploadingNamed(fileName), style: TextStyle()),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: _uploadProgress,
                  backgroundColor: Colors.grey[300],
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueGrey),
                ),
                const SizedBox(height: 16),
                Text(
                  _uploadProgress != null
                      ? '${(_uploadProgress! * 100).toStringAsFixed(0)}%'
                      : context.l10n.startingUpload,
                  style: TextStyle(),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (uploadTask != null) {
                await uploadTask.cancel();
                widget.logger.d('📤 FinancialScreen: Upload cancelled by user');
              }
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: Text(context.l10n.cancel, style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('${_currentProject.id}/Financials/${timestamp}_$fileName');

      final metadata = SettableMetadata(
        contentType: _getContentType(extension),
        customMetadata: {
          'projectId': _currentProject.id,
          'role': role,
          'title': title,
          'teamMemberName': teamMemberName ?? '',
          'platform': kIsWeb ? 'web' : Platform.operatingSystem,
        },
      );

      uploadTask = storageRef.putData(fileBytes, metadata);

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        if (mounted) {
          setState(() {
            _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
          });
        }
      }, onError: (e) {
        widget.logger.e('Upload progress error: $e');
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(friendlyError(e, action: context.l10n.couldNotUpload), style: TextStyle()),
            ),
          );
        }
      });

      await uploadTask;
      final url = await storageRef.getDownloadURL();
      widget.logger.d('📤 FinancialScreen: Upload complete, URL obtained');

      await FirebaseFirestore.instance
          .collection('Financials')
          .add({
        'projectId': _currentProject.id,
        'projectName': _currentProject.name,
        'title': title,
        'fileName': fileName,
        'url': url,
        'role': role,
        'teamMemberName': teamMemberName ?? '',
        'uploadedAt': Timestamp.now(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.financialDocAdded(title), style: TextStyle()),
          ),
        );
        widget.logger.i('✅ FinancialScreen: Document uploaded successfully: $fileName with title $title');
      }
    } on FirebaseException catch (e) {
      if (e.code == 'canceled') {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.uploadCancelled, style: TextStyle()),
            ),
          );
        }
      } else {
        widget.logger.e('❌ FinancialScreen: Error adding document', error: e);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(friendlyError(e, action: context.l10n.couldNotAddDocument), style: TextStyle()),
            ),
          );
        }
      }
    } catch (e) {
      widget.logger.e('❌ FinancialScreen: Error adding document', error: e);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, action: context.l10n.couldNotAddDocument), style: TextStyle()),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _uploadProgress = null;
        });
      }
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
      case 'xlsx':
      case 'xls':
        return Icons.table_chart;
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
      case 'xlsx':
      case 'xls':
        return Colors.green[600]!;
      default:
        return Colors.grey[600]!;
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
              labelText: context.l10n.financialTitleHint,
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
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'xls':
        return 'application/vnd.ms-excel';
      default:
        return 'application/octet-stream';
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
    widget.logger.i('👀 FinancialScreen: Viewing document: $name ($type)');
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

  Future<void> _deleteDocument(String docId, String url) async {
    widget.logger.i('🗑️ FinancialScreen: Deleting document: $docId');

    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteDocumentTitle, style: TextStyle()),
        content: Text(
          context.l10n.deleteFinancialDocConfirm,
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

    if (confirmDelete != true) return;

    try {
      widget.logger.d('🗑️ FinancialScreen: Deleting from storage');
      final ref = FirebaseStorage.instance.refFromURL(url);
      await ref.delete();
      widget.logger.d('🗑️ FinancialScreen: Deleting from Firestore');
      await FirebaseFirestore.instance
          .collection('Financials')
          .doc(docId)
          .delete();
      if (mounted) {
        widget.logger.i('✅ FinancialScreen: Document deleted successfully');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.financialDocDeleted, style: TextStyle()),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      widget.logger.e('❌ FinancialScreen: Error deleting document', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, action: context.l10n.couldNotDeleteDocument), style: TextStyle()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(Timestamp timestamp) {
    return DateFormat.yMd().format(timestamp.toDate());
  }
}