import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:almaworks/models/project_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
// image_cropper is used on Android / iOS only.
// On web it depends on Cropper.js which may not be loaded, causing
// "dart.global.Cropper is not a constructor" and the
// "cropper has not been initialized" cascade. We therefore gate the
// import behind a non-web conditional and use crop_your_image (pure
// Flutter, zero JS dependencies) for web / desktop instead.
import 'package:image_cropper/image_cropper.dart'
    if (dart.library.html) 'package:almaworks/screens/utils/image_cropper_stub.dart';
import 'package:crop_your_image/crop_your_image.dart' hide ImageCropper;
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

// ══════════════════════════════════════════════════════════════════
// MONTHLY TABLE DATA MODEL
// Represents an inline editable table embedded within a section.
// ══════════════════════════════════════════════════════════════════
class MonthlyTableData {
  final String id;
  String title;
  List<String> columnNames;
  List<Map<String, String>> rows;
  bool showRowNumbers; // whether to prepend a read-only "#" row-number column

  MonthlyTableData({
    required this.id,
    this.title = 'Table',
    required this.columnNames,
    required this.rows,
    this.showRowNumbers = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'columnNames': columnNames,
        'rows': rows,
        'showRowNumbers': showRowNumbers,
      };

  factory MonthlyTableData.fromMap(Map<String, dynamic> m) => MonthlyTableData(
        id: m['id'] ?? const Uuid().v4(),
        title: m['title'] ?? 'Table',
        columnNames: List<String>.from(m['columnNames'] ?? []),
        rows: (m['rows'] as List<dynamic>?)
                ?.map((r) => Map<String, String>.from(r as Map))
                .toList() ??
            [],
        showRowNumbers: m['showRowNumbers'] as bool? ?? false,
      );
}

// ══════════════════════════════════════════════════════════════════
// SIGNEE DATA MODEL
// ══════════════════════════════════════════════════════════════════
class SigneeData {
  String name;
  String organisation;
  /// In-memory PNG bytes — captured from the draw pad or an uploaded image.
  /// Uploaded to Firebase Storage on save; do NOT store directly in Firestore.
  Uint8List? signatureBytes;
  /// Firebase Storage download URL of the uploaded signature PNG.
  /// Persisted in Firestore so the signature survives reload.
  String? signatureUrl;

  SigneeData({
    this.name = '',
    this.organisation = '',
    this.signatureBytes,
    this.signatureUrl,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'organisation': organisation,
        // signatureBytes intentionally omitted (too large for Firestore)
        'signatureUrl': signatureUrl, // Firebase Storage URL — persisted
      };

  factory SigneeData.fromMap(Map<String, dynamic> m) => SigneeData(
        name: m['name'] as String? ?? '',
        organisation: m['organisation'] as String? ?? '',
        signatureUrl: m['signatureUrl'] as String?,
      );
}

// ══════════════════════════════════════════════════════════════════
// MONTHLY REPORT DATA MODEL
// ══════════════════════════════════════════════════════════════════
class MonthlyReportData {
  final String id;
  final String projectId;
  final String projectName;
  String contractNumber;
  DateTime monthStart;
  DateTime monthEnd;
  // Section A
  String building;
  String sectionAJson;
  List<MonthlyTableData> sectionATables;
  List<String> sectionAImageUrls;
  // Section B
  String sectionBJson;
  List<MonthlyTableData> sectionBTables;
  List<String> sectionBImageUrls;
  // Section C
  String sectionCJson;
  List<MonthlyTableData> sectionCTables;
  List<String> sectionCImageUrls;
  // Section D
  int plannedMonth; // 1–12
  String sectionDJson;
  List<MonthlyTableData> sectionDTables;
  List<String> sectionDImageUrls;
  // Signatories
  List<SigneeData> signees;
  bool isDraft;
  DateTime? savedAt;

  MonthlyReportData({
    required this.id,
    required this.projectId,
    required this.projectName,
    this.contractNumber = '',
    required this.monthStart,
    required this.monthEnd,
    this.building = '',
    this.sectionAJson = '',
    List<MonthlyTableData>? sectionATables,
    this.sectionAImageUrls = const [],
    this.sectionBJson = '',
    List<MonthlyTableData>? sectionBTables,
    this.sectionBImageUrls = const [],
    this.sectionCJson = '',
    List<MonthlyTableData>? sectionCTables,
    this.sectionCImageUrls = const [],
    int? plannedMonth,
    this.sectionDJson = '',
    List<MonthlyTableData>? sectionDTables,
    this.sectionDImageUrls = const [],
    List<SigneeData>? signees,
    this.isDraft = true,
    this.savedAt,
  })  : sectionATables = sectionATables ?? [],
        sectionBTables = sectionBTables ?? [],
        sectionCTables = sectionCTables ?? [],
        sectionDTables = sectionDTables ?? [],
        plannedMonth = plannedMonth ?? DateTime.now().month,
        signees = signees ?? [SigneeData(), SigneeData()];

  Map<String, dynamic> toMap() => {
        'id': id,
        'projectId': projectId,
        'projectName': projectName,
        'contractNumber': contractNumber,
        'monthStart': Timestamp.fromDate(monthStart),
        'monthEnd': Timestamp.fromDate(monthEnd),
        'building': building,
        'sectionAJson': sectionAJson,
        'sectionATables': sectionATables.map((t) => t.toMap()).toList(),
        'sectionAImageUrls': sectionAImageUrls,
        'sectionBJson': sectionBJson,
        'sectionBTables': sectionBTables.map((t) => t.toMap()).toList(),
        'sectionBImageUrls': sectionBImageUrls,
        'sectionCJson': sectionCJson,
        'sectionCTables': sectionCTables.map((t) => t.toMap()).toList(),
        'sectionCImageUrls': sectionCImageUrls,
        'plannedMonth': plannedMonth,
        'sectionDJson': sectionDJson,
        'sectionDTables': sectionDTables.map((t) => t.toMap()).toList(),
        'sectionDImageUrls': sectionDImageUrls,
        'signees': signees.map((s) => s.toMap()).toList(),
        'isDraft': isDraft,
        'savedAt': Timestamp.now(),
        'type': 'Monthly',
      };

