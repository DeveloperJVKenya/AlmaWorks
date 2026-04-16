import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'dart:math' show pi, min, max;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

// ══════════════════════════════════════════════════════════════════
// CHECKLIST ITEM MODEL
// ══════════════════════════════════════════════════════════════════
class ChecklistItem {
  String label;
  bool checked;

  ChecklistItem({required this.label, this.checked = false});

  Map<String, dynamic> toMap() => {'label': label, 'checked': checked};

  factory ChecklistItem.fromMap(Map<String, dynamic> m) => ChecklistItem(
        label: m['label'] ?? '',
        checked: m['checked'] ?? false,
      );
}

// ══════════════════════════════════════════════════════════════════
// ATTENDANCE ROW MODEL
// ══════════════════════════════════════════════════════════════════
class AttendanceRow {
  String? companyName;
  String name;
  String title;
  String signature;

  AttendanceRow({
    this.companyName,
    this.name = '',
    this.title = '',
    this.signature = '',
  });

  Map<String, dynamic> toMap() => {
        if (companyName != null) 'companyName': companyName,
        'name': name,
        'title': title,
        'signature': signature,
      };

  factory AttendanceRow.fromMap(Map<String, dynamic> m,
          {bool isSubContractor = false}) =>
      AttendanceRow(
        companyName:
            isSubContractor ? (m['companyName'] ?? '') : null,
        name: m['name'] ?? '',
        title: m['title'] ?? '',
        signature: m['signature'] ?? '',
      );
}

// ══════════════════════════════════════════════════════════════════
// ATTENDANCE TABLE DATA MODEL  (flexible key-value rows)
// ══════════════════════════════════════════════════════════════════
class AttendanceTableData {
  String title;
  List<String> columnNames;
  List<Map<String, String>> rows;
  bool showRowNumbers;

  AttendanceTableData({
    required this.title,
    required this.columnNames,
    required this.rows,
    this.showRowNumbers = true,
  });

  Map<String, dynamic> toMap() => {
        'title': title,
        'columnNames': columnNames,
        'rows': rows,
        'showRowNumbers': showRowNumbers,
      };

  factory AttendanceTableData.fromMap(Map<String, dynamic> m) =>
      AttendanceTableData(
        title: m['title'] ?? '',
        columnNames: List<String>.from(m['columnNames'] ?? []),
        rows: (m['rows'] as List<dynamic>?)
                ?.map((r) => Map<String, String>.from(r as Map))
                .toList() ??
            [],
        showRowNumbers: m['showRowNumbers'] as bool? ?? true,
      );
}

// ══════════════════════════════════════════════════════════════════
// SAFETY REPORT DATA MODEL
// ══════════════════════════════════════════════════════════════════
class SafetyReportData {
  final String id;
  final String projectId;
  final String projectName;
  String contractNumber;
  String building;
  DateTime reportDate;
  String type;
  List<ChecklistItem> checklistItems;
  String observationsJson;
  String actionsJson;
  List<AttendanceRow> jvAlmaRows;
  List<AttendanceRow> subContractorRows;
  List<String> imageUrls;
  bool isDraft;
  DateTime? savedAt;
  /// Firebase Storage download URL of the generated PDF.
  /// Stored so the list screen can offer Open/Download for form-filled reports.
  String? fileUrl;

  SafetyReportData({
    required this.id,
    required this.projectId,
    required this.projectName,
    this.contractNumber = '',
    this.building = '',
    required this.reportDate,
    required this.type,
    List<ChecklistItem>? checklistItems,
    this.observationsJson = '',
    this.actionsJson = '',
    List<AttendanceRow>? jvAlmaRows,
    List<AttendanceRow>? subContractorRows,
    this.imageUrls = const [],
    this.isDraft = true,
    this.savedAt,
    this.fileUrl,
  })  : checklistItems = checklistItems ?? _defaultChecklist(),
        jvAlmaRows = jvAlmaRows ?? [],
        subContractorRows = subContractorRows ?? [];

  static List<ChecklistItem> _defaultChecklist() => [
        ChecklistItem(label: 'Housekeeping'),
        ChecklistItem(label: 'Personal Protective Equipment'),
        ChecklistItem(label: 'Fall Protection'),
        ChecklistItem(label: 'Scaffolds'),
        ChecklistItem(label: 'Ladders'),
        ChecklistItem(label: 'Excavations'),
        ChecklistItem(label: 'Electrical'),
        ChecklistItem(label: 'Hand & Power Tools'),
        ChecklistItem(label: 'Fire Protection'),
        ChecklistItem(label: 'Hazard Communication'),
        ChecklistItem(label: 'Cranes & Rigging'),
        ChecklistItem(label: 'Heavy Equipment'),
        ChecklistItem(label: 'Traffic Control'),
        ChecklistItem(label: 'Other'),
      ];

  Map<String, dynamic> toMap() => {
        'id': id,
        'projectId': projectId,
        'projectName': projectName,
        'contractNumber': contractNumber,
        'building': building,
        'reportDate': Timestamp.fromDate(reportDate),
        'type': type,
        'checklistItems': checklistItems.map((i) => i.toMap()).toList(),
        'observationsJson': observationsJson,
        'actionsJson': actionsJson,
        'jvAlmaRows': jvAlmaRows.map((r) => r.toMap()).toList(),
        'subContractorRows': subContractorRows.map((r) => r.toMap()).toList(),
        'imageUrls': imageUrls,
        'isDraft': isDraft,
        'savedAt': Timestamp.now(),
        'type_category': 'Safety',
        if (fileUrl != null) 'fileUrl': fileUrl!,
      };

  factory SafetyReportData.fromMap(Map<String, dynamic> m) {
    final isWeekly = (m['type'] ?? 'SafetyWeekly') == 'SafetyWeekly';
    return SafetyReportData(
      id: m['id'] ?? '',
      projectId: m['projectId'] ?? '',
      projectName: m['projectName'] ?? '',
      contractNumber: m['contractNumber'] ?? '',
      building: m['building'] ?? '',
      reportDate: (m['reportDate'] as Timestamp).toDate(),
      type: m['type'] ?? 'SafetyWeekly',
      checklistItems: (m['checklistItems'] as List<dynamic>? ?? [])
          .map((e) =>
              ChecklistItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      observationsJson: m['observationsJson'] ?? '',
      actionsJson: m['actionsJson'] ?? '',
      jvAlmaRows: (m['jvAlmaRows'] as List<dynamic>? ?? [])
          .map((e) =>
              AttendanceRow.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      subContractorRows: isWeekly
          ? (m['subContractorRows'] as List<dynamic>? ?? [])
              .map((e) => AttendanceRow.fromMap(
                  Map<String, dynamic>.from(e as Map),
                  isSubContractor: true))
              .toList()
          : [],
      imageUrls: List<String>.from(m['imageUrls'] ?? []),
      isDraft: m['isDraft'] ?? true,
      fileUrl: m['fileUrl'] as String?,
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// SAFETY FORM SCREEN
// ══════════════════════════════════════════════════════════════════
class SafetyFormScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final SafetyReportData? existingReport;
  final bool isReadOnly;

  const SafetyFormScreen({
    super.key,
    required this.project,
    required this.logger,
    this.existingReport,
    this.isReadOnly = false,
  });

  @override
  State<SafetyFormScreen> createState() => _SafetyFormScreenState();
}

class _SafetyFormScreenState extends State<SafetyFormScreen> {
  // ── Design constants ──────────────────────────────────────────
  static const _navy = Color(0xFF0A2E5A);
  static const _fieldBorder = Color(0xFFB0BEC5);
  static const _gap = 16.0;

  // ── Controllers ───────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();
  final _contractCtrl = TextEditingController();
  final _buildingCtrl = TextEditingController();
  late quill.QuillController _observationsCtrl;
  late quill.QuillController _actionsCtrl;

  // ── Checklist ─────────────────────────────────────────────────
  late List<ChecklistItem> _checklistItems;
  final List<TextEditingController> _checklistLabelCtrls = [];

  // ── Attendance Tables ─────────────────────────────────────────
  late AttendanceTableData _jvAlmaTable;
  late AttendanceTableData _subContractorTable;

  // ── Images ────────────────────────────────────────────────────
  final List<Uint8List> _localImages = [];
  final List<String> _savedImageUrls = [];

  // ── Signature bytes cache (table.title → rowIdx → PNG bytes) ──
  final Map<String, Map<int, Uint8List>> _sigBytes = {};

  // ── State flags ───────────────────────────────────────────────
  bool _isReadOnly = false;
  bool _isSaving = false;
  bool _isGeneratingPdf = false;

  // ── Saved PDF URL (Firebase Storage) ───────────────────────────
  // Populated after first save; lets the list screen show Open/Download
  // for form-filled reports exactly like PDF-uploaded ones.
  String? _savedPdfUrl;

  // ── Report meta ───────────────────────────────────────────────
  late String _reportId;
  late DateTime _reportDate;
  late String _type;

  // ── Cache key ─────────────────────────────────────────────────
  String get _cacheKey =>
      'safety_report_draft_${widget.project.id}_$_reportId';

  // ─────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    widget.logger.i('📋 SafetyForm: initState START');
    _reportId = widget.existingReport?.id ?? const Uuid().v4();
    _isReadOnly = widget.isReadOnly;
    _reportDate = DateTime.now();
    _type = 'SafetyWeekly';

    if (widget.existingReport != null) {
      _loadFromExisting(widget.existingReport!);
    } else {
      _observationsCtrl = quill.QuillController.basic();
      _actionsCtrl = quill.QuillController.basic();
      _checklistItems = List.from(SafetyReportData._defaultChecklist());
      _syncChecklistControllers();
      _initDefaultAttendanceTables();
      _loadDraftFromCache();
    }
    widget.logger.i('📋 SafetyForm: initState END');
  }

  void _loadFromExisting(SafetyReportData r) {
    _contractCtrl.text = r.contractNumber;
    _buildingCtrl.text = r.building;
    _reportDate = r.reportDate;
    _type = r.type;
    _checklistItems = List.from(r.checklistItems);
    _syncChecklistControllers();
    _observationsCtrl = _quillFromJson(r.observationsJson);
    _actionsCtrl = _quillFromJson(r.actionsJson);

    _jvAlmaTable = AttendanceTableData(
      title: 'JV Alma CIS Attendance',
      columnNames: ['Name', 'Title', 'Signature'],
      rows: r.jvAlmaRows
          .map((row) => {
                'Name': row.name,
                'Title': row.title,
                'Signature': row.signature,
              })
          .toList(),
      showRowNumbers: true,
    );

    _subContractorTable = AttendanceTableData(
      title: 'Sub-Contractor Attendance',
      columnNames: ['Company Name', 'Name', 'Title', 'Signature'],
      rows: r.subContractorRows
          .map((row) => {
                'Company Name': row.companyName ?? '',
                'Name': row.name,
                'Title': row.title,
                'Signature': row.signature,
              })
          .toList(),
      showRowNumbers: true,
    );

    _savedImageUrls.addAll(r.imageUrls);
    _savedPdfUrl = r.fileUrl;
  }

  void _initDefaultAttendanceTables() {
    _jvAlmaTable = AttendanceTableData(
      title: 'JV Alma CIS Attendance',
      columnNames: ['Name', 'Title', 'Signature'],
      rows: List.generate(
          4, (_) => {'Name': '', 'Title': '', 'Signature': ''}),
      showRowNumbers: true,
    );
    _subContractorTable = AttendanceTableData(
      title: 'Sub-Contractor Attendance',
      columnNames: ['Company Name', 'Name', 'Title', 'Signature'],
      rows: List.generate(4, (_) => {
            'Company Name': '',
            'Name': '',
            'Title': '',
            'Signature': '',
          }),
      showRowNumbers: true,
    );
  }

  quill.QuillController _quillFromJson(String jsonStr) {
    if (jsonStr.isEmpty) return quill.QuillController.basic();
    try {
      final decoded = jsonDecode(jsonStr);
      return quill.QuillController(
        document: quill.Document.fromJson(decoded as List),
        selection: const TextSelection.collapsed(offset: 0),
      );
    } catch (_) {
      return quill.QuillController.basic();
    }
  }

  // ── Checklist controller sync ─────────────────────────────────
  void _syncChecklistControllers() {
    for (final c in _checklistLabelCtrls) {
      c.dispose();
    }
    _checklistLabelCtrls.clear();
    _checklistLabelCtrls.addAll(
      _checklistItems.map((i) => TextEditingController(text: i.label)),
    );
  }

  @override
  void dispose() {
    widget.logger.i('📋 SafetyForm: dispose');
    _contractCtrl.dispose();
    _buildingCtrl.dispose();
    _observationsCtrl.dispose();
    _actionsCtrl.dispose();
    _scrollCtrl.dispose();
    for (final c in _checklistLabelCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // CACHE
  // ─────────────────────────────────────────────────────────────
  Future<void> _saveDraftToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'contractNumber': _contractCtrl.text,
        'building': _buildingCtrl.text,
        'reportDate': _reportDate.toIso8601String(),
        'type': _type,
        'checklistItems': _checklistItems.map((i) => i.toMap()).toList(),
        'observationsJson':
            jsonEncode(_observationsCtrl.document.toDelta().toJson()),
        'actionsJson':
            jsonEncode(_actionsCtrl.document.toDelta().toJson()),
        'jvAlmaTable': _jvAlmaTable.toMap(),
        'subContractorTable': _subContractorTable.toMap(),
        'imageUrls': _savedImageUrls,
      };
      await prefs.setString(_cacheKey, jsonEncode(data));
      widget.logger.d('📋 SafetyForm: draft cached');
    } catch (e) {
      widget.logger.w('⚠️ SafetyForm: cache save failed – $e');
    }
  }

  Future<void> _loadDraftFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _contractCtrl.text = data['contractNumber'] ?? '';
        _buildingCtrl.text = data['building'] ?? '';
        if (data['reportDate'] != null) {
          _reportDate = DateTime.parse(data['reportDate']);
        }
        _type = data['type'] ?? 'SafetyWeekly';
        _checklistItems = (data['checklistItems'] as List? ?? [])
            .map((e) =>
                ChecklistItem.fromMap(Map<String, dynamic>.from(e)))
            .toList();
        _syncChecklistControllers();
        _observationsCtrl =
            _quillFromJson(data['observationsJson'] ?? '');
        _actionsCtrl = _quillFromJson(data['actionsJson'] ?? '');
        if (data['jvAlmaTable'] != null) {
          _jvAlmaTable =
              AttendanceTableData.fromMap(data['jvAlmaTable']);
        }
        if (data['subContractorTable'] != null) {
          _subContractorTable =
              AttendanceTableData.fromMap(data['subContractorTable']);
        }
        _savedImageUrls.clear();
        _savedImageUrls
            .addAll(List<String>.from(data['imageUrls'] ?? []));
      });
      widget.logger.i('📋 SafetyForm: draft restored from cache');
    } catch (e, st) {
      widget.logger.e('❌ SafetyForm: cache load failed',
          error: e, stackTrace: st);
    }
  }

  Future<void> _clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }

  // ─────────────────────────────────────────────────────────────
  // DATE / TIME PICKERS
  // ─────────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _reportDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
              primary: _navy, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (date == null) return;
    setState(() {
      _reportDate = DateTime(
          date.year, date.month, date.day,
          _reportDate.hour, _reportDate.minute);
    });
    _saveDraftToCache();
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_reportDate),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
              primary: _navy, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (time == null) return;
    setState(() {
      _reportDate = DateTime(_reportDate.year, _reportDate.month,
          _reportDate.day, time.hour, time.minute);
    });
    _saveDraftToCache();
  }

  // ─────────────────────────────────────────────────────────────
  // CHECKLIST MANAGEMENT
  // ─────────────────────────────────────────────────────────────
  void _addChecklistItem() {
    setState(() {
      _checklistItems.add(ChecklistItem(label: 'New Item'));
      _checklistLabelCtrls
          .add(TextEditingController(text: 'New Item'));
    });
    _saveDraftToCache();
  }

  void _removeChecklistItem(int index) {
    if (_checklistItems.length <= 1) { return; }
    setState(() {
      _checklistItems.removeAt(index);
      _checklistLabelCtrls[index].dispose();
      _checklistLabelCtrls.removeAt(index);
    });
    _saveDraftToCache();
  }

  void _updateChecklistLabel(int index, String newLabel) {
    setState(() => _checklistItems[index].label = newLabel);
    _saveDraftToCache();
  }

  // ─────────────────────────────────────────────────────────────
  // IMAGES
  // ─────────────────────────────────────────────────────────────
  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 80);
    if (picked.isEmpty) return;
    for (final xf in picked) {
      final bytes = await xf.readAsBytes();
      setState(() => _localImages.add(bytes));
    }
    widget.logger.i('📋 SafetyForm: ${picked.length} image(s) added');
  }

  void _showImageViewer(List<_SImageItem> images, int initialIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => _SImageViewerDialog(
          images: images, initialIndex: initialIndex),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SAVE
  // ─────────────────────────────────────────────────────────────
  Future<SafetyReportData> _buildReportData() async {
    // ── Upload any pending in-memory signature bytes ──────────────
    for (final tableEntry in _sigBytes.entries) {
      final tableTitle = tableEntry.key;
      final rowMap = tableEntry.value;
      final tableRef = tableTitle.contains('JV')
          ? _jvAlmaTable
          : _subContractorTable;
      for (final rowEntry in rowMap.entries) {
        final rowIdx = rowEntry.key;
        final bytes = rowEntry.value;
        try {
          final ref = FirebaseStorage.instance
              .ref()
              .child(widget.project.id)
              .child('Reports')
              .child('Safety')
              .child('signatures')
              .child(
                  '${_reportId}_${tableTitle.replaceAll(' ', '_')}_row$rowIdx.png');
          await ref.putData(bytes,
              SettableMetadata(contentType: 'image/png'));
          final url = await ref.getDownloadURL();
          if (rowIdx < tableRef.rows.length) {
            tableRef.rows[rowIdx]['Signature'] = url;
          }
        } catch (e) {
          widget.logger
              .w('⚠️ SafetyForm: sig upload failed row=$rowIdx – $e');
        }
      }
    }

    final List<String> allUrls = List.from(_savedImageUrls);
    for (int i = 0; i < _localImages.length; i++) {
      final ref = FirebaseStorage.instance
          .ref()
          .child(widget.project.id)
          .child('Reports')
          .child('Safety')
          .child('images')
          .child('${_reportId}_img_$i.jpg');
      await ref.putData(
          _localImages[i],
          SettableMetadata(contentType: 'image/jpeg'));
      allUrls.add(await ref.getDownloadURL());
    }

    return SafetyReportData(
      id: _reportId,
      projectId: widget.project.id,
      projectName: widget.project.name,
      contractNumber: _contractCtrl.text.trim(),
      building: _buildingCtrl.text.trim(),
      reportDate: _reportDate,
      type: _type,
      checklistItems: _checklistItems,
      observationsJson:
          jsonEncode(_observationsCtrl.document.toDelta().toJson()),
      actionsJson:
          jsonEncode(_actionsCtrl.document.toDelta().toJson()),
      jvAlmaRows: _jvAlmaTable.rows
          .map((map) => AttendanceRow(
                name: map['Name'] ?? '',
                title: map['Title'] ?? '',
                signature: map['Signature'] ?? '',
              ))
          .toList(),
      subContractorRows: _type == 'SafetyWeekly'
          ? _subContractorTable.rows
              .map((map) => AttendanceRow(
                    companyName: map['Company Name'],
                    name: map['Name'] ?? '',
                    title: map['Title'] ?? '',
                    signature: map['Signature'] ?? '',
                  ))
              .toList()
          : [],
      imageUrls: allUrls,
      isDraft: false,
    );
  }

  Future<void> _saveReport({bool silent = false}) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await _saveDraftToCache();
      final report = await _buildReportData();
      final map = report.toMap();

      if (widget.existingReport == null) {
        map['uploadedAt'] = Timestamp.now();
        map['name'] =
            'Safety Report – ${DateFormat('dd MMM yyyy HH:mm').format(_reportDate)}';
        await FirebaseFirestore.instance
            .collection('Reports')
            .doc(_reportId)
            .set(map);
      } else {
        await FirebaseFirestore.instance
            .collection('Reports')
            .doc(_reportId)
            .update(map);
      }

      // ── Generate PDF → upload to Firebase Storage → write fileUrl ─────────
      // Gives form-filled reports a fileUrl identical to PDF-uploaded ones
      // so the list screen can show Open / Download menu actions.
      try {
        final pdfUrl = await _generateAndUploadPdf(report);
        if (pdfUrl != null) {
          setState(() => _savedPdfUrl = pdfUrl);
          await FirebaseFirestore.instance
              .collection('Reports')
              .doc(_reportId)
              .update({'fileUrl': pdfUrl});
          widget.logger.i('✅ SafetyForm: PDF uploaded → \$pdfUrl');
        }
      } catch (pdfErr) {
        // Non-fatal — PDF failure must not block the overall save.
        widget.logger.w('⚠️ SafetyForm: PDF upload after save failed – \$pdfErr');
      }

      await _clearCache();
      _localImages.clear();

      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Safety report saved successfully.',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e, st) {
      widget.logger.e('❌ SafetyForm: save failed',
          error: e, stackTrace: st);
      if (mounted) _showError('Error saving report: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins()),
      backgroundColor: Colors.red[700],
    ));
  }

  // ─────────────────────────────────────────────────────────────
  // PDF GENERATION
  // ─────────────────────────────────────────────────────────────
  // _downloadAsPdf re-uses _buildPdfBytes so save-time generation
  // and on-demand download always produce an identical document.
  Future<void> _downloadAsPdf() async {
    widget.logger.i('📋 SafetyForm: _downloadAsPdf START');
    setState(() => _isGeneratingPdf = true);
    try {
      final report = await _buildReportData();
      final typeLabel =
          report.type == 'SafetyWeekly' ? 'Weekly' : 'Monthly';
      final fileName =
          'Safety_${typeLabel}_Report_${report.projectName.replaceAll(' ', '_')}'
          '_${DateFormat('yyyyMMdd_HHmm').format(report.reportDate)}.pdf';

      if (_savedPdfUrl != null) {
        // Re-use the PDF already stored in Firebase Storage so we never
        // regenerate an identical document unnecessarily.
        widget.logger.i('📋 SafetyForm: reusing saved PDF URL');
        await _openOrDownloadFromUrl(_savedPdfUrl!, fileName);
      } else {
        // No saved URL yet — build and save/share locally.
        final bytes = await _buildPdfBytes(report);
        if (bytes != null) await _savePdfBytes(bytes, fileName);
      }
      widget.logger.i('✅ SafetyForm: _downloadAsPdf done → $fileName');
    } catch (e, st) {
      widget.logger.e('❌ SafetyForm: PDF failed',
          error: e, stackTrace: st);
      if (mounted) _showError('Error generating PDF: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  /// Downloads the cloud PDF at [url] from Firebase Storage and opens it
  /// locally via [_savePdfBytes], giving the user the same Open + snackbar
  /// experience regardless of whether the PDF was just built or retrieved.
  Future<void> _openOrDownloadFromUrl(String url, String fileName) async {
    final data = await FirebaseStorage.instance
        .refFromURL(url)
        .getData(50 * 1024 * 1024);
    if (data != null) {
      await _savePdfBytes(Uint8List.fromList(data), fileName);
    }
  }

  /// Saves [bytes] as [fileName] to the platform Downloads folder (or
  /// Documents on iOS), opens it with [OpenFile], and shows a snackbar.
  /// Falls back to [Printing.sharePdf] when direct file access fails.
  /// Mirrors [MonthlyReportFormScreen._savePdfBytes] exactly.
  Future<void> _savePdfBytes(Uint8List bytes, String fileName) async {
    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
      return;
    }
    try {
      String dirPath;
      if (defaultTargetPlatform == TargetPlatform.android) {
        const androidDownloads = '/storage/emulated/0/Download';
        if (await Directory(androidDownloads).exists()) {
          dirPath = androidDownloads;
        } else {
          final ext = await getExternalStorageDirectory();
          if (ext != null) {
            final parts = ext.path.split('/');
            final idx = parts.indexOf('Android');
            final base =
                idx > 0 ? parts.sublist(0, idx).join('/') : ext.path;
            dirPath = '$base/Download';
          } else {
            dirPath = (await getApplicationDocumentsDirectory()).path;
          }
        }
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        dirPath = (await getApplicationDocumentsDirectory()).path;
      } else {
        final homeDir = Platform.environment['USERPROFILE'] ??
            Platform.environment['HOME'];
        dirPath = homeDir != null && homeDir.isNotEmpty
            ? '$homeDir${Platform.pathSeparator}Downloads'
            : (await getApplicationDocumentsDirectory()).path;
      }
      final dir = Directory(dirPath);
      if (!await dir.exists()) await dir.create(recursive: true);
      final filePath = '$dirPath${Platform.pathSeparator}$fileName';
      await File(filePath).writeAsBytes(bytes);
      await OpenFile.open(filePath);
      final ctx = context;
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('PDF saved: $fileName',
            style: GoogleFonts.poppins()),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    }
  }

  /// Builds the PDF for [report] and uploads it to Firebase Storage.
  /// Returns the public download URL, or null on failure.
  /// Called from [_saveReport] so every saved report immediately gets a
  /// fileUrl, enabling Open / Download in the list screen.
  Future<String?> _generateAndUploadPdf(SafetyReportData report) async {
    widget.logger.i('📋 SafetyForm: _generateAndUploadPdf START');
    final bytes = await _buildPdfBytes(report);
    if (bytes == null) return null;
    final typeLabel =
        report.type == 'SafetyWeekly' ? 'Weekly' : 'Monthly';
    final fileName =
        'Safety_${typeLabel}_Report_${report.projectName.replaceAll(' ', '_')}'
        '_${DateFormat('yyyyMMdd_HHmm').format(report.reportDate)}.pdf';
    final ref = FirebaseStorage.instance
        .ref()
        .child(widget.project.id)
        .child('Reports')
        .child('Safety')
        .child('pdf')
        .child(fileName);
    await ref.putData(
        bytes, SettableMetadata(contentType: 'application/pdf'));
    return await ref.getDownloadURL();
  }

  /// Builds and returns the raw PDF bytes for [report].
  /// Single source of truth for the PDF layout — both [_generateAndUploadPdf]
  /// (called at save time) and the fallback path in [_downloadAsPdf] use this.
  Future<Uint8List?> _buildPdfBytes(SafetyReportData report) async {
    try {
      final typeLabel =
          report.type == 'SafetyWeekly' ? 'Weekly' : 'Monthly';

      // ── Load Unicode-capable TTF fonts ────────────────────────
      // Roboto supports hyphens (U+2013 –), bullets (U+2022 •),
      // checkmarks (U+2713 ✓) and all other Latin extended chars
      // that Helvetica (a Type-1 font) cannot render.
      final robotoRegularFont =
          await PdfGoogleFonts.robotoRegular();
      final robotoBoldFont =
          await PdfGoogleFonts.robotoBold();

      // ── Gather images ─────────────────────────────────────────
      final List<pw.MemoryImage> pdfImages = [];
      for (final b in _localImages) {
        pdfImages.add(pw.MemoryImage(b));
      }
      for (final url in _savedImageUrls) {
        try {
          final data = await FirebaseStorage.instance
              .refFromURL(url)
              .getData(10 * 1024 * 1024);
          if (data != null) pdfImages.add(pw.MemoryImage(data));
        } catch (_) {}
      }

      // ── Quill plain text ──────────────────────────────────────
      final observationsText =
          _observationsCtrl.document.toPlainText().trim();
      final actionsText =
          _actionsCtrl.document.toPlainText().trim();

      // ── PDF Colours ───────────────────────────────────────────
      final navyColor      = PdfColor.fromHex('#0A2E5A');
      final lightBlue      = PdfColor.fromHex('#E8EEF6');
      final checkedGreen   = PdfColor.fromHex('#1B5E20');
      final checkedGreenBg = PdfColor.fromHex('#E8F5E9');
      final emptyFieldGrey = PdfColors.grey400;

      // ── PDF Text Styles (all use Roboto for full Unicode) ─────
      final sectionHeaderStyle = pw.TextStyle(
        font: robotoBoldFont,
        fontSize: 9.5,
        color: PdfColors.white,
        letterSpacing: 0.5,
      );
      final tableHeaderStyle = pw.TextStyle(
        font: robotoBoldFont,
        fontSize: 8,
        color: PdfColors.white,
      );
      final cellStyle = pw.TextStyle(
        font: robotoRegularFont,
        fontSize: 8.5,
        color: PdfColors.black,
      );
      final fieldLabelStyle = pw.TextStyle(
        font: robotoBoldFont,
        fontSize: 8,
        color: navyColor,
        letterSpacing: 0.3,
      );
      final fieldValueStyle = pw.TextStyle(
        font: robotoRegularFont,
        fontSize: 9,
        color: PdfColors.black,
      );
      final emptyValueStyle = pw.TextStyle(
        font: robotoRegularFont,
        fontSize: 9,
        color: emptyFieldGrey,
      );

      // ── "Empty field" placeholder widget ─────────────────────
      // Renders a light-grey dash (—) for unfilled single-line text.
      pw.Widget emptyFieldPlaceholder() => pw.Text('\u2014',
          style: emptyValueStyle); // U+2014 em-dash

      // ── "Missing element" placeholder widget ─────────────────
      // Renders a small rectangle with a cross inside, used when
      // an element cannot be rendered (truly missing data).
      /*pw.Widget missingElementBox({double size = 10}) {
        return pw.SizedBox(
          width: size,
          height: size,
          child: pw.CustomPaint(
            painter: (canvas, sizeArg) {
              // Outer border
              canvas
                ..setStrokeColor(PdfColors.grey500)
                ..setLineWidth(0.8)
                ..drawRect(0, 0, sizeArg.x, sizeArg.y)
                ..strokePath();
              // Diagonal cross
              canvas
                ..setLineWidth(0.7)
                ..moveTo(1.5, 1.5)
                ..lineTo(sizeArg.x - 1.5, sizeArg.y - 1.5)
                ..strokePath()
                ..moveTo(sizeArg.x - 1.5, 1.5)
                ..lineTo(1.5, sizeArg.y - 1.5)
                ..strokePath();
            },
          ),
        );
      }*/

      // ── Checkbox widget drawn via CustomPaint (no Unicode) ────
      // Renders exactly as the form checkbox: white square with
      // a thick navy checkmark when checked, plain border when not.
      pw.Widget pdfCheckbox(bool checked, {double size = 11}) {
        return pw.SizedBox(
          width: size,
          height: size,
          child: pw.CustomPaint(
            painter: (canvas, sizeArg) {
              final w = sizeArg.x;
              final h = sizeArg.y;
              if (checked) {
                // Filled navy square
                canvas
                  ..setFillColor(navyColor)
                  ..drawRect(0, 0, w, h)
                  ..fillPath();
                // White checkmark (✓ shape: two strokes)
                // PDF canvas Y=0 is at the BOTTOM of the box, so Y values
                // are the mirror image of screen coordinates:
                //   short left leg:  left-middle → down-centre tick
                //     screen (Y↓): h*0.50 → h*0.78   ← goes DOWN visually
                //     PDF    (Y↑): h*0.50 → h*0.22   ← same visual result
                //   long right arm: down-centre tick → upper-right corner
                //     screen (Y↓): h*0.78 → h*0.22   ← goes UP visually
                //     PDF    (Y↑): h*0.22 → h*0.78   ← same visual result
                canvas
                  ..setStrokeColor(PdfColors.white)
                  ..setLineWidth(1.4)
                  ..setLineCap(PdfLineCap.round)
                  ..setLineJoin(PdfLineJoin.round)
                  ..moveTo(w * 0.15, h * 0.50)
                  ..lineTo(w * 0.40, h * 0.22)
                  ..lineTo(w * 0.85, h * 0.78)
                  ..strokePath();
              } else {
                // White square with grey border
                canvas
                  ..setFillColor(PdfColors.white)
                  ..drawRect(0, 0, w, h)
                  ..fillPath()
                  ..setStrokeColor(PdfColors.grey400)
                  ..setLineWidth(0.8)
                  ..drawRect(0, 0, w, h)
                  ..strokePath();
              }
            },
          ),
        );
      }

      // ── Reusable PDF widget builders ──────────────────────────
      pw.Widget sectionBar(String label) => pw.Container(
            width: double.infinity,
            color: navyColor,
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 8, vertical: 5),
            child: pw.Text(label, style: sectionHeaderStyle),
          );

      pw.Widget metaCellFilled(String label, String value) =>
          pw.Expanded(
            child: pw.Container(
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: PdfColors.blueGrey300, width: 0.5)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: double.infinity,
                    color: lightBlue,
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 5, vertical: 3),
                    child: pw.Text(label, style: fieldLabelStyle),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 5, vertical: 5),
                    child: value.isEmpty
                        ? emptyFieldPlaceholder()
                        : pw.Text(value, style: fieldValueStyle),
                  ),
                ],
              ),
            ),
          );

      // ── Signature images for PDF ──────────────────────────────
      // Priority: in-memory _sigBytes cache → Firebase download.
      final Map<String, Map<int, pw.MemoryImage>> pdfSigImages = {};

      Future<void> collectSigImages(AttendanceTableData td) async {
        for (int ri = 0; ri < td.rows.length; ri++) {
          Uint8List? bytes;
          if (_sigBytes[td.title]?[ri] != null) {
            bytes = _sigBytes[td.title]![ri];
            widget.logger.d(
                '🖊 PDF sig: ${td.title} row $ri – using cached bytes'
                ' (${bytes!.length} bytes)');
          } else {
            final sigVal = td.rows[ri]['Signature'] ?? '';
            if (sigVal.startsWith('http')) {
              try {
                bytes = await FirebaseStorage.instance
                    .refFromURL(sigVal)
                    .getData(5 * 1024 * 1024);
                widget.logger.d(
                    '🖊 PDF sig: ${td.title} row $ri – downloaded from'
                    ' Firebase (${bytes?.length ?? 0} bytes)');
              } catch (e) {
                widget.logger.w(
                    '⚠️ PDF sig: ${td.title} row $ri – Firebase download'
                    ' failed: $e');
              }
            }
          }
          if (bytes != null && bytes.isNotEmpty) {
            pdfSigImages.putIfAbsent(td.title, () => {});
            pdfSigImages[td.title]![ri] = pw.MemoryImage(bytes);
          }
        }
      }

      await collectSigImages(_jvAlmaTable);
      await collectSigImages(_subContractorTable);
      widget.logger.i(
          '🖊 PDF sig: collected images for '
          '${pdfSigImages.values.fold(0, (s, m) => s + m.length)}'
          ' signature(s)');

      // ── Attendance table builder ──────────────────────────────
      pw.Widget buildAttendanceTable(
          AttendanceTableData td, pw.TextStyle headerStyle,
          pw.TextStyle bodyStyle) {
        final cols = td.columnNames;
        if (cols.isEmpty || td.rows.isEmpty) {
          return pw.Container(
            width: double.infinity,
            height: 30,
            decoration: pw.BoxDecoration(
                border: pw.Border.all(
                    color: PdfColors.blueGrey300, width: 0.5)),
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 8, vertical: 8),
            child: pw.Text('No entries',
                style: pw.TextStyle(
                    font: robotoRegularFont,
                    fontSize: 8,
                    color: PdfColors.grey400)),
          );
        }
        final colWidths = <int, pw.TableColumnWidth>{};
        if (td.showRowNumbers) {
          colWidths[0] = const pw.FixedColumnWidth(20);
          for (var i = 0; i < cols.length; i++) {
            colWidths[i + 1] = cols[i] == 'Signature'
                ? const pw.FlexColumnWidth(1.4)
                : const pw.FlexColumnWidth(1);
          }
        } else {
          for (var i = 0; i < cols.length; i++) {
            colWidths[i] = cols[i] == 'Signature'
                ? const pw.FlexColumnWidth(1.4)
                : const pw.FlexColumnWidth(1);
          }
        }
        final headerCells = <pw.Widget>[];
        if (td.showRowNumbers) {
          headerCells.add(pw.Container(
            color: navyColor,
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text('#', style: headerStyle),
          ));
        }
        for (final col in cols) {
          headerCells.add(pw.Container(
            color: navyColor,
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(col, style: headerStyle),
          ));
        }
        final dataRows = <pw.TableRow>[];
        for (var ri = 0; ri < td.rows.length; ri++) {
          final rowData = td.rows[ri];
          final bg = ri.isEven
              ? PdfColors.white
              : PdfColor.fromHex('#F5F7FA');
          final cells = <pw.Widget>[];
          if (td.showRowNumbers) {
            cells.add(pw.Container(
              color: bg,
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('${ri + 1}', style: bodyStyle),
            ));
          }
          for (final col in cols) {
            if (col == 'Signature') {
              final sigImg = pdfSigImages[td.title]?[ri];
              cells.add(pw.Container(
                color: bg,
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4, vertical: 3),
                child: sigImg != null
                    ? pw.Center(
                        child: pw.Image(sigImg,
                            height: 32, fit: pw.BoxFit.contain),
                      )
                    : pw.SizedBox(height: 32),
              ));
            } else {
              final val = rowData[col] ?? '';
              cells.add(pw.Container(
                color: bg,
                padding: const pw.EdgeInsets.all(4),
                child: val.isEmpty
                    ? emptyFieldPlaceholder()
                    : pw.Text(val, style: bodyStyle),
              ));
            }
          }
          dataRows.add(pw.TableRow(children: cells));
        }
        return pw.Table(
          border: pw.TableBorder.all(
              color: PdfColors.blueGrey300, width: 0.4),
          columnWidths: colWidths,
          children: [
            pw.TableRow(children: headerCells),
            ...dataRows,
          ],
        );
      }

      // ── Checklist PDF builder (SINGLE column, mirrors form UI) ──
      // Each checklist item gets its own full-width row — no 2-column
      // splitting. The checkbox is drawn with CustomPaint so it
      // renders identically to the Flutter form without any Unicode
      // character issues.
      pw.Widget buildChecklistPdf() {
        final items = report.checklistItems;
        if (items.isEmpty) {
          return pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(
                    color: PdfColors.blueGrey200, width: 0.4)),
            child: pw.Text('No checklist items',
                style: pw.TextStyle(
                    font: robotoRegularFont,
                    fontSize: 8,
                    color: PdfColors.grey400)),
          );
        }
        return pw.Column(
          children: items.asMap().entries.map((entry) {
            final i    = entry.key;
            final item = entry.value;
            final isLast = i == items.length - 1;
            final rowBg = item.checked
                ? checkedGreenBg
                : (i.isEven ? PdfColors.white : PdfColor.fromHex('#FAFAFA'));
            final labelColor =
                item.checked ? checkedGreen : PdfColors.black;
            final labelFont =
                item.checked ? robotoBoldFont : robotoRegularFont;

            return pw.Container(
              width: double.infinity,
              decoration: pw.BoxDecoration(
                color: rowBg,
                border: pw.Border(
                  left: pw.BorderSide(
                      color: PdfColors.blueGrey200, width: 0.4),
                  right: pw.BorderSide(
                      color: PdfColors.blueGrey200, width: 0.4),
                  top: pw.BorderSide(
                      color: PdfColors.blueGrey200, width: 0.4),
                  bottom: isLast
                      ? pw.BorderSide(
                          color: PdfColors.blueGrey200, width: 0.4)
                      : pw.BorderSide.none,
                ),
              ),
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6, vertical: 5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  // Row number badge — matches form UI
                  pw.Container(
                    width: 20,
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      '${i + 1}',
                      style: pw.TextStyle(
                        font: robotoBoldFont,
                        fontSize: 7.5,
                        color: navyColor,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  // Checkbox drawn with CustomPaint — no Unicode needed
                  pdfCheckbox(item.checked, size: 11),
                  pw.SizedBox(width: 7),
                  // Item label
                  pw.Expanded(
                    child: pw.Text(
                      item.label.isNotEmpty ? item.label : '\u2014',
                      style: pw.TextStyle(
                        font: labelFont,
                        fontSize: 8.5,
                        color: labelColor,
                      ),
                    ),
                  ),
                  // NOTE: No "CHECKED" tag pill in the PDF —
                  // the filled checkbox itself is the checked indicator.
                ],
              ),
            );
          }).toList(),
        );
      }

      // ── Image grid ────────────────────────────────────────────
      List<pw.Widget> buildPdfImageGrid(List<pw.MemoryImage> imgs) {
        const double pageW = 539.0;
        const double gap = 8.0;
        const double colW = (pageW - gap) / 2;
        const double colH = colW * 0.68;
        const double soloW = pageW * 0.55;
        const double soloH = soloW * 0.68;
        final rows = <pw.Widget>[];
        if (imgs.length == 1) {
          rows.add(pw.Center(
              child: pw.Image(imgs[0],
                  width: soloW,
                  height: soloH,
                  fit: pw.BoxFit.cover)));
          return rows;
        }
        for (int i = 0; i < imgs.length; i += 2) {
          final hasNext = i + 1 < imgs.length;
          rows.add(pw.Row(children: [
            pw.Image(imgs[i],
                width: colW, height: colH, fit: pw.BoxFit.cover),
            if (hasNext) ...[
              pw.SizedBox(width: gap),
              pw.Image(imgs[i + 1],
                  width: colW, height: colH, fit: pw.BoxFit.cover),
            ] else
              pw.SizedBox(width: colW + gap),
          ]));
          if (i + 2 < imgs.length) rows.add(pw.SizedBox(height: gap));
        }
        return rows;
      }

      // ── Build PDF document ────────────────────────────────────
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 48),
          // Set default theme fonts to Roboto so any pw.Text that
          // doesn't specify a font still gets Unicode support.
          theme: pw.ThemeData.withFont(
            base: robotoRegularFont,
            bold: robotoBoldFont,
          ),
          footer: (ctx) => pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                  top: pw.BorderSide(
                      color: PdfColors.grey400, width: 0.5)),
            ),
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '\u00A9 JV Almacis Site Management System \u2013 Safety Report',
                  style: pw.TextStyle(
                      font: robotoRegularFont,
                      fontSize: 7,
                      color: PdfColors.grey600),
                ),
                pw.Text(
                    'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                    style: pw.TextStyle(
                        font: robotoRegularFont,
                        fontSize: 7,
                        color: PdfColors.grey600)),
              ],
            ),
          ),
          build: (ctx) => [
            // ══ TITLE BLOCK ════════════════════════════════════
            pw.Container(
              width: double.infinity,
              color: navyColor,
              padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 2),
              child: pw.Text(
                report.projectName,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: robotoBoldFont,
                  fontSize: 14,
                  color: PdfColors.white,
                ),
              ),
            ),
            pw.Container(
              width: double.infinity,
              color: navyColor,
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 16, vertical: 4),
              child: pw.Text(
                'SAFETY REPORT \u2014 $typeLabel'.toUpperCase(),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: robotoBoldFont,
                  fontSize: 10,
                  color: PdfColors.white,
                  letterSpacing: 2.5,
                ),
              ),
            ),
            pw.Container(
              width: double.infinity,
              color: navyColor,
              padding: const pw.EdgeInsets.fromLTRB(16, 2, 16, 12),
              child: pw.Text(
                report.contractNumber.isEmpty
                    ? 'Contract No: \u2014'
                    : 'Contract No: ${report.contractNumber}',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: robotoRegularFont,
                  fontSize: 8.5,
                  color: PdfColor.fromHex('#FFFFFFB3'),
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            // ══ META ROWS ══════════════════════════════════════
            // Row 1 — DATE + TIME  (matches _buildDateTimeRow())
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                metaCellFilled('DATE',
                    DateFormat('EEE, MMM d, yyyy')
                        .format(report.reportDate)),
                pw.SizedBox(width: 4),
                metaCellFilled('TIME',
                    DateFormat('HH:mm').format(report.reportDate)),
              ],
            ),
            pw.SizedBox(height: 4),
            // Row 2 — BUILDING on its own full-width row
            // (matches _buildBuildingField() in the Flutter UI)
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                metaCellFilled('BUILDING', report.building),
              ],
            ),
            pw.SizedBox(height: 8),
            // ══ CHECKLIST ══════════════════════════════════════
            sectionBar('SAFETY CHECKLIST ITEMS'),
            pw.SizedBox(height: 4),
            buildChecklistPdf(),
            pw.SizedBox(height: 8),
            // ══ OBSERVATIONS ═══════════════════════════════════
            sectionBar('OBSERVATIONS & COMMENTS'),
            pw.Container(
              width: double.infinity,
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: PdfColors.blueGrey300, width: 0.5)),
              padding: const pw.EdgeInsets.all(8),
              child: observationsText.isEmpty
                  ? pw.Column(
                      crossAxisAlignment:
                          pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('\u2014',
                            style: emptyValueStyle),
                        pw.SizedBox(height: 36),
                      ],
                    )
                  : pw.Text(observationsText,
                      style: fieldValueStyle),
            ),
            pw.SizedBox(height: 8),
            // ══ ACTIONS TAKEN ══════════════════════════════════
            sectionBar('ACTIONS TAKEN'),
            pw.Container(
              width: double.infinity,
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: PdfColors.blueGrey300, width: 0.5)),
              padding: const pw.EdgeInsets.all(8),
              child: actionsText.isEmpty
                  ? pw.Column(
                      crossAxisAlignment:
                          pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('\u2014',
                            style: emptyValueStyle),
                        pw.SizedBox(height: 36),
                      ],
                    )
                  : pw.Text(actionsText, style: fieldValueStyle),
            ),
            pw.SizedBox(height: 8),
            // ══ JV ALMA CIS ATTENDANCE ═════════════════════════
            sectionBar('JV ALMA CIS ATTENDANCE'),
            pw.SizedBox(height: 4),
            buildAttendanceTable(
                _jvAlmaTable, tableHeaderStyle, cellStyle),
            pw.SizedBox(height: 8),
            // ══ SUB-CONTRACTOR ATTENDANCE (Weekly only) ════════
            if (report.type == 'SafetyWeekly') ...[
              sectionBar('SUB-CONTRACTOR ATTENDANCE'),
              pw.SizedBox(height: 4),
              buildAttendanceTable(
                  _subContractorTable, tableHeaderStyle, cellStyle),
              pw.SizedBox(height: 8),
            ],
            // ══ IMAGES ═════════════════════════════════════════
            if (pdfImages.isNotEmpty) ...[
              sectionBar('ATTACHED IMAGES'),
              pw.SizedBox(height: 8),
              ...buildPdfImageGrid(pdfImages),
            ],
          ],
        ),
      );

      return Uint8List.fromList(await pdf.save());
    } catch (e, st) {
      widget.logger.e('❌ SafetyForm: _buildPdfBytes failed',
          error: e, stackTrace: st);
      return null;
    }
  }


  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      floatingActionButton: _isReadOnly
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _isReadOnly = false),
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.edit_rounded),
              label: Text('Edit',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600)),
            )
          : null,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.project.name} — Safety Report'
          '${_isReadOnly ? ' (View)' : ''}',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, fontSize: 15),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              controller: _scrollCtrl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Full-width header (navy band) ───────────
                  _buildFormHeader(),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),
                        // ── Centred title + type badge ─────────
                        _buildSafetyTitle(),
                        const SizedBox(height: _gap),
                        // ── Date & Time row ────────────────────
                        _buildDateTimeRow(),
                        const SizedBox(height: _gap),
                        // ── Building field ─────────────────────
                        _buildBuildingField(),
                        const SizedBox(height: _gap),
                        // ── Report type toggle ─────────────────
                        _buildReportTypeSection(),
                        const SizedBox(height: _gap),
                        // ── Checklist ──────────────────────────
                        _buildChecklistSection(),
                        const SizedBox(height: _gap),
                        // ── Observations & Comments ────────────
                        _buildRichTextSection(
                            'OBSERVATIONS & COMMENTS',
                            _observationsCtrl),
                        const SizedBox(height: _gap),
                        // ── Actions Taken ──────────────────────
                        _buildRichTextSection(
                            'ACTIONS TAKEN', _actionsCtrl),
                        const SizedBox(height: _gap),
                        // ── JV Alma attendance ─────────────────
                        _buildAttendanceSectionCard(
                            'JV ALMA CIS ATTENDANCE',
                            _jvAlmaTable,
                            signatureColumnName: 'Signature'),
                        // ── Sub-contractor (Weekly only) ───────
                        if (_type == 'SafetyWeekly') ...[
                          const SizedBox(height: _gap),
                          _buildAttendanceSectionCard(
                              'SUB-CONTRACTOR ATTENDANCE',
                              _subContractorTable,
                              signatureColumnName: 'Signature'),
                        ],
                        const SizedBox(height: _gap),
                        // ── Images ─────────────────────────────
                        _buildImageSection(
                            constraints.maxWidth - 32),
                        const SizedBox(height: 20),
                        // ── Action buttons ─────────────────────
                        _buildActionButtons(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // WIDGET BUILDERS
  // ─────────────────────────────────────────────────────────────

  // ── Navy header band (matches weekly form) ────────────────────
  Widget _buildFormHeader() {
    return Container(
      color: _navy,
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            widget.project.name,
            textAlign: TextAlign.center,
            softWrap: true,
            overflow: TextOverflow.visible,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Contract No: ',
                  style: GoogleFonts.poppins(
                      color: Colors.white70, fontSize: 13)),
              SizedBox(
                width: 180,
                child: TextFormField(
                  controller: _contractCtrl,
                  readOnly: _isReadOnly,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'e.g. CN-2024-001',
                    hintStyle: GoogleFonts.poppins(
                        color: Colors.white38, fontSize: 12),
                    isDense: true,
                    border: const UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: Colors.white54, width: 1)),
                    enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: Colors.white54, width: 1)),
                    focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: Colors.white, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 4, horizontal: 2),
                  ),
                  onChanged:
                      _isReadOnly ? null : (_) => _saveDraftToCache(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── "SAFETY REPORT" centred title + type badge ────────────────
  Widget _buildSafetyTitle() {
    final isWeekly = _type == 'SafetyWeekly';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          children: [
            Text(
              'SAFETY REPORT',
              style: GoogleFonts.poppins(
                color: _navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 3),
              decoration: BoxDecoration(
                color: isWeekly
                    ? const Color(0xFF1565C0)
                    : const Color(0xFF6A1B9A),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isWeekly ? 'WEEKLY' : 'MONTHLY',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Date and Time row ─────────────────────────────────────────
  Widget _buildDateTimeRow() {
    Widget card({
      required IconData icon,
      required String label,
      required String value,
      required VoidCallback onTap,
    }) {
      return GestureDetector(
        onTap: _isReadOnly ? null : onTap,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _fieldBorder, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              )
            ],
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(children: [
                Icon(icon, color: _navy, size: 13),
                const SizedBox(width: 4),
                Text(label,
                    style: GoogleFonts.poppins(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: _navy.withValues(alpha: 0.7),
                      letterSpacing: 0.4,
                    )),
              ]),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    return Row(children: [
      Expanded(
        flex: 3,
        child: card(
          icon: Icons.calendar_today_rounded,
          label: 'DATE',
          value: DateFormat('EEE, MMM d, yyyy').format(_reportDate),
          onTap: _pickDate,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 2,
        child: card(
          icon: Icons.access_time_rounded,
          label: 'TIME',
          value: DateFormat('HH:mm').format(_reportDate),
          onTap: _pickTime,
        ),
      ),
    ]);
  }

  // ── Building field ────────────────────────────────────────────
  Widget _buildBuildingField() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _fieldBorder, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 100,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFE8EEF6),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(6),
                bottomLeft: Radius.circular(6),
              ),
            ),
            child: Text('BUILDING',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _navy,
                  letterSpacing: 0.5,
                )),
          ),
          Expanded(
            child: TextFormField(
              controller: _buildingCtrl,
              readOnly: _isReadOnly,
              textAlignVertical: TextAlignVertical.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.black87),
              decoration: InputDecoration(
                hintText: 'Building number, ID, or name…',
                hintStyle: GoogleFonts.poppins(
                    color: Colors.grey[400], fontSize: 12),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 14),
              ),
              onChanged:
                  _isReadOnly ? null : (_) => _saveDraftToCache(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Report type toggle (Weekly / Monthly) ─────────────────────
  Widget _buildReportTypeSection() {
    Widget typeChip(String value, String label, IconData icon) {
      final selected = _type == value;
      return Expanded(
        child: GestureDetector(
          onTap: _isReadOnly
              ? null
              : () => setState(() {
                    _type = value;
                    _saveDraftToCache();
                  }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: selected ? _navy : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: selected ? _navy : _fieldBorder,
                  width: selected ? 2 : 1),
              boxShadow: selected
                  ? [
                      BoxShadow(
                          color: _navy.withValues(alpha: 0.22),
                          blurRadius: 6,
                          offset: const Offset(0, 3))
                    ]
                  : null,
            ),
            child: Column(
              children: [
                Icon(icon,
                    color: selected ? Colors.white : _navy, size: 22),
                const SizedBox(height: 5),
                Text(label,
                    style: GoogleFonts.poppins(
                      color: selected ? Colors.white : _navy,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    )),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _fieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitleBar('REPORT TYPE', 8),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              typeChip('SafetyWeekly', 'Weekly',
                  Icons.calendar_view_week_rounded),
              const SizedBox(width: 12),
              typeChip('SafetyMonthly', 'Monthly',
                  Icons.calendar_month_rounded),
            ]),
          ),
        ],
      ),
    );
  }

  // ── Checklist section ─────────────────────────────────────────
  Widget _buildChecklistSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _fieldBorder),
      ),
      child: Column(
        children: [
          _sectionTitleBar('SAFETY CHECKLIST ITEMS', 8),
          ..._checklistItems.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final isLast = i == _checklistItems.length - 1;
            return Container(
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(
                        bottom: BorderSide(
                            color: _fieldBorder.withValues(alpha: 0.5))),
                color: item.checked
                    ? const Color(0xFFE8F5E9)
                    : (i.isEven ? Colors.white : const Color(0xFFFAFAFA)),
                borderRadius: isLast && !_isReadOnly
                    ? null
                    : null,
              ),
              child: Row(
                children: [
                  // Row number badge
                  Container(
                    width: 32,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    color: _navy.withValues(alpha: 0.06),
                    child: Text(
                      '${i + 1}',
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _navy),
                    ),
                  ),
                  // Checkbox
                  Checkbox(
                    value: item.checked,
                    activeColor: _navy,
                    checkColor: Colors.white,
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                    onChanged: _isReadOnly
                        ? null
                        : (v) {
                            setState(() => item.checked = v!);
                            _saveDraftToCache();
                          },
                  ),
                  // Label (editable in edit mode)
                  Expanded(
                    child: _isReadOnly
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12),
                            child: Text(
                              item.label,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: item.checked
                                    ? const Color(0xFF1B5E20)
                                    : Colors.black87,
                                fontWeight: item.checked
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          )
                        : TextField(
                            controller: _checklistLabelCtrls[i],
                            style: GoogleFonts.poppins(fontSize: 13),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 0),
                            ),
                            onChanged: (v) =>
                                _updateChecklistLabel(i, v),
                          ),
                  ),
                  // Checked indicator
                  if (item.checked)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.check_circle_rounded,
                          color: Color(0xFF2E7D32), size: 18),
                    ),
                  // Delete button (edit mode only)
                  if (!_isReadOnly)
                    IconButton(
                      icon: Icon(Icons.remove_circle_outline_rounded,
                          size: 18, color: Colors.red[400]),
                      onPressed: () => _removeChecklistItem(i),
                      tooltip: 'Remove item',
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            );
          }),
          // Add item button
          if (!_isReadOnly)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _addChecklistItem,
                  icon: const Icon(
                      Icons.add_circle_outline_rounded,
                      size: 16),
                  label: Text('Add Checklist Item',
                      style: GoogleFonts.poppins(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _navy,
                    side:
                        const BorderSide(color: _navy, width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 16),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Rich text editor section (Observations / Actions) ─────────
  Widget _buildRichTextSection(
      String title, quill.QuillController ctrl) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _fieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitleBar(title, 8),
          // Quill formatting toolbar (edit mode only)
          if (!_isReadOnly) ...[
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                border: Border(
                    bottom: BorderSide(
                        color: _fieldBorder.withValues(alpha: 0.7))),
              ),
              child: quill.QuillSimpleToolbar(
                controller: ctrl,
                config: const quill.QuillSimpleToolbarConfig(
                  showBoldButton: true,
                  showItalicButton: true,
                  showUnderLineButton: true,
                  showStrikeThrough: false,
                  showListBullets: true,
                  showListNumbers: true,
                  showIndent: true,
                  showClearFormat: true,
                  showFontFamily: false,
                  showFontSize: false,
                  showColorButton: false,
                  showBackgroundColorButton: false,
                  showSubscript: false,
                  showSuperscript: false,
                ),
              ),
            ),
          ],
          // Editor
          ConstrainedBox(
            constraints: const BoxConstraints(
                minHeight: 80, maxHeight: 220),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AbsorbPointer(
                absorbing: _isReadOnly,
                child: quill.QuillEditor.basic(
                  controller: ctrl,
                  config: const quill.QuillEditorConfig(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Attendance table section card ─────────────────────────────
  Widget _buildAttendanceSectionCard(
      String title, AttendanceTableData tableData,
      {String signatureColumnName = 'Signature'}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _fieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitleBar(title, 8),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _SafetyAttendanceTableWidget(
              key: ValueKey('attendance_${tableData.title}'),
              tableData: tableData,
              readOnly: _isReadOnly,
              signatureColumnName: signatureColumnName,
              sigBytesProvider: (rowIdx) =>
                  _sigBytes[tableData.title]?[rowIdx],
              onChanged: () {
                setState(() {});
                _saveDraftToCache();
              },
              onSignatureTap: (rowIdx) =>
                  _handleSignatureTap(rowIdx, tableData),
            ),
          ),
        ],
      ),
    );
  }

  // ── Signature tap handler — shows 3-mode popup ────────────────
  Future<void> _handleSignatureTap(
      int rowIdx, AttendanceTableData table) async {
    if (_isReadOnly) return;

    widget.logger.i(
        '✏️ SafetyForm: _handleSignatureTap table="${table.title}" row=$rowIdx');

    final existingUrl = table.rows[rowIdx]['Signature'] ?? '';
    final Uint8List? existingBytes = _sigBytes[table.title]?[rowIdx];

    widget.logger.d(
        '✏️ SafetyForm: existingUrl="${existingUrl.isEmpty ? "(empty)" : existingUrl.substring(0, existingUrl.length.clamp(0, 60))}…" '
        'existingBytes=${existingBytes == null ? "null" : "${existingBytes.length} bytes"}');

    final Uint8List? newBytes = await showDialog<Uint8List?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SSignaturePickerDialog(
        storedUrl: existingBytes == null ? existingUrl : null,
        storedBytes: existingBytes,
        logger: widget.logger,
      ),
    );

    widget.logger.i(
        '✏️ SafetyForm: dialog returned ${newBytes == null ? "null (cancelled)" : "${newBytes.length} bytes"}');

    if (!mounted) {
      widget.logger.w('⚠️ SafetyForm: not mounted after dialog close – skipping setState');
      return;
    }
    if (newBytes != null) {
      setState(() {
        _sigBytes.putIfAbsent(table.title, () => {})[rowIdx] = newBytes;
        table.rows[rowIdx]['Signature'] = '__signed__';
      });
      widget.logger.i(
          '✏️ SafetyForm: _sigBytes["${table.title}"][$rowIdx] updated (${newBytes.length} bytes), cell marked __signed__');
      _saveDraftToCache();
    } else {
      widget.logger.i('✏️ SafetyForm: no new bytes – keeping existing signature');
    }
  }

  // ── Image section ─────────────────────────────────────────────
  Widget _buildImageSection(double aw) {
    final thumbW = (aw - 8 * 2) / 3;
    final thumbH = thumbW * 0.72;
    final allImages = [
      ..._localImages.map((b) => _SImageItem(bytes: b)),
      ..._savedImageUrls.map((u) => _SImageItem(url: u)),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _fieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitleBar('ATTACHED IMAGES', 8),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                if (allImages.isNotEmpty) ...[
                  if (allImages.length == 1) ...[
                    GestureDetector(
                      onTap: () => _showImageViewer(allImages, 0),
                      child: Stack(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: allImages[0].bytes != null
                              ? Image.memory(allImages[0].bytes!,
                                  width: double.infinity,
                                  height: 160,
                                  fit: BoxFit.cover)
                              : Image.network(allImages[0].url!,
                                  width: double.infinity,
                                  height: 160,
                                  fit: BoxFit.cover),
                        ),
                        if (!_isReadOnly)
                          Positioned(
                            top: 6, right: 6,
                            child: GestureDetector(
                              onTap: () => setState(() {
                                if (_localImages.isNotEmpty) {
                                  _localImages.removeAt(0);
                                } else {
                                  _savedImageUrls.removeAt(0);
                                }
                              }),
                              child: Container(
                                decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(Icons.close,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ] else ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(allImages.length, (i) {
                        final item = allImages[i];
                        return GestureDetector(
                          onTap: () =>
                              _showImageViewer(allImages, i),
                          child: Stack(children: [
                            ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(6),
                              child: item.bytes != null
                                  ? Image.memory(item.bytes!,
                                      width: thumbW,
                                      height: thumbH,
                                      fit: BoxFit.cover)
                                  : Image.network(item.url!,
                                      width: thumbW,
                                      height: thumbH,
                                      fit: BoxFit.cover),
                            ),
                            Positioned(
                              bottom: 4,
                              right: _isReadOnly ? 4 : 22,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                    color: Colors.black45,
                                    shape: BoxShape.circle),
                                child: const Icon(
                                    Icons.zoom_out_map_rounded,
                                    size: 11,
                                    color: Colors.white),
                              ),
                            ),
                            if (!_isReadOnly)
                              Positioned(
                                top: 4, right: 4,
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    if (i < _localImages.length) {
                                      _localImages.removeAt(i);
                                    } else {
                                      _savedImageUrls.removeAt(
                                          i - _localImages.length);
                                    }
                                  }),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle),
                                    padding: const EdgeInsets.all(3),
                                    child: const Icon(Icons.close,
                                        size: 12,
                                        color: Colors.white),
                                  ),
                                ),
                              ),
                          ]),
                        );
                      }),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
                if (!_isReadOnly)
                  OutlinedButton.icon(
                    onPressed: _pickImages,
                    icon: const Icon(
                        Icons.add_photo_alternate_rounded,
                        size: 18),
                    label: Text(
                      allImages.isEmpty
                          ? 'Attach Image(s)'
                          : 'Add More Images',
                      style: GoogleFonts.poppins(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _navy,
                      side: const BorderSide(
                          color: _navy, width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Action buttons ────────────────────────────────────────────
  Widget _buildActionButtons() {
    Widget btn({
      required String label,
      required IconData icon,
      required Color color,
      required bool isLoading,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: SizedBox(
          height: 44,
          child: ElevatedButton.icon(
            onPressed: isLoading ? null : onTap,
            icon: isLoading
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white)))
                : Icon(icon, size: 16),
            label: Text(label,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  color.withValues(alpha: 0.5),
              disabledForegroundColor: Colors.white70,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
              elevation: 2,
            ),
          ),
        ),
      );
    }

    return Row(children: [
      if (!_isReadOnly) ...[
        btn(
          label: 'Save Report',
          icon: Icons.save_rounded,
          color: _navy,
          isLoading: _isSaving,
          onTap: _saveReport,
        ),
        const SizedBox(width: 10),
      ],
      btn(
        label: 'Download PDF',
        icon: Icons.picture_as_pdf_rounded,
        color: const Color(0xFF1B5E20),
        isLoading: _isGeneratingPdf,
        onTap: _downloadAsPdf,
      ),
    ]);
  }

  // ── Section title bar ─────────────────────────────────────────
  Widget _sectionTitleBar(String title, double radius) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius),
        ),
      ),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// SAFETY ATTENDANCE TABLE WIDGET
// Full-featured editable attendance table with add/remove rows,
// add/remove columns, rename headers, and row-number toggle.
// ══════════════════════════════════════════════════════════════════
class _SafetyAttendanceTableWidget extends StatefulWidget {
  final AttendanceTableData tableData;
  final bool readOnly;
  final VoidCallback onChanged;
  final String signatureColumnName;
  final Function(int rowIdx)? onSignatureTap;
  /// Provides in-memory PNG bytes for a given row index.
  final Uint8List? Function(int rowIdx)? sigBytesProvider;

  const _SafetyAttendanceTableWidget({
    super.key,
    required this.tableData,
    required this.readOnly,
    required this.onChanged,
    this.signatureColumnName = 'Signature',
    this.onSignatureTap,
    this.sigBytesProvider,
  });

  @override
  State<_SafetyAttendanceTableWidget> createState() =>
      _SafetyAttendanceTableWidgetState();
}

class _SafetyAttendanceTableWidgetState
    extends State<_SafetyAttendanceTableWidget> {
  static const _navy = Color(0xFF0A2E5A);
  static const _fieldBorder = Color(0xFFB0BEC5);

  // _controllers[rowIdx][colIdx]
  late List<List<TextEditingController>> _controllers;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  @override
  void didUpdateWidget(_SafetyAttendanceTableWidget old) {
    super.didUpdateWidget(old);
    if (old.tableData != widget.tableData ||
        old.tableData.rows.length != _controllers.length ||
        (old.tableData.columnNames.length !=
            widget.tableData.columnNames.length)) {
      _disposeControllers();
      _initControllers();
    }
  }

  void _initControllers() {
    _controllers = widget.tableData.rows.map((row) {
      return widget.tableData.columnNames.map((col) {
        return TextEditingController(text: row[col] ?? '');
      }).toList();
    }).toList();
  }

  void _disposeControllers() {
    for (final rowCtrls in _controllers) {
      for (final c in rowCtrls) {
        c.dispose();
      }
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _notifyChanged() {
    for (int ri = 0; ri < _controllers.length; ri++) {
      if (ri >= widget.tableData.rows.length) break;
      for (int ci = 0; ci < _controllers[ri].length; ci++) {
        if (ci >= widget.tableData.columnNames.length) break;
        widget.tableData.rows[ri]
            [widget.tableData.columnNames[ci]] =
            _controllers[ri][ci].text;
      }
    }
    widget.onChanged();
  }

  // ── Row management ────────────────────────────────────────────
  void _addRow() {
    final newRow = <String, String>{};
    for (final col in widget.tableData.columnNames) {
      newRow[col] = '';
    }
    widget.tableData.rows.add(newRow);
    setState(() {
      _controllers.add(widget.tableData.columnNames
          .map((_) => TextEditingController())
          .toList());
    });
    widget.onChanged();
  }

  void _removeRow(int index) {
    if (widget.tableData.rows.length <= 1) { return; }
    widget.tableData.rows.removeAt(index);
    setState(() {
      final rowCtrls = _controllers.removeAt(index);
      for (final c in rowCtrls) {
        c.dispose();
      }
    });
    widget.onChanged();
  }

  void _removeLastRow() {
    if (widget.tableData.rows.isEmpty ||
        widget.tableData.rows.length <= 1) {
      return;
    }
    _removeRow(widget.tableData.rows.length - 1);
  }

  // ── Column management ─────────────────────────────────────────
  void _addColumn() {
    const newCol = 'New Column';
    // Ensure unique name
    String col = newCol;
    int n = 2;
    while (widget.tableData.columnNames.contains(col)) {
      col = '$newCol $n';
      n++;
    }
    widget.tableData.columnNames.add(col);
    for (int ri = 0; ri < widget.tableData.rows.length; ri++) {
      widget.tableData.rows[ri][col] = '';
      _controllers[ri].add(TextEditingController());
    }
    setState(() {});
    widget.onChanged();
  }

  void _removeLastColumn() {
    if (widget.tableData.columnNames.length <= 1) { return; }
    final removed = widget.tableData.columnNames.removeLast();
    for (int ri = 0; ri < widget.tableData.rows.length; ri++) {
      widget.tableData.rows[ri].remove(removed);
      final last = _controllers[ri].removeLast();
      last.dispose();
    }
    setState(() {});
    widget.onChanged();
  }

  // ── Toggle row numbers ────────────────────────────────────────
  void _toggleRowNumbers() {
    setState(() =>
        widget.tableData.showRowNumbers =
            !widget.tableData.showRowNumbers);
  }

  // ── Edit column headers dialog ────────────────────────────────
  Future<void> _showEditHeadersDialog() async {
    final ctrls = widget.tableData.columnNames
        .map((h) => TextEditingController(text: h))
        .toList();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: 420, maxHeight: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 13),
                decoration: const BoxDecoration(
                  color: _navy,
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(14)),
                ),
                child: Row(children: [
                  const Icon(
                      Icons.drive_file_rename_outline_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Text('Edit Column Headers',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx, false),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 18),
                  ),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Column(
                    children: List.generate(
                      ctrls.length,
                      (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(children: [
                          Container(
                            width: 26, height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _navy.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text('${i + 1}',
                                style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _navy)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: ctrls[i],
                              style: GoogleFonts.poppins(fontSize: 12),
                              autofocus: i == 0,
                              textInputAction: i < ctrls.length - 1
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'Column ${i + 1}',
                                hintStyle: GoogleFonts.poppins(
                                    color: Colors.grey[400],
                                    fontSize: 11),
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(6)),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(6),
                                    borderSide: const BorderSide(
                                        color: _navy, width: 1.5)),
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _navy),
                        padding:
                            const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text('Cancel',
                          style: GoogleFonts.poppins(
                              color: _navy, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.check_rounded,
                          size: 16),
                      label: Text('Apply',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _navy,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) {
      for (final c in ctrls) {
        c.dispose();
      }
      return;
    }

    // Apply new header names and remap row data
    final oldNames = List<String>.from(widget.tableData.columnNames);
    final newNames = ctrls.map((c) => c.text.trim()).toList();

    for (int i = 0; i < newNames.length; i++) {
      if (newNames[i].isEmpty) newNames[i] = oldNames[i];
    }

    for (int ri = 0; ri < widget.tableData.rows.length; ri++) {
      final row = widget.tableData.rows[ri];
      final newRow = <String, String>{};
      for (int ci = 0; ci < oldNames.length && ci < newNames.length;
          ci++) {
        newRow[newNames[ci]] = row[oldNames[ci]] ?? '';
      }
      widget.tableData.rows[ri] = newRow;
    }

    setState(() {
      widget.tableData.columnNames
        ..clear()
        ..addAll(newNames);
    });

    widget.onChanged();
    for (final c in ctrls) {
      c.dispose();
    }
  }

  // ── Toolbar action button ─────────────────────────────────────
  Widget _actionBtn({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28, height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onTap != null
                ? color.withValues(alpha: 0.12)
                : Colors.grey[200],
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
                color: onTap != null
                    ? color.withValues(alpha: 0.4)
                    : Colors.grey[300]!,
                width: 0.8),
          ),
          child: Icon(icon,
              size: 15,
              color: onTap != null ? color : Colors.grey[400]),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cols = widget.tableData.columnNames;
    final rows = widget.tableData.rows;
    final showNums = widget.tableData.showRowNumbers;
    final canRemoveRow = rows.length > 1;
    final canRemoveCol = cols.length > 1;

    // Column flex widths
    final List<int> colFlexes = cols.map((col) {
      if (col.toLowerCase().contains('name')) return 3;
      if (col.toLowerCase().contains('company')) return 3;
      if (col.toLowerCase().contains('title')) return 2;
      if (col.toLowerCase().contains('signature')) return 2;
      return 2;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Toolbar ──────────────────────────────────────────
        if (!widget.readOnly) ...[
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4F8),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: _fieldBorder.withValues(alpha: 0.6)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                // Row management
                _actionBtn(
                  icon: Icons.add_box_outlined,
                  tooltip: 'Add Row',
                  color: const Color(0xFF1B5E20),
                  onTap: _addRow,
                ),
                const SizedBox(width: 4),
                _actionBtn(
                  icon: Icons.indeterminate_check_box_outlined,
                  tooltip: 'Remove Last Row',
                  color: Colors.red,
                  onTap: canRemoveRow ? _removeLastRow : null,
                ),
                Container(
                    width: 1, height: 20,
                    color: Colors.grey[300],
                    margin: const EdgeInsets.symmetric(
                        horizontal: 6)),
                // Column management
                _actionBtn(
                  icon: Icons.view_column_outlined,
                  tooltip: 'Add Column',
                  color: const Color(0xFF1565C0),
                  onTap: _addColumn,
                ),
                const SizedBox(width: 4),
                _actionBtn(
                  icon: Icons.remove_circle_outline,
                  tooltip: 'Remove Last Column',
                  color: Colors.orange,
                  onTap: canRemoveCol ? _removeLastColumn : null,
                ),
                Container(
                    width: 1, height: 20,
                    color: Colors.grey[300],
                    margin: const EdgeInsets.symmetric(
                        horizontal: 6)),
                // Headers
                _actionBtn(
                  icon: Icons.drive_file_rename_outline_rounded,
                  tooltip: 'Edit Column Headers',
                  color: const Color(0xFF6A1B9A),
                  onTap: _showEditHeadersDialog,
                ),
                const SizedBox(width: 4),
                // Row numbers toggle
                Tooltip(
                  message: showNums
                      ? 'Hide Row Numbers'
                      : 'Show Row Numbers',
                  child: GestureDetector(
                    onTap: _toggleRowNumbers,
                    child: Container(
                      width: 28, height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: showNums
                            ? _navy.withValues(alpha: 0.12)
                            : Colors.grey[200],
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                            color: showNums
                                ? _navy.withValues(alpha: 0.4)
                                : Colors.grey[300]!,
                            width: 0.8),
                      ),
                      child: Icon(Icons.format_list_numbered_rounded,
                          size: 15,
                          color: showNums
                              ? _navy
                              : Colors.grey[400]),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // ── Table ─────────────────────────────────────────────
        if (cols.isEmpty || rows.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: _fieldBorder),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text('No data — use toolbar to add rows/columns',
                  style: GoogleFonts.poppins(
                      color: Colors.grey[400], fontSize: 12)),
            ),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width - 56,
                ),
                child: Table(
                  border: TableBorder.all(
                      color: Colors.grey.shade300, width: 0.8),
                  defaultColumnWidth:
                      const FlexColumnWidth(1),
                  columnWidths: {
                    if (showNums)
                      0: const FixedColumnWidth(30),
                    ...{
                      for (int i = 0; i < cols.length; i++)
                        (showNums ? i + 1 : i):
                            FlexColumnWidth(
                                colFlexes[i].toDouble()),
                    },
                    // Action column (remove row)
                    if (!widget.readOnly)
                      (showNums
                          ? cols.length + 1
                          : cols.length): const FixedColumnWidth(32),
                  },
                  children: [
                    // ── Header row ───────────────────────────
                    TableRow(
                      decoration:
                          const BoxDecoration(color: _navy),
                      children: [
                        if (showNums)
                          _headerCell('#'),
                        ...cols.map((col) => _headerCell(col)),
                        if (!widget.readOnly)
                          _headerCell(''),
                      ],
                    ),
                    // ── Data rows ────────────────────────────
                    ...rows.asMap().entries.map((entry) {
                      final ri = entry.key;
                      final bg = ri.isEven
                          ? Colors.white
                          : const Color(0xFFF8FAFC);
                      return TableRow(children: [
                        if (showNums)
                          Container(
                            color: bg,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                                vertical: 8),
                            child: Text('${ri + 1}',
                                style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: _navy.withValues(
                                        alpha: 0.55))),
                          ),
                        ...List.generate(cols.length, (ci) {
                          final col = cols[ci];
                          final isSig = col.toLowerCase() ==
                              widget.signatureColumnName
                                  .toLowerCase();
                          if (isSig) {
                            return _signatureCell(ri, ci, bg);
                          }
                          return _dataCell(ri, ci, bg);
                        }),
                        if (!widget.readOnly)
                          Container(
                            color: bg,
                            alignment: Alignment.center,
                            child: rows.length > 1
                                ? GestureDetector(
                                    onTap: () => _removeRow(ri),
                                    child: Icon(
                                        Icons
                                            .remove_circle_outline,
                                        size: 16,
                                        color: Colors.red[400]),
                                  )
                                : const SizedBox(),
                          ),
                      ]);
                    }),
                  ],
                ),
              ),
            ),
          ),

        // ── Quick add row button ───────────────────────────────
        if (!widget.readOnly) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text('Add Row',
                  style: GoogleFonts.poppins(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _navy,
                side: BorderSide(
                    color: _navy.withValues(alpha: 0.5), width: 1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
                padding: const EdgeInsets.symmetric(
                    vertical: 6, horizontal: 12),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _headerCell(String text) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 9),
        child: Text(text,
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 11)),
      );

  Widget _dataCell(int ri, int ci, Color bg) {
    if (ri >= _controllers.length ||
        ci >= _controllers[ri].length) {
      return Container(color: bg);
    }
    if (widget.readOnly) {
      return Container(
        color: bg,
        padding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 8),
        child: Text(
          _controllers[ri][ci].text,
          style: GoogleFonts.poppins(
              fontSize: 12, color: Colors.black87),
          softWrap: true,
        ),
      );
    }
    return Container(
      color: bg,
      child: TextFormField(
        controller: _controllers[ri][ci],
        maxLines: null,
        minLines: 1,
        style: GoogleFonts.poppins(
            fontSize: 12, color: Colors.black87),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding:
              EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          isDense: true,
        ),
        onChanged: (_) => _notifyChanged(),
      ),
    );
  }

  Widget _signatureCell(int ri, int ci, Color bg) {
    final storedValue = ri < _controllers.length &&
            ci < _controllers[ri].length
        ? _controllers[ri][ci].text
        : '';
    // In-memory PNG bytes have highest priority (drawn/photo/pdf this session)
    final Uint8List? localBytes = widget.sigBytesProvider?.call(ri);
    // A stored URL is a real Firebase URL (not the placeholder sentinel)
    final bool hasUrl = storedValue.isNotEmpty &&
        storedValue != '__signed__' &&
        storedValue.startsWith('http');
    // '__signed__' sentinel means bytes are in _sigBytes but not uploaded yet
    final bool isSignedSentinel = storedValue == '__signed__';
    final bool hasSig = localBytes != null || hasUrl || isSignedSentinel;

    return GestureDetector(
      onTap: widget.readOnly
          ? null
          : () => widget.onSignatureTap?.call(ri),
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: localBytes != null
            // ── In-memory PNG preview (best case) ────────────────
            ? Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(
                    localBytes,
                    height: 36,
                    width: 60,
                    fit: BoxFit.contain,
                    // gaplessPlayback prevents flicker on rebuild
                    gaplessPlayback: true,
                  ),
                ),
                const SizedBox(width: 4),
                if (!widget.readOnly)
                  Icon(Icons.edit_rounded,
                      size: 11, color: Colors.grey[400]),
              ])
            : hasUrl
                // ── Remote Firebase URL preview ───────────────────
                ? Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        storedValue,
                        height: 36,
                        width: 60,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.broken_image_rounded,
                          size: 18,
                          color: Colors.grey[400],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (!widget.readOnly)
                      Icon(Icons.edit_rounded,
                          size: 11, color: Colors.grey[400]),
                  ])
                : hasSig
                    // ── __signed__ sentinel — bytes pending upload ─
                    ? Row(children: [
                        Icon(Icons.check_circle_rounded,
                            size: 14,
                            color: const Color(0xFF2E7D32)),
                        const SizedBox(width: 4),
                        Text(
                          'Signed',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: const Color(0xFF2E7D32),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!widget.readOnly) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.edit_rounded,
                              size: 11, color: Colors.grey[400]),
                        ],
                      ])
                    // ── Empty — invite to sign ────────────────────
                    : Row(children: [
                        Icon(Icons.draw_outlined,
                            size: 14, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.readOnly ? '—' : 'Tap to sign',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.grey[400],
                              fontStyle: FontStyle.italic,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// SIGNATURE PICKER DIALOG
// ══════════════════════════════════════════════════════════════════
class _SSignaturePickerDialog extends StatefulWidget {
  final Uint8List? storedBytes;
  final String? storedUrl;
  final Logger logger;

  const _SSignaturePickerDialog({
    required this.storedBytes,
    required this.storedUrl,
    required this.logger,
  });

  @override
  State<_SSignaturePickerDialog> createState() =>
      _SSignaturePickerDialogState();
}

class _SSignaturePickerDialogState
    extends State<_SSignaturePickerDialog> {
  static const _navy = Color(0xFF0A2E5A);
  static const _fieldBorder = Color(0xFFB0BEC5);

  int _mode = 0; // 0=Draw  1=Photo  2=PDF
  Uint8List? _drawnBytes;
  Uint8List? _pickedBytes;
  bool _isLoadingPdf = false;

  // ── Internal crop helpers (use THIS dialog's context) ─────────
  Future<Uint8List?> _cropFromPath(String sourcePath) async {
    widget.logger.d('✂️ SigDialog: _cropFromPath called path="$sourcePath"');
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: sourcePath,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Signature',
            toolbarColor: _navy,
            toolbarWidgetColor: Colors.white,
            statusBarLight: false,
            backgroundColor: Colors.black,
            activeControlsWidgetColor: _navy,
            lockAspectRatio: false,
            hideBottomControls: false,
            aspectRatioPresets: [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.ratio16x9,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.square,
            ],
          ),
          IOSUiSettings(
            title: 'Crop Signature',
            doneButtonTitle: 'Use',
            cancelButtonTitle: 'Cancel',
            resetAspectRatioEnabled: true,
            aspectRatioPickerButtonHidden: false,
            minimumAspectRatio: 0.2,
          ),
          if (kIsWeb)
            WebUiSettings(
              // Use the dialog's OWN context — not the parent screen's
              context: context,
              presentStyle: WebPresentStyle.dialog,
              // ── Dynamic CropperSize calculation ──────────────────
              size: () {
                final mq = MediaQuery.of(context);

                // True available screen height after OS chrome is removed
                final availableScreen = mq.size.height
                    - mq.padding.top           // status bar / notch
                    - mq.padding.bottom        // home indicator
                    - mq.viewInsets.bottom;    // on-screen keyboard (if open)

                // Space the dialog itself occupies minus Flutter's own insets
                const dialogSystemInsets = 48.0; // vertical:24 × 2

                // Proven chrome of image_cropper_for_web's cropper_dialog.dart
                // (title bar + action buttons + internal padding = 220 px)
                const packageChrome = 220.0;

                final h = (availableScreen - dialogSystemInsets - packageChrome)
                    .clamp(100.0, 490.0)   // min=100: never clamp UP past what
                    .toInt();              // the dialog can hold on tiny screens

                // Width: 85 % of viewport, clamped to a sensible range
                final w =
                    (mq.size.width * 0.85).clamp(280.0, 580.0).toInt();

                return CropperSize(width: w, height: h);
              }(),
            ),
        ],
      );
      if (cropped == null) {
        widget.logger.i('✂️ SigDialog: user cancelled crop (cropped == null)');
        return null;
      }
      final bytes = await cropped.readAsBytes();
      widget.logger.i(
          '✂️ SigDialog: crop succeeded – ${bytes.length} bytes from "${cropped.path}"');
      return bytes;
    } catch (e, st) {
      widget.logger.e('❌ SigDialog: _cropFromPath failed', error: e, stackTrace: st);
      return null;
    }
  }

  /// Writes [bytes] to a uniquely-named temp PNG, crops it, then
  /// deletes the temp file only AFTER bytes are safely read.
  ///
  /// On web: uses the self-contained [_InAppCropperDialog] — no Cropper.js
  /// dependency, no JS bridge, works on any screen size.
  Future<Uint8List?> _cropFromBytes(Uint8List bytes) async {
    widget.logger.d('✂️ SigDialog: _cropFromBytes called (${bytes.length} bytes)');
    if (kIsWeb) {
      widget.logger.d('✂️ SigDialog: web – launching in-app cropper');
      return _cropWithInAppCropper(bytes);
    }
    File? tmp;
    try {
      final dir = await getTemporaryDirectory();
      final tmpPath =
          '${dir.path}/sig_tmp_${DateTime.now().millisecondsSinceEpoch}.png';
      tmp = File(tmpPath);
      await tmp.writeAsBytes(bytes, flush: true);
      widget.logger.d('✂️ SigDialog: temp file written to $tmpPath');
      // Crop FIRST — await full completion before finally deletes the file
      final result = await _cropFromPath(tmpPath);
      return result;
    } catch (e, st) {
      widget.logger.e('❌ SigDialog: _cropFromBytes failed', error: e, stackTrace: st);
      return null;
    } finally {
      // Temp source file cleanup — safe here because ImageCropper writes
      // its output to a SEPARATE file; the source path is no longer needed.
      try {
        if (tmp != null && await tmp.exists()) {
          await tmp.delete();
          widget.logger.d('✂️ SigDialog: temp file deleted');
        }
      } catch (_) {}
    }
  }

  void _showError(String msg) {
    widget.logger.w('⚠️ SigDialog: showing error to user – "$msg"');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins()),
      backgroundColor: Colors.red[700],
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── In-app crop (web replacement for image_cropper_for_web) ───
  /// Shows [_InAppCropperDialog] — pure Flutter, no JS dependency.
  /// Returns cropped PNG bytes, or null if the user cancelled.
  Future<Uint8List?> _cropWithInAppCropper(Uint8List bytes) async {
    if (!mounted) return null;
    widget.logger.d(
        '✂️ SigDialog: _cropWithInAppCropper – ${bytes.length} bytes');
    final result = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InAppCropperDialog(
        imageBytes: bytes,
        logger: widget.logger,
      ),
    );
    widget.logger.d('✂️ SigDialog: in-app cropper returned '
        '${result == null ? "null (cancelled)" : "${result.length} bytes"}');
    return result;
  }

  // ── Mode tab ─────────────────────────────────────────────────
  Widget _modeTab({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _navy : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? _navy : _fieldBorder, width: 1.2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: active ? Colors.white : _navy),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : _navy)),
        ]),
      ),
    );
  }

  // ── Photo pick + crop ─────────────────────────────────────────
  Future<void> _pickPhoto() async {
    widget.logger.i('📷 SigDialog: _pickPhoto() called');
    if (!mounted) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Select Signature Photo',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: _navy)),
            ),
            const Divider(height: 1),
            ListTile(
              leading:
                  const Icon(Icons.photo_library_rounded, color: _navy),
              title: Text('Choose from Gallery',
                  style: GoogleFonts.poppins(fontSize: 13)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading:
                  const Icon(Icons.camera_alt_rounded, color: _navy),
              title: Text('Take a Photo',
                  style: GoogleFonts.poppins(fontSize: 13)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) {
      widget.logger.i('📷 SigDialog: bottom sheet dismissed – no source selected');
      return;
    }
    if (!mounted) return;
    widget.logger.i(
        '📷 SigDialog: source selected = ${source == ImageSource.gallery ? "gallery" : "camera"}');

    XFile? xfile;
    try {
      xfile = await ImagePicker().pickImage(
          source: source, imageQuality: 92, maxWidth: 2000);
    } catch (e, st) {
      widget.logger.e('❌ SigDialog: ImagePicker.pickImage failed',
          error: e, stackTrace: st);
      _showError('Could not open image picker: $e');
      return;
    }

    if (xfile == null) {
      widget.logger.i('📷 SigDialog: image picker returned null – user cancelled');
      return;
    }
    if (!mounted) return;
    widget.logger.i(
        '📷 SigDialog: image picked path="${xfile.path}" name="${xfile.name}"');

    Uint8List? cropped;
    try {
      if (kIsWeb) {
        // On web, image_cropper_for_web requires Cropper.js loaded in
        // index.html — which may not exist. Use the self-contained Flutter
        // cropper instead; it requires only the raw bytes.
        widget.logger.d('📷 SigDialog: web – reading bytes for in-app cropper');
        final raw = await xfile.readAsBytes();
        widget.logger.d('📷 SigDialog: web – ${raw.length} bytes read');
        cropped = await _cropWithInAppCropper(raw);
      } else {
        widget.logger.d('📷 SigDialog: native – calling _cropFromPath directly');
        cropped = await _cropFromPath(xfile.path);
      }
    } catch (e, st) {
      widget.logger.e('❌ SigDialog: crop step failed', error: e, stackTrace: st);
      _showError('Could not crop image: $e');
      return;
    }

    if (!mounted) return;
    if (cropped == null) {
      widget.logger.i('📷 SigDialog: crop returned null – user cancelled cropper');
      // Don't show error — user intentionally cancelled
      return;
    }

    widget.logger.i(
        '📷 SigDialog: ✅ photo cropped successfully (${cropped.length} bytes) – updating state');
    setState(() {
      _pickedBytes = cropped;
      _drawnBytes = null;
    });
  }

  // ── PDF pick, rasterise, page-select, crop ───────────────────
  Future<void> _pickFromPdf() async {
    widget.logger.i('📄 SigDialog: _pickFromPdf() called');

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
        withReadStream: false,
      );
    } catch (e, st) {
      widget.logger.e('❌ SigDialog: FilePicker failed', error: e, stackTrace: st);
      _showError('Could not open file picker: $e');
      return;
    }

    if (result == null || result.files.isEmpty) {
      widget.logger.i('📄 SigDialog: FilePicker cancelled or no files');
      return;
    }
    if (!mounted) return;
    final picked = result.files.first;
    widget.logger.i(
        '📄 SigDialog: PDF selected name="${picked.name}" '
        'bytes=${picked.bytes?.length ?? "null"} path="${picked.path}"');

    // Resolve PDF bytes (bytes from withData, or path fallback on native)
    Uint8List? pdfBytes = picked.bytes;
    if (pdfBytes == null && picked.path != null && !kIsWeb) {
      widget.logger.d('📄 SigDialog: bytes null – reading from path "${picked.path}"');
      try {
        pdfBytes = await File(picked.path!).readAsBytes();
        widget.logger.d('📄 SigDialog: read ${pdfBytes.length} bytes from path');
      } catch (e, st) {
        widget.logger.e('❌ SigDialog: PDF read from path failed',
            error: e, stackTrace: st);
      }
    }
    if (pdfBytes == null) {
      widget.logger.e('❌ SigDialog: pdfBytes still null – cannot proceed');
      _showError('Could not read the selected PDF file.');
      return;
    }
    widget.logger.i('📄 SigDialog: PDF bytes ready (${pdfBytes.length} bytes) – rasterising');

    if (mounted) setState(() => _isLoadingPdf = true);

    final List<Uint8List> pageImages = [];
    try {
      await for (final page in Printing.raster(pdfBytes, dpi: 180)) {
        final png = await page.toPng();
        pageImages.add(png);
        widget.logger.d('📄 SigDialog: rasterised page ${pageImages.length} (${png.length} bytes)');
        if (pageImages.length >= 10) break;
      }
    } catch (e, st) {
      widget.logger.e('❌ SigDialog: PDF raster failed', error: e, stackTrace: st);
      if (mounted) {
        setState(() => _isLoadingPdf = false);
        _showError('Could not render PDF: $e');
      }
      return;
    } finally {
      if (mounted) setState(() => _isLoadingPdf = false);
    }

    widget.logger.i('📄 SigDialog: rasterised ${pageImages.length} page(s)');

    if (pageImages.isEmpty) {
      widget.logger.w('⚠️ SigDialog: no pages rasterised from PDF');
      _showError('The PDF appears to have no pages.');
      return;
    }
    if (!mounted) return;

    Uint8List chosenPage;
    if (pageImages.length == 1) {
      widget.logger.d('📄 SigDialog: single page PDF – skipping page selector');
      chosenPage = pageImages.first;
    } else {
      widget.logger.d('📄 SigDialog: showing page selector for ${pageImages.length} pages');
      final chosen = await showDialog<Uint8List>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: 480, maxHeight: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 13),
                  decoration: const BoxDecoration(
                    color: _navy,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(14)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.picture_as_pdf_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Text('Select a Page',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white70, size: 20),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Text(
                    'Tap the page that contains the signature',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
                Flexible(
                  child: GridView.builder(
                    padding:
                        const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: pageImages.length,
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => Navigator.pop(ctx, pageImages[i]),
                      child: Column(children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: _navy.withValues(alpha: 0.3),
                                    width: 1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Image.memory(pageImages[i],
                                  fit: BoxFit.cover),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('Page ${i + 1}',
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _navy)),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (chosen == null) {
        widget.logger.i('📄 SigDialog: page selector dismissed – no page chosen');
        return;
      }
      if (!mounted) return;
      widget.logger.i('📄 SigDialog: page chosen (${chosen.length} bytes)');
      chosenPage = chosen;
    }

    widget.logger.d('📄 SigDialog: sending chosen page to cropper');
    final cropped = await _cropFromBytes(chosenPage);
    if (!mounted) return;
    if (cropped == null) {
      widget.logger.i('📄 SigDialog: PDF crop returned null – user cancelled cropper');
      return;
    }
    widget.logger.i(
        '📄 SigDialog: ✅ PDF page cropped successfully (${cropped.length} bytes) – updating state');
    setState(() {
      _pickedBytes = cropped;
      _drawnBytes = null;
    });
  }

  // ── Preview box (shared by Photo + PDF modes) ─────────────────
  Widget _previewBox(Uint8List? localBytes, String? storedUrl) {
    final bool hasUrl = storedUrl != null &&
        storedUrl.isNotEmpty &&
        storedUrl.startsWith('http');
    final bool hasImage = localBytes != null || hasUrl;

    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasImage ? _navy.withValues(alpha: 0.45) : _fieldBorder,
          width: hasImage ? 1.5 : 1.0,
        ),
      ),
      child: hasImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: localBytes != null
                  ? Image.memory(localBytes, fit: BoxFit.contain)
                  : Image.network(
                      storedUrl!,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, prog) => prog == null
                          ? child
                          : const Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2)),
                      errorBuilder: (_, __, ___) => Center(
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image_rounded,
                                  color: Colors.grey[400], size: 18),
                              const SizedBox(width: 6),
                              Text('Could not load signature',
                                  style: GoogleFonts.poppins(
                                      color: Colors.grey[400],
                                      fontSize: 11)),
                            ]),
                      ),
                    ),
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.crop_free_rounded,
                      color: Colors.grey[300], size: 28),
                  const SizedBox(height: 6),
                  Text('No signature yet',
                      style: GoogleFonts.poppins(
                          color: Colors.grey[400], fontSize: 12)),
                ],
              ),
            ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final Uint8List? localBytes = _pickedBytes ?? _drawnBytes;
    final String? storedUrl = widget.storedUrl;

    // resultBytes: new bytes this session, or fall back to passed-in stored bytes
    final Uint8List? resultBytes = localBytes ?? widget.storedBytes;
    final bool canConfirm = resultBytes != null;

    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: 440, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title bar ────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: _navy,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                const Icon(Icons.draw_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Text('Add Signature',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    widget.logger.i('✏️ SigDialog: cancelled by user (X)');
                    Navigator.pop(context);
                  },
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white70, size: 20),
                ),
              ]),
            ),

            // ── Body ─────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Mode tabs
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        _modeTab(
                          label: 'Draw',
                          icon: Icons.draw_rounded,
                          active: _mode == 0,
                          onTap: () {
                            widget.logger.d('✏️ SigDialog: switched to Draw mode');
                            setState(() => _mode = 0);
                          },
                        ),
                        const SizedBox(width: 6),
                        _modeTab(
                          label: 'Photo',
                          icon: Icons.photo_camera_rounded,
                          active: _mode == 1,
                          onTap: () {
                            widget.logger.d('✏️ SigDialog: switched to Photo mode');
                            setState(() => _mode = 1);
                          },
                        ),
                        const SizedBox(width: 6),
                        _modeTab(
                          label: 'From PDF',
                          icon: Icons.picture_as_pdf_rounded,
                          active: _mode == 2,
                          onTap: () {
                            widget.logger.d('✏️ SigDialog: switched to PDF mode');
                            setState(() => _mode = 2);
                          },
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),

                    // Mode content
                    if (_mode == 0) ...[
                      _SDrawPadWidget(
                        onSignatureChanged: (b) {
                          widget.logger.d(
                              '✏️ SigDialog: draw pad changed – ${b == null ? "cleared" : "${b.length} bytes"}');
                          setState(() {
                            _drawnBytes = b;
                            _pickedBytes = null;
                          });
                        },
                      ),
                    ] else if (_mode == 1) ...[
                      // Photo preview + pick button
                      _previewBox(_pickedBytes ?? _drawnBytes, storedUrl),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickPhoto,
                            icon: const Icon(
                                Icons.photo_camera_rounded,
                                size: 14),
                            label: Text(
                              (_pickedBytes ?? _drawnBytes) != null
                                  ? 'Replace & Crop'
                                  : 'Pick Photo & Crop',
                              style:
                                  GoogleFonts.poppins(fontSize: 11),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _navy,
                              side: const BorderSide(
                                  color: _navy, width: 1.2),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(7)),
                            ),
                          ),
                        ),
                        if ((_pickedBytes ?? _drawnBytes) != null) ...[
                          const SizedBox(width: 8),
                          _clearBtn(),
                        ],
                      ]),
                    ] else ...[
                      // PDF instructions
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8EEF6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(children: [
                          Icon(Icons.info_outline_rounded,
                              size: 13,
                              color: _navy.withValues(alpha: 0.7)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Pick a PDF → select the page → drag to crop the signature area',
                              style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color:
                                      _navy.withValues(alpha: 0.75)),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      _previewBox(_pickedBytes ?? _drawnBytes, storedUrl),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                _isLoadingPdf ? null : _pickFromPdf,
                            icon: _isLoadingPdf
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<
                                            Color>(Colors.white)))
                                : const Icon(
                                    Icons.picture_as_pdf_rounded,
                                    size: 14),
                            label: Text(
                              (_pickedBytes ?? _drawnBytes) != null
                                  ? 'Replace from PDF'
                                  : 'Pick PDF & Crop',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _navy,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 9),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(7)),
                              elevation: 1,
                            ),
                          ),
                        ),
                        if ((_pickedBytes ?? _drawnBytes) != null) ...[
                          const SizedBox(width: 8),
                          _clearBtn(),
                        ],
                      ]),
                    ],
                  ],
                ),
              ),
            ),

            // ── Footer ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      widget.logger
                          .i('✏️ SigDialog: cancelled by user (Cancel button)');
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _navy),
                      padding:
                          const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('Cancel',
                        style: GoogleFonts.poppins(
                            color: _navy, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canConfirm
                        ? () {
                            widget.logger.i(
                                '✏️ SigDialog: confirmed – returning ${resultBytes.length} bytes');
                            Navigator.pop(context, resultBytes);
                          }
                        : null,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: Text('Confirm',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _navy,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      padding:
                          const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 1,
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clearBtn() => TextButton.icon(
        onPressed: () {
          widget.logger.i('✏️ SigDialog: signature cleared by user');
          setState(() {
            _pickedBytes = null;
            _drawnBytes = null;
          });
        },
        icon: Icon(Icons.delete_outline_rounded,
            size: 14, color: Colors.red[400]),
        label: Text('Clear',
            style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.red[400],
                fontWeight: FontWeight.w600)),
        style: TextButton.styleFrom(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          minimumSize: Size.zero,
        ),
      );
}

// ══════════════════════════════════════════════════════════════════
// DRAW PAD (safety-scoped, mirrors _SignaturePadWidget in monthly)
// ══════════════════════════════════════════════════════════════════
class _SStrokePoint {
  final Offset position;
  final double pressure;
  const _SStrokePoint(this.position, this.pressure);
}

class _SStrokeModel extends ChangeNotifier {
  final List<List<_SStrokePoint>> strokes = [];
  List<_SStrokePoint>? current;

  void startStroke(_SStrokePoint p) {
    final s = [p];
    current = s;
    strokes.add(s);
    notifyListeners();
  }

  void addPoint(_SStrokePoint p) {
    current?.add(p);
    notifyListeners();
  }

  void endStroke() {
    current = null;
  }

  void clear() {
    strokes.clear();
    current = null;
    notifyListeners();
  }

  bool get isEmpty => strokes.isEmpty;
}

class _SDrawPadWidget extends StatefulWidget {
  final Function(Uint8List?)? onSignatureChanged;
  const _SDrawPadWidget({this.onSignatureChanged});

  @override
  State<_SDrawPadWidget> createState() => _SDrawPadWidgetState();
}

class _SDrawPadWidgetState extends State<_SDrawPadWidget> {
  static const _navy = Color(0xFF0A2E5A);
  static const _inkColor = Color(0xFF0A2E5A);

  final _model = _SStrokeModel();
  final _repaintKey = GlobalKey();

  bool _hasSignature = false;
  String _inputLabel = '';

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  void _doReset() {
    _model.clear();
    setState(() {
      _hasSignature = false;
      _inputLabel = '';
    });
    widget.onSignatureChanged?.call(null);
  }

  Future<Uint8List?> _toImageBytes() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  String _kindLabel(PointerDeviceKind kind) {
    switch (kind) {
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
        return '✒ Stylus';
      case PointerDeviceKind.touch:
        return '👆 Touch';
      default:
        return '🖱 Mouse';
    }
  }

  bool _hasPressure(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  void _onDown(PointerDownEvent e) {
    final pressure =
        _hasPressure(e.kind) ? e.pressure.clamp(0.0, 1.0) : 1.0;
    _model.startStroke(_SStrokePoint(e.localPosition, pressure));
    if (_kindLabel(e.kind) != _inputLabel) {
      setState(() => _inputLabel = _kindLabel(e.kind));
    }
  }

  void _onMove(PointerMoveEvent e) {
    final pressure =
        _hasPressure(e.kind) ? e.pressure.clamp(0.0, 1.0) : 1.0;
    _model.addPoint(_SStrokePoint(e.localPosition, pressure));
  }

  void _onUp(PointerUpEvent e) async {
    _model.endStroke();
    if (!_hasSignature) {
      setState(() => _hasSignature = true);
    }
    final bytes = await _toImageBytes();
    widget.onSignatureChanged?.call(bytes);
  }

  void _onCancel(PointerCancelEvent e) {
    _model.endStroke();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScrollConfiguration(
          behavior:
              ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: RepaintBoundary(
            key: _repaintKey,
            child: Listener(
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: _onUp,
              onPointerCancel: _onCancel,
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _hasSignature
                        ? _navy.withValues(alpha: 0.5)
                        : const Color(0xFFB0BEC5),
                    width: _hasSignature ? 1.5 : 1.0,
                  ),
                  boxShadow: _hasSignature
                      ? [
                          BoxShadow(
                              color: _navy.withValues(alpha: 0.06),
                              blurRadius: 6,
                              offset: const Offset(0, 2))
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const RepaintBoundary(
                        child: CustomPaint(
                            painter: _SRuledPainter()),
                      ),
                      CustomPaint(
                        painter: _SInkPainter(_model, _inkColor),
                      ),
                      if (!_hasSignature)
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.draw_outlined,
                                  color: Colors.grey[300], size: 28),
                              const SizedBox(height: 5),
                              Text('Sign here',
                                  style: GoogleFonts.poppins(
                                      color: Colors.grey[350],
                                      fontSize: 12)),
                              const SizedBox(height: 2),
                              Text(
                                  'Finger · Stylus · Mouse — all supported',
                                  style: GoogleFonts.poppins(
                                      color: Colors.grey[350],
                                      fontSize: 9.5)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              if (_hasSignature) ...[
                Icon(Icons.check_circle_rounded,
                    size: 13, color: Colors.green[700]),
                const SizedBox(width: 4),
                Text('Signature captured',
                    style: GoogleFonts.poppins(
                        color: Colors.green[700],
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
                if (_inputLabel.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: _navy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_inputLabel,
                        style: GoogleFonts.poppins(
                            fontSize: 9,
                            color: _navy,
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ] else
                Text('Draw your signature above',
                    style: GoogleFonts.poppins(
                        color: Colors.grey[400], fontSize: 10)),
            ]),
            if (_hasSignature)
              TextButton.icon(
                onPressed: _doReset,
                icon: Icon(Icons.refresh_rounded,
                    size: 13, color: Colors.red[400]),
                label: Text('Clear',
                    style: GoogleFonts.poppins(
                        color: Colors.red[400],
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SRuledPainter extends CustomPainter {
  const _SRuledPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final guide = Paint()
      ..color = const Color(0xFFF0F4F8)
      ..strokeWidth = 0.7;
    for (final y in [
      size.height * 0.30,
      size.height * 0.55,
      size.height * 0.80,
    ]) {
      canvas.drawLine(Offset(12, y), Offset(size.width - 12, y), guide);
    }
    canvas.drawLine(
      Offset(12, size.height * 0.72),
      Offset(size.width - 12, size.height * 0.72),
      Paint()
        ..color = const Color(0xFFCFD8DC)
        ..strokeWidth = 0.9,
    );
  }

  @override
  bool shouldRepaint(_SRuledPainter _) => false;
}

class _SInkPainter extends CustomPainter {
  final _SStrokeModel model;
  final Color inkColor;

  late final Paint _strokePaint = Paint()
    ..color = inkColor
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  late final Paint _dotPaint = Paint()
    ..color = inkColor
    ..style = PaintingStyle.fill;

  _SInkPainter(this.model, this.inkColor)
      : super(repaint: model);

  static const _baseWidth = 1.8;
  static const _maxWidth  = 3.2;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in model.strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        final p = stroke.first;
        _dotPaint.color = inkColor;
        canvas.drawCircle(
          p.position,
          (_baseWidth * (0.6 + p.pressure * 0.4)).clamp(1.0, 2.5),
          _dotPaint,
        );
        continue;
      }

      for (int i = 0; i < stroke.length - 1; i++) {
        final p0 = stroke[i];
        final p1 = stroke[i + 1];

        final Offset ctrl = p0.position;
        final Offset end = i == stroke.length - 2
            ? p1.position
            : Offset(
                (p0.position.dx + p1.position.dx) / 2,
                (p0.position.dy + p1.position.dy) / 2,
              );

        final w = (_baseWidth +
                (_maxWidth - _baseWidth) *
                    ((p0.pressure + p1.pressure) / 2))
            .clamp(_baseWidth, _maxWidth);

        final seg = Path()
          ..moveTo(
              i == 0
                  ? stroke[0].position.dx
                  : (stroke[i - 1].position.dx + p0.position.dx) / 2,
              i == 0
                  ? stroke[0].position.dy
                  : (stroke[i - 1].position.dy + p0.position.dy) / 2)
          ..quadraticBezierTo(
              ctrl.dx, ctrl.dy, end.dx, end.dy);

        _strokePaint
          ..color = inkColor
          ..strokeWidth = w;
        canvas.drawPath(seg, _strokePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_SInkPainter old) =>
      old.model != model || old.inkColor != inkColor;
}


// ══════════════════════════════════════════════════════════════════
// HELPERS
// ══════════════════════════════════════════════════════════════════
class _SImageItem {
  final Uint8List? bytes;
  final String? url;
  _SImageItem({this.bytes, this.url});
}

// ══════════════════════════════════════════════════════════════════
// FULL-SCREEN IMAGE VIEWER DIALOG
// ══════════════════════════════════════════════════════════════════
class _SImageViewerDialog extends StatefulWidget {
  final List<_SImageItem> images;
  final int initialIndex;
  const _SImageViewerDialog(
      {required this.images, required this.initialIndex});

  @override
  State<_SImageViewerDialog> createState() =>
      _SImageViewerDialogState();
}

class _SImageViewerDialogState
    extends State<_SImageViewerDialog> {
  late int _current;
  late PageController _pageCtrl;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageCtrl =
        PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) {
                final item = widget.images[i];
                return InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5.0,
                  child: Center(
                    child: item.bytes != null
                        ? Image.memory(item.bytes!,
                            fit: BoxFit.contain)
                        : Image.network(item.url!,
                            fit: BoxFit.contain),
                  ),
                );
              },
            ),
          ),
          // Close button
          Positioned(
            top: 40, right: 16,
            child: SafeArea(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4),
                        width: 1),
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
          // Page counter
          if (widget.images.length > 1)
            Positioned(
              top: 48, left: 0, right: 0,
              child: SafeArea(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_current + 1} / ${widget.images.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          // Previous arrow
          if (_current > 0)
            Positioned(
              left: 8, top: 0, bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => _pageCtrl.previousPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chevron_left_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),
          // Next arrow
          if (_current < widget.images.length - 1)
            Positioned(
              right: 8, top: 0, bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => _pageCtrl.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chevron_right_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// IN-APP IMAGE CROPPER  (web-safe — pure Flutter, zero JS deps)
//
// Replaces image_cropper_for_web on the web platform entirely.
// Features:
//   • Eight drag handles (4 corners + 4 edge midpoints) — drag to resize
//   • Drag inside the crop rect to reposition it
//   • Drag outside the crop rect to draw a brand-new selection
//   • Rule-of-thirds grid overlay while cropping
//   • Rotate Left / Rotate Right — re-renders the image via PictureRecorder
//   • "Use Crop" button — renders only the selected region to PNG bytes
// ══════════════════════════════════════════════════════════════════
class _InAppCropperDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final Logger logger;

  const _InAppCropperDialog({
    required this.imageBytes,
    required this.logger,
  });

  @override
  State<_InAppCropperDialog> createState() =>
      _InAppCropperDialogState();
}

class _InAppCropperDialogState
    extends State<_InAppCropperDialog> {
  static const _navy = Color(0xFF0A2E5A);
  static const _handleR = 7.0;   // handle circle radius
  static const _hitSlop = 12.0;  // extra tap area around each handle
  static const _minCrop = 40.0;  // minimum crop dimension in px

  // ── Image state ───────────────────────────────────────────────
  ui.Image? _image;
  bool _loading  = true;
  bool _cropping = false;
  String? _error;

  // ── Layout (updated each build, NOT setState — no rebuild loop) ─
  Rect _imageDisplayRect = Rect.zero;

  // ── Crop rect (in widget-space coords matching _imageDisplayRect) ─
  Rect _cropRect        = Rect.zero;
  bool _cropInitialized = false;

  // ── Drag state ────────────────────────────────────────────────
  _CropHandle? _activeHandle;
  Offset?      _dragStart;
  Rect?        _rectAtDragStart;

  // ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadImage(widget.imageBytes);
  }

  Future<void> _loadImage(Uint8List bytes) async {
    setState(() { _loading = true; _error = null; });
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _image = frame.image;
        _loading = false;
        _cropInitialized = false; // triggers full-image init on next build
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Could not decode image: $e'; });
    }
  }

  // ── Rotation ─────────────────────────────────────────────────
  Future<void> _rotate({required bool clockwise}) async {
    if (_image == null || _loading) return;
    setState(() => _loading = true);
    try {
      final src = _image!;
      final newW = src.height;
      final newH = src.width;
      final recorder = ui.PictureRecorder();
      final canvas  = Canvas(recorder,
          Rect.fromLTWH(0, 0, newW.toDouble(), newH.toDouble()));
      canvas.translate(newW / 2.0, newH / 2.0);
      canvas.rotate(clockwise ? pi / 2 : -pi / 2);
      canvas.drawImage(
          src, Offset(-src.width / 2.0, -src.height / 2.0), Paint());
      final picture = recorder.endRecording();
      final rotated = await picture.toImage(newW, newH);
      if (!mounted) return;
      setState(() {
        _image           = rotated;
        _loading         = false;
        _cropInitialized = false; // reset crop to full image after rotation
      });
    } catch (e) {
      widget.logger.e('❌ InAppCropper: rotate failed – $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Confirm crop ─────────────────────────────────────────────
  Future<void> _confirmCrop() async {
    if (_image == null || _cropping) return;
    setState(() => _cropping = true);
    try {
      final img  = _image!;
      final disp = _imageDisplayRect;

      // Map crop rect from display-space → image-space
      final scaleX = img.width  / disp.width;
      final scaleY = img.height / disp.height;
      final rel    = _cropRect.translate(-disp.left, -disp.top);

      final srcX = (rel.left   * scaleX).round().clamp(0, img.width  - 1);
      final srcY = (rel.top    * scaleY).round().clamp(0, img.height - 1);
      final srcW = (rel.width  * scaleX).round().clamp(1, img.width  - srcX);
      final srcH = (rel.height * scaleY).round().clamp(1, img.height - srcY);

      final recorder = ui.PictureRecorder();
      final canvas   = Canvas(recorder,
          Rect.fromLTWH(0, 0, srcW.toDouble(), srcH.toDouble()));
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(srcX.toDouble(), srcY.toDouble(),
                      srcW.toDouble(), srcH.toDouble()),
        Rect.fromLTWH(0, 0, srcW.toDouble(), srcH.toDouble()),
        Paint(),
      );
      final picture  = recorder.endRecording();
      final cropped  = await picture.toImage(srcW, srcH);
      final byteData = await cropped.toByteData(
          format: ui.ImageByteFormat.png);

      if (byteData == null) throw Exception('PNG encoding returned null');
      final out = byteData.buffer.asUint8List();
      widget.logger.i(
          '✂️ InAppCropper: ✅ cropped to $srcW×$srcH (${out.length} bytes)');
      if (mounted) Navigator.of(context).pop(out);
    } catch (e, st) {
      widget.logger.e('❌ InAppCropper: crop failed',
          error: e, stackTrace: st);
      if (mounted) {
        setState(() => _cropping = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Crop failed: $e',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red[700],
        ));
      }
    }
  }

  // ── Layout helper (called inside LayoutBuilder, no setState) ──
  static Rect _fitRect(Size box, ui.Image img) {
    final imgAR = img.width / img.height;
    final boxAR = box.width / box.height;
    double w, h;
    if (imgAR > boxAR) { w = box.width;  h = box.width  / imgAR; }
    else               { h = box.height; w = box.height * imgAR; }
    return Rect.fromLTWH(
        (box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  // ── Handle hit-testing ────────────────────────────────────────
  static Map<_CropHandle, Offset> _handleCenters(Rect r) => {
    _CropHandle.topLeft:      r.topLeft,
    _CropHandle.topCenter:    Offset(r.center.dx, r.top),
    _CropHandle.topRight:     r.topRight,
    _CropHandle.midLeft:      Offset(r.left,  r.center.dy),
    _CropHandle.midRight:     Offset(r.right, r.center.dy),
    _CropHandle.bottomLeft:   r.bottomLeft,
    _CropHandle.bottomCenter: Offset(r.center.dx, r.bottom),
    _CropHandle.bottomRight:  r.bottomRight,
  };

  _CropHandle? _hitHandle(Offset pos) {
    for (final e in _handleCenters(_cropRect).entries) {
      if ((pos - e.value).distance <= _handleR + _hitSlop) return e.key;
    }
    return null;
  }

  // ── Gesture callbacks ─────────────────────────────────────────
  void _onPanStart(DragStartDetails d) {
    final pos = d.localPosition;
    final hit = _hitHandle(pos);
    _activeHandle      = hit ?? (_cropRect.contains(pos)
        ? _CropHandle.move         // drag whole rect
        : _CropHandle.newRect);    // draw fresh selection
    _dragStart         = pos;
    _rectAtDragStart   = _cropRect;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_dragStart == null || _rectAtDragStart == null) return;
    final delta = d.localPosition - _dragStart!;
    final old   = _rectAtDragStart!;
    final img   = _imageDisplayRect;

    Rect next;
    switch (_activeHandle!) {
      case _CropHandle.move:
        next = _clamp(old.translate(delta.dx, delta.dy), img);
        break;
      case _CropHandle.newRect:
        next = _clamp(Rect.fromPoints(_dragStart!, d.localPosition), img);
        break;
      case _CropHandle.topLeft:
        next = _clamp(Rect.fromLTRB(
            old.left + delta.dx, old.top + delta.dy,
            old.right, old.bottom), img);
        break;
      case _CropHandle.topCenter:
        next = _clamp(Rect.fromLTRB(
            old.left, old.top + delta.dy,
            old.right, old.bottom), img);
        break;
      case _CropHandle.topRight:
        next = _clamp(Rect.fromLTRB(
            old.left, old.top + delta.dy,
            old.right + delta.dx, old.bottom), img);
        break;
      case _CropHandle.midLeft:
        next = _clamp(Rect.fromLTRB(
            old.left + delta.dx, old.top,
            old.right, old.bottom), img);
        break;
      case _CropHandle.midRight:
        next = _clamp(Rect.fromLTRB(
            old.left, old.top,
            old.right + delta.dx, old.bottom), img);
        break;
      case _CropHandle.bottomLeft:
        next = _clamp(Rect.fromLTRB(
            old.left + delta.dx, old.top,
            old.right, old.bottom + delta.dy), img);
        break;
      case _CropHandle.bottomCenter:
        next = _clamp(Rect.fromLTRB(
            old.left, old.top,
            old.right, old.bottom + delta.dy), img);
        break;
      case _CropHandle.bottomRight:
        next = _clamp(Rect.fromLTRB(
            old.left, old.top,
            old.right + delta.dx, old.bottom + delta.dy), img);
        break;
    }

    // Only accept if large enough
    if (next.width >= _minCrop && next.height >= _minCrop) {
      setState(() => _cropRect = next);
    }
  }

  void _onPanEnd(DragEndDetails _) {
    _activeHandle    = null;
    _dragStart       = null;
    _rectAtDragStart = null;
  }

  /// Normalise and clamp [r] so it stays within [imgRect].
  Rect _clamp(Rect r, Rect imgRect) {
    final l = min(r.left,   r.right);
    final t = min(r.top,    r.bottom);
    final ri = max(r.left,  r.right);
    final b  = max(r.top,   r.bottom);
    return Rect.fromLTRB(
      l.clamp(imgRect.left,  imgRect.right),
      t.clamp(imgRect.top,   imgRect.bottom),
      ri.clamp(imgRect.left, imgRect.right),
      b.clamp(imgRect.top,   imgRect.bottom),
    );
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mq   = MediaQuery.of(context);
    final maxH = (mq.size.height * 0.88).clamp(420.0, 820.0);
    final maxW = (mq.size.width  * 0.92).clamp(340.0, 720.0);

    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: maxW, maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title bar ────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 13),
              decoration: const BoxDecoration(
                color: _navy,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(children: [
                const Icon(Icons.crop_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Text('Crop Signature',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(null),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white70, size: 20),
                ),
              ]),
            ),

            // ── Crop canvas ──────────────────────────────────────
            Flexible(
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ))
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!,
                                style: GoogleFonts.poppins(
                                    color: Colors.red[700])),
                          ))
                      : LayoutBuilder(
                          builder: (_, cst) {
                            final img  = _image!;
                            final size = Size(cst.maxWidth,
                                cst.maxHeight);

                            // Update layout field (no setState)
                            _imageDisplayRect = _fitRect(size, img);

                            // Initialise crop rect once after image load
                            // or rotation — scheduled post-frame to avoid
                            // setState-during-build.
                            if (!_cropInitialized) {
                              WidgetsBinding.instance
                                  .addPostFrameCallback((_) {
                                if (mounted && !_cropInitialized) {
                                  setState(() {
                                    _cropRect        = _imageDisplayRect;
                                    _cropInitialized = true;
                                  });
                                }
                              });
                            }

                            final effectiveCrop = _cropInitialized
                                ? _cropRect
                                : _imageDisplayRect;

                            return GestureDetector(
                              onPanStart:  _onPanStart,
                              onPanUpdate: _onPanUpdate,
                              onPanEnd:    _onPanEnd,
                              child: CustomPaint(
                                size: size,
                                painter: _CropOverlayPainter(
                                  image:            img,
                                  imageDisplayRect: _imageDisplayRect,
                                  cropRect:         effectiveCrop,
                                  handleRadius:     _handleR,
                                  navy:             _navy,
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // ── Toolbar ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(14)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, -2)),
                ],
              ),
              child: Row(children: [
                // ── Rotate CCW ──────────────────────────────────
                _ToolbarIconBtn(
                  icon: Icons.rotate_left_rounded,
                  label: 'Rotate Left',
                  enabled: !_loading && !_cropping,
                  onTap: () => _rotate(clockwise: false),
                ),
                const SizedBox(width: 6),
                // ── Rotate CW ───────────────────────────────────
                _ToolbarIconBtn(
                  icon: Icons.rotate_right_rounded,
                  label: 'Rotate Right',
                  enabled: !_loading && !_cropping,
                  onTap: () => _rotate(clockwise: true),
                ),
                const Spacer(),
                // ── Cancel ──────────────────────────────────────
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: Text('Cancel',
                      style: GoogleFonts.poppins(
                          color: Colors.grey[600],
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ),
                const SizedBox(width: 8),
                // ── Use Crop ────────────────────────────────────
                ElevatedButton.icon(
                  onPressed: (_loading || _cropping || !_cropInitialized)
                      ? null
                      : _confirmCrop,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        _navy.withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: _cropping
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 16),
                  label: Text(
                      _cropping ? 'Cropping…' : 'Use Crop',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small toolbar icon button ──────────────────────────────────────
class _ToolbarIconBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final bool     enabled;
  final VoidCallback onTap;

  const _ToolbarIconBtn({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? const Color(0xFF0A2E5A)
        : Colors.grey[300]!;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled ? onTap : null,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 9,
                  color: color,
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

// ── Crop handle enum ───────────────────────────────────────────────
enum _CropHandle {
  topLeft, topCenter, topRight,
  midLeft, midRight,
  bottomLeft, bottomCenter, bottomRight,
  move,    // drag whole rect
  newRect, // drawing brand-new selection
}

// ── Crop overlay painter ───────────────────────────────────────────
class _CropOverlayPainter extends CustomPainter {
  final ui.Image image;
  final Rect     imageDisplayRect;
  final Rect     cropRect;
  final double   handleRadius;
  final Color    navy;

  const _CropOverlayPainter({
    required this.image,
    required this.imageDisplayRect,
    required this.cropRect,
    required this.handleRadius,
    required this.navy,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── 1. Draw the source image scaled to imageDisplayRect ──────
    paintImage(
      canvas: canvas,
      rect:   imageDisplayRect,
      image:  image,
      fit:    BoxFit.fill,
    );

    // ── 2. Semi-transparent dark mask outside the crop rect ──────
    final mask = Paint()..color = Colors.black.withValues(alpha: 0.52);
    // Top strip
    canvas.drawRect(
        Rect.fromLTRB(imageDisplayRect.left, imageDisplayRect.top,
            imageDisplayRect.right, cropRect.top),
        mask);
    // Bottom strip
    canvas.drawRect(
        Rect.fromLTRB(imageDisplayRect.left, cropRect.bottom,
            imageDisplayRect.right, imageDisplayRect.bottom),
        mask);
    // Left strip
    canvas.drawRect(
        Rect.fromLTRB(imageDisplayRect.left, cropRect.top,
            cropRect.left, cropRect.bottom),
        mask);
    // Right strip
    canvas.drawRect(
        Rect.fromLTRB(cropRect.right, cropRect.top,
            imageDisplayRect.right, cropRect.bottom),
        mask);

    // ── 3. Crop border ───────────────────────────────────────────
    canvas.drawRect(
        cropRect,
        Paint()
          ..color     = Colors.white
          ..style     = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // ── 4. Rule-of-thirds grid ────────────────────────────────────
    final grid = Paint()
      ..color       = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 0.7;
    for (int i = 1; i <= 2; i++) {
      final x = cropRect.left + cropRect.width  * i / 3;
      final y = cropRect.top  + cropRect.height * i / 3;
      canvas.drawLine(Offset(x, cropRect.top),    Offset(x, cropRect.bottom), grid);
      canvas.drawLine(Offset(cropRect.left, y),   Offset(cropRect.right, y),  grid);
    }

    // ── 5. Corner L-bracket accents (bold, 16 px arms) ───────────
    const arm = 16.0;
    final corner = Paint()
      ..color       = Colors.white
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap   = StrokeCap.square;
    // Top-left
    canvas.drawLine(cropRect.topLeft, cropRect.topLeft + const Offset(arm, 0), corner);
    canvas.drawLine(cropRect.topLeft, cropRect.topLeft + const Offset(0, arm), corner);
    // Top-right
    canvas.drawLine(cropRect.topRight, cropRect.topRight + const Offset(-arm, 0), corner);
    canvas.drawLine(cropRect.topRight, cropRect.topRight + const Offset(0, arm), corner);
    // Bottom-left
    canvas.drawLine(cropRect.bottomLeft, cropRect.bottomLeft + const Offset(arm, 0), corner);
    canvas.drawLine(cropRect.bottomLeft, cropRect.bottomLeft + const Offset(0, -arm), corner);
    // Bottom-right
    canvas.drawLine(cropRect.bottomRight, cropRect.bottomRight + const Offset(-arm, 0), corner);
    canvas.drawLine(cropRect.bottomRight, cropRect.bottomRight + const Offset(0, -arm), corner);

    // ── 6. Drag handles (filled circles at 8 control points) ─────
    final hFill   = Paint()..color = Colors.white;
    final hBorder = Paint()
      ..color       = navy.withValues(alpha: 0.75)
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final r = cropRect;
    for (final pt in [
      r.topLeft,
      Offset(r.center.dx, r.top),
      r.topRight,
      Offset(r.left,  r.center.dy),
      Offset(r.right, r.center.dy),
      r.bottomLeft,
      Offset(r.center.dx, r.bottom),
      r.bottomRight,
    ]) {
      canvas.drawCircle(pt, handleRadius, hFill);
      canvas.drawCircle(pt, handleRadius, hBorder);
    }
  }

  @override
  bool shouldRepaint(_CropOverlayPainter old) =>
      old.image            != image            ||
      old.imageDisplayRect != imageDisplayRect ||
      old.cropRect         != cropRect;
}