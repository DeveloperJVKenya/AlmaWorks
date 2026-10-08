import 'package:almaworks/core/theme/app_theme.dart';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:almaworks/models/project_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
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
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/errors/friendly_error.dart';
import 'package:almaworks/core/theme/app_colors.dart';

// ══════════════════════════════════════════════════════════════════
//  DATA MODEL
// ══════════════════════════════════════════════════════════════════

class DailyReportData {
  final String id;
  final String projectId;
  final String projectName;
  String contractNumber;
  DateTime date;
  TimeOfDay? startTime;
  TimeOfDay? stopTime;
  String weather;
  String building;

  // Rich-text sections stored as Quill Delta JSON strings
  String visitorsJson;
  List<String> subContractors;
  String personnelVehiclesJson;
  String activitiesJson;
  String remarksJson;

  List<String> imageUrls; // Firebase Storage URLs after upload
  List<Uint8List> localImages; // transient – picked but not yet uploaded
  bool isDraft;
  DateTime? savedAt;

  DailyReportData({
    required this.id,
    required this.projectId,
    required this.projectName,
    this.contractNumber = '',
    required this.date,
    this.startTime,
    this.stopTime,
    this.weather = '',
    this.building = '',
    this.visitorsJson = '',
    this.subContractors = const [],
    this.personnelVehiclesJson = '',
    this.activitiesJson = '',
    this.remarksJson = '',
    this.imageUrls = const [],
    this.localImages = const [],
    this.isDraft = true,
    this.savedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'projectId': projectId,
        'projectName': projectName,
        'contractNumber': contractNumber,
        'date': Timestamp.fromDate(date),
        'startTime': startTime != null
            ? '${startTime!.hour}:${startTime!.minute}'
            : null,
        'stopTime':
            stopTime != null ? '${stopTime!.hour}:${stopTime!.minute}' : null,
        'weather': weather,
        'building': building,
        'visitorsJson': visitorsJson,
        'subContractors': subContractors,
        'personnelVehiclesJson': personnelVehiclesJson,
        'activitiesJson': activitiesJson,
        'remarksJson': remarksJson,
        'imageUrls': imageUrls,
        'isDraft': isDraft,
        'savedAt': Timestamp.now(),
        'type': 'Daily',
      };

  static TimeOfDay? _parseTime(String? s) {
    if (s == null) return null;
    final parts = s.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  factory DailyReportData.fromMap(Map<String, dynamic> m) => DailyReportData(
        id: m['id'] ?? '',
        projectId: m['projectId'] ?? '',
        projectName: m['projectName'] ?? '',
        contractNumber: m['contractNumber'] ?? '',
        date: (m['date'] as Timestamp).toDate(),
        startTime: _parseTime(m['startTime']),
        stopTime: _parseTime(m['stopTime']),
        weather: m['weather'] ?? '',
        building: m['building'] ?? '',
        visitorsJson: m['visitorsJson'] ?? '',
        subContractors: m['subContractors'] != null
            ? List<String>.from(m['subContractors'])
            // Backward-compat: old docs stored a single string in 'subContractor'
            : (m['subContractor'] != null &&
                    (m['subContractor'] as String).isNotEmpty
                ? [m['subContractor'] as String]
                : []),
        personnelVehiclesJson: m['personnelVehiclesJson'] ?? '',
        activitiesJson: m['activitiesJson'] ?? '',
        remarksJson: m['remarksJson'] ?? '',
        imageUrls: List<String>.from(m['imageUrls'] ?? []),
        isDraft: m['isDraft'] ?? true,
        savedAt: m['savedAt'] != null ? (m['savedAt'] as Timestamp).toDate() : null,
      );
}

// ══════════════════════════════════════════════════════════════════
//  SCREEN
// ══════════════════════════════════════════════════════════════════

class DailyReportFormScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  /// Pass an existing report to open in view/edit mode; null = new form.
  final DailyReportData? existingReport;
  /// When true, all fields are read-only and a floating Edit button is shown.
  final bool isReadOnly;

  const DailyReportFormScreen({
    super.key,
    required this.project,
    required this.logger,
    this.existingReport,
    this.isReadOnly = false,
  });

  @override
  State<DailyReportFormScreen> createState() => _DailyReportFormScreenState();
}

class _DailyReportFormScreenState extends State<DailyReportFormScreen> {
  // ── controllers ──────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _contractController = TextEditingController();
  final _buildingController = TextEditingController();
  final _scrollController = ScrollController();

  late quill.QuillController _visitorsCtrl;
  late quill.QuillController _personnelCtrl;
  late quill.QuillController _activitiesCtrl;
  late quill.QuillController _remarksCtrl;

  // ── state ─────────────────────────────────────────────────────
  late String _reportId;
  DateTime _date = DateTime.now();
  TimeOfDay? _startTime;
  TimeOfDay? _stopTime;
  String _weather = '';
  final List<String> _selectedSubContractors = [];
  final List<Uint8List> _localImages = [];
  final List<String> _savedImageUrls = [];
  bool _isSaving = false;
  bool _isGeneratingPdf = false;
  bool _isReadOnly = false;

  List<String> _subcontractorNames = [];

  static const List<String> _weatherOptions = [
    'Calm & Warm',
    'Chilly & Cold',
    'Hot',
    'Windy',
    'Rainy',
  ];

  // ── colours / constants ────────────────────────────────────────
  static const _navy = Color(0xFF0A2E5A);
  static const _fieldBorder = Color(0xFFB0BEC5);
  static Color get _sectionBg => AppColors.surfaceAlt;

  // ── cache key ─────────────────────────────────────────────────
  String get _cacheKey =>
      'daily_report_draft_${widget.project.id}_$_reportId';

  @override
  void initState() {
    super.initState();
    widget.logger.i('📋 DailyForm: ── initState START ──');
    widget.logger.i('📋 DailyForm: project.id=${widget.project.id}  name=${widget.project.name}');
    widget.logger.i('📋 DailyForm: existingReport=${widget.existingReport?.id ?? 'null (new form)'}');

    _reportId = widget.existingReport?.id ?? const Uuid().v4();
    widget.logger.i('📋 DailyForm: reportId=$_reportId');
    _isReadOnly = widget.isReadOnly;

    _extractSubcontractors();

    if (widget.existingReport != null) {
      widget.logger.i('📋 DailyForm: initState: loading existing report data');
      _loadFromExisting(widget.existingReport!);
    } else {
      widget.logger.d('📋 DailyForm: initState: new form – creating blank Quill controllers');
      try {
        _visitorsCtrl   = quill.QuillController.basic();
        widget.logger.d('📋 DailyForm: _visitorsCtrl  OK');
        _personnelCtrl  = quill.QuillController.basic();
        widget.logger.d('📋 DailyForm: _personnelCtrl OK');
        _activitiesCtrl = quill.QuillController.basic();
        widget.logger.d('📋 DailyForm: _activitiesCtrl OK');
        _remarksCtrl    = quill.QuillController.basic();
        widget.logger.d('📋 DailyForm: _remarksCtrl  OK');
      } catch (e, st) {
        widget.logger.e('❌ DailyForm: ERROR creating blank Quill controllers', error: e, stackTrace: st);
      }
      widget.logger.d('📋 DailyForm: initState: calling _loadDraftFromCache');
      _loadDraftFromCache();
    }
    widget.logger.i('📋 DailyForm: ── initState END ──');
  }

  void _extractSubcontractors() {
    widget.logger.d('📋 DailyForm: _extractSubcontractors: teamMembers.length=${widget.project.teamMembers.length}');
    _subcontractorNames = widget.project.teamMembers
        .where((m) => m.role.toLowerCase() == 'subcontractor')
        .map((m) => m.name)
        .toList();
    widget.logger.i('📋 DailyForm: _extractSubcontractors: found ${_subcontractorNames.length} → $_subcontractorNames');
  }

  void _loadFromExisting(DailyReportData r) {
    widget.logger.i('📋 DailyForm: _loadFromExisting: id=${r.id}');
    _contractController.text = r.contractNumber;
    _buildingController.text = r.building;
    _date = r.date;
    _startTime = r.startTime;
    _stopTime = r.stopTime;
    _weather = r.weather;
    _selectedSubContractors
      ..clear()
      ..addAll(r.subContractors);
    _savedImageUrls.addAll(r.imageUrls);
    widget.logger.i('📋 DailyForm: _loadFromExisting: basic fields loaded. imageUrls.count=${r.imageUrls.length}');

    widget.logger.d('📋 DailyForm: _loadFromExisting: creating visitorsCtrl from visitorsJson (len=${r.visitorsJson.length})');
    _visitorsCtrl   = _quillFromJson('visitors',  r.visitorsJson);
    widget.logger.d('📋 DailyForm: _loadFromExisting: creating personnelCtrl from personnelVehiclesJson (len=${r.personnelVehiclesJson.length})');
    _personnelCtrl  = _quillFromJson('personnel', r.personnelVehiclesJson);
    widget.logger.d('📋 DailyForm: _loadFromExisting: creating activitiesCtrl from activitiesJson (len=${r.activitiesJson.length})');
    _activitiesCtrl = _quillFromJson('activities', r.activitiesJson);
    widget.logger.d('📋 DailyForm: _loadFromExisting: creating remarksCtrl from remarksJson (len=${r.remarksJson.length})');
    _remarksCtrl    = _quillFromJson('remarks',   r.remarksJson);
    widget.logger.i('📋 DailyForm: _loadFromExisting: all Quill controllers ready');
  }

  quill.QuillController _quillFromJson(String fieldKey, String json) {
    widget.logger.d('📋 DailyForm: _quillFromJson [$fieldKey]: json.length=${json.length}');
    if (json.isEmpty) {
      widget.logger.d('📋 DailyForm: _quillFromJson [$fieldKey]: empty JSON → returning basic controller');
      return quill.QuillController.basic();
    }
    try {
      final decoded = jsonDecode(json);
      widget.logger.d('📋 DailyForm: _quillFromJson [$fieldKey]: decoded type=${decoded.runtimeType}');
      if (decoded is! List) {
        widget.logger.w('⚠️ DailyForm: _quillFromJson [$fieldKey]: decoded is NOT a List – returning basic controller');
        return quill.QuillController.basic();
      }
      final doc = quill.Document.fromJson(decoded);
      widget.logger.d('📋 DailyForm: _quillFromJson [$fieldKey]: Document.fromJson OK');
      final ctrl = quill.QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );
      widget.logger.d('📋 DailyForm: _quillFromJson [$fieldKey]: QuillController created OK');
      return ctrl;
    } catch (e, st) {
      widget.logger.e('❌ DailyForm: _quillFromJson [$fieldKey]: EXCEPTION – falling back to basic', error: e, stackTrace: st);
      return quill.QuillController.basic();
    }
  }

  // ── local cache ───────────────────────────────────────────────
  Future<void> _saveDraftToCache() async {
    widget.logger.d('📋 DailyForm: _saveDraftToCache: cacheKey=$_cacheKey');
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'contractNumber': _contractController.text,
        'building': _buildingController.text,
        'date': _date.toIso8601String(),
        'startTime': _startTime != null
            ? '${_startTime!.hour}:${_startTime!.minute}'
            : null,
        'stopTime': _stopTime != null
            ? '${_stopTime!.hour}:${_stopTime!.minute}'
            : null,
        'weather': _weather,
        'subContractors': _selectedSubContractors,
        'visitorsJson': jsonEncode(_visitorsCtrl.document.toDelta().toJson()),
        'personnelVehiclesJson':
            jsonEncode(_personnelCtrl.document.toDelta().toJson()),
        'activitiesJson':
            jsonEncode(_activitiesCtrl.document.toDelta().toJson()),
        'remarksJson': jsonEncode(_remarksCtrl.document.toDelta().toJson()),
        'imageUrls': _savedImageUrls,
      };
      await prefs.setString(_cacheKey, jsonEncode(data));
      widget.logger.d('📋 DailyForm: _saveDraftToCache: saved OK');
    } catch (e) {
      widget.logger.w('⚠️ DailyForm: _saveDraftToCache: FAILED – $e');
    }
  }

  Future<void> _loadDraftFromCache() async {
    widget.logger.d('📋 DailyForm: _loadDraftFromCache: cacheKey=$_cacheKey');
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) {
        widget.logger.d('📋 DailyForm: _loadDraftFromCache: no cached data found');
        return;
      }
      widget.logger.i('📋 DailyForm: _loadDraftFromCache: cache hit – raw.length=${raw.length}');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _contractController.text = data['contractNumber'] ?? '';
        _buildingController.text = data['building'] ?? '';
        if (data['date'] != null) _date = DateTime.parse(data['date']);
        _startTime = _parseTime(data['startTime']);
        _stopTime = _parseTime(data['stopTime']);
        _weather = data['weather'] ?? '';
        // Restore list — supports both old single-string and new list format
        _selectedSubContractors.clear();
        if (data['subContractors'] != null) {
          _selectedSubContractors.addAll(
              List<String>.from(data['subContractors']));
        } else if (data['subContractor'] != null &&
            (data['subContractor'] as String).isNotEmpty) {
          _selectedSubContractors.add(data['subContractor'] as String);
        }
        _savedImageUrls.clear();
        _savedImageUrls.addAll(List<String>.from(data['imageUrls'] ?? []));
      });
      widget.logger.i('📋 DailyForm: _loadDraftFromCache: basic fields restored');
      // Re-build Quill controllers from cached JSON AFTER setState
      _visitorsCtrl   = _quillFromJson('visitors_cache',  data['visitorsJson'] ?? '');
      _personnelCtrl  = _quillFromJson('personnel_cache', data['personnelVehiclesJson'] ?? '');
      _activitiesCtrl = _quillFromJson('activities_cache', data['activitiesJson'] ?? '');
      _remarksCtrl    = _quillFromJson('remarks_cache',   data['remarksJson'] ?? '');
      widget.logger.i('📋 DailyForm: _loadDraftFromCache: Quill controllers restored from cache');
    } catch (e, st) {
      widget.logger.e('❌ DailyForm: _loadDraftFromCache: FAILED', error: e, stackTrace: st);
    }
  }

  Future<void> _clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    widget.logger.d('📋 DailyForm: _clearCache: cache cleared for key=$_cacheKey');
  }

  TimeOfDay? _parseTime(String? s) {
    if (s == null) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  // ── time validation ───────────────────────────────────────────
  /// Working hours: 06:00 – 19:00
  bool _isWithinWorkingHours(TimeOfDay t) =>
      (t.hour > 5) && (t.hour < 19 || (t.hour == 19 && t.minute == 0));

  // ── pickers ───────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme:
              pickerColorScheme(primary: _navy, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      widget.logger.i('📋 DailyForm: date picked → ${picked.toIso8601String()}');
      setState(() => _date = picked);
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart
        ? (_startTime ?? const TimeOfDay(hour: 7, minute: 0))
        : (_stopTime ?? const TimeOfDay(hour: 16, minute: 0));

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme:
              pickerColorScheme(primary: _navy, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;

    if (!_isWithinWorkingHours(picked)) {
      widget.logger.w('⚠️ DailyForm: time out of working hours → ${picked.hour}:${picked.minute}');
      _showError(
          context.l10n.rfWorkingHoursOnly);
      return;
    }
    if (!isStart && _startTime != null) {
      final s = _startTime!.hour * 60 + _startTime!.minute;
      final e = picked.hour * 60 + picked.minute;
      if (e <= s) {
        widget.logger.w('⚠️ DailyForm: stop time not after start time');
        _showError(context.l10n.rfStopAfterStart);
        return;
      }
    }
    if (isStart && _stopTime != null) {
      final s = picked.hour * 60 + picked.minute;
      final e = _stopTime!.hour * 60 + _stopTime!.minute;
      if (s >= e) {
        widget.logger.w('⚠️ DailyForm: start time not before stop time');
        _showError(context.l10n.rfStartBeforeStop);
        return;
      }
    }
    widget.logger.i('📋 DailyForm: ${isStart ? 'startTime' : 'stopTime'} set → ${picked.hour}:${picked.minute}');
    setState(() => isStart ? _startTime = picked : _stopTime = picked);
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: TextStyle()),
          backgroundColor: Colors.red[700],
        ),
      );

  // ── images ────────────────────────────────────────────────────
  Future<void> _pickImages() async {
    widget.logger.d('📋 DailyForm: _pickImages: opening image picker');
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 80);
    if (picked.isEmpty) {
      widget.logger.d('📋 DailyForm: _pickImages: no images selected');
      return;
    }
    widget.logger.i('📋 DailyForm: _pickImages: ${picked.length} image(s) selected');
    for (final xfile in picked) {
      final bytes = await xfile.readAsBytes();
      setState(() => _localImages.add(bytes));
    }
    widget.logger.i('📋 DailyForm: _pickImages: total local images now=${_localImages.length}');
  }

  // ── Full-screen image viewer ──────────────────────────────────
  void _showImageViewer(List<_ImageItem> images, int initialIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => _ImageViewerDialog(
        images: images,
        initialIndex: initialIndex,
      ),
    );
  }

  // ── save to Firestore ─────────────────────────────────────────
  Future<DailyReportData> _buildReportData() async {
    widget.logger.d('📋 DailyForm: _buildReportData: uploading ${_localImages.length} local image(s)');
    // Upload any local images first
    final List<String> allUrls = List.from(_savedImageUrls);
    for (int i = 0; i < _localImages.length; i++) {
      final ref = FirebaseStorage.instance
          .ref()
          .child(widget.project.id)
          .child('Reports')
          .child('Daily')
          .child('images')
          .child('${_reportId}_img_$i.jpg');
      await ref.putData(_localImages[i],
          SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      widget.logger.d('📋 DailyForm: _buildReportData: image[$i] uploaded → $url');
      allUrls.add(url);
    }
    widget.logger.i('📋 DailyForm: _buildReportData: all images uploaded, total urls=${allUrls.length}');

    return DailyReportData(
      id: _reportId,
      projectId: widget.project.id,
      projectName: widget.project.name,
      contractNumber: _contractController.text.trim(),
      date: _date,
      startTime: _startTime,
      stopTime: _stopTime,
      weather: _weather,
      building: _buildingController.text.trim(),
      visitorsJson: jsonEncode(_visitorsCtrl.document.toDelta().toJson()),
      subContractors: List<String>.from(_selectedSubContractors),
      personnelVehiclesJson:
          jsonEncode(_personnelCtrl.document.toDelta().toJson()),
      activitiesJson: jsonEncode(_activitiesCtrl.document.toDelta().toJson()),
      remarksJson: jsonEncode(_remarksCtrl.document.toDelta().toJson()),
      imageUrls: allUrls,
      isDraft: false,
      savedAt: DateTime.now(),
    );
  }

  Future<void> _saveReport({bool silent = false}) async {
    if (_isSaving) return;
    widget.logger.i('📋 DailyForm: _saveReport: START (silent=$silent, reportId=$_reportId)');
    setState(() => _isSaving = true);
    try {
      await _saveDraftToCache();
      final report = await _buildReportData();
      final map = report.toMap();
      if (widget.existingReport == null) {
        widget.logger.i('📋 DailyForm: _saveReport: creating new Firestore doc');
        // Use the date filled in the form (not the save timestamp) as the
        // human-readable document title shown in the reports list.
        final readableName =
            l10nNow.reportTitleDated(l10nNow.rptDailyReport, DateFormat.yMMMd().format(_date));
        await FirebaseFirestore.instance
            .collection('Reports')
            .doc(_reportId)
            .set({
          ...map,
          'uploadedAt': Timestamp.now(),
          'name': readableName,
        });
      } else {
        widget.logger.i('📋 DailyForm: _saveReport: updating existing Firestore doc');
        await FirebaseFirestore.instance
            .collection('Reports')
            .doc(_reportId)
            .update(map);
      }
      await _clearCache();
      _localImages.clear();
      widget.logger.i('✅ DailyForm: _saveReport: saved successfully (id=$_reportId)');
      if (!silent && mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(context.l10n.dailyReportSaved, style: TextStyle()),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e, st) {
      widget.logger.e('❌ DailyForm: _saveReport: FAILED', error: e, stackTrace: st);
      if (mounted) _showError(friendlyError(e, action: context.l10n.couldNotSaveReport));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  PDF GENERATION
  // ══════════════════════════════════════════════════════════════

  // ── Resolve Quill font attr → pw.Font ────────────────────────
  // font attr value coming from flutter_quill is the CSS font-family
  // string set by the toolbar (e.g. "Arial", "Times New Roman").
  // We purposely do NOT default to Times — plain text with no font
  // attr stays Helvetica (the clean PDF default).
  pw.Font _resolveFont(String? family,
      {bool bold = false, bool italic = false}) {
    final f = (family ?? '').toLowerCase().trim();
    if (f.isEmpty) {
      // No font attr → Helvetica family
      if (bold && italic) return pw.Font.helveticaBoldOblique();
      if (bold)           return pw.Font.helveticaBold();
      if (italic)         return pw.Font.helveticaOblique();
      return pw.Font.helvetica();
    }
    if (f.contains('times') || f.contains('serif')) {
      if (bold && italic) return pw.Font.timesBoldItalic();
      if (bold)           return pw.Font.timesBold();
      if (italic)         return pw.Font.timesItalic();
      return pw.Font.times();
    }
    if (f.contains('courier') || f.contains('mono')) {
      if (bold && italic) return pw.Font.courierBoldOblique();
      if (bold)           return pw.Font.courierBold();
      if (italic)         return pw.Font.courierOblique();
      return pw.Font.courier();
    }
    // Arial / Helvetica / Sans-serif / anything else
    if (bold && italic) return pw.Font.helveticaBoldOblique();
    if (bold)           return pw.Font.helveticaBold();
    if (italic)         return pw.Font.helveticaOblique();
    return pw.Font.helvetica();
  }

  // ── Convert Quill Delta → list of pdf paragraph widgets ───────
  // Maps bold, italic, underline, colour, bullet, numbered list,
  // text-align and font-family to their pdf equivalents.
  // Each paragraph is a separate widget so MultiPage reflowing works.
  List<pw.Widget> _quillDeltaToPdfWidgets(
    quill.QuillController ctrl,
    pw.TextStyle baseStyle,
  ) {
    final List<pw.Widget> widgets = [];
    final ops = ctrl.document.toDelta().toJson() as List<dynamic>;

    final List<pw.InlineSpan> currentSpans = [];
    pw.TextAlign blockAlign = pw.TextAlign.left;
    bool isBullet  = false;
    bool isOrdered = false;
    int  orderedIndex = 1;
    // Last seen inline attrs — Quill puts block attrs on '\n' ops
    // which carry no text, so we keep inline attrs from the previous
    // text op to detect bold-bullet combos.
    Map<String, dynamic> lastInlineAttrs = {};

    void flushBlock() {
      if (currentSpans.isEmpty) return;
      final richText = pw.RichText(
        textAlign: blockAlign,
        text: pw.TextSpan(children: List.of(currentSpans)),
      );
      pw.Widget line;
      if (isBullet) {
        line = pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('•  ',
                style: baseStyle.copyWith(
                    font: _resolveFont(null, bold: true))),
            pw.Expanded(child: richText),
          ],
        );
      } else if (isOrdered) {
        line = pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('$orderedIndex.  ', style: baseStyle),
            pw.Expanded(child: richText),
          ],
        );
        orderedIndex++;
      } else {
        line = richText;
      }
      widgets.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: line,
      ));
      currentSpans.clear();
      blockAlign = pw.TextAlign.left;
      isBullet   = false;
      isOrdered  = false;
    }

    for (final op in ops) {
      if (op is! Map) continue;
      final insert = op['insert'];
      final attrs  = (op['attributes'] as Map<String, dynamic>?) ?? {};
      if (insert is! String) continue;

      final parts = insert.split('\n');
      for (int pi = 0; pi < parts.length; pi++) {
        final part = parts[pi];

        if (part.isNotEmpty) {
          lastInlineAttrs = Map.of(attrs);
          final bold      = attrs['bold']      == true;
          final italic    = attrs['italic']    == true;
          final underline = attrs['underline'] == true;
          // font attr stores the CSS font-family string
          final family    = attrs['font'] as String?;
          final colorHex  = attrs['color'] as String?;

          PdfColor spanColor = PdfColors.black;
          if (colorHex != null && colorHex.startsWith('#')) {
            try { spanColor = PdfColor.fromHex(colorHex); } catch (_) {}
          }

          final spanStyle = baseStyle.copyWith(
            font: _resolveFont(family, bold: bold, italic: italic),
            fontFallback: [],
            decoration: underline
                ? pw.TextDecoration.underline
                : pw.TextDecoration.none,
            color: spanColor,
          );
          currentSpans.add(pw.TextSpan(text: part, style: spanStyle));
        }

        if (pi < parts.length - 1) {
          // Block-level attrs sit on the '\n' op; merge with last
          // inline attrs so bold-bullet, italic-centre, etc. work.
          final blockAttrs =
              attrs.isNotEmpty ? attrs : lastInlineAttrs;
          final align = blockAttrs['align'] as String?;
          blockAlign = align == 'center'
              ? pw.TextAlign.center
              : align == 'right'
                  ? pw.TextAlign.right
                  : align == 'justify'
                      ? pw.TextAlign.justify
                      : pw.TextAlign.left;
          isBullet  = blockAttrs['list'] == 'bullet';
          isOrdered = blockAttrs['list'] == 'ordered';
          flushBlock();
          lastInlineAttrs = {};
        }
      }
    }
    flushBlock();
    return widgets;
  }

  // ── Cross-platform PDF save to device Downloads ───────────────
  // Web     → browser download via Printing.sharePdf
  // Android → system public Downloads folder
  //           (/storage/emulated/0/Download  — the folder every
  //            Android file manager and the Downloads app shows)
  // iOS     → app Documents directory (accessible in Files app
  //           under On My iPhone → AlmaWorks)
  // Windows → %USERPROFILE%\Downloads
  // macOS   → $HOME/Downloads
  // Linux   → $HOME/Downloads
  Future<void> _savePdfBytes(Uint8List bytes, String fileName) async {
    widget.logger.i(
        '📋 DailyForm: _savePdfBytes platform=${kIsWeb ? "web" : defaultTargetPlatform.name}');

    // ── Web ──────────────────────────────────────────────────────
    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
      return;
    }

    try {
      String dirPath;

      if (defaultTargetPlatform == TargetPlatform.android) {
        // Android public Downloads directory.
        // /storage/emulated/0/Download is the canonical path that
        // maps to Environment.getExternalStoragePublicDirectory(
        //   Environment.DIRECTORY_DOWNLOADS) on all Android versions.
        // We verify it exists before using it; if somehow it doesn't
        // (e.g. unusual OEM setup) we fall back to the path_provider
        // external storage root trimmed above the /Android/ segment.
        const androidDownloads = '/storage/emulated/0/Download';
        if (await Directory(androidDownloads).exists()) {
          dirPath = androidDownloads;
        } else {
          // Fallback: walk up from app-specific external path
          final ext = await getExternalStorageDirectory();
          if (ext != null) {
            final parts = ext.path.split('/');
            final idx   = parts.indexOf('Android');
            dirPath     = idx > 0
                ? parts.sublist(0, idx).join('/')
                : ext.path;
            // Append the standard Downloads sub-folder name
            dirPath = '$dirPath/Download';
          } else {
            dirPath = (await getApplicationDocumentsDirectory()).path;
          }
        }

      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        // iOS sandbox: Documents is visible to the user in Files app.
        dirPath = (await getApplicationDocumentsDirectory()).path;

      } else {
        // Windows → %USERPROFILE%\Downloads
        // macOS   → $HOME/Downloads
        // Linux   → $HOME/Downloads
        final homeDir = Platform.environment['USERPROFILE']  // Windows
            ?? Platform.environment['HOME'];                 // macOS / Linux
        if (homeDir != null && homeDir.isNotEmpty) {
          dirPath =
              '$homeDir${Platform.pathSeparator}Downloads';
        } else {
          // Rare fallback if HOME is not set
          dirPath = (await getApplicationDocumentsDirectory()).path;
        }
      }

      // Ensure directory exists (needed on desktop when ~/Downloads
      // has never been created, or on first run).
      final dir = Directory(dirPath);
      if (!await dir.exists()) await dir.create(recursive: true);

      final filePath = '$dirPath${Platform.pathSeparator}$fileName';
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      widget.logger.i('✅ DailyForm: PDF saved → $filePath');

      // Open the saved file so the user can view / share it.
      await OpenFile.open(filePath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            context.l10n.pdfSavedToDownloads(fileName),
            style: TextStyle(),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e, st) {
      widget.logger.e(
          '❌ DailyForm: _savePdfBytes failed, falling back to share',
          error: e,
          stackTrace: st);
      // Last resort: system share sheet (always works)
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    }
  }

  // ── PDF 2-column image grid ───────────────────────────────────
  // A4 content width after 28pt margins = ~539pt.
  // 1 image  → centred at 55% of page width.
  // 2+ images → rows of 2, each column ~half page width.
  List<pw.Widget> _buildPdfImageGrid(List<pw.MemoryImage> images) {
    const double pageW  = 539.0;
    const double gap    = 8.0;
    const double colW2  = (pageW - gap) / 2;   // 2-col width
    const double colH2  = colW2 * 0.68;        // ~3:2 ratio
    const double soloW  = pageW * 0.55;         // single-image width
    const double soloH  = soloW * 0.68;

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
      rows.add(pw.Row(
        children: [
          pw.Image(images[i],
              width: colW2, height: colH2, fit: pw.BoxFit.cover),
          if (hasNext) ...[
            pw.SizedBox(width: gap),
            pw.Image(images[i + 1],
                width: colW2, height: colH2, fit: pw.BoxFit.cover),
          ] else
            pw.SizedBox(width: colW2 + gap), // keep row balanced
        ],
      ));
      if (i + 2 < images.length) rows.add(pw.SizedBox(height: gap));
    }
    return rows;
  }

  Future<void> _downloadAsPdf() async {
    widget.logger.i('📋 DailyForm: _downloadAsPdf: START');
    setState(() => _isGeneratingPdf = true);
    try {
      final report  = await _buildReportData();
      if (!mounted) return;
      final l = context.l10n;
      final dateStr = DateFormat.yMMMMd().format(report.date);
      final fileName =
          'Daily_Report_${report.projectName.replaceAll(' ', '_')}_'
          '${DateFormat('yyyyMMdd').format(_date)}.pdf';

      widget.logger.d('📋 DailyForm: building PDF');

      String fmtTime(TimeOfDay? t) {
        if (t == null) return '';
        final h      = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
        final m      = t.minute.toString().padLeft(2, '0');
        final period = t.period == DayPeriod.am ? 'AM' : 'PM';
        return '$h:$m $period';
      }

      // ── Collect images: local (in-session) + saved (Firebase Storage URLs) ──
      final List<pw.MemoryImage> pdfImages = [];
      // 1) Local bytes picked this session
      for (final bytes in _localImages) {
        pdfImages.add(pw.MemoryImage(bytes));
      }
      // 2) Previously-saved URLs — download bytes via Firebase Storage
      for (final url in _savedImageUrls) {
        try {
          final data = await FirebaseStorage.instance
              .refFromURL(url)
              .getData(10 * 1024 * 1024); // 10 MB cap per image
          if (data != null) pdfImages.add(pw.MemoryImage(data));
        } catch (e) {
          widget.logger.w('⚠️ DailyForm: could not fetch image for PDF – $url – $e');
        }
      }

      // ── Colour palette ────────────────────────────────────────
      final navyColor = PdfColor.fromHex('#0A2E5A');
      final lightBlue = PdfColor.fromHex('#E8EEF6');

      // ── Shared text styles ────────────────────────────────────
      final sectionHeaderStyle = pw.TextStyle(
        font: pw.Font.helveticaBold(),
        fontSize: 9.5,
        color: PdfColors.white,
        letterSpacing: 0.5,
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

      // ── Navy section title bar ────────────────────────────────
      pw.Widget sectionBar(String label) => pw.Container(
            width: double.infinity,
            color: navyColor,
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 8, vertical: 5),
            child: pw.Text(label, style: sectionHeaderStyle),
          );

      // ── 4-column meta cell ────────────────────────────────────
      pw.Widget metaCell(String label, String value) => pw.Expanded(
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
                  pw.SizedBox(height: 20),  // writing space
                ],
              ),
            ),
          );

      // When the form has data, show the actual value; when blank,
      // show only writing space so the printed form looks clean.
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
                    child: pw.Text(
                      value.isEmpty ? '' : value,
                      style: fieldValueStyle,
                    ),
                  ),
                ],
              ),
            ),
          );

      // ── Rich-text section builder ─────────────────────────────
      // Has content → render rich paragraphs from Delta.
      // Empty       → render a clean blank box (no ruled lines).
      List<pw.Widget> richSectionWidgets(
          String label, quill.QuillController ctrl) {
        final raw = ctrl.document.toPlainText().trim();
        final List<pw.Widget> body;
        if (raw.isEmpty) {
          body = [pw.SizedBox(height: 60)];
        } else {
          body = _quillDeltaToPdfWidgets(ctrl, fieldValueStyle);
          if (body.isEmpty) body.add(pw.SizedBox(height: 60));
        }
        return [
          sectionBar(label),
          pw.Container(
            width: double.infinity,
            decoration: pw.BoxDecoration(
                border: pw.Border.all(
                    color: PdfColors.blueGrey300, width: 0.5)),
            padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: body,
            ),
          ),
          pw.SizedBox(height: 6),
        ];
      }

      // ── Multi-row sub-contractor section (one row per entry) ──
      List<pw.Widget> subContractorSectionWidgets(
          String label, List<String> contractors) {
        final List<pw.Widget> rows;
        if (contractors.isEmpty) {
          rows = [pw.SizedBox(height: 60)];
        } else {
          rows = contractors.asMap().entries.map((entry) {
            final idx  = entry.key + 1;
            final name = entry.value;
            return pw.Container(
              width: double.infinity,
              decoration: pw.BoxDecoration(
                color: idx.isEven
                    ? PdfColor.fromHex('#F5F7FA')
                    : PdfColors.white,
                border: const pw.Border(
                  bottom: pw.BorderSide(
                      color: PdfColors.blueGrey200, width: 0.4),
                ),
              ),
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8, vertical: 5),
              child: pw.Row(
                children: [
                  pw.Container(
                    width: 20,
                    child: pw.Text(
                      '$idx.',
                      style: pw.TextStyle(
                        font: pw.Font.helveticaBold(),
                        fontSize: 8.5,
                        color: navyColor,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(name, style: fieldValueStyle),
                  ),
                ],
              ),
            );
          }).toList();
        }
        return [
          sectionBar(label),
          pw.Container(
            width: double.infinity,
            decoration: pw.BoxDecoration(
                border: pw.Border.all(
                    color: PdfColors.blueGrey300, width: 0.5)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: rows,
            ),
          ),
          pw.SizedBox(height: 6),
        ];
      }

      // ── Determine if the form has any data (filled vs blank) ──
      final isFilled = report.building.isNotEmpty ||
          _visitorsCtrl.document.toPlainText().trim().isNotEmpty ||
          _personnelCtrl.document.toPlainText().trim().isNotEmpty ||
          _activitiesCtrl.document.toPlainText().trim().isNotEmpty ||
          _remarksCtrl.document.toPlainText().trim().isNotEmpty;

      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 48),

          // ── FOOTER — every page ───────────────────────────────
          footer: (ctx) => pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(
                    color: PdfColors.grey400, width: 0.5),
              ),
            ),
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  l.pdfDailyFooter,
                  style: pw.TextStyle(
                      font: pw.Font.helvetica(),
                      fontSize: 7,
                      color: PdfColors.grey600),
                ),
                pw.Text(
                  l.pdfPageOf(ctx.pageNumber, ctx.pagesCount),
                  style: pw.TextStyle(
                      font: pw.Font.helvetica(),
                      fontSize: 7,
                      color: PdfColors.grey600),
                ),
              ],
            ),
          ),

          build: (ctx) => [
            // ══ TITLE BLOCK ══════════════════════════════════════
            // Three separate Containers sharing navyColor so they
            // appear as one seamless navy band but each text widget
            // gets its own padding — this prevents "DAILY REPORT"
            // from being swallowed into the project name Container.
            pw.Container(
              width: double.infinity,
              color: navyColor,
              padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 2),
              child: pw.Text(
                report.projectName,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: pw.Font.helveticaBold(),
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
                l.rfDailyReportCaps,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: pw.Font.helveticaBold(),
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
                l.contractNoValue(report.contractNumber),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: pw.Font.helvetica(),
                  fontSize: 8.5,
                  color: PdfColor.fromHex('#FFFFFFB3'),
                ),
              ),
            ),
            pw.SizedBox(height: 10),

            // ══ 4-COLUMN META ROW ════════════════════════════════
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                isFilled
                    ? metaCellFilled(l.rfDateCaps, dateStr)
                    : metaCell(l.rfDateCaps, ''),
                pw.SizedBox(width: 4),
                isFilled
                    ? metaCellFilled(l.rfStartTimeCaps, fmtTime(_startTime))
                    : metaCell(l.rfStartTimeCaps, ''),
                pw.SizedBox(width: 4),
                isFilled
                    ? metaCellFilled(l.rfStopTimeCaps, fmtTime(_stopTime))
                    : metaCell(l.rfStopTimeCaps, ''),
                pw.SizedBox(width: 4),
                isFilled
                    ? metaCellFilled(l.rfWeatherCaps, weatherLabel(report.weather))
                    : metaCell(l.rfWeatherCaps, ''),
              ],
            ),
            pw.SizedBox(height: 6),

            // ══ BUILDING ═════════════════════════════════════════
            pw.Container(
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: PdfColors.blueGrey300, width: 0.5)),
              child: pw.Row(
                children: [
                  pw.Container(
                    width: 65,
                    color: lightBlue,
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 5, vertical: 10),
                    child: pw.Text(l.rfBuildingCaps, style: fieldLabelStyle),
                  ),
                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      child: report.building.isEmpty
                          ? pw.SizedBox()
                          : pw.Text(
                              report.building,
                              style: fieldValueStyle,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),

            // ══ CONTENT SECTIONS ═════════════════════════════════
            ...richSectionWidgets(l.rfVisitorsCaps, _visitorsCtrl),
            ...subContractorSectionWidgets(
                l.rfSubContractorCaps, report.subContractors),
            ...richSectionWidgets(
                l.rfPersonnelCaps, _personnelCtrl),
            ...richSectionWidgets(l.rfActivitiesCaps, _activitiesCtrl),
            ...richSectionWidgets(l.rfRemarksCaps, _remarksCtrl),

            // ══ ATTACHED IMAGES ══════════════════════════════════
            if (pdfImages.isNotEmpty) ...[
              sectionBar(l.rfAttachedImagesCaps),
              pw.SizedBox(height: 8),
              // 2-column grid: single image centred at 60% width,
              // multiple images in rows of 2 filling page width.
              ..._buildPdfImageGrid(pdfImages),
            ],
          ],
        ),
      );

      final bytes = await pdf.save();
      await _savePdfBytes(Uint8List.fromList(bytes), fileName);
      widget.logger.i('✅ DailyForm: PDF complete: $fileName');
    } catch (e, st) {
      widget.logger.e('❌ DailyForm: _downloadAsPdf FAILED',
          error: e, stackTrace: st);
      if (mounted) _showError(friendlyError(e, action: context.l10n.couldNotCreatePdf));
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  // ── new form (save current + reset) ──────────────────────────
  Future<void> _addNewForm() async {
    widget.logger.i('📋 DailyForm: _addNewForm: saving current form before reset');
    await _saveReport(silent: true);
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.l10n.newDailyReport,
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
            context.l10n.newDailyReportBody,
            style: TextStyle()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel, style: TextStyle())),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: _navy, foregroundColor: Colors.white),
            child: Text(context.l10n.newForm, style: TextStyle()),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      widget.logger.d('📋 DailyForm: _addNewForm: user cancelled new form dialog');
      return;
    }

    widget.logger.i('📋 DailyForm: _addNewForm: user confirmed – pushing fresh form screen');
    // Push a fresh screen instance
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DailyReportFormScreen(
          project: widget.project,
          logger: widget.logger,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    widget.logger.d('📋 DailyForm: build()');
    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '${context.l10n.projectDailyReport(widget.project.name)}'
          '${_isReadOnly ? context.l10n.viewSuffix : ''}',
          style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () async {
            final nav = Navigator.of(context);
            widget.logger.d('📋 DailyForm: back pressed – saving draft');
            if (!_isReadOnly) await _saveDraftToCache();
            nav.pop();
          },
        ),
      ),
      // ── Floating Edit button (read-only mode only) ──────────────
      floatingActionButton: _isReadOnly
          ? FloatingActionButton.extended(
              onPressed: () {
                widget.logger.i('📋 DailyForm: FAB Edit tapped – switching to edit mode');
                setState(() => _isReadOnly = false);
              },
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.edit_rounded),
              label: Text(context.l10n.edit, style: TextStyle(fontWeight: FontWeight.w600)),
            )
          : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final aw = constraints.maxWidth;
          // Cap the usable content width so fields don't stretch absurdly on
          // ultra-wide desktop screens.  Everything beyond 860 px gets centred.
          final contentW = aw.clamp(0.0, 860.0);
          final hPad = contentW * 0.04;
          final gap  = 14.0; // fixed vertical gap — no more percentage scaling
          widget.logger.d('📋 DailyForm: LayoutBuilder: availableWidth=$aw  contentW=$contentW  hPad=$hPad');

          return Form(
            key: _formKey,
            child: SingleChildScrollView(
              controller: _scrollController,
              // No horizontal padding here — header needs full width.
              // Inner sections add their own horizontal padding.
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── FORM HEADER (full width — no side padding) ──
                  _buildFormHeader(contentW),

                  // ── padded content starts here ──────────────────
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: gap),

                        // ── REPORT TYPE SUBTITLE ─────────────────
                        _buildReportTypeTitle(),
                        SizedBox(height: gap),

                        // ── DATE / TIME / WEATHER (4 columns) ────
                        _buildDateTimeWeatherRow(contentW),
                        SizedBox(height: gap),

                        // ── BUILDING ─────────────────────────────
                        _buildBuildingField(contentW),
                        SizedBox(height: gap),

                        // ── VISITORS ─────────────────────────────
                        _buildRichSection(
                          title: context.l10n.rfVisitorsCaps,
                          fieldKey: 'visitors',
                          hint: context.l10n.rfVisitorsHint,
                          controller: _visitorsCtrl,
                          aw: contentW,
                        ),
                        SizedBox(height: gap),

                        // ── SUB-CONTRACTOR ───────────────────────
                        _buildSubContractorSection(contentW),
                        SizedBox(height: gap),

                        // ── PERSONNEL AND VEHICLES ───────────────
                        _buildRichSection(
                          title: context.l10n.rfPersonnelCaps,
                          fieldKey: 'personnel',
                          hint: context.l10n.rfPersonnelHint,
                          controller: _personnelCtrl,
                          aw: contentW,
                        ),
                        SizedBox(height: gap),

                        // ── ACTIVITIES ───────────────────────────
                        _buildRichSection(
                          title: context.l10n.rfActivitiesCaps,
                          fieldKey: 'activities',
                          hint: context.l10n.rfActivitiesHint,
                          controller: _activitiesCtrl,
                          aw: contentW,
                        ),
                        SizedBox(height: gap),

                        // ── REMARKS ──────────────────────────────
                        _buildRichSection(
                          title: context.l10n.rfRemarksCaps,
                          fieldKey: 'remarks',
                          hint: context.l10n.rfRemarksHint,
                          controller: _remarksCtrl,
                          aw: contentW,
                        ),
                        SizedBox(height: gap),

                        // ── IMAGE ATTACHMENTS ─────────────────────
                        _buildImageSection(contentW),
                        const SizedBox(height: 20),

                        // ── ACTION BUTTONS ────────────────────────
                        _buildActionButtons(contentW),
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
  //  WIDGET BUILDERS
  // ══════════════════════════════════════════════════════════════

  // ── Form header — full-width navy band, no rounded corners ──────
  Widget _buildFormHeader(double aw) {
    widget.logger.d('📋 DailyForm: _buildFormHeader → aw=$aw');
    return Container(
      // Square corners — fills flush edge-to-edge under the AppBar
      color: _navy,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Project name: full width, wraps freely, never ellipsis ──
          Text(
            widget.project.name,
            textAlign: TextAlign.center,
            softWrap: true,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          // ── Contract No as subtitle row ──────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.contractNoLabel,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
              SizedBox(
                width: 180,
                child: TextFormField(
                  controller: _contractController,
                  readOnly: _isReadOnly,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: _isReadOnly ? '—' : context.l10n.contractNoHint,
                    hintStyle: TextStyle(
                        color: Colors.white38, fontSize: 12),
                    isDense: true,
                    border: const UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: Colors.white54, width: 1)),
                    enabledBorder: const UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: Colors.white54, width: 1)),
                    focusedBorder: const UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: Colors.white, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 4, horizontal: 2),
                  ),
                  onChanged: _isReadOnly ? null : (v) {
                    widget.logger.d(
                        '📋 DailyForm: contractNumber changed → "$v"');
                    _saveDraftToCache();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Report type title — plain centred text, no border/box ───────
  Widget _buildReportTypeTitle() {
    widget.logger.d('📋 DailyForm: _buildReportTypeTitle');
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          context.l10n.rfDailyReportCaps,
          style: TextStyle(
            color: AppColors.brandInk,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
      ),
    );
  }

  // ── Date / Time / Weather — 4 compact equal columns in one row ──
  Widget _buildDateTimeWeatherRow(double aw) {
    widget.logger.d('📋 DailyForm: _buildDateTimeWeatherRow → aw=$aw');

    const double labelFs = 10.0;
    const double valueFs = 12.5;
    const double iconSz  = 15.0;
    const double cellPH  = 10.0;
    const double cellPV  = 8.0;
    const double cellRad = 6.0;

    final String dateStr = DateFormat.yMMMEd().format(_date);
    final tapToSet = context.l10n.tapToSet;
    String fmtTime(TimeOfDay? t) => t == null
        ? tapToSet
        : '${t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod}:'
            '${t.minute.toString().padLeft(2, '0')} '
            '${t.period == DayPeriod.am ? 'AM' : 'PM'}';

    widget.logger.d('📋 DailyForm: date=$dateStr  '
        'start=${fmtTime(_startTime)}  stop=${fmtTime(_stopTime)}  weather="$_weather"');

    // Compact tappable cell
    Widget cell({
      required String label,
      required String value,
      required IconData icon,
      required VoidCallback onTap,
    }) {
      return GestureDetector(
        onTap: _isReadOnly ? null : onTap,
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(cellRad),
            border: Border.all(color: _fieldBorder, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 3,
                offset: const Offset(0, 1),
              )
            ],
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: cellPH, vertical: cellPV),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(children: [
                Icon(icon, color: AppColors.brandInk, size: iconSz),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                      fontSize: labelFs,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brandInk.withValues(alpha: 0.7),
                      letterSpacing: 0.3,
                    )),
              ]),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  fontSize: valueFs,
                  fontWeight: FontWeight.w500,
                  color: value == tapToSet
                      ? Colors.grey[400]
                      : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    // Weather dropdown cell — same fixed height
    final weatherCell = Container(
      height: 58,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(cellRad),
        border: Border.all(color: _fieldBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 3,
            offset: const Offset(0, 1),
          )
        ],
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: cellPH, vertical: cellPV),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Icon(Icons.wb_sunny_rounded, color: AppColors.brandInk, size: iconSz),
            const SizedBox(width: 4),
            Text(context.l10n.rfWeatherCaps,
                style: TextStyle(
                  fontSize: labelFs,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandInk.withValues(alpha: 0.7),
                  letterSpacing: 0.3,
                )),
          ]),
          const SizedBox(height: 1),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _weather.isEmpty ? null : _weather,
              hint: Text(context.l10n.selectEllipsis,
                  style: TextStyle(
                      color: Colors.grey[400], fontSize: valueFs)),
              isExpanded: true,
              isDense: true,
              icon: Icon(Icons.expand_more_rounded,
                  color: AppColors.brandInk, size: 16),
              style: TextStyle(
                  fontSize: valueFs, color: AppColors.ink),
              items: _weatherOptions
                  .map((w) => DropdownMenuItem(
                      value: w,
                      child: Text(weatherLabel(w),
                          style:
                              TextStyle(fontSize: valueFs))))
                  .toList(),
              onChanged: _isReadOnly ? null : (v) {
                widget.logger.i('📋 DailyForm: weather selected → "$v"');
                setState(() => _weather = v ?? '');
                _saveDraftToCache();
              },
            ),
          ),
        ],
      ),
    );

    return Row(
      children: [
        Expanded(
            child: cell(
                label: context.l10n.rfDateCaps,
                value: dateStr,
                icon: Icons.calendar_today_rounded,
                onTap: _pickDate)),
        const SizedBox(width: 8),
        Expanded(
            child: cell(
                label: context.l10n.rfStartTimeCaps,
                value: fmtTime(_startTime),
                icon: Icons.access_time_rounded,
                onTap: () => _pickTime(isStart: true))),
        const SizedBox(width: 8),
        Expanded(
            child: cell(
                label: context.l10n.rfStopTimeCaps,
                value: fmtTime(_stopTime),
                icon: Icons.timer_off_rounded,
                onTap: () => _pickTime(isStart: false))),
        const SizedBox(width: 8),
        Expanded(child: weatherCell),
      ],
    );
  }

  // ── Building field — compact single-line, fixed height ──────────
  Widget _buildBuildingField(double aw) {
    widget.logger.d('📋 DailyForm: _buildBuildingField → aw=$aw');
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _fieldBorder, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Fixed-width label tab
          Container(
            width: 100,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(6),
                bottomLeft: Radius.circular(6),
              ),
            ),
            child: Text(
              context.l10n.rfBuildingCaps,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.brandInk,
                letterSpacing: 0.5,
              ),
            ),
          ),
          // Input — text vertically centred inside the fixed-height row
          Expanded(
            child: Center(
              child: TextFormField(
                controller: _buildingController,
                readOnly: _isReadOnly,
                textAlignVertical: TextAlignVertical.center,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'[a-zA-Z0-9\s\-_/]'))
                ],
                style:
                    TextStyle(fontSize: 13, color: AppColors.ink),
                decoration: InputDecoration(
                  hintText: _isReadOnly ? '—' : context.l10n.buildingHint,
                  hintStyle: TextStyle(
                      color: Colors.grey[400], fontSize: 12),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                ),
                onChanged: _isReadOnly ? null : (v) {
                  widget.logger.d('📋 DailyForm: building changed → "$v"');
                  _saveDraftToCache();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Rich-text section ─────────────────────────────────────────
  Widget _buildRichSection({
    required String fieldKey,
    required String title,
    required String hint,
    required quill.QuillController controller,
    required double aw,
  }) {
    widget.logger.d('📋 DailyForm: _buildRichSection[$fieldKey] → aw=$aw  controller.hashCode=${controller.hashCode}');

    final double titleFs   = (aw * 0.030).clamp(10.0, 14.0);
    final double editorFs  = (aw * 0.032).clamp(11.0, 14.0);
    final double minH      = (aw * 0.38).clamp(120.0, 300.0);
    final double radius    = aw * 0.022;
    final double titlePH   = aw * 0.035;
    final double titlePV   = aw * 0.025;
    final double editorPad = aw * 0.030;
    final double toolbarSz = (aw * 0.088).clamp(32.0, 44.0);

    try {
      // ── Toolbar ──────────────────────────────────────────────
      Widget toolbarWidget;
      if (_isReadOnly) {
        toolbarWidget = const SizedBox.shrink();
      } else {
      try {
        widget.logger.d('📋 DailyForm: [$fieldKey] building QuillSimpleToolbar (toolbarSize=$toolbarSz)');
        toolbarWidget = quill.QuillSimpleToolbar(
          controller: controller,
          config: quill.QuillSimpleToolbarConfig(
            showBoldButton: true,
            showItalicButton: true,
            showUnderLineButton: true,
            showListBullets: true,
            showListNumbers: true,
            showIndent: true,
            showClearFormat: true,
            showFontSize: false,
            showFontFamily: false,          // disabled — font picker needs custom config not supported in 11.5.0 SimpleToolbar
            showColorButton: false,
            showBackgroundColorButton: false,
            showSubscript: false,
            showSuperscript: false,
            showInlineCode: false,
            showCodeBlock: false,
            showQuote: false,
            showLink: false,
            showSearchButton: false,
            showAlignmentButtons: true,     // ← ENABLED: L / C / R / Justify
            showHeaderStyle: false,
            showDividers: true,
            toolbarIconAlignment: WrapAlignment.start,
            toolbarSize: toolbarSz,
          ),
        );
        widget.logger.d('📋 DailyForm: [$fieldKey] QuillSimpleToolbar built OK');
      } catch (e, st) {
        widget.logger.e('❌ DailyForm: [$fieldKey] QuillSimpleToolbar FAILED', error: e, stackTrace: st);
        toolbarWidget = Container(
          color: Colors.amber[100],
          padding: EdgeInsets.all(editorPad),
          child: Text(
            '⚠ ${context.l10n.rfSectionError}',
            style: TextStyle(
                color: AppColors.danger, fontSize: 11),
          ),
        );
      }
      }

      // ── Editor ───────────────────────────────────────────────
      Widget editorWidget;
      try {
        widget.logger.d('📋 DailyForm: [$fieldKey] building QuillEditor (minH=$minH  fontSize=$editorFs)');
        editorWidget = AbsorbPointer(
          absorbing: _isReadOnly,
          child: Container(
            constraints: BoxConstraints(minHeight: minH),
            padding: EdgeInsets.all(editorPad),
            child: quill.QuillEditor.basic(
              controller: controller,
              config: quill.QuillEditorConfig(
                placeholder: hint,
                minHeight: minH,
                expands: false,
                scrollable: true,
                autoFocus: false,
                enableInteractiveSelection: true,
                customStyles: quill.DefaultStyles(
                  placeHolder: quill.DefaultTextBlockStyle(
                    TextStyle(
                        color: Colors.grey[400], fontSize: editorFs),
                    const quill.HorizontalSpacing(0, 0),
                    const quill.VerticalSpacing(0, 0),
                    const quill.VerticalSpacing(0, 0),
                    null,
                  ),
                  paragraph: quill.DefaultTextBlockStyle(
                    TextStyle(
                        color: AppColors.ink, fontSize: editorFs),
                    const quill.HorizontalSpacing(0, 0),
                    const quill.VerticalSpacing(2, 2),
                    const quill.VerticalSpacing(0, 0),
                    null,
                  ),
                ),
              ),
            ),
          ),
        );
        widget.logger.d('📋 DailyForm: [$fieldKey] QuillEditor built OK');
      } catch (e, st) {
        widget.logger.e('❌ DailyForm: [$fieldKey] QuillEditor FAILED', error: e, stackTrace: st);
        editorWidget = Container(
          constraints: BoxConstraints(minHeight: minH),
          color: AppColors.dangerTint,
          padding: EdgeInsets.all(editorPad),
          child: Text(
            '⚠ ${context.l10n.rfSectionError}',
            style: TextStyle(
                color: AppColors.danger, fontSize: 11),
          ),
        );
      }

      return Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: _fieldBorder, width: 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                  horizontal: titlePH, vertical: titlePV),
              decoration: BoxDecoration(
                color: _navy,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(radius),
                  topRight: Radius.circular(radius),
                ),
              ),
              child: Text(title,
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: titleFs,
                      letterSpacing: 0.8)),
            ),
            if (!_isReadOnly) Container(
              decoration: BoxDecoration(
                color: _sectionBg,
                border: Border(
                    bottom: BorderSide(color: _fieldBorder, width: 0.5)),
              ),
              child: toolbarWidget,
            ),
            editorWidget,
          ],
        ),
      );
    } catch (e, st) {
      widget.logger.e('❌ DailyForm: [$fieldKey] section container FAILED', error: e, stackTrace: st);
      return Container(
        padding: EdgeInsets.all(aw * 0.04),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.red, width: 1.5),
          borderRadius: BorderRadius.circular(aw * 0.022),
          color: AppColors.dangerTint,
        ),
        child: Text(
          '⚠ ${context.l10n.rfSectionError}',
          style: TextStyle(color: AppColors.danger, fontSize: 11),
        ),
      );
    }
  }

  // ── Sub-contractor section (multi-select) ─────────────────────
  Widget _buildSubContractorSection(double aw) {
    widget.logger.d(
        '📋 DailyForm: _buildSubContractorSection → aw=$aw  '
        'names=${_subcontractorNames.length}  '
        'selected=${_selectedSubContractors.length}');

    final double titleFs  = (aw * 0.030).clamp(10.0, 14.0);
    final double valueFs  = (aw * 0.032).clamp(11.0, 14.0);
    final double labelFs  = (aw * 0.026).clamp(9.5, 12.0);
    final double radius   = aw * 0.022;
    final double padH     = aw * 0.035;
    final double padV     = aw * 0.025;

    // Names still available to select (not yet chosen)
    final available = _subcontractorNames
        .where((n) => !_selectedSubContractors.contains(n))
        .toList();

    // Whether the dropdown should even show
    final bool canAddMore = !_isReadOnly && available.isNotEmpty;

    // ── Pre-build selected rows to avoid DDC web spread crash ──
    // Flutter Web (DDC) cannot reliably spread List.generate(...)
    // inline inside a children:[...] array; building the list
    // eagerly beforehand is the safe cross-platform pattern.
    final List<Widget> selectedRows = <Widget>[];
    for (int i = 0; i < _selectedSubContractors.length; i++) {
      final String name = _selectedSubContractors[i];
      final int    idx  = i; // capture for closure
      selectedRows.add(
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(aw * 0.014),
            border: Border.all(color: _fieldBorder, width: 0.8),
          ),
          child: Row(
            children: [
              // Index badge
              Container(
                width: 32,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.only(
                    topLeft:     Radius.circular(aw * 0.014),
                    bottomLeft:  Radius.circular(aw * 0.014),
                  ),
                ),
                child: Text(
                  '${idx + 1}',
                  style: TextStyle(
                      fontSize: labelFs,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandInk),
                ),
              ),
              const SizedBox(width: 10),
              // Name
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                      fontSize: valueFs,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink),
                ),
              ),
              // Remove button — edit mode only
              if (!_isReadOnly)
                IconButton(
                  onPressed: () {
                    widget.logger.i(
                        '📋 DailyForm: subContractor removed → "$name"');
                    setState(() => _selectedSubContractors.removeAt(idx));
                    _saveDraftToCache();
                  },
                  icon: const Icon(
                      Icons.remove_circle_outline_rounded, size: 18),
                  color: Colors.red[400],
                  tooltip: context.l10n.remove,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _fieldBorder, width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Navy header bar ─────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
            decoration: BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(radius),
                topRight: Radius.circular(radius),
              ),
            ),
            child: Row(
              children: [
                Text(context.l10n.rfSubContractorCaps,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: titleFs,
                        letterSpacing: 0.8)),
                const Spacer(),
                if (_selectedSubContractors.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      context.l10n.selectedCount(_selectedSubContractors.length),
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: titleFs * 0.82,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
            ),
          ),

          Padding(
            padding: EdgeInsets.fromLTRB(padH, padV, padH, padV),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── No sub-contractors on this project at all ──
                if (_subcontractorNames.isEmpty)
                  Text(
                    context.l10n.noSubcontractorsOnProject,
                    style: TextStyle(
                        color: Colors.grey[500], fontSize: valueFs),
                  )
                else ...[

                  // ── Dropdown — edit mode, un-selected names only ──
                  if (canAddMore) ...[
                    Text(
                      context.l10n.rfAddSubContractorCaps,
                      style: TextStyle(
                          fontSize: labelFs,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandInk.withValues(alpha: 0.7),
                          letterSpacing: 0.4),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      // key forces rebuild → hint reappears after each pick
                      key: ValueKey(_selectedSubContractors.length),
                      initialValue: null,
                      hint: Text(context.l10n.selectSubContractor,
                          style: TextStyle(
                              color: Colors.grey[400], fontSize: valueFs)),
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: aw * 0.030,
                            vertical: aw * 0.025),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(aw * 0.018),
                          borderSide:
                              BorderSide(color: _fieldBorder, width: 1),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(aw * 0.018),
                          borderSide:
                              BorderSide(color: _fieldBorder, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(aw * 0.018),
                          borderSide:
                              const BorderSide(color: _navy, width: 1.5),
                        ),
                      ),
                      style: TextStyle(
                          fontSize: valueFs, color: AppColors.ink),
                      items: available
                          .map((n) => DropdownMenuItem(
                              value: n,
                              child: Text(n,
                                  style: TextStyle(
                                      fontSize: valueFs))))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        widget.logger.i(
                            '📋 DailyForm: subContractor added → "$v"');
                        setState(() => _selectedSubContractors.add(v));
                        _saveDraftToCache();
                      },
                    ),
                    if (_selectedSubContractors.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: padV * 0.8),
                        child: Divider(
                            color: _fieldBorder,
                            thickness: 0.8,
                            height: 1),
                      ),
                  ],

                  // ── Selected list (uses pre-built rows) ────────
                  if (_selectedSubContractors.isNotEmpty) ...[
                    if (!canAddMore && !_isReadOnly)
                      Padding(
                        padding: EdgeInsets.only(bottom: padV * 0.6),
                        child: Text(
                          context.l10n.allSubcontractorsSelected,
                          style: TextStyle(
                              color: AppColors.success,
                              fontSize: labelFs,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    if (!_isReadOnly || _selectedSubContractors.isNotEmpty)
                      Text(
                        _isReadOnly
                            ? context.l10n.rfSubContractorsCaps
                            : context.l10n.rfSelectedSubContractorsCaps,
                        style: TextStyle(
                            fontSize: labelFs,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brandInk.withValues(alpha: 0.7),
                            letterSpacing: 0.4),
                      ),
                    const SizedBox(height: 8),
                    // Rows were pre-built above — safe on Flutter Web
                    ...selectedRows,
                  ],

                  // ── Empty state (edit mode, nothing selected) ──
                  if (_selectedSubContractors.isEmpty && !_isReadOnly)
                    Padding(
                      padding: EdgeInsets.only(top: padV * 0.5),
                      child: Text(
                        context.l10n.noSubcontractorSelected,
                        style: TextStyle(
                            color: Colors.grey[400], fontSize: valueFs),
                      ),
                    ),

                  // ── Read-only empty state ──────────────────────
                  if (_selectedSubContractors.isEmpty && _isReadOnly)
                    Text(
                      '—',
                      style: TextStyle(
                          color: Colors.grey[400], fontSize: valueFs),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Image attachments section ─────────────────────────────────
  Widget _buildImageSection(double aw) {
    final allImages = [
      ..._localImages.map((b) => _ImageItem(bytes: b)),
      ..._savedImageUrls.map((u) => _ImageItem(url: u)),
    ];
    widget.logger.d('📋 DailyForm: _buildImageSection → aw=$aw  local=${_localImages.length}  saved=${_savedImageUrls.length}');

    final double titleFs = (aw * 0.030).clamp(10.0, 14.0);
    final double radius  = aw * 0.022;
    final double padH    = aw * 0.035;
    final double padV    = aw * 0.025;

    // Thumbnail width: 2 columns with 8px gap
    final double thumbW = ((aw - padH * 2 - 8) / 2).clamp(100.0, 300.0);
    final double thumbH = thumbW * 0.70; // 10:7 ratio

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _fieldBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header bar ───────────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
            decoration: BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(radius),
                topRight: Radius.circular(radius),
              ),
            ),
            child: Row(children: [
              const Icon(Icons.photo_library_rounded,
                  color: Colors.white70, size: 16),
              const SizedBox(width: 8),
              Text(context.l10n.rfAttachedImagesCaps,
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: titleFs,
                      letterSpacing: 0.8)),
              const Spacer(),
              if (allImages.isNotEmpty)
                Text(context.l10n.imagesCount(allImages.length),
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: titleFs * 0.85)),
            ]),
          ),

          Padding(
            padding: EdgeInsets.all(padH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (allImages.isNotEmpty) ...[
                  // ── 2-column image grid ─────────────────────
                  if (allImages.length == 1) ...[
                    // Single image: centred, wider display
                    Center(
                      child: GestureDetector(
                        onTap: () => _showImageViewer(allImages, 0),
                        child: Stack(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(radius * 0.6),
                            child: allImages[0].bytes != null
                                ? Image.memory(allImages[0].bytes!,
                                    width: thumbW * 1.5,
                                    height: thumbH * 1.5,
                                    fit: BoxFit.cover)
                                : Image.network(allImages[0].url!,
                                    width: thumbW * 1.5,
                                    height: thumbH * 1.5,
                                    fit: BoxFit.cover),
                          ),
                          // Expand hint
                          Positioned(
                            bottom: 6, right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                  color: Colors.black45,
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.zoom_out_map_rounded,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                          if (!_isReadOnly)
                            Positioned(
                              top: 4, right: 4,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (_localImages.isNotEmpty) {
                                      _localImages.removeAt(0);
                                    } else {
                                      _savedImageUrls.removeAt(0);
                                    }
                                  });
                                },
                                child: Container(
                                  decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle),
                                  padding: const EdgeInsets.all(3),
                                  child: const Icon(Icons.close,
                                      size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                        ]),
                      ),
                    ),
                  ] else ...[
                    // Multiple images: 2-column wrap grid
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(allImages.length, (i) {
                        final item = allImages[i];
                        widget.logger.d('📋 DailyForm: image[$i] ${item.bytes != null ? "local" : "url"}');
                        return GestureDetector(
                          onTap: () => _showImageViewer(allImages, i),
                          child: Stack(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(radius * 0.6),
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
                            // Expand hint
                            Positioned(
                              bottom: 4, right: _isReadOnly ? 4 : 24,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                    color: Colors.black45,
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.zoom_out_map_rounded,
                                    size: 11, color: Colors.white),
                              ),
                            ),
                            if (!_isReadOnly)
                              Positioned(
                                top: 4, right: 4,
                                child: GestureDetector(
                                  onTap: () {
                                    widget.logger.i('📋 DailyForm: removing image[$i]');
                                    setState(() {
                                      if (i < _localImages.length) {
                                        _localImages.removeAt(i);
                                      } else {
                                        _savedImageUrls.removeAt(
                                            i - _localImages.length);
                                      }
                                    });
                                  },
                                  child: Container(
                                    decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle),
                                    padding: const EdgeInsets.all(3),
                                    child: const Icon(Icons.close,
                                        size: 12, color: Colors.white),
                                  ),
                                ),
                              ),
                          ]),
                        );
                      }),
                    ),
                  ],
                  SizedBox(height: aw * 0.025),
                ],
                if (!_isReadOnly)
                  OutlinedButton.icon(
                    onPressed: () {
                      widget.logger.d('📋 DailyForm: pick images tapped');
                      _pickImages();
                    },
                    icon: const Icon(
                        Icons.add_photo_alternate_rounded, size: 18),
                    label: Text(
                      allImages.isEmpty ? context.l10n.attachImages : context.l10n.addMoreImages,
                      style: TextStyle(
                          fontSize: (aw * 0.032).clamp(11.0, 14.0)),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brandInk,
                      side: const BorderSide(color: _navy, width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(aw * 0.018)),
                      padding: EdgeInsets.symmetric(
                          horizontal: aw * 0.045, vertical: aw * 0.030),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Action buttons — fixed size, capped width on wide screens ───
  Widget _buildActionButtons(double aw) {
    widget.logger.d('📋 DailyForm: _buildActionButtons → aw=$aw');

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
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white)))
                : Icon(icon, size: 16),
            label: Text(
              label,
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              disabledBackgroundColor: color.withValues(alpha: 0.5),
              disabledForegroundColor: Colors.white70,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
              padding:
                  const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              elevation: 2,
            ),
          ),
        ),
      );
    }

    return _isReadOnly
        ? Row(children: [
            btn(
              label: context.l10n.downloadPdf,
              icon: Icons.picture_as_pdf_rounded,
              color: const Color(0xFF1B5E20),
              isLoading: _isGeneratingPdf,
              onTap: () {
                widget.logger.i('📋 DailyForm: Download PDF tapped (readOnly)');
                _downloadAsPdf();
              },
            ),
          ])
        : Row(children: [
      btn(
        label: context.l10n.saveReport,
        icon: Icons.save_rounded,
        color: _navy,
        isLoading: _isSaving,
        onTap: () {
          widget.logger.i('📋 DailyForm: Save Report tapped');
          _saveReport();
        },
      ),
      const SizedBox(width: 10),
      btn(
        label: context.l10n.downloadPdf,
        icon: Icons.picture_as_pdf_rounded,
        color: const Color(0xFF1B5E20),
        isLoading: _isGeneratingPdf,
        onTap: () {
          widget.logger.i('📋 DailyForm: Download PDF tapped');
          _downloadAsPdf();
        },
      ),
      const SizedBox(width: 10),
      btn(
        label: context.l10n.newFormPlus,
        icon: Icons.add_circle_outline_rounded,
        color: const Color(0xFF6A1B9A),
        isLoading: false,
        onTap: () {
          widget.logger.i('📋 DailyForm: New Form tapped');
          _addNewForm();
        },
      ),
    ]);
  }

  @override
  void dispose() {
    widget.logger.i('📋 DailyForm: dispose()');
    _contractController.dispose();
    _buildingController.dispose();
    _scrollController.dispose();
    _visitorsCtrl.dispose();
    _personnelCtrl.dispose();
    _activitiesCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }
}

// ══════════════════════════════════════════════════════════════════
//  SMALL HELPERS
// ══════════════════════════════════════════════════════════════════

class _ImageItem {
  final Uint8List? bytes;
  final String? url;
  _ImageItem({this.bytes, this.url});
}

// ══════════════════════════════════════════════════════════════════
//  FULL-SCREEN IMAGE VIEWER DIALOG
// ══════════════════════════════════════════════════════════════════

class _ImageViewerDialog extends StatefulWidget {
  final List<_ImageItem> images;
  final int initialIndex;
  const _ImageViewerDialog(
      {required this.images, required this.initialIndex});

  @override
  State<_ImageViewerDialog> createState() => _ImageViewerDialogState();
}

class _ImageViewerDialogState extends State<_ImageViewerDialog> {
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
          // ── Full-screen paged viewer ─────────────────────────
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

          // ── Close button ─────────────────────────────────────
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

          // ── Image counter ────────────────────────────────────
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

          // ── Prev arrow ───────────────────────────────────────
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

          // ── Next arrow ───────────────────────────────────────
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

/// Display name for a stored weather value ('Calm & Warm', 'Rainy', …).
String weatherLabel(String weather) {
  final l = l10nNow;
  return switch (weather) {
    'Calm & Warm' => l.wxCalmWarm,
    'Chilly & Cold' => l.wxChillyCold,
    'Hot' => l.wxHot,
    'Windy' => l.wxWindy,
    'Rainy' => l.wxRainy,
    _ => weather,
  };
}