  static List<MonthlyTableData> _parseTables(dynamic raw) {
    if (raw == null) return [];
    return (raw as List<dynamic>)
        .map((e) => MonthlyTableData.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  factory MonthlyReportData.fromMap(Map<String, dynamic> m) => MonthlyReportData(
        id: m['id'] ?? '',
        projectId: m['projectId'] ?? '',
        projectName: m['projectName'] ?? '',
        contractNumber: m['contractNumber'] ?? '',
        monthStart: (m['monthStart'] as Timestamp).toDate(),
        monthEnd: (m['monthEnd'] as Timestamp).toDate(),
        building: m['building'] ?? '',
        sectionAJson: m['sectionAJson'] ?? '',
        sectionATables: _parseTables(m['sectionATables']),
        sectionAImageUrls: List<String>.from(m['sectionAImageUrls'] ?? []),
        sectionBJson: m['sectionBJson'] ?? '',
        sectionBTables: _parseTables(m['sectionBTables']),
        sectionBImageUrls: List<String>.from(m['sectionBImageUrls'] ?? []),
        sectionCJson: m['sectionCJson'] ?? '',
        sectionCTables: _parseTables(m['sectionCTables']),
        sectionCImageUrls: List<String>.from(m['sectionCImageUrls'] ?? []),
        plannedMonth: m['plannedMonth'] ?? DateTime.now().month,
        sectionDJson: m['sectionDJson'] ?? '',
        sectionDTables: _parseTables(m['sectionDTables']),
        sectionDImageUrls: List<String>.from(m['sectionDImageUrls'] ?? []),
        signees: (m['signees'] as List<dynamic>?)
                ?.map((e) =>
                    SigneeData.fromMap(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [SigneeData(), SigneeData()],
        isDraft: m['isDraft'] ?? true,
      );
}

// ══════════════════════════════════════════════════════════════════
// SCREEN WIDGET
// ══════════════════════════════════════════════════════════════════
class MonthlyReportFormScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final MonthlyReportData? existingReport;
  /// When true all fields are read-only; a floating Edit button unlocks them.
  final bool isReadOnly;
  /// When true the Edit FAB is permanently hidden regardless of [isReadOnly].
  /// Set this for client users who are allowed to view but never modify reports.
  final bool isClientView;

  const MonthlyReportFormScreen({
    super.key,
    required this.project,
    required this.logger,
    this.existingReport,
    this.isReadOnly = false,
    this.isClientView = false,
  });

  @override
  State<MonthlyReportFormScreen> createState() =>
      _MonthlyReportFormScreenState();
}

class _MonthlyReportFormScreenState extends State<MonthlyReportFormScreen> {
  // ── Form + scroll ──────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();

  // ── Read-only mode ─────────────────────────────────────────────
  bool _isReadOnly = false;

  // ── Design constants ───────────────────────────────────────────
  static const _navy = Color(0xFF0A2E5A);
  static const _fieldBorder = Color(0xFFB0BEC5);
  static const _sectionBg = Color(0xFFF5F7FA);
  static const _accentGreen = Color(0xFF1B5E20);
  static const _accentPurple = Color(0xFF6A1B9A);

  // ── Header fields ──────────────────────────────────────────────
  final _contractCtrl = TextEditingController();
  final _buildingCtrl = TextEditingController();

  // ── Date range ─────────────────────────────────────────────────
  late DateTime _monthStart;
  late DateTime _monthEnd;

  // ── Section Quill controllers ──────────────────────────────────
  late quill.QuillController _sectionACtrl;
  late quill.QuillController _sectionBCtrl;
  late quill.QuillController _sectionCCtrl;
  late quill.QuillController _sectionDCtrl;

  // ── Inline tables per section ──────────────────────────────────
  final List<MonthlyTableData> _sectionATables = [];
  final List<MonthlyTableData> _sectionBTables = [];
  final List<MonthlyTableData> _sectionCTables = [];
  final List<MonthlyTableData> _sectionDTables = [];

  // ── Images per section ─────────────────────────────────────────
  final List<Uint8List> _sectionALocalImages = [];
  final List<String> _sectionASavedUrls = [];
  final List<Uint8List> _sectionBLocalImages = [];
  final List<String> _sectionBSavedUrls = [];
  final List<Uint8List> _sectionCLocalImages = [];
  final List<String> _sectionCSavedUrls = [];
  final List<Uint8List> _sectionDLocalImages = [];
  final List<String> _sectionDSavedUrls = [];

  // ── Section D – planned month ──────────────────────────────────
  int _plannedMonth = DateTime.now().month;

  // ── Signees ────────────────────────────────────────────────────
  final _signee1NameCtrl = TextEditingController();
  final _signee1OrgCtrl = TextEditingController();
  final _signee2NameCtrl = TextEditingController();
  final _signee2OrgCtrl = TextEditingController();
  /// In-memory bytes from the draw pad for each signee.
  Uint8List? _signee1Bytes;
  Uint8List? _signee2Bytes;
  /// Bytes picked via image picker (alternative to drawing).
  Uint8List? _signee1PickedBytes;
  Uint8List? _signee2PickedBytes;
  /// Firebase Storage URLs loaded from a saved report.
  String? _signee1SigUrl;
  String? _signee2SigUrl;
  /// Active input mode per signee:  0 = Draw · 1 = Photo · 2 = From PDF
  int _signee1Mode = 0;
  int _signee2Mode = 0;

  // ── Loading flags ──────────────────────────────────────────────
  bool _isSaving = false;
  bool _isGeneratingPdf = false;

  // ── Report ID ─────────────────────────────────────────────────
  late String _reportId;

  // ── Cache key ─────────────────────────────────────────────────
  String get _cacheKey =>
      'monthly_report_draft_${widget.project.id}_$_reportId';

  // ── Month names helper ─────────────────────────────────────────
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  // ─────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    widget.logger.i('📋 MonthlyForm: initState START');
    _reportId = widget.existingReport?.id ?? const Uuid().v4();
    _isReadOnly = widget.isReadOnly;

    // Default month: first→last of current month
    final now = DateTime.now();
    _monthStart = DateTime(now.year, now.month, 1);
    _monthEnd = DateTime(now.year, now.month + 1, 0); // last day of month

    if (widget.existingReport != null) {
      _loadFromExisting(widget.existingReport!);
    } else {
      _sectionACtrl = quill.QuillController.basic();
      _sectionBCtrl = quill.QuillController.basic();
      _sectionCCtrl = quill.QuillController.basic();
      _sectionDCtrl = quill.QuillController.basic();
      _loadDraftFromCache();
    }
    widget.logger.i('📋 MonthlyForm: initState END reportId=$_reportId');
  }

  void _loadFromExisting(MonthlyReportData r) {
    _contractCtrl.text = r.contractNumber;
    _buildingCtrl.text = r.building;
    _monthStart = r.monthStart;
    _monthEnd = r.monthEnd;
    _plannedMonth = r.plannedMonth;
    _sectionASavedUrls.addAll(r.sectionAImageUrls);
    _sectionBSavedUrls.addAll(r.sectionBImageUrls);
    _sectionCSavedUrls.addAll(r.sectionCImageUrls);
    _sectionDSavedUrls.addAll(r.sectionDImageUrls);
    _sectionATables.addAll(r.sectionATables);
    _sectionBTables.addAll(r.sectionBTables);
    _sectionCTables.addAll(r.sectionCTables);
    _sectionDTables.addAll(r.sectionDTables);
    _sectionACtrl = _quillFromJson('sectionA', r.sectionAJson);
    _sectionBCtrl = _quillFromJson('sectionB', r.sectionBJson);
    _sectionCCtrl = _quillFromJson('sectionC', r.sectionCJson);
    _sectionDCtrl = _quillFromJson('sectionD', r.sectionDJson);
    // Signees — name, organisation, and persisted signature URL
    if (r.signees.isNotEmpty) {
      _signee1NameCtrl.text = r.signees[0].name;
      _signee1OrgCtrl.text  = r.signees[0].organisation;
      _signee1SigUrl        = r.signees[0].signatureUrl;
    }
    if (r.signees.length > 1) {
      _signee2NameCtrl.text = r.signees[1].name;
      _signee2OrgCtrl.text  = r.signees[1].organisation;
      _signee2SigUrl        = r.signees[1].signatureUrl;
    }
  }

  quill.QuillController _quillFromJson(String key, String json) {
    if (json.isEmpty) return quill.QuillController.basic();
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return quill.QuillController.basic();
      return quill.QuillController(
        document: quill.Document.fromJson(decoded),
        selection: const TextSelection.collapsed(offset: 0),
      );
    } catch (e) {
      widget.logger.w('⚠️ MonthlyForm: quillFromJson [$key] failed – $e');
      return quill.QuillController.basic();
    }
  }

  @override
  void dispose() {
    widget.logger.i('📋 MonthlyForm: dispose');
    _contractCtrl.dispose();
    _buildingCtrl.dispose();
    _scrollCtrl.dispose();
    _sectionACtrl.dispose();
    _sectionBCtrl.dispose();
    _sectionCCtrl.dispose();
    _sectionDCtrl.dispose();
    _signee1NameCtrl.dispose();
    _signee1OrgCtrl.dispose();
    _signee2NameCtrl.dispose();
    _signee2OrgCtrl.dispose();
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
        'monthStart': _monthStart.toIso8601String(),
        'monthEnd': _monthEnd.toIso8601String(),
        'plannedMonth': _plannedMonth,
        'sectionAJson':
            jsonEncode(_sectionACtrl.document.toDelta().toJson()),
        'sectionBJson':
            jsonEncode(_sectionBCtrl.document.toDelta().toJson()),
        'sectionCJson':
            jsonEncode(_sectionCCtrl.document.toDelta().toJson()),
        'sectionDJson':
            jsonEncode(_sectionDCtrl.document.toDelta().toJson()),
        'sectionATables': _sectionATables.map((t) => t.toMap()).toList(),
        'sectionBTables': _sectionBTables.map((t) => t.toMap()).toList(),
        'sectionCTables': _sectionCTables.map((t) => t.toMap()).toList(),
        'sectionDTables': _sectionDTables.map((t) => t.toMap()).toList(),
        'sectionASavedUrls': _sectionASavedUrls,
        'sectionBSavedUrls': _sectionBSavedUrls,
        'sectionCSavedUrls': _sectionCSavedUrls,
        'sectionDSavedUrls': _sectionDSavedUrls,
        'signee1Name': _signee1NameCtrl.text,
        'signee1Org': _signee1OrgCtrl.text,
        'signee2Name': _signee2NameCtrl.text,
        'signee2Org': _signee2OrgCtrl.text,
        // Persist signature URLs so draft restoration shows existing sigs
        if (_signee1SigUrl != null) 'signee1SigUrl': _signee1SigUrl,
        if (_signee2SigUrl != null) 'signee2SigUrl': _signee2SigUrl,
      };
      await prefs.setString(_cacheKey, jsonEncode(data));
    } catch (e) {
      widget.logger.w('⚠️ MonthlyForm: cache save failed – $e');
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
        if (data['monthStart'] != null) {
          _monthStart = DateTime.parse(data['monthStart']);
        }
        if (data['monthEnd'] != null) {
          _monthEnd = DateTime.parse(data['monthEnd']);
        }
        _plannedMonth = data['plannedMonth'] ?? DateTime.now().month;
        _sectionACtrl =
            _quillFromJson('sectionA', data['sectionAJson'] ?? '');
        _sectionBCtrl =
            _quillFromJson('sectionB', data['sectionBJson'] ?? '');
        _sectionCCtrl =
            _quillFromJson('sectionC', data['sectionCJson'] ?? '');
        _sectionDCtrl =
            _quillFromJson('sectionD', data['sectionDJson'] ?? '');
        // Tables
        void loadTables(
            List<dynamic>? raw, List<MonthlyTableData> target) {
          if (raw == null) return;
          target.clear();
          target.addAll(raw.map((e) =>
              MonthlyTableData.fromMap(Map<String, dynamic>.from(e as Map))));
        }

        loadTables(data['sectionATables'] as List?, _sectionATables);
        loadTables(data['sectionBTables'] as List?, _sectionBTables);
        loadTables(data['sectionCTables'] as List?, _sectionCTables);
        loadTables(data['sectionDTables'] as List?, _sectionDTables);
        _sectionASavedUrls
          ..clear()
          ..addAll(List<String>.from(data['sectionASavedUrls'] ?? []));
        _sectionBSavedUrls
          ..clear()
          ..addAll(List<String>.from(data['sectionBSavedUrls'] ?? []));
        _sectionCSavedUrls
          ..clear()
          ..addAll(List<String>.from(data['sectionCSavedUrls'] ?? []));
        _sectionDSavedUrls
          ..clear()
          ..addAll(List<String>.from(data['sectionDSavedUrls'] ?? []));
        _signee1NameCtrl.text = data['signee1Name'] ?? '';
        _signee1OrgCtrl.text = data['signee1Org'] ?? '';
        _signee2NameCtrl.text = data['signee2Name'] ?? '';
        _signee2OrgCtrl.text = data['signee2Org'] ?? '';
        // Restore persisted signature URLs
        _signee1SigUrl = data['signee1SigUrl'] as String?;
        _signee2SigUrl = data['signee2SigUrl'] as String?;
      });
      widget.logger.i('📋 MonthlyForm: draft restored from cache');
    } catch (e, st) {
      widget.logger.e('❌ MonthlyForm: cache load failed',
          error: e, stackTrace: st);
    }
  }

  Future<void> _clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }

  // ─────────────────────────────────────────────────────────────
  // DATE PICKERS
  // ─────────────────────────────────────────────────────────────
  Future<void> _pickMonthStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _monthStart,
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
    if (picked == null) return;
    setState(() {
      _monthStart = picked;
      if (_monthEnd.isBefore(_monthStart)) {
        _monthEnd = DateTime(_monthStart.year, _monthStart.month + 1, 0);
      }
    });
    _saveDraftToCache();
  }

  Future<void> _pickMonthEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _monthEnd.isBefore(_monthStart) ? _monthStart : _monthEnd,
      firstDate: _monthStart,
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
              primary: _navy, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _monthEnd = picked);
    _saveDraftToCache();
  }

  // ─────────────────────────────────────────────────────────────
  // SIGNATURE CROP / PHOTO / PDF HELPERS
  // ─────────────────────────────────────────────────────────────
  //
  // PLATFORM STRATEGY
  // ─────────────────
  // • Web / desktop  → _showInAppCropper()
  //   Uses crop_your_image — a pure-Flutter widget with zero JS
  //   dependencies.  This eliminates the "dart.global.Cropper is
  //   not a constructor" and "cropper has not been initialized"
  //   errors that were caused by image_cropper_for_web requiring
  //   Cropper.js to be loaded in index.html.
  //
  // • Android / iOS  → image_cropper native UI (unchanged).
  //   image_cropper delegates to the platform's native cropping
  //   activity and works perfectly on mobile.

  /// Shows the pure-Flutter crop dialog (crop_your_image).
  /// Returns cropped PNG bytes, or null if cancelled.
  Future<Uint8List?> _showInAppCropper(Uint8List imageBytes) async {
    return showDialog<Uint8List?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CropDialog(imageBytes: imageBytes),
    );
  }

  /// Crop bytes on Android/iOS via image_cropper (native UI).
  /// On web/desktop this path is never called — _cropImage routes to
  /// _showInAppCropper instead.
  Future<Uint8List?> _cropFromPathNative(String sourcePath) async {
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
        ],
      );
      if (cropped == null) return null;
      return await cropped.readAsBytes();
    } catch (e) {
      widget.logger.w('⚠️ MonthlyForm: native crop failed – $e');
      return null;
    }
  }

  /// Crops [bytes] using the appropriate strategy for the current platform:
  ///   • Web / desktop  → in-app Flutter dialog (crop_your_image)
  ///   • Android / iOS  → native image_cropper (temp-file round-trip)
  Future<Uint8List?> _cropImage(Uint8List bytes) async {
    // ── Web & desktop: pure-Flutter in-app cropper ──────────────
    if (kIsWeb ||
        (!kIsWeb &&
            defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return _showInAppCropper(bytes);
    }

    // ── Android / iOS: image_cropper via temp file ───────────────
    File? tmp;
    try {
      final dir = await getTemporaryDirectory();
      tmp = File(
          '${dir.path}/sig_tmp_${DateTime.now().millisecondsSinceEpoch}.png');
      await tmp.writeAsBytes(bytes);
      return await _cropFromPathNative(tmp.path);
    } catch (e) {
      widget.logger.w('⚠️ MonthlyForm: _cropImage write failed – $e');
      return null;
    } finally {
      try {
        await tmp?.delete();
      } catch (_) {}
    }
  }

  /// Pick a photo (gallery / camera) then launch the platform-appropriate
  /// cropper.
  Future<void> _pickAndCropPhoto(int signeeIndex) async {
    if (!mounted) return;

    // ── On web, camera is not reliably available — skip the source sheet ──
    ImageSource? source;
    if (kIsWeb) {
      source = ImageSource.gallery;
    } else {
      source = await showModalBottomSheet<ImageSource>(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
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
                leading: const Icon(Icons.camera_alt_rounded, color: _navy),
                title: Text('Take a Photo',
                    style: GoogleFonts.poppins(fontSize: 13)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    }

    if (source == null || !mounted) return;

    try {
      final xfile = await ImagePicker()
          .pickImage(source: source, imageQuality: 92, maxWidth: 2000);
      if (xfile == null || !mounted) return;

      // Read bytes first so both paths (web + native) work uniformly
      // through _cropImage, which handles the platform branching.
      final rawBytes = await xfile.readAsBytes();
      final Uint8List? cropped = await _cropImage(rawBytes);

      if (cropped == null || !mounted) return;
      setState(() {
        if (signeeIndex == 1) {
          _signee1PickedBytes = cropped;
          _signee1Bytes = null;
        } else {
          _signee2PickedBytes = cropped;
          _signee2Bytes = null;
        }
      });
      _saveDraftToCache();
    } catch (e) {
      widget.logger.w('⚠️ MonthlyForm: pick+crop photo failed – $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not process photo: $e',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red[700],
        ));
      }
    }
  }

  /// Pick a PDF, render pages via Printing.raster(), select page, crop.
  /// Handles both bytes (web/some Android) and path (mobile) from FilePicker.
  Future<void> _pickFromPdf(int signeeIndex) async {
    // ── Step 1: pick PDF ────────────────────────────────────────
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,      // populated on web + some mobile configs
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final picked = result.files.first;

    // ── Step 2: resolve bytes (bytes OR path fallback) ──────────
    Uint8List? pdfBytes = picked.bytes;
    if (pdfBytes == null && picked.path != null && !kIsWeb) {
      try {
        pdfBytes = await File(picked.path!).readAsBytes();
      } catch (e) {
        widget.logger.w('⚠️ MonthlyForm: PDF read from path failed – $e');
      }
    }
    if (pdfBytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not read the selected PDF file.',
            style: GoogleFonts.poppins()),
        backgroundColor: Colors.red[700],
      ));
      return;
    }

    // ── Step 3: show loading + rasterise pages ──────────────────
    if (mounted) setState(() => _isGeneratingPdf = true);

    final List<Uint8List> pageImages = [];
    try {
      await for (final page
          in Printing.raster(pdfBytes, dpi: 180)) {
        pageImages.add(await page.toPng());
        if (pageImages.length >= 10) break;
      }
    } catch (e) {
      widget.logger.w('⚠️ MonthlyForm: PDF raster failed – $e');
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not render PDF: $e',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red[700],
        ));
      }
      return;
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }

    if (pageImages.isEmpty || !mounted) return;

    // ── Step 4: page selector — single-page skips the dialog ────
    Uint8List chosenPage;
    if (pageImages.length == 1) {
      // Single-page PDF: go straight to cropper
      chosenPage = pageImages.first;
    } else {
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
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(14)),
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: pageImages.length,
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () =>
                          Navigator.pop(ctx, pageImages[i]),
                      child: Column(children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color:
                                        _navy.withValues(alpha: 0.3),
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
      if (chosen == null || !mounted) return;
      chosenPage = chosen;
    }

    // ── Step 5: crop ─────────────────────────────────────────────
    final cropped = await _cropImage(chosenPage);
    if (cropped == null || !mounted) return;

    setState(() {
      if (signeeIndex == 1) {
        _signee1PickedBytes = cropped;
        _signee1Bytes = null;
      } else {
        _signee2PickedBytes = cropped;
        _signee2Bytes = null;
      }
    });
    _saveDraftToCache();
  }

  // ─────────────────────────────────────────────────────────────
  // IMAGE PICKING (per section)
  // ─────────────────────────────────────────────────────────────
  Future<void> _pickImages(int sectionIndex) async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 80);
    if (picked.isEmpty) return;
    final lists = [
      _sectionALocalImages,
      _sectionBLocalImages,
      _sectionCLocalImages,
      _sectionDLocalImages,
    ];
    for (final xf in picked) {
      final bytes = await xf.readAsBytes();
      setState(() => lists[sectionIndex].add(bytes));
    }
  }

  // ── Full-screen image viewer ──────────────────────────────────
  void _showImageViewer(List<_MImageItem> images, int initialIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => _MImageViewerDialog(
        images: images,
        initialIndex: initialIndex,
      ),
    );
  }

  // ── PDF 2-column image grid ───────────────────────────────────
  List<pw.Widget> _buildPdfImageGrid(List<pw.MemoryImage> images) {
    const double pageW = 539.0;
    const double gap   = 8.0;
    const double colW2 = (pageW - gap) / 2;
    const double colH2 = colW2 * 0.68;
    const double soloW = pageW * 0.55;
    const double soloH = soloW * 0.68;
    final rows = <pw.Widget>[];
    if (images.length == 1) {
      rows.add(pw.Center(
        child: pw.Image(images[0],
            width: soloW, height: soloH, fit: pw.BoxFit.cover),
      ));
      return rows;
    }
    for (int i = 0; i < images.length; i += 2) {
      final hasNext = i + 1 < images.length;
      rows.add(pw.Row(children: [
        pw.Image(images[i],
            width: colW2, height: colH2, fit: pw.BoxFit.cover),
        if (hasNext) ...[
          pw.SizedBox(width: gap),
          pw.Image(images[i + 1],
              width: colW2, height: colH2, fit: pw.BoxFit.cover),
        ] else
          pw.SizedBox(width: colW2 + gap),
      ]));
      if (i + 2 < images.length) rows.add(pw.SizedBox(height: gap));
    }
    return rows;
  }

  // ─────────────────────────────────────────────────────────────
  // TABLE INSERT DIALOG
  // Uses a dedicated StatefulWidget so TextFields never lose focus
  // on counter-button rebuilds.
  // ─────────────────────────────────────────────────────────────
  Future<void> _showInsertTableDialog({
    required List<MonthlyTableData> targetList,
  }) async {
    final result = await showDialog<MonthlyTableData?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _InsertTableDialog(),
    );

    if (result == null) return;
    setState(() => targetList.add(result));
    _saveDraftToCache();
  }


  // ─────────────────────────────────────────────────────────────
  // SAVE
  // ─────────────────────────────────────────────────────────────
  /// Uploads a signature PNG to Firebase Storage and returns the download URL.
  /// Accepts either draw-pad bytes or image-picker bytes, whichever is set.
  Future<String?> _uploadSignature(
      int signeeIndex, Uint8List? drawBytes, Uint8List? pickedBytes) async {
    final bytes = drawBytes ?? pickedBytes;
    if (bytes == null) return null;
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child(widget.project.id)
          .child('Reports')
          .child('Monthly')
          .child('signatures')
          .child('${_reportId}_signee${signeeIndex + 1}.png');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/png'));
      final url = await ref.getDownloadURL();
      widget.logger.i('📋 MonthlyForm: signature[$signeeIndex] uploaded → $url');
      return url;
    } catch (e) {
      widget.logger.w('⚠️ MonthlyForm: signature[$signeeIndex] upload failed – $e');
      return null;
    }
  }

  Future<void> _saveReport({bool silent = false}) async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? true)) return;
    setState(() => _isSaving = true);
    try {
      final allUrls = await _uploadSectionImages();

      // ── Upload signatures if new bytes are available ──────────
      // Only re-upload when the user has drawn or picked a NEW signature
      // this session; otherwise keep the existing URL as-is.
      final sig1Url = (_signee1Bytes != null || _signee1PickedBytes != null)
          ? await _uploadSignature(0, _signee1Bytes, _signee1PickedBytes)
          : _signee1SigUrl;
      final sig2Url = (_signee2Bytes != null || _signee2PickedBytes != null)
          ? await _uploadSignature(1, _signee2Bytes, _signee2PickedBytes)
          : _signee2SigUrl;

      // Persist URLs back to state so a subsequent save doesn't re-upload
      setState(() {
        if (sig1Url != null) _signee1SigUrl = sig1Url;
        if (sig2Url != null) _signee2SigUrl = sig2Url;
      });
      final report = MonthlyReportData(
        id: _reportId,
        projectId: widget.project.id,
        projectName: widget.project.name,
        contractNumber: _contractCtrl.text.trim(),
        monthStart: _monthStart,
        monthEnd: _monthEnd,
        building: _buildingCtrl.text.trim(),
        sectionAJson:
            jsonEncode(_sectionACtrl.document.toDelta().toJson()),
        sectionATables: _sectionATables,
        sectionAImageUrls: allUrls[0],
        sectionBJson:
            jsonEncode(_sectionBCtrl.document.toDelta().toJson()),
        sectionBTables: _sectionBTables,
        sectionBImageUrls: allUrls[1],
        sectionCJson:
            jsonEncode(_sectionCCtrl.document.toDelta().toJson()),
        sectionCTables: _sectionCTables,
        sectionCImageUrls: allUrls[2],
        plannedMonth: _plannedMonth,
        sectionDJson:
            jsonEncode(_sectionDCtrl.document.toDelta().toJson()),
        sectionDTables: _sectionDTables,
        sectionDImageUrls: allUrls[3],
        signees: [
          SigneeData(
              name: _signee1NameCtrl.text,
              organisation: _signee1OrgCtrl.text,
              signatureBytes: _signee1Bytes ?? _signee1PickedBytes,
              signatureUrl: sig1Url),
          SigneeData(
              name: _signee2NameCtrl.text,
              organisation: _signee2OrgCtrl.text,
              signatureBytes: _signee2Bytes ?? _signee2PickedBytes,
              signatureUrl: sig2Url),
        ],
        isDraft: false,
      );
      final map = report.toMap();
      if (widget.existingReport == null) {
        map['uploadedAt'] = Timestamp.now();
        map['name'] =
            'Monthly Report – ${DateFormat('MMMM yyyy').format(_monthStart)}';
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
      await _clearCache();
      widget.logger.i('✅ MonthlyForm: saved $_reportId');
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Monthly report saved!',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.green[700],
        ));
      }
    } catch (e, st) {
      widget.logger.e('❌ MonthlyForm: save failed', error: e, stackTrace: st);
      if (!silent && mounted) _showError('Save failed: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Uploads all section local images and returns lists of URLs per section.
  Future<List<List<String>>> _uploadSectionImages() async {
    final result = <List<String>>[
      List.from(_sectionASavedUrls),
      List.from(_sectionBSavedUrls),
      List.from(_sectionCSavedUrls),
      List.from(_sectionDSavedUrls),
    ];
    final locals = [
      _sectionALocalImages,
      _sectionBLocalImages,
      _sectionCLocalImages,
      _sectionDLocalImages,
    ];
    final labels = ['A', 'B', 'C', 'D'];
    for (int s = 0; s < 4; s++) {
      for (int i = 0; i < locals[s].length; i++) {
        final ref = FirebaseStorage.instance
            .ref()
            .child(widget.project.id)
            .child('Reports')
            .child('Monthly')
            .child('section${labels[s]}')
            .child('${_reportId}_img_$i.jpg');
        await ref.putData(
            locals[s][i], SettableMetadata(contentType: 'image/jpeg'));
        result[s].add(await ref.getDownloadURL());
      }
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────
  // ADD NEW FORM
  // ─────────────────────────────────────────────────────────────
  Future<void> _addNewForm() async {
    await _saveReport(silent: true);
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('New Monthly Report',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text('Current form saved. Start a fresh monthly report?',
            style: GoogleFonts.poppins()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: GoogleFonts.poppins())),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: _navy, foregroundColor: Colors.white),
            child: Text('New Form', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => MonthlyReportFormScreen(
                project: widget.project, logger: widget.logger)));
  }

  // ─────────────────────────────────────────────────────────────
  // PDF GENERATION
  Future<void> _downloadAsPdf() async {
    setState(() => _isGeneratingPdf = true);
    try {
      // ── Colours ──────────────────────────────────────────────
      final navyColor = PdfColor.fromHex('#0A2E5A');
      final lightBlue = PdfColor.fromHex('#E8EEF6');

      // ── Text styles ──────────────────────────────────────────
      final sectionHeaderStyle = pw.TextStyle(
        font: pw.Font.helveticaBold(),
        fontSize: 9.5,
        color: PdfColors.white,
        letterSpacing: 0.5,
      );
      final tableHeaderStyle = pw.TextStyle(
        font: pw.Font.helveticaBold(),
        fontSize: 7.5,
        color: PdfColors.white,
      );
      final fieldLabelStyle = pw.TextStyle(
        font: pw.Font.helveticaBold(),
        fontSize: 8,
        color: navyColor,
        letterSpacing: 0.3,
      );
      final fieldValueStyle = pw.TextStyle(
        font: pw.Font.helvetica(),
        fontSize: 9,
        color: PdfColors.black,
      );

      // ── Collect section images ────────────────────────────────
      Future<List<pw.MemoryImage>> loadImgs(
          List<Uint8List> local, List<String> urls) async {
        final imgs = <pw.MemoryImage>[];
        for (final b in local) {
          imgs.add(pw.MemoryImage(b));
        }
        for (final url in urls) {
          try {
            final data = await FirebaseStorage.instance
                .refFromURL(url)
                .getData(10 * 1024 * 1024);
            if (data != null) imgs.add(pw.MemoryImage(data));
          } catch (e) {
            widget.logger.w('⚠️ MonthlyForm: image fetch – $url – $e');
          }
        }
        return imgs;
      }

      final aImgs = await loadImgs(_sectionALocalImages, _sectionASavedUrls);
      final bImgs = await loadImgs(_sectionBLocalImages, _sectionBSavedUrls);
      final cImgs = await loadImgs(_sectionCLocalImages, _sectionCSavedUrls);
      final dImgs = await loadImgs(_sectionDLocalImages, _sectionDSavedUrls);

      // ── Resolve signature bytes for PDF ──────────────────────
      // Priority: in-session drawn/picked bytes → stored Firebase URL
      Future<Uint8List?> resolveSigBytes(
          Uint8List? drawn, Uint8List? picked, String? url) async {
        if (drawn != null) return drawn;
        if (picked != null) return picked;
        if (url != null && url.isNotEmpty) {
          try {
            return await FirebaseStorage.instance
                .refFromURL(url)
                .getData(2 * 1024 * 1024); // 2 MB cap for signatures
          } catch (e) {
            widget.logger.w('⚠️ MonthlyForm: sig fetch from URL failed – $e');
          }
        }
        return null;
      }

      final sig1Bytes = await resolveSigBytes(
          _signee1Bytes, _signee1PickedBytes, _signee1SigUrl);
      final sig2Bytes = await resolveSigBytes(
          _signee2Bytes, _signee2PickedBytes, _signee2SigUrl);

      // ── Helper: section bar ──────────────────────────────────
      // Identical structure to weekly sectionBar — plain Container + Text,
      // NO pw.Row / pw.Expanded inside. The letter badge uses a Row but
      // the Container itself is the top-level MultiPage child.
      pw.Widget sectionBar(String letter, String title) =>
          pw.Container(
            width: double.infinity,
            color: navyColor,
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Letter badge — rounded white box with navy text,
                // matching the screen's semi-transparent white badge.
                pw.Container(
                  width: 24,
                  height: 24,
                  alignment: pw.Alignment.center,
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius:
                        pw.BorderRadius.all(pw.Radius.circular(5)),
                  ),
                  child: pw.Text(letter,
                      style: pw.TextStyle(
                          font: pw.Font.helveticaBold(),
                          fontSize: 12,
                          color: navyColor)),
                ),
                pw.SizedBox(width: 10),
                pw.Text(title, style: sectionHeaderStyle),
              ],
            ),
          );

      // ── Helper: date cell (replaces plain metaCell for dates) ──
      // Mirrors the screen's _buildMonthDateRow: coloured label strip
      // on left, label text + bold date value on right.
      // IMPORTANT: no pw.Center with stretch, no emoji (Helvetica can't
      // render Unicode), no MainAxisAlignment.center in an unbounded Column.
      pw.Widget dateCell(String label, String value) =>
          pw.Expanded(
            child: pw.Container(
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                border: pw.Border.all(
                    color: PdfColors.blueGrey300, width: 0.5)),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left accent strip — fixed width, no stretch/Center
                  pw.Container(
                    width: 28,
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 4, vertical: 7),
                    color: lightBlue,
                    child: pw.Text('CAL',
                        style: pw.TextStyle(
                            font: pw.Font.helveticaBold(),
                            fontSize: 5,
                            color: navyColor,
                            letterSpacing: 0.3)),
                  ),
                  // Label + value stacked
                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(label,
                              style: pw.TextStyle(
                                  font: pw.Font.helveticaBold(),
                                  fontSize: 7,
                                  color: navyColor,
                                  letterSpacing: 0.4)),
                          pw.SizedBox(height: 3),
                          pw.Text(value,
                              style: pw.TextStyle(
                                  font: pw.Font.helveticaBold(),
                                  fontSize: 9.5,
                                  color: PdfColors.black)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );



      // ── Helper: text body for a section ──────────────────────
      pw.Widget richBody(quill.QuillController ctrl) {
        final text = ctrl.document.toPlainText().trim();
        return pw.Container(
          width: double.infinity,
          height: text.isEmpty ? 60 : null,
          decoration: pw.BoxDecoration(
              border: pw.Border.all(
                  color: PdfColors.blueGrey300, width: 0.5)),
          padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: text.isEmpty
              ? pw.SizedBox()
              : pw.Text(text, style: fieldValueStyle),
        );
      }

      // ── Helper: inline table bodies ──────────────────────────
      // Structurally identical to weekly _buildPdfTable.
      List<pw.Widget> tableBodies(List<MonthlyTableData> tables) {
        return tables.map((t) {
          if (t.columnNames.isEmpty) return pw.SizedBox();
          final colCount = t.columnNames.length;
          final Map<int, pw.TableColumnWidth> colWidths = {};
          int offset = 0;
          if (t.showRowNumbers) {
            colWidths[0] = const pw.FixedColumnWidth(28);
            offset = 1;
          }
          for (int i = 0; i < colCount; i++) {
            colWidths[i + offset] = const pw.FlexColumnWidth(1);
          }
          final tableRows = <pw.TableRow>[];
          // Header row
          final headerCells = <pw.Widget>[];
          if (t.showRowNumbers) {
            headerCells.add(pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 4, vertical: 5),
              child: pw.Text('#', style: tableHeaderStyle),
            ));
          }
          for (final col in t.columnNames) {
            headerCells.add(pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 4, vertical: 5),
              child: pw.Text(col,
                  softWrap: true, style: tableHeaderStyle),
            ));
          }
          tableRows.add(pw.TableRow(
            decoration: pw.BoxDecoration(color: navyColor),
            children: headerCells,
          ));
          // Data / blank rows
          // Empty rows are sized for hand-writing after printing:
          // 26pt total height (vertical: 13 top + bottom padding).
          if (t.rows.isEmpty) {
            for (int i = 0; i < 6; i++) {
              final bg = i.isEven
                  ? PdfColors.white
                  : PdfColor.fromHex('#F5F7FA');
              final totalCols =
                  t.showRowNumbers ? colCount + 1 : colCount;
              tableRows.add(pw.TableRow(
                decoration: pw.BoxDecoration(color: bg),
                children: List.generate(
                  totalCols,
                  (_) => pw.SizedBox(height: 26),
                ),
              ));
            }
          } else {
            for (int i = 0; i < t.rows.length; i++) {
              final bg = i.isEven
                  ? PdfColors.white
                  : PdfColor.fromHex('#F5F7FA');
              final cells = <pw.Widget>[];
              if (t.showRowNumbers) {
                cells.add(pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 4, vertical: 5),
                  child: pw.Text('${i + 1}',
                      style: fieldValueStyle),
                ));
              }
              for (final col in t.columnNames) {
                cells.add(pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 4, vertical: 5),
                  child: pw.Text(
                    t.rows[i][col] ?? '',
                    softWrap: true,
                    style: fieldValueStyle,
                  ),
                ));
              }
              tableRows.add(pw.TableRow(
                decoration: pw.BoxDecoration(color: bg),
                children: cells,
              ));
            }
          }
          // Outer Column — same as weekly _buildPdfTable (no mainAxisSize)
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 6),
              pw.Container(
                width: double.infinity,
                color: lightBlue,
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6, vertical: 3),
                child: pw.Text(t.title,
                    style: pw.TextStyle(
                        font: pw.Font.helveticaBold(),
                        fontSize: 8,
                        color: navyColor)),
              ),
              pw.Table(
                border: pw.TableBorder.all(
                    color: PdfColors.blueGrey300, width: 0.5),
                columnWidths: colWidths,
                children: tableRows,
              ),
            ],
          );
        }).toList();
      }

      // ── Helper: single-line write-in field ───────────────────
      // Renders a labelled row with a ruled underline when empty,
      // or the filled value as text — NO em-dash placeholders that
      // can render as black boxes in some PDF viewers.
      pw.Widget writeField(String label, String value) =>
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 8, vertical: 6),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('$label: ',
                    style: pw.TextStyle(
                        font: pw.Font.helveticaBold(),
                        fontSize: 8,
                        color: navyColor)),
                pw.Expanded(
                  child: value.isEmpty
                      ? pw.SizedBox()
                      : pw.Text(value, style: fieldValueStyle),
                ),
              ],
            ),
          );

      // ── Helper: signature block ───────────────────────────────
      pw.Widget signeeBlock(
          String label, String name, String org, Uint8List? sig) {
        return pw.Expanded(
          child: pw.Container(
            decoration: pw.BoxDecoration(
                border: pw.Border.all(
                    color: PdfColors.blueGrey300, width: 0.5)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Label strip
                pw.Container(
                  width: double.infinity,
                  color: lightBlue,
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: pw.Text(label, style: fieldLabelStyle),
                ),
                // Name field
                writeField('Name', name),
                pw.Divider(color: PdfColors.blueGrey100, thickness: 0.3),
                // Organisation field
                writeField('Organisation', org),
                pw.Divider(color: PdfColors.blueGrey100, thickness: 0.3),
                // Signature area
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Signature:',
                          style: pw.TextStyle(
                              font: pw.Font.helveticaBold(),
                              fontSize: 8,
                              color: navyColor)),
                      pw.SizedBox(height: 6),
                      // Signature image OR a blank ruled box
                      sig != null && sig.isNotEmpty
                          ? pw.Image(pw.MemoryImage(sig),
                              height: 55, fit: pw.BoxFit.contain)
                          : pw.Container(
                              height: 55,
                              decoration: pw.BoxDecoration(
                                  border: pw.Border.all(
                                      color: PdfColors.blueGrey200,
                                      width: 0.5),
                                  borderRadius:
                                      const pw.BorderRadius.all(
                                          pw.Radius.circular(3)))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }

      // ── Smart section body ────────────────────────────────────
      List<pw.Widget> sectionBody(
          quill.QuillController ctrl, List<MonthlyTableData> tables) {
        final hasText = ctrl.document.toPlainText().trim().isNotEmpty;
        final hasTables = tables.isNotEmpty;
        if (!hasText && !hasTables) return [richBody(ctrl)];
        return [
          if (hasText) richBody(ctrl),
          ...tableBodies(tables),
        ];
      }

      // ══════════════════════════════════════════════════════════
      // BUILD PDF — structure mirrors the working weekly report
      // ══════════════════════════════════════════════════════════
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 48),
          footer: (ctx) => pw.Container(
            decoration: const pw.BoxDecoration(
                border: pw.Border(
                    top: pw.BorderSide(
                        color: PdfColors.grey400, width: 0.5))),
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                    '© JV Almacis Site Management System - Monthly Report',
                    style: pw.TextStyle(
                        font: pw.Font.helvetica(),
                        fontSize: 7,
                        color: PdfColors.grey600)),
                pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                    style: pw.TextStyle(
                        font: pw.Font.helvetica(),
                        fontSize: 7,
                        color: PdfColors.grey600)),
              ],
            ),
          ),
          build: (ctx) => [
            // ── HEADER BAND ────────────────────────────────────
            // Mirrors the screen: navy band contains project name
            // + contract number. "MONTHLY REPORT" sits BELOW the
            // band as a large navy bold title, just like the UI.
            pw.Container(
              width: double.infinity,
              color: navyColor,
              padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(widget.project.name,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                          font: pw.Font.helveticaBold(),
                          fontSize: 14,
                          color: PdfColors.white)),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text('Contract No: ',
                          style: pw.TextStyle(
                              font: pw.Font.helvetica(),
                              fontSize: 8.5,
                              color: PdfColor.fromHex('#FFFFFFB3'))),
                      _contractCtrl.text.isEmpty
                          ? pw.SizedBox()
                          : pw.Text(
                              _contractCtrl.text,
                              style: pw.TextStyle(
                                  font: pw.Font.helveticaBold(),
                                  fontSize: 8.5,
                                  color: PdfColors.white)),
                    ],
                  ),
                ],
              ),
            ),
            // ── "MONTHLY REPORT" title — below the header band,
            //    navy-coloured bold text, matching the screen UI.
            pw.SizedBox(height: 10),
            pw.Container(
              width: double.infinity,
              child: pw.Text(
                'MONTHLY REPORT',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    font: pw.Font.helveticaBold(),
                    fontSize: 16,
                    color: navyColor,
                    letterSpacing: 3),
              ),
            ),
            pw.SizedBox(height: 10),
            // ── DATE META ROW ──────────────────────────────────
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                dateCell('MONTH START',
                    DateFormat('EEE, MMM d, yyyy').format(_monthStart)),
                pw.SizedBox(width: 6),
                dateCell('MONTH END',
                    DateFormat('EEE, MMM d, yyyy').format(_monthEnd)),
              ],
            ),
            pw.SizedBox(height: 10),
            // ══ SECTION A ══════════════════════════════════════
            sectionBar('A', 'SITE ACTIVITIES'),
            pw.SizedBox(height: 4),
            // Building — inline label + value row
            pw.Container(
              width: double.infinity,
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: PdfColors.blueGrey300, width: 0.5)),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    color: lightBlue,
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 8),
                    child: pw.Text('BUILDING',
                        style: fieldLabelStyle),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: _buildingCtrl.text.isEmpty
                        ? pw.SizedBox()
                        : pw.Text(_buildingCtrl.text,
                            style: fieldValueStyle),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 4),
            ...sectionBody(_sectionACtrl, _sectionATables),
            if (aImgs.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              ..._buildPdfImageGrid(aImgs),
            ],
            pw.SizedBox(height: 10),
            // ══ SECTION B ══════════════════════════════════════
            sectionBar('B', 'QUALITY REPORT'),
            pw.SizedBox(height: 4),
            ...sectionBody(_sectionBCtrl, _sectionBTables),
            if (bImgs.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              ..._buildPdfImageGrid(bImgs),
            ],
            pw.SizedBox(height: 10),
            // ══ SECTION C ══════════════════════════════════════
            sectionBar('C', 'SAFETY REPORT'),
            pw.SizedBox(height: 4),
            ...sectionBody(_sectionCCtrl, _sectionCTables),
            if (cImgs.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              ..._buildPdfImageGrid(cImgs),
            ],
            pw.SizedBox(height: 10),
            // ══ SECTION D ══════════════════════════════════════
            sectionBar('D',
                'PLANNED ACTIVITIES FOR ${_monthNames[_plannedMonth - 1].toUpperCase()}'),
            pw.SizedBox(height: 4),
            ...sectionBody(_sectionDCtrl, _sectionDTables),
            if (dImgs.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              ..._buildPdfImageGrid(dImgs),
            ],
            pw.SizedBox(height: 12),
            // ══ SIGNATURES ═════════════════════════════════════
            pw.Container(
              width: double.infinity,
              color: navyColor,
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    width: 24,
                    height: 24,
                    alignment: pw.Alignment.center,
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius:
                          pw.BorderRadius.all(pw.Radius.circular(5)),
                    ),
                    child: pw.Text('S',
                        style: pw.TextStyle(
                            font: pw.Font.helveticaBold(),
                            fontSize: 12,
                            color: navyColor)),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Text('SIGNATURES', style: sectionHeaderStyle),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                signeeBlock('SIGNEE 1', _signee1NameCtrl.text,
                    _signee1OrgCtrl.text, sig1Bytes),
                pw.SizedBox(width: 8),
                signeeBlock('SIGNEE 2', _signee2NameCtrl.text,
                    _signee2OrgCtrl.text, sig2Bytes),
              ],
            ),
          ],
        ),
      );

      final bytes = await pdf.save();
      final fileName =
          'Monthly_Report_${widget.project.name.replaceAll(' ', '_')}_'
          '${DateFormat('yyyyMM').format(_monthStart)}.pdf';
      await _savePdfBytes(Uint8List.fromList(bytes), fileName);
      widget.logger.i('✅ MonthlyForm: PDF complete $fileName');
    } catch (e, st) {
      widget.logger.e('❌ MonthlyForm: PDF failed', error: e, stackTrace: st);
      if (mounted) _showError('Error generating PDF: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

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
        content: Text('PDF saved: $fileName', style: GoogleFonts.poppins()),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: GoogleFonts.poppins()),
        backgroundColor: Colors.red[700]));
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      floatingActionButton: _isReadOnly && !widget.isClientView
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _isReadOnly = false),
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.edit_rounded),
              label: Text('Edit', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            )
          : null,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '${widget.project.name} — Monthly Report${_isReadOnly ? ' (View)' : ''}',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () async {
            final nav = Navigator.of(context);
            await _saveDraftToCache();
            if (!context.mounted) return;
            nav.pop();
          },
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                  child:
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final aw = constraints.maxWidth;
          final contentW = aw.clamp(0.0, 860.0);
          final hPad = contentW * 0.04;
          const gap = 14.0;

          return Form(
            key: _formKey,
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── FORM HEADER ────────────────────────────────
                  _buildFormHeader(),

                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: gap),

                        // ── REPORT TYPE TITLE ─────────────────────
                        _buildReportTypeTitle(),
                        const SizedBox(height: gap),

                        // ── MONTH DATE RANGE ──────────────────────
                        _buildMonthDateRow(),
                        const SizedBox(height: gap + 4),

                        // ── SECTION A: SITE ACTIVITIES ────────────
                        _buildSectionCard(
                          letter: 'A',
                          title: 'SITE ACTIVITIES',
                          sectionIndex: 0,
                          ctrl: _sectionACtrl,
                          tables: _sectionATables,
                          localImages: _sectionALocalImages,
                          savedUrls: _sectionASavedUrls,
                          hint: 'Describe site activities for the month…',
                          showBuildingField: true,
                        ),
                        const SizedBox(height: gap + 4),

                        // ── SECTION B: QUALITY REPORT ─────────────
                        _buildSectionCard(
                          letter: 'B',
                          title: 'QUALITY REPORT',
                          sectionIndex: 1,
                          ctrl: _sectionBCtrl,
                          tables: _sectionBTables,
                          localImages: _sectionBLocalImages,
                          savedUrls: _sectionBSavedUrls,
                          hint: 'Enter quality observations and findings…',
                          showBuildingField: false,
                        ),
                        const SizedBox(height: gap + 4),

                        // ── SECTION C: SAFETY REPORT ──────────────
                        _buildSectionCard(
                          letter: 'C',
                          title: 'SAFETY REPORT',
                          sectionIndex: 2,
                          ctrl: _sectionCCtrl,
                          tables: _sectionCTables,
                          localImages: _sectionCLocalImages,
                          savedUrls: _sectionCSavedUrls,
                          hint: 'Document safety incidents, observations…',
                          showBuildingField: false,
                        ),
                        const SizedBox(height: gap + 4),

                        // ── SECTION D: PLANNED ACTIVITIES ─────────
                        _buildSectionD(),
                        const SizedBox(height: gap + 4),

                        // ── SIGNING SECTION ───────────────────────
                        _buildSigningSection(),
                        const SizedBox(height: 20),

                        // ── GLOBAL ACTION BUTTONS ─────────────────
                        _buildGlobalActionButtons(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // WIDGET BUILDERS
  // ══════════════════════════════════════════════════════════════

  // ── Full-width navy header band ──────────────────────────────
  Widget _buildFormHeader() {
    return Container(
      color: _navy,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                  onChanged: _isReadOnly ? null : (_) => _saveDraftToCache(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── "MONTHLY REPORT" centred subtitle ───────────────────────
  Widget _buildReportTypeTitle() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'MONTHLY REPORT',
          style: GoogleFonts.poppins(
            color: _navy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
      ),
    );
  }

  // ── Month Start / Month End date pickers (2 columns) ────────
  Widget _buildMonthDateRow() {
    const double labelFs = 10.0;
    const double valueFs = 12.5;

    Widget dateCell(
        {required String label,
        required DateTime date,
        required VoidCallback onTap}) {
      return Expanded(
        child: GestureDetector(
          onTap: _isReadOnly ? null : onTap,
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _fieldBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                )
              ],
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  const Icon(Icons.calendar_month_rounded,
                      color: _navy, size: 15),
                  const SizedBox(width: 4),
                  Text(label,
                      style: GoogleFonts.poppins(
                        fontSize: labelFs,
                        fontWeight: FontWeight.w600,
                        color: _navy.withValues(alpha: 0.7),
                        letterSpacing: 0.3,
                      )),
                ]),
                const SizedBox(height: 3),
                Text(
                  DateFormat('EEE, MMM d, yyyy').format(date),
                  style: GoogleFonts.poppins(
                    fontSize: valueFs,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(children: [
      dateCell(
          label: 'MONTH START',
          date: _monthStart,
          onTap: _pickMonthStart),
      const SizedBox(width: 8),
      dateCell(
          label: 'MONTH END', date: _monthEnd, onTap: _pickMonthEnd),
    ]);
  }

  // ── Building field (Section A only) ─────────────────────────
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
            child: Center(
              child: TextFormField(
                controller: _buildingCtrl,
                readOnly: _isReadOnly,
                textAlignVertical: TextAlignVertical.center,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'[a-zA-Z0-9\s\-_/]'))
                ],
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
                onChanged: _isReadOnly ? null : (_) => _saveDraftToCache(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Generic section card (A / B / C) ────────────────────────
  Widget _buildSectionCard({
    required String letter,
    required String title,
    required int sectionIndex,
    required quill.QuillController ctrl,
    required List<MonthlyTableData> tables,
    required List<Uint8List> localImages,
    required List<String> savedUrls,
    required String hint,
    required bool showBuildingField,
  }) {
    const double radius = 10.0;
    final allImages = [
      ...localImages.map((b) => _MImageItem(bytes: b)),
      ...savedUrls.map((u) => _MImageItem(url: u)),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final aw = constraints.maxWidth;
      final double thumbW = ((aw - 24 - 8) / 2).clamp(100.0, 300.0);
      final double thumbH = thumbW * 0.70;

      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: _fieldBorder, width: 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section title bar with letter badge ───────────
            _buildSectionTitleBar(letter, title, radius),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Building field — Section A only
                  if (showBuildingField) ...[
                    _buildBuildingField(),
                    const SizedBox(height: 12),
                  ],

                  // ACTIVITIES rich text editor + inline tables
                  _buildRichEditorWithTables(
                    sectionKey: 'section$letter',
                    sectionTitle: 'ACTIVITIES',
                    hint: hint,
                    ctrl: ctrl,
                    tables: tables,
                  ),
                  const SizedBox(height: 12),

                  // ── Image thumbnails (if any attached) ───────
                  if (allImages.isNotEmpty) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FA),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFFB0BEC5), width: 0.8),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.photo_library_rounded,
                                size: 14, color: _navy),
                            const SizedBox(width: 6),
                            Text('Images (${allImages.length})',
                                style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _navy)),
                          ]),
                          const SizedBox(height: 8),
                          if (allImages.length == 1) ...[
                            Center(
                              child: GestureDetector(
                                onTap: () =>
                                    _showImageViewer(allImages, 0),
                                child: Stack(children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(7),
                                    child: allImages[0].bytes != null
                                        ? Image.memory(
                                            allImages[0].bytes!,
                                            width: thumbW * 1.4,
                                            height: thumbH * 1.4,
                                            fit: BoxFit.cover)
                                        : Image.network(
                                            allImages[0].url!,
                                            width: thumbW * 1.4,
                                            height: thumbH * 1.4,
                                            fit: BoxFit.cover),
                                  ),
                                  Positioned(
                                    bottom: 5, right: 5,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                          color: Colors.black45,
                                          shape: BoxShape.circle),
                                      child: const Icon(
                                          Icons.zoom_out_map_rounded,
                                          size: 13,
                                          color: Colors.white),
                                    ),
                                  ),
                                  if (!_isReadOnly)
                                    Positioned(
                                      top: 4, right: 4,
                                      child: GestureDetector(
                                        onTap: () => setState(() {
                                          if (localImages.isNotEmpty) {
                                            localImages.removeAt(0);
                                          } else {
                                            savedUrls.removeAt(0);
                                          }
                                        }),
                                        child: Container(
                                          decoration: const BoxDecoration(
                                              color: Colors.black54,
                                              shape: BoxShape.circle),
                                          padding:
                                              const EdgeInsets.all(3),
                                          child: const Icon(Icons.close,
                                              size: 11,
                                              color: Colors.white),
                                        ),
                                      ),
                                    ),
                                ]),
                              ),
                            ),
                          ] else ...[
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children:
                                  List.generate(allImages.length, (i) {
                                final item = allImages[i];
                                return GestureDetector(
                                  onTap: () =>
                                      _showImageViewer(allImages, i),
                                  child: Stack(children: [
                                    ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(7),
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
                                        padding:
                                            const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(
                                            color: Colors.black45,
                                            shape: BoxShape.circle),
                                        child: const Icon(
                                            Icons.zoom_out_map_rounded,
                                            size: 10,
                                            color: Colors.white),
                                      ),
                                    ),
                                    if (!_isReadOnly)
                                      Positioned(
                                        top: 4, right: 4,
                                        child: GestureDetector(
                                          onTap: () => setState(() {
                                            if (i < localImages.length) {
                                              localImages.removeAt(i);
                                            } else {
                                              savedUrls.removeAt(
                                                  i - localImages.length);
                                            }
                                          }),
                                          child: Container(
                                            decoration: const BoxDecoration(
                                                color: Colors.black54,
                                                shape: BoxShape.circle),
                                            padding:
                                                const EdgeInsets.all(3),
                                            child: const Icon(Icons.close,
                                                size: 11,
                                                color: Colors.white),
                                          ),
                                        ),
                                      ),
                                  ]),
                                );
                              }),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Section action buttons
                  _buildSectionButtons(sectionIndex, localImages, savedUrls),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  // ── Section D: Planned Activities (with month picker) ───────
  Widget _buildSectionD() {
    const double radius = 10.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _fieldBorder, width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section D title with inline month picker ──────
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: _navy,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(radius),
                topRight: Radius.circular(radius),
              ),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Letter badge
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('D',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14)),
                ),
                const SizedBox(width: 10),
                Text('PLANNED ACTIVITIES FOR',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.6,
                    )),
                const SizedBox(width: 8),
                // Month dropdown
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4), width: 1),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _plannedMonth,
                      isDense: true,
                      dropdownColor: _navy,
                      icon: const Icon(Icons.arrow_drop_down_rounded,
                          color: Colors.white, size: 18),
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12),
                      items: List.generate(
                          12,
                          (i) => DropdownMenuItem(
                              value: i + 1,
                              child: Text(_monthNames[i].toUpperCase(),
                                  style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)))),
                      onChanged: _isReadOnly
                          ? null
                          : (v) {
                              setState(() => _plannedMonth = v ?? _plannedMonth);
                              _saveDraftToCache();
                            },
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildRichEditorWithTables(
                  sectionKey: 'sectionD',
                  sectionTitle: 'PLANNED ACTIVITIES',
                  hint:
                      'Describe planned activities for ${_monthNames[_plannedMonth - 1]}…',
                  ctrl: _sectionDCtrl,
                  tables: _sectionDTables,
                ),
                const SizedBox(height: 12),
                _buildSectionButtons(3, _sectionDLocalImages,
                    _sectionDSavedUrls),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section title bar with letter badge ─────────────────────
  Widget _buildSectionTitleBar(
      String letter, String title, double radius) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius),
        ),
      ),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          // Letter badge
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(letter,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14)),
          ),
          const SizedBox(width: 10),
          Text(title,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.6,
              )),
        ],
      ),
    );
  }

  // ── Rich text editor + inline PlutoGrid tables ───────────────
  Widget _buildRichEditorWithTables({
    required String sectionKey,
    required String sectionTitle,
    required String hint,
    required quill.QuillController ctrl,
    required List<MonthlyTableData> tables,
  }) {
    final double toolbarSz = 38.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _fieldBorder, width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 3,
              offset: const Offset(0, 1))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sub-section title
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0F3A6B), // slightly lighter navy
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Text(sectionTitle,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 0.7)),
          ),

          // Toolbar + table insert button — hidden in read-only mode
          if (!_isReadOnly)
          Container(
            decoration: BoxDecoration(
              color: _sectionBg,
              border: Border(
                  bottom: BorderSide(color: _fieldBorder, width: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: quill.QuillSimpleToolbar(
                    controller: ctrl,
                    config: quill.QuillSimpleToolbarConfig(
                      showBoldButton: true,
                      showItalicButton: true,
                      showUnderLineButton: true,
                      showListBullets: true,
                      showListNumbers: true,
                      showIndent: true,
                      showClearFormat: true,
                      showFontSize: false,
                      showFontFamily: false,
                      showColorButton: false,
                      showBackgroundColorButton: false,
                      showSubscript: false,
                      showSuperscript: false,
                      showInlineCode: false,
                      showCodeBlock: false,
                      showQuote: false,
                      showLink: false,
                      showSearchButton: false,
                      showAlignmentButtons: true,
                      showHeaderStyle: false,
                      showDividers: true,
                      toolbarIconAlignment: WrapAlignment.start,
                      toolbarSize: toolbarSz,
                    ),
                  ),
                ),
                // Custom "Insert Table" button
                Tooltip(
                  message: 'Insert Table',
                  child: InkWell(
                    onTap: () =>
                        _showInsertTableDialog(targetList: tables),
                    child: Container(
                      width: toolbarSz,
                      height: toolbarSz,
                      alignment: Alignment.center,
                      child: const Icon(Icons.table_chart_rounded,
                          color: _navy, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),

          // Quill editor
          AbsorbPointer(
            absorbing: _isReadOnly,
            child: Container(
              constraints: const BoxConstraints(minHeight: 160),
              padding: const EdgeInsets.all(12),
              child: quill.QuillEditor.basic(
                controller: ctrl,
                config: quill.QuillEditorConfig(
                  placeholder: hint,
                  minHeight: 160,
                  expands: false,
                  scrollable: true,
                  autoFocus: false,
                  enableInteractiveSelection: true,
                  customStyles: quill.DefaultStyles(
                    placeHolder: quill.DefaultTextBlockStyle(
                      GoogleFonts.poppins(
                          color: Colors.grey[400], fontSize: 13),
                      const quill.HorizontalSpacing(0, 0),
                      const quill.VerticalSpacing(0, 0),
                      const quill.VerticalSpacing(0, 0),
                      null,
                    ),
                    paragraph: quill.DefaultTextBlockStyle(
                      GoogleFonts.poppins(
                          color: Colors.black87, fontSize: 13),
                      const quill.HorizontalSpacing(0, 0),
                      const quill.VerticalSpacing(2, 2),
                      const quill.VerticalSpacing(0, 0),
                      null,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Inline PlutoGrid tables
          if (tables.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                children: tables.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final table = entry.value;
                  return _InlineTableWidget(
                    key: ValueKey(table.id),
                    tableData: table,
                    readOnly: _isReadOnly,
                    onDelete: () {
                      setState(() => tables.removeAt(idx));
                      _saveDraftToCache();
                    },
                    onChanged: (_) => _saveDraftToCache(),
                  );
                }).toList(),
              ),
            ),

          // "Add Table" hint when no tables yet
          if (tables.isEmpty)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: InkWell(
                onTap: () =>
                    _showInsertTableDialog(targetList: tables),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: _navy.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _navy.withValues(alpha: 0.15),
                        width: 1,
                        style: BorderStyle.solid),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.table_chart_outlined,
                          color: _navy.withValues(alpha: 0.5), size: 16),
                      const SizedBox(width: 6),
                      Text('Tap ⊞ in toolbar to insert a table',
                          style: GoogleFonts.poppins(
                              color: _navy.withValues(alpha: 0.5),
                              fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Section action buttons (Attach Image / Add New Form) — edit mode only ─
  Widget _buildSectionButtons(
    int sectionIndex,
    List<Uint8List> localImages,
    List<String> savedUrls,
  ) {
    final imageCount = localImages.length + savedUrls.length;

    // In read-only mode there are no section-level action buttons
    if (_isReadOnly) return const SizedBox.shrink();

    return Row(children: [
      Expanded(
        child: SizedBox(
          height: 40,
          child: OutlinedButton.icon(
            onPressed: () => _pickImages(sectionIndex),
            icon: const Icon(Icons.attach_file_rounded, size: 15),
            label: Text(
              imageCount > 0 ? 'Attach ($imageCount)' : 'Attach',
              style: GoogleFonts.poppins(fontSize: 12),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _navy,
              side: const BorderSide(color: _navy, width: 1.2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7)),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      // Add New Form
      Expanded(
        child: SizedBox(
          height: 40,
          child: ElevatedButton.icon(
            onPressed: _addNewForm,
            icon: const Icon(Icons.add_circle_outline_rounded, size: 15),
            label: Text('Add Form',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7)),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              elevation: 1,
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
    ]);
  }

  // ── Signing section (2 signees) ──────────────────────────────
  Widget _buildSigningSection() {
    const double radius = 10.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _fieldBorder, width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title bar
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(radius),
                topRight: Radius.circular(radius),
              ),
            ),
            child: Row(children: [
              const Icon(Icons.draw_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('SIGNATURES',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.8)),
            ]),
          ),

          // Signee grid
          Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(builder: (ctx, c) {
              final twoCol = c.maxWidth > 480;
              if (twoCol) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        child: _buildSigneeCard(
                            1, _signee1NameCtrl, _signee1OrgCtrl,
                            (b) => setState(() => _signee1Bytes = b))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _buildSigneeCard(
                            2, _signee2NameCtrl, _signee2OrgCtrl,
                            (b) => setState(() => _signee2Bytes = b))),
                  ],
                );
              }
              return Column(children: [
                _buildSigneeCard(
                    1, _signee1NameCtrl, _signee1OrgCtrl,
                    (b) => setState(() => _signee1Bytes = b)),
                const SizedBox(height: 12),
                _buildSigneeCard(
                    2, _signee2NameCtrl, _signee2OrgCtrl,
                    (b) => setState(() => _signee2Bytes = b)),
              ]);
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSigneeCard(
    int index,
    TextEditingController nameCtrl,
    TextEditingController orgCtrl,
    Function(Uint8List?) onDrawSignature,
  ) {
    final int mode   = index == 1 ? _signee1Mode : _signee2Mode;
    final Uint8List? pickedBytes  = index == 1 ? _signee1PickedBytes : _signee2PickedBytes;
    final String?    sigUrl       = index == 1 ? _signee1SigUrl      : _signee2SigUrl;
    final Uint8List? drawnBytes   = index == 1 ? _signee1Bytes       : _signee2Bytes;
    final bool hasSig = drawnBytes != null ||
        pickedBytes != null ||
        (sigUrl != null && sigUrl.isNotEmpty);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _fieldBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Signee badge + Signed status ────────────────────────
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                  color: _navy, borderRadius: BorderRadius.circular(20)),
              child: Text('Signee $index',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11)),
            ),
            const Spacer(),
            if (hasSig)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  border: Border.all(color: Colors.green[300]!),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_rounded,
                      size: 12, color: Colors.green[700]),
                  const SizedBox(width: 4),
                  Text('Signed',
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.green[700])),
                ]),
              ),
          ]),
          const SizedBox(height: 10),

          // ── Name ────────────────────────────────────────────────
          _signeeTextField(
              ctrl: nameCtrl,
              label: 'Name',
              hint: 'Full name…',
              icon: Icons.person_outline_rounded),
          const SizedBox(height: 8),

          // ── Organisation ────────────────────────────────────────
          _signeeTextField(
              ctrl: orgCtrl,
              label: 'Organisation',
              hint: 'Company / organisation…',
              icon: Icons.business_outlined),
          const SizedBox(height: 12),

          // ── Signature label ─────────────────────────────────────
          Text('Signature',
              style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _navy.withValues(alpha: 0.8))),
          const SizedBox(height: 6),

          if (_isReadOnly) ...[
            // ── Read-only: show stored signature ──────────────────
            _buildSignatureDisplay(drawnBytes, pickedBytes, sigUrl),
          ] else ...[
            // ── Edit mode: 3-tab mode selector ────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _sigModeTab(
                    label: 'Draw',
                    icon: Icons.draw_rounded,
                    active: mode == 0,
                    onTap: () => setState(() {
                          if (index == 1) {
                            _signee1Mode = 0;
                          } else {
                            _signee2Mode = 0;
                          }
                        })),
                const SizedBox(width: 6),
                _sigModeTab(
                    label: 'Photo',
                    icon: Icons.photo_camera_rounded,
                    active: mode == 1,
                    onTap: () => setState(() {
                          if (index == 1) {
                            _signee1Mode = 1;
                          } else {
                            _signee2Mode = 1;
                          }
                        })),
                const SizedBox(width: 6),
                _sigModeTab(
                    label: 'From PDF',
                    icon: Icons.picture_as_pdf_rounded,
                    active: mode == 2,
                    onTap: () => setState(() {
                          if (index == 1) {
                            _signee1Mode = 2;
                          } else {
                            _signee2Mode = 2;
                          }
                        })),
              ]),
            ),
            const SizedBox(height: 10),

            // ── Mode content ──────────────────────────────────────
            if (mode == 0)
              // Draw pad
              _SignaturePadWidget(onSignatureChanged: onDrawSignature)
            else if (mode == 1)
              // Photo + crop
              _buildPhotoSignatureArea(index, pickedBytes, drawnBytes, sigUrl)
            else
              // PDF extraction + crop
              _buildPdfSignatureArea(index, pickedBytes, drawnBytes, sigUrl),
          ],
        ],
      ),
    );
  }

  /// Small pill-style tab for switching between Draw and Upload modes.
  Widget _sigModeTab({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

  /// Photo mode: shows picked/drawn/URL preview with a Pick & Crop button.
  Widget _buildPhotoSignatureArea(int signeeIndex,
      Uint8List? pickedBytes, Uint8List? drawnBytes, String? storedUrl) {
    final Uint8List? localBytes = pickedBytes ?? drawnBytes;
    final bool hasUrl = storedUrl != null && storedUrl.isNotEmpty;
    final bool hasImage = localBytes != null || hasUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sigPreviewBox(localBytes, storedUrl),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pickAndCropPhoto(signeeIndex),
              icon: const Icon(Icons.photo_camera_rounded, size: 14),
              label: Text(
                hasImage ? 'Replace & Crop' : 'Pick Photo & Crop',
                style: GoogleFonts.poppins(fontSize: 11),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _navy,
                side: const BorderSide(color: _navy, width: 1.2),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7)),
              ),
            ),
          ),
          if (hasImage) ...[
            const SizedBox(width: 8),
            _sigClearButton(signeeIndex),
          ],
        ]),
      ],
    );
  }

  /// PDF mode: shows current preview and a Pick PDF button.
  Widget _buildPdfSignatureArea(int signeeIndex,
      Uint8List? pickedBytes, Uint8List? drawnBytes, String? storedUrl) {
    final Uint8List? localBytes = pickedBytes ?? drawnBytes;
    final bool hasUrl = storedUrl != null && storedUrl.isNotEmpty;
    final bool hasImage = localBytes != null || hasUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Instruction strip
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFE8EEF6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(children: [
            Icon(Icons.info_outline_rounded,
                size: 13, color: _navy.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Pick a PDF → select the page → drag to crop the signature area',
                style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: _navy.withValues(alpha: 0.75)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        _sigPreviewBox(localBytes, storedUrl),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _pickFromPdf(signeeIndex),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 14),
              label: Text(
                hasImage ? 'Replace from PDF' : 'Pick PDF & Crop',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, fontSize: 11),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 9),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7)),
                elevation: 1,
              ),
            ),
          ),
          if (hasImage) ...[
            const SizedBox(width: 8),
            _sigClearButton(signeeIndex),
          ],
        ]),
      ],
    );
  }

  /// Shared preview box used by both Photo and PDF modes.
  Widget _sigPreviewBox(Uint8List? localBytes, String? storedUrl) {
    final bool hasUrl = storedUrl != null && storedUrl.isNotEmpty;
    final bool hasImage = localBytes != null || hasUrl;

    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasImage
              ? _navy.withValues(alpha: 0.45)
              : _fieldBorder,
          width: hasImage ? 1.5 : 1.0,
        ),
      ),
      child: hasImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: localBytes != null
                  ? Image.memory(localBytes, fit: BoxFit.contain)
                  : Image.network(storedUrl!,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, prog) =>
                          prog == null
                              ? child
                              : const Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                      errorBuilder: (_, _, _) => Center(
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
                      )),
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

  /// Shared Clear button for Photo and PDF modes.
  Widget _sigClearButton(int signeeIndex) {
    return TextButton.icon(
      onPressed: () {
        setState(() {
          if (signeeIndex == 1) {
            _signee1PickedBytes = null;
            _signee1SigUrl = null;
          } else {
            _signee2PickedBytes = null;
            _signee2SigUrl = null;
          }
        });
        _saveDraftToCache();
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

  /// Read-only signature display — shows draw bytes, picked bytes,
  /// or fetches the stored Firebase Storage URL image inline.
  Widget _buildSignatureDisplay(
      Uint8List? drawnBytes, Uint8List? pickedBytes, String? url) {
    final Uint8List? localBytes = drawnBytes ?? pickedBytes;
    final bool hasUrl = url != null && url.isNotEmpty;
    final bool hasAny = localBytes != null || hasUrl;

    if (!hasAny) {
      return Container(
        height: 80,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _fieldBorder),
        ),
        child: Center(
          child: Text('No signature provided',
              style: GoogleFonts.poppins(
                  color: Colors.grey[400], fontSize: 12)),
        ),
      );
    }

    return Container(
      height: 100,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: _navy.withValues(alpha: 0.3), width: 1.2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: localBytes != null
            ? Image.memory(localBytes, fit: BoxFit.contain)
            : Image.network(
                url!,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                errorBuilder: (_, _, _) => Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image_rounded,
                          color: Colors.grey[400], size: 18),
                      const SizedBox(width: 6),
                      Text('Could not load signature',
                          style: GoogleFonts.poppins(
                              color: Colors.grey[400], fontSize: 11)),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _signeeTextField({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return TextFormField(
      controller: ctrl,
      readOnly: _isReadOnly,
      style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            GoogleFonts.poppins(fontSize: 11, color: _navy.withValues(alpha: 0.7)),
        hintText: hint,
        hintStyle:
            GoogleFonts.poppins(color: Colors.grey[400], fontSize: 12),
        prefixIcon:
            Icon(icon, color: _navy.withValues(alpha: 0.6), size: 18),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: _fieldBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: _fieldBorder)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: _navy, width: 1.5),
        ),
      ),
      onChanged: _isReadOnly ? null : (_) => _saveDraftToCache(),
    );
  }

  // ── Global save + full PDF buttons ──────────────────────────
  Widget _buildGlobalActionButtons() {
    Widget btn({
      required String label,
      required IconData icon,
      required Color color,
      required bool isLoading,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: SizedBox(
          height: 46,
          child: ElevatedButton.icon(
            onPressed: isLoading ? null : onTap,
            icon: isLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white)))
                : Icon(icon, size: 16),
            label: Text(label,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              disabledBackgroundColor: color.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
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
        color: _accentGreen,
        isLoading: _isGeneratingPdf,
        onTap: _downloadAsPdf,
      ),
      if (!_isReadOnly) ...[
      const SizedBox(width: 10),
      btn(
        label: '+ New Form',
        icon: Icons.add_circle_outline_rounded,
        color: _accentPurple,
        isLoading: false,
        onTap: _addNewForm,
      ),
      ],
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════
// INLINE TABLE WIDGET — Custom wrapping-cell editable table
// Replaces PlutoGrid with Flutter Table + TextFormField(maxLines:null)
// so every cell fully wraps its content — no "..." truncation — both
// in the UI and when exported to PDF.
// Features: rename headers · add column · toggle row-numbers ·
//           add/remove rows · delete table
// ══════════════════════════════════════════════════════════════════
class _InlineTableWidget extends StatefulWidget {
  final MonthlyTableData tableData;
  final bool readOnly;
  final VoidCallback onDelete;
  final Function(MonthlyTableData) onChanged;

  const _InlineTableWidget({
    super.key,
    required this.tableData,
    this.readOnly = false,
    required this.onDelete,
    required this.onChanged,
  });

  @override
  State<_InlineTableWidget> createState() => _InlineTableWidgetState();
}

class _InlineTableWidgetState extends State<_InlineTableWidget> {
  static const _navy = Color(0xFF0A2E5A);
  static const _fieldBorder = Color(0xFFB0BEC5);

  // Cell controllers: _controllers[rowIndex][colIndex]
  // colIndex matches widget.tableData.columnNames index
  late List<List<TextEditingController>> _controllers;

  // ── Lifecycle ─────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  @override
  void didUpdateWidget(_InlineTableWidget old) {
    super.didUpdateWidget(old);
    // Rebuild controllers if row count or column count changed externally
    final colChanged =
        old.tableData.columnNames.length != widget.tableData.columnNames.length ||
        old.tableData.columnNames.join('|') != widget.tableData.columnNames.join('|');
    final rowChanged = old.tableData.rows.length != _controllers.length;
    if (colChanged || rowChanged) {
      _disposeControllers();
      _initControllers();
    }
  }

  void _initControllers() {
    _controllers = widget.tableData.rows.map((rowMap) {
      return widget.tableData.columnNames
          .map((col) => TextEditingController(text: rowMap[col] ?? ''))
          .toList();
    }).toList();
  }

  void _disposeControllers() {
    for (final row in _controllers) {
      for (final c in row) {
        c.dispose();
      }
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  // ── Sync controllers → data model ─────────────────────────────
  void _syncAndNotify() {
    for (int r = 0; r < _controllers.length && r < widget.tableData.rows.length; r++) {
      for (int c = 0; c < _controllers[r].length && c < widget.tableData.columnNames.length; c++) {
        widget.tableData.rows[r][widget.tableData.columnNames[c]] =
            _controllers[r][c].text;
      }
    }
    widget.onChanged(widget.tableData);
  }

  // ── Add blank row ──────────────────────────────────────────────
  void _addRow() {
    final newMap = {for (final n in widget.tableData.columnNames) n: ''};
    widget.tableData.rows.add(newMap);
    setState(() {
      _controllers.add(
        widget.tableData.columnNames
            .map((_) => TextEditingController())
            .toList(),
      );
    });
    widget.onChanged(widget.tableData);
  }

  // ── Remove last row ────────────────────────────────────────────
  void _removeLastRow() {
    if (widget.tableData.rows.isEmpty || widget.tableData.rows.length <= 1) return;
    widget.tableData.rows.removeLast();
    setState(() {
      final last = _controllers.removeLast();
      for (final c in last) {
        c.dispose();
      }
    });
    widget.onChanged(widget.tableData);
  }

  // ── Toggle row-number column ───────────────────────────────────
  void _toggleRowNumbers() {
    setState(() {
      widget.tableData.showRowNumbers = !widget.tableData.showRowNumbers;
    });
    widget.onChanged(widget.tableData);
  }

  // ── Edit all column headers ────────────────────────────────────
  Future<void> _showEditHeadersDialog() async {
    _syncAndNotify();
    final ctrls = widget.tableData.columnNames
        .map((n) => TextEditingController(text: n))
        .toList();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header bar
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                decoration: const BoxDecoration(
                  color: _navy,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                ),
                child: Row(children: [
                  const Icon(Icons.drive_file_rename_outline_rounded,
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
                          color: Colors.white70, size: 18)),
                ]),
              ),
              // Field list
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Column(
                    children: List.generate(ctrls.length, (i) => Padding(
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
                                  color: Colors.grey[400], fontSize: 11),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6)),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide:
                                      const BorderSide(color: _navy, width: 1.5)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                            ),
                          ),
                        ),
                      ]),
                    )),
                  ),
                ),
              ),
              // Action buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _navy),
                        padding: const EdgeInsets.symmetric(vertical: 11),
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
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: Text('Apply',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _navy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
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

    // Apply renames — migrate row data keys
    final newNames = ctrls.asMap().entries.map((e) {
      final v = e.value.text.trim();
      return v.isNotEmpty ? v : widget.tableData.columnNames[e.key];
    }).toList();

    for (var i = 0; i < widget.tableData.columnNames.length; i++) {
      final oldName = widget.tableData.columnNames[i];
      final newName = newNames[i];
      if (oldName == newName) continue;
      for (final row in widget.tableData.rows) {
        final val = row.remove(oldName) ?? '';
        row[newName] = val;
      }
    }
    for (final c in ctrls) {
      c.dispose();
    }

    // Rebuild controllers with new names (text stays, just key changes)
    _disposeControllers();
    setState(() {
      for (var i = 0; i < widget.tableData.columnNames.length; i++) {
        widget.tableData.columnNames[i] = newNames[i];
      }
    });
    _initControllers();
    widget.onChanged(widget.tableData);
  }

  // ── Add a new column ──────────────────────────────────────────
  Future<void> _showAddColumnDialog() async {
    _syncAndNotify();
    final nameCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                decoration: const BoxDecoration(
                  color: _navy,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                ),
                child: Row(children: [
                  const Icon(Icons.add_box_outlined,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Text('Add New Column',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  const Spacer(),
                  GestureDetector(
                      onTap: () => Navigator.pop(ctx, false),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white70, size: 18)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: GoogleFonts.poppins(fontSize: 13),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => Navigator.pop(ctx, true),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Column Name',
                    labelStyle:
                        GoogleFonts.poppins(fontSize: 12, color: _navy),
                    hintText: 'e.g. Status',
                    hintStyle: GoogleFonts.poppins(
                        color: Colors.grey[400], fontSize: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7),
                        borderSide:
                            const BorderSide(color: _navy, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
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
                        padding: const EdgeInsets.symmetric(vertical: 11),
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
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text('Add Column',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _navy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
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

    nameCtrl.dispose();
    if (confirmed != true) return;

    // Deduplicate new column name
    String newName = nameCtrl.text.trim().isEmpty
        ? 'Column ${widget.tableData.columnNames.length + 1}'
        : nameCtrl.text.trim();
    int suffix = 2;
    String candidate = newName;
    while (widget.tableData.columnNames.contains(candidate)) {
      candidate = '$newName ($suffix)';
      suffix++;
    }
    newName = candidate;

    // Add column: update data model + add controller per row
    setState(() {
      widget.tableData.columnNames.add(newName);
      for (int r = 0; r < widget.tableData.rows.length; r++) {
        widget.tableData.rows[r][newName] = '';
        _controllers[r].add(TextEditingController());
      }
    });
    widget.onChanged(widget.tableData);
  }

  // ── Toolbar icon button ────────────────────────────────────────
  Widget _tableBtn({
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
          width: 26, height: 26,
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
              size: 14,
              color: onTap != null ? color : Colors.grey[400]),
        ),
      ),
    );
  }

  // ── Header cell ────────────────────────────────────────────────
  Widget _headerCell(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Text(
          text,
          style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 11),
          softWrap: true,
        ),
      );

  // ── Data cell — wrapping TextField or read-only Text ──────────
  Widget _dataCell(int rowIdx, int colIdx, Color bg, bool readOnly) {
    if (readOnly) {
      return Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(
          _controllers[rowIdx][colIdx].text,
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.black87),
          softWrap: true,
        ),
      );
    }
    return Container(
      color: bg,
      child: TextFormField(
        controller: _controllers[rowIdx][colIdx],
        maxLines: null,   // ← unlimited lines; cell grows with content
        minLines: 1,
        style: GoogleFonts.poppins(fontSize: 12, color: Colors.black87),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding:
              EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          isDense: true,
        ),
        onChanged: (_) => _syncAndNotify(),
      ),
    );
  }

  // ── Build the Flutter Table ────────────────────────────────────
  Widget _buildTable(bool readOnly) {
    return LayoutBuilder(builder: (context, constraints) {
      final colCount = widget.tableData.columnNames.length;
      const double noW = 42.0;
      final availW = constraints.maxWidth;
      final dataW =
          widget.tableData.showRowNumbers ? availW - noW : availW;
      // Equal width per column
      final perColW = colCount > 0 ? dataW / colCount : dataW;

      final Map<int, TableColumnWidth> colWidths = {};
      int offset = 0;
      if (widget.tableData.showRowNumbers) {
        colWidths[0] = const FixedColumnWidth(noW);
        offset = 1;
      }
      for (int i = 0; i < colCount; i++) {
        colWidths[i + offset] = FixedColumnWidth(perColW);
      }

      return Table(
        border: TableBorder.all(color: _fieldBorder, width: 0.8),
        columnWidths: colWidths,
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          // ── Header row ──────────────────────────────────────
          TableRow(
            decoration: const BoxDecoration(color: _navy),
            children: [
              if (widget.tableData.showRowNumbers) _headerCell('#'),
              ...widget.tableData.columnNames.map(_headerCell),
            ],
          ),
          // ── Data rows ───────────────────────────────────────
          ...widget.tableData.rows.asMap().entries.map((entry) {
            final idx = entry.key;
            final bg =
                idx.isEven ? Colors.white : const Color(0xFFF8FAFC);
            return TableRow(children: [
              if (widget.tableData.showRowNumbers)
                Container(
                  color: bg,
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: 4),
                  child: Text('${idx + 1}',
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _navy.withValues(alpha: 0.55))),
                ),
              ...List.generate(
                  colCount, (ci) => _dataCell(idx, ci, bg, readOnly)),
            ]);
          }),
        ],
      );
    });
  }

  // ── Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bool readOnly = widget.readOnly;

    final rowCount = widget.tableData.rows.length;
    final colCount = widget.tableData.columnNames.length;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: _navy.withValues(alpha: 0.22), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Toolbar ───────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: _navy.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(7),
                  topRight: Radius.circular(7)),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(children: [
              const Icon(Icons.table_chart_rounded,
                  color: _navy, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(widget.tableData.title,
                    style: GoogleFonts.poppins(
                        color: _navy,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
              ),
              // Row-number toggle pill
              Tooltip(
                message: widget.tableData.showRowNumbers
                    ? 'Hide Row Numbers'
                    : 'Show Row Numbers',
                child: InkWell(
                  onTap: _toggleRowNumbers,
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.tableData.showRowNumbers
                          ? _navy.withValues(alpha: 0.14)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: widget.tableData.showRowNumbers
                              ? _navy.withValues(alpha: 0.45)
                              : Colors.grey.withValues(alpha: 0.35),
                          width: 0.9),
                    ),
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.format_list_numbered_rounded,
                              size: 13,
                              color: widget.tableData.showRowNumbers
                                  ? _navy
                                  : Colors.grey[500]),
                          const SizedBox(width: 3),
                          Text(' # ',
                              style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: widget.tableData.showRowNumbers
                                      ? _navy
                                      : Colors.grey[500])),
                        ]),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Edit column headers
              Tooltip(
                message: 'Edit Column Headers',
                child: InkWell(
                  onTap: _showEditHeadersDialog,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.35),
                          width: 0.9),
                    ),
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                              Icons.drive_file_rename_outline_rounded,
                              size: 13,
                              color: Colors.grey[600]),
                          const SizedBox(width: 3),
                          Text('Headers',
                              style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[600])),
                        ]),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Add new column
              Tooltip(
                message: colCount < 10
                    ? 'Add New Column'
                    : 'Maximum 10 columns reached',
                child: InkWell(
                  onTap: colCount < 10 ? _showAddColumnDialog : null,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: colCount < 10
                          ? Colors.teal.withValues(alpha: 0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: colCount < 10
                              ? Colors.teal.withValues(alpha: 0.45)
                              : Colors.grey.withValues(alpha: 0.35),
                          width: 0.9),
                    ),
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_box_outlined,
                              size: 13,
                              color: colCount < 10
                                  ? Colors.teal[700]
                                  : Colors.grey[400]),
                          const SizedBox(width: 3),
                          Text('+ Col',
                              style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: colCount < 10
                                      ? Colors.teal[700]
                                      : Colors.grey[400])),
                        ]),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Add row
              _tableBtn(
                  icon: Icons.add_rounded,
                  tooltip: 'Add Row',
                  color: Colors.green[700]!,
                  onTap: _addRow),
              const SizedBox(width: 4),
              // Remove last row
              _tableBtn(
                  icon: Icons.remove_rounded,
                  tooltip: 'Remove Last Row',
                  color: Colors.orange[700]!,
                  onTap: rowCount > 1 ? _removeLastRow : null),
              const SizedBox(width: 4),
              // Delete table
              _tableBtn(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Delete Table',
                  color: Colors.red[600]!,
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        title: Text('Delete Table',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        content: Text(
                            'Delete "${widget.tableData.title}"?',
                            style: GoogleFonts.poppins(fontSize: 13)),
                        actions: [
                          TextButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, false),
                              child: Text('Cancel',
                                  style: GoogleFonts.poppins())),
                          ElevatedButton(
                            onPressed: () =>
                                Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red[600],
                                foregroundColor: Colors.white),
                            child: Text('Delete',
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) widget.onDelete();
                  }),
            ]),
          ),

          // ── Hint strip ────────────────────────────────────────
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: const Color(0xFFF3F6FA),
            child: Row(children: [
              Icon(Icons.info_outline_rounded,
                  size: 12, color: Colors.grey[450]),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                    '"Headers" to rename · "+ Col" to add column · content wraps automatically',
                    style: GoogleFonts.poppins(
                        fontSize: 10, color: Colors.grey[500])),
              ),
            ]),
          ),

          // ── Wrapping Table ────────────────────────────────────
          ClipRRect(
            borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(7),
                bottomRight: Radius.circular(7)),
            child: _buildTable(readOnly),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// INSERT TABLE DIALOG — standalone StatefulWidget so TextFields
// never lose focus when counter buttons call setState.
// Returns a fully configured MonthlyTableData or null on cancel.
// ══════════════════════════════════════════════════════════════════
class _InsertTableDialog extends StatefulWidget {
  const _InsertTableDialog();

  @override
  State<_InsertTableDialog> createState() => _InsertTableDialogState();
}

class _InsertTableDialogState extends State<_InsertTableDialog> {
  static const _navy = Color(0xFF0A2E5A);

  final _titleCtrl = TextEditingController(text: 'Table');
  late final List<TextEditingController> _colCtrls;
  int _colCount = 3;
  int _rowCount = 3;
  bool _showRowNumbers = false;

  @override
  void initState() {
    super.initState();
    // Pre-allocate controllers for max supported columns (10)
    _colCtrls = List.generate(
        10, (i) => TextEditingController(text: 'Column ${i + 1}'));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    for (final c in _colCtrls) { c.dispose(); }
    super.dispose();
  }

  void _decCol() { if (_colCount > 1) setState(() => _colCount--); }
  void _incCol() { if (_colCount < 10) setState(() => _colCount++); }
  void _decRow() { if (_rowCount > 1) setState(() => _rowCount--); }
  void _incRow() { if (_rowCount < 30) setState(() => _rowCount++); }

  void _submit() {
    final colNames = List.generate(_colCount, (i) {
      final v = _colCtrls[i].text.trim();
      return v.isNotEmpty ? v : 'Column ${i + 1}';
    });
    // Deduplicate: if two headers are the same, suffix the later ones
    final seen = <String, int>{};
    final deduped = colNames.map((n) {
      final count = seen[n] = (seen[n] ?? 0) + 1;
      return count == 1 ? n : '$n ($count)';
    }).toList();

    final table = MonthlyTableData(
      id: const Uuid().v4(),
      title: _titleCtrl.text.trim().isEmpty ? 'Table' : _titleCtrl.text.trim(),
      columnNames: deduped,
      showRowNumbers: _showRowNumbers,
      rows: List.generate(_rowCount, (_) => {for (final c in deduped) c: ''}),
    );
    Navigator.pop(context, table);
  }

  Widget _counterBtn(IconData icon, VoidCallback? onTap) {
    final active = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? _navy : Colors.grey[200],
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon,
            size: 16, color: active ? Colors.white : Colors.grey[400]),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text,
        style: GoogleFonts.poppins(
            fontSize: 12, fontWeight: FontWeight.w600, color: _navy)),
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: _navy,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                const Icon(Icons.table_chart_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text('Insert Table',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                const Spacer(),
                GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 20)),
              ]),
            ),

            // ── Body ────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Table title
                    _sectionLabel('Table Title'),
                    TextField(
                      controller: _titleCtrl,
                      style: GoogleFonts.poppins(fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'e.g. Materials Used',
                        hintStyle: GoogleFonts.poppins(
                            color: Colors.grey[400], fontSize: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide:
                              const BorderSide(color: _navy, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Column count + Row number toggle (same row)
                    Row(children: [
                      _sectionLabel('Columns'),
                      const Spacer(),
                      _counterBtn(Icons.remove, _colCount > 1 ? _decCol : null),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('$_colCount',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: _navy)),
                      ),
                      _counterBtn(
                          Icons.add, _colCount < 10 ? _incCol : null),
                    ]),
                    const SizedBox(height: 10),

                    // Column name fields — keyed so focus is preserved
                    ...List.generate(_colCount, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Row(children: [
                          Container(
                            width: 28,
                            height: 28,
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
                              key: ValueKey('col_$i'),
                              controller: _colCtrls[i],
                              style: GoogleFonts.poppins(fontSize: 12),
                              textInputAction: i < _colCount - 1
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'Header ${i + 1}',
                                hintStyle: GoogleFonts.poppins(
                                    color: Colors.grey[400], fontSize: 11),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6)),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(
                                        color: _navy, width: 1.5)),
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                              ),
                            ),
                          ),
                        ]),
                      );
                    }),

                    const SizedBox(height: 14),

                    // Initial rows counter
                    Row(children: [
                      _sectionLabel('Initial Rows'),
                      const Spacer(),
                      _counterBtn(
                          Icons.remove, _rowCount > 1 ? _decRow : null),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('$_rowCount',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: _navy)),
                      ),
                      _counterBtn(
                          Icons.add, _rowCount < 30 ? _incRow : null),
                    ]),
                    const SizedBox(height: 14),

                    // Row numbers toggle
                    InkWell(
                      onTap: () =>
                          setState(() => _showRowNumbers = !_showRowNumbers),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 38,
                            height: 22,
                            padding: EdgeInsets.only(
                                left: _showRowNumbers ? 18 : 2, right: 2),
                            decoration: BoxDecoration(
                              color: _showRowNumbers
                                  ? _navy
                                  : Colors.grey[300],
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black26, blurRadius: 2)
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(Icons.format_list_numbered_rounded,
                              size: 16,
                              color: _showRowNumbers
                                  ? _navy
                                  : Colors.grey[500]),
                          const SizedBox(width: 6),
                          Text('Show row numbers',
                              style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _showRowNumbers
                                      ? _navy
                                      : Colors.grey[600])),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // ── Footer buttons ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _navy),
                      padding: const EdgeInsets.symmetric(vertical: 12),
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
                    onPressed: _submit,
                    icon: const Icon(Icons.table_chart_rounded, size: 16),
                    label: Text('Insert',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
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
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// SIGNATURE PAD WIDGET
// Canvas-based handwriting capture with clear functionality.
// Uses a ChangeNotifier repaint model so pointer-move events only
// repaint the CustomPaint — no full widget-tree rebuild per point.
// ══════════════════════════════════════════════════════════════════

// ── Stroke point: position + normalised pressure (0.0–1.0) ─────
class _StrokePoint {
  final Offset position;
  final double pressure;
  const _StrokePoint(this.position, this.pressure);
}

// ── Stroke model / repaint notifier ────────────────────────────
// Holds the strokes list and notifies the CustomPainter directly
// so pointer-move events never trigger a setState / widget rebuild.
class _StrokeModel extends ChangeNotifier {
  final List<List<_StrokePoint>> strokes = [];
  List<_StrokePoint>? current;

  void startStroke(_StrokePoint p) {
    final s = [p];
    current = s;
    strokes.add(s);
    notifyListeners();
  }

  void addPoint(_StrokePoint p) {
    current?.add(p);
    notifyListeners(); // only repaints the CustomPaint, not the widget tree
  }

  void endStroke() {
    current = null;
    // No notifyListeners needed — caller handles post-processing
  }

  void clear() {
    strokes.clear();
    current = null;
    notifyListeners();
  }

  bool get isEmpty => strokes.isEmpty;
}

class _SignaturePadWidget extends StatefulWidget {
  final Function(Uint8List?)? onSignatureChanged;
  const _SignaturePadWidget({this.onSignatureChanged});

  @override
  State<_SignaturePadWidget> createState() => _SignaturePadWidgetState();
}

class _SignaturePadWidgetState extends State<_SignaturePadWidget> {
  static const _navy = Color(0xFF0A2E5A);
  static const _inkColor = Color(0xFF0A2E5A);

  final _model = _StrokeModel();
  final _repaintKey = GlobalKey();

  // UI-only state — only these trigger setState
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
    _model.startStroke(_StrokePoint(e.localPosition, pressure));
    // setState only for the label badge — not called on every move
    if (_kindLabel(e.kind) != _inputLabel) {
      setState(() => _inputLabel = _kindLabel(e.kind));
    }
  }

  void _onMove(PointerMoveEvent e) {
    // ← no setState here — model notifier repaints only the CustomPaint
    final pressure =
        _hasPressure(e.kind) ? e.pressure.clamp(0.0, 1.0) : 1.0;
    _model.addPoint(_StrokePoint(e.localPosition, pressure));
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
        // ── Canvas ───────────────────────────────────────────────
        // ScrollConfiguration disables scroll physics inside the pad
        // so the parent ScrollView never steals pointer events while
        // the user is signing.
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
                height: 160, // taller for comfortable signing
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
                      // Ruled-line background (static — never repaints)
                      const RepaintBoundary(
                        child: CustomPaint(
                            painter: _SignatureRuledPainter()),
                      ),
                      // Ink strokes — repaints via _model notifier only
                      CustomPaint(
                        painter:
                            _SignatureInkPainter(_model, _inkColor),
                      ),
                      // Placeholder hint
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

        // ── Status row ───────────────────────────────────────────
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

// ── Ruled background painter ────────────────────────────────────
class _SignatureRuledPainter extends CustomPainter {
  const _SignatureRuledPainter();

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
  bool shouldRepaint(_SignatureRuledPainter _) => false;
}

// ── Ink painter — subscribes to _StrokeModel via repaint notifier
class _SignatureInkPainter extends CustomPainter {
  final _StrokeModel model;
  final Color inkColor;

  // Cached Paint objects — created once, reused every paint call
  late final Paint _strokePaint = Paint()
    ..color = inkColor
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  late final Paint _dotPaint = Paint()
    ..color = inkColor
    ..style = PaintingStyle.fill;

  _SignatureInkPainter(this.model, this.inkColor)
      : super(repaint: model); // ← subscribes: notifyListeners → repaint

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

      // Build a single continuous path per stroke using midpoint
      // Bézier curves — far smoother than segment-by-segment drawing.
      final path = Path();
      path.moveTo(stroke[0].position.dx, stroke[0].position.dy);

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

        // Variable width per segment via separate drawPath calls
        final w = (_baseWidth +
                (_maxWidth - _baseWidth) *
                    ((p0.pressure + p1.pressure) / 2))
            .clamp(_baseWidth, _maxWidth);

        final seg = Path()
          ..moveTo(i == 0
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
  bool shouldRepaint(_SignatureInkPainter old) =>
      old.model != model || old.inkColor != inkColor;
}
// ══════════════════════════════════════════════════════════════════
//  MONTHLY FORM IMAGE HELPERS
// ══════════════════════════════════════════════════════════════════

class _MImageItem {
  final Uint8List? bytes;
  final String? url;
  _MImageItem({this.bytes, this.url});
}

// ══════════════════════════════════════════════════════════════════
//  FULL-SCREEN IMAGE VIEWER DIALOG (monthly)
// ══════════════════════════════════════════════════════════════════

class _MImageViewerDialog extends StatefulWidget {
  final List<_MImageItem> images;
  final int initialIndex;
  const _MImageViewerDialog(
      {required this.images, required this.initialIndex});

  @override
  State<_MImageViewerDialog> createState() => _MImageViewerDialogState();
}

class _MImageViewerDialogState extends State<_MImageViewerDialog> {
  late int _current;
  late PageController _pageCtrl;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
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
                        ? Image.memory(item.bytes!, fit: BoxFit.contain)
                        : Image.network(item.url!, fit: BoxFit.contain),
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
                        color: Colors.white.withValues(alpha: 0.4), width: 1),
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
          // Counter
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
          // Prev arrow
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
// _CropDialog — Pure-Flutter in-app image cropper
// ══════════════════════════════════════════════════════════════════
//
// Replaces image_cropper on web and desktop where Cropper.js is not
// available.  Uses the crop_your_image package which is 100 % Flutter
// (no JS, no platform channels) and therefore works on every platform.
//
// Returns the cropped PNG bytes, or null if the user cancelled.
// ══════════════════════════════════════════════════════════════════

class _CropDialog extends StatefulWidget {
  final Uint8List imageBytes;
  const _CropDialog({required this.imageBytes});

  @override
  State<_CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<_CropDialog> {
  static const _navy = Color(0xFF0A2E5A);

  final CropController _cropCtrl = CropController();
  bool _isCropping = false;

  Future<void> _confirmCrop() async {
    setState(() => _isCropping = true);
    try {
      _cropCtrl.crop();
      // Result arrives via onCropped callback below — Navigator.pop()
      // is called from there once the cropped bytes are ready.
    } catch (e) {
      if (mounted) {
        setState(() => _isCropping = false);
        Navigator.of(context).pop(null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogW = (screenSize.width * 0.92).clamp(320.0, 700.0);
    final dialogH = (screenSize.height * 0.82).clamp(400.0, 680.0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SizedBox(
        width: dialogW,
        height: dialogH,
        child: Column(
          children: [
            // ── Title bar ─────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 13),
              decoration: const BoxDecoration(
                color: _navy,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(children: [
                const Icon(Icons.crop_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Text(
                  'Crop Signature',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _isCropping
                      ? null
                      : () => Navigator.of(context).pop(null),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white70, size: 20),
                ),
              ]),
            ),

            // ── Hint ──────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                'Drag to reposition · Use handles to resize the crop area',
                style: GoogleFonts.poppins(
                    fontSize: 11, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ),

            // ── Crop widget ───────────────────────────────────────
            Expanded(
              child: ClipRect(
                child: Crop(
                  controller: _cropCtrl,
                  image: widget.imageBytes,
                  // Free-form aspect ratio so any signature region works
                  aspectRatio: null,
                  baseColor: Colors.black,
                  maskColor: Colors.black.withValues(alpha: 0.5),
                  cornerDotBuilder: (size, edgeAlignment) =>
                      const DotControl(color: _navy),
                  onCropped: (result) {
                    if (!mounted) return;
                    final Uint8List? bytes =
                        result is CropSuccess ? result.croppedImage : null;
                    Navigator.of(context).pop(bytes);
                  },
                  onStatusChanged: (status) {
                    // Clear the spinner if something unexpected stops the crop
                    if (mounted &&
                        status != CropStatus.cropping &&
                        _isCropping) {
                      setState(() => _isCropping = false);
                    }
                  },
                ),
              ),
            ),

            // ── Actions ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isCropping
                        ? null
                        : () => Navigator.of(context).pop(null),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: Text('Cancel',
                        style: GoogleFonts.poppins(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _navy),
                      foregroundColor: _navy,
                      padding:
                          const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isCropping ? null : _confirmCrop,
                    icon: _isCropping
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : const Icon(Icons.check_rounded, size: 16),
                    label: Text(
                      _isCropping ? 'Cropping…' : 'Use Crop',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _navy,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          _navy.withValues(alpha: 0.55),
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
    );
  }
}