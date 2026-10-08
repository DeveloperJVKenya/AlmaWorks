import 'package:almaworks/core/theme/app_theme.dart';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:almaworks/models/project_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
// ACTIVITY ROW MODEL
// ══════════════════════════════════════════════════════════════════
class ActivityRow {
  String activity;
  String progress;
  String comment;
  ActivityRow({
    this.activity = '',
    this.progress = '',
    this.comment = '',
  });
  Map<String, dynamic> toMap() => {
        'activity': activity,
        'progress': progress,
        'comment': comment,
      };
  factory ActivityRow.fromMap(Map<String, dynamic> m) => ActivityRow(
        activity: m['activity'] ?? '',
        progress: m['progress'] ?? '',
        comment: m['comment'] ?? '',
      );
}
// ══════════════════════════════════════════════════════════════════
// DATA MODEL
// ══════════════════════════════════════════════════════════════════
class WeeklyReportData {
  final String id;
  final String projectId;
  final String projectName;
  String contractNumber;
  DateTime weekStart;
  DateTime weekEnd;
  List<String> subContractors;
  String building;
  // Activities template — SLOPED ROOF only
  List<ActivityRow> slopedRoofRows;
  // Notes and percentage
  String notes;
  double percentageDone;
  List<String> imageUrls;
  List<Uint8List> localImages;
  bool isDraft;
  DateTime? savedAt;
  WeeklyReportData({
    required this.id,
    required this.projectId,
    required this.projectName,
    this.contractNumber = '',
    required this.weekStart,
    required this.weekEnd,
    this.subContractors = const [],
    this.building = '',
    List<ActivityRow>? slopedRoofRows,
    this.notes = '',
    this.percentageDone = 0,
    this.imageUrls = const [],
    this.localImages = const [],
    this.isDraft = true,
    this.savedAt,
  }) : slopedRoofRows = slopedRoofRows ?? _defaultRows();
  static List<ActivityRow> _defaultRows() =>
      List.generate(5, (_) => ActivityRow());
  Map<String, dynamic> toMap() => {
        'id': id,
        'projectId': projectId,
        'projectName': projectName,
        'contractNumber': contractNumber,
        'weekStart': Timestamp.fromDate(weekStart),
        'weekEnd': Timestamp.fromDate(weekEnd),
        'subContractors': subContractors,
        'building': building,
        'slopedRoofRows': slopedRoofRows.map((r) => r.toMap()).toList(),
        'notes': notes,
        'percentageDone': percentageDone,
        'imageUrls': imageUrls,
        'isDraft': isDraft,
        'savedAt': Timestamp.now(),
        'type': 'Weekly',
      };
  factory WeeklyReportData.fromMap(Map<String, dynamic> m) {
    List<ActivityRow> parseRows(dynamic raw) {
      if (raw == null) return WeeklyReportData._defaultRows();
      return (raw as List<dynamic>)
          .map((e) => ActivityRow.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    final ws = (m['weekStart'] as Timestamp).toDate();
    final we = (m['weekEnd'] as Timestamp).toDate();
    return WeeklyReportData(
      id: m['id'] ?? '',
      projectId: m['projectId'] ?? '',
      projectName: m['projectName'] ?? '',
      contractNumber: m['contractNumber'] ?? '',
      weekStart: ws,
      weekEnd: we,
      subContractors: m['subContractors'] != null
          ? List<String>.from(m['subContractors'])
          // Backward-compat: old docs stored a single string in 'subContractor'
          : (m['subContractor'] != null &&
                  (m['subContractor'] as String).isNotEmpty
              ? [m['subContractor'] as String]
              : []),
      building: m['building'] ?? '',
      slopedRoofRows: parseRows(m['slopedRoofRows']),
      notes: m['notes'] ?? '',
      percentageDone: (m['percentageDone'] as num?)?.toDouble() ?? 0.0,
      imageUrls: List<String>.from(m['imageUrls'] ?? []),
      isDraft: m['isDraft'] ?? true,
    );
  }
}
// ══════════════════════════════════════════════════════════════════
// SCREEN
// ══════════════════════════════════════════════════════════════════
class WeeklyReportFormScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final WeeklyReportData? existingReport;
  /// When true all fields are read-only; a floating Edit button unlocks them.
  final bool isReadOnly;
  /// When true the Edit FAB is permanently hidden regardless of [isReadOnly].
  /// Set this for client users who are allowed to view but never modify reports.
  final bool isClientView;
  const WeeklyReportFormScreen({
    super.key,
    required this.project,
    required this.logger,
    this.existingReport,
    this.isReadOnly = false,
    this.isClientView = false,
  });
  @override
  State<WeeklyReportFormScreen> createState() => _WeeklyReportFormScreenState();
}
class _WeeklyReportFormScreenState extends State<WeeklyReportFormScreen> {
  // ── form key ──────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _contractCtrl = TextEditingController();
  final _buildingCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _percentageCtrl = TextEditingController(text: '0');
  final _scrollCtrl = ScrollController();
  // ── read-only mode ────────────────────────────────────────────
  bool _isReadOnly = false;
  // ── state ─────────────────────────────────────────────────────
  late String _reportId;
  // Week range — default to current Mon–Sun
  late DateTime _weekStart;
  late DateTime _weekEnd;
  final List<String> _selectedSubContractors = [];
  List<String> _subcontractorNames = [];
  // Activity table rows — 5 default rows, user can add more
  late List<ActivityRow> _slopedRows;
  final List<Uint8List> _localImages = [];
  final List<String> _savedImageUrls = [];
  bool _isSaving = false;
  bool _isGeneratingPdf = false;
  // ── design constants ─────────────────────────────────────────
  static const _navy = Color(0xFF0A2E5A);
  static const _fieldBorder = Color(0xFFB0BEC5);
  // ── cache key ─────────────────────────────────────────────────
  String get _cacheKey =>
      'weekly_report_draft_${widget.project.id}_$_reportId';
  // ─────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    widget.logger.i('📋 WeeklyForm: initState START project=${widget.project.name}');
    _reportId = widget.existingReport?.id ?? const Uuid().v4();
    _isReadOnly = widget.isReadOnly;
    _extractSubcontractors();
    // Default week: most recent Monday → Sunday
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    _weekStart = DateTime(monday.year, monday.month, monday.day);
    _weekEnd = _weekStart.add(const Duration(days: 6));
    if (widget.existingReport != null) {
      _loadFromExisting(widget.existingReport!);
    } else {
      _slopedRows = WeeklyReportData._defaultRows();
      _loadDraftFromCache();
    }
    widget.logger.i('📋 WeeklyForm: initState END reportId=$_reportId');
  }
  void _extractSubcontractors() {
    _subcontractorNames = widget.project.teamMembers
        .where((m) => m.role.toLowerCase() == 'subcontractor')
        .map((m) => m.name)
        .toList();
    widget.logger.d('📋 WeeklyForm: subcontractors → $_subcontractorNames');
  }
  void _loadFromExisting(WeeklyReportData r) {
    _contractCtrl.text = r.contractNumber;
    _buildingCtrl.text = r.building;
    _notesCtrl.text = r.notes;
    _percentageCtrl.text = r.percentageDone.toStringAsFixed(0);
    _weekStart = r.weekStart;
    _weekEnd = r.weekEnd;
    _selectedSubContractors
      ..clear()
      ..addAll(r.subContractors);
    _savedImageUrls.addAll(r.imageUrls);
    _slopedRows = r.slopedRoofRows;
    widget.logger.i('📋 WeeklyForm: loaded from existing report');
  }
  @override
  void dispose() {
    widget.logger.i('📋 WeeklyForm: dispose');
    _contractCtrl.dispose();
    _buildingCtrl.dispose();
    _notesCtrl.dispose();
    _percentageCtrl.dispose();
    _scrollCtrl.dispose();
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
        'weekStart': _weekStart.toIso8601String(),
        'weekEnd': _weekEnd.toIso8601String(),
        'subContractors': _selectedSubContractors,
        'slopedRoofRows': _slopedRows.map((r) => r.toMap()).toList(),
        'notes': _notesCtrl.text,
        'percentage': _percentageCtrl.text,
        'imageUrls': _savedImageUrls,
      };
      await prefs.setString(_cacheKey, jsonEncode(data));
      widget.logger.d('📋 WeeklyForm: draft cached');
    } catch (e) {
      widget.logger.w('⚠️ WeeklyForm: cache save failed – $e');
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
        _notesCtrl.text = data['notes'] ?? '';
        _percentageCtrl.text = data['percentage'] ?? '0';
        if (data['weekStart'] != null) {
          _weekStart = DateTime.parse(data['weekStart']);
        }
        if (data['weekEnd'] != null) {
          _weekEnd = DateTime.parse(data['weekEnd']);
        }
        // Restore list — supports both old single-string and new list format
        _selectedSubContractors.clear();
        if (data['subContractors'] != null) {
          _selectedSubContractors
              .addAll(List<String>.from(data['subContractors']));
        } else if (data['subContractor'] != null &&
            (data['subContractor'] as String).isNotEmpty) {
          _selectedSubContractors.add(data['subContractor'] as String);
        }
        _savedImageUrls.clear();
        _savedImageUrls.addAll(List<String>.from(data['imageUrls'] ?? []));
        // Restore table rows
        if (data['slopedRoofRows'] != null) {
          _slopedRows = (data['slopedRoofRows'] as List)
              .map((e) => ActivityRow.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList();
        }
      });
      widget.logger.i('📋 WeeklyForm: draft restored from cache');
    } catch (e, st) {
      widget.logger.e('❌ WeeklyForm: cache load failed', error: e, stackTrace: st);
    }
  }
  Future<void> _clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }
  // ─────────────────────────────────────────────────────────────
  // TABLE ROW MANAGEMENT (called from _WeeklyActivityTableWidget)
  // ─────────────────────────────────────────────────────────────
  void _onSlopedRowsChanged(List<ActivityRow> updated) {
    _slopedRows = updated;
    _saveDraftToCache();
  }
  // ─────────────────────────────────────────────────────────────
  // PICKERS
  // ─────────────────────────────────────────────────────────────
  Future<void> _pickWeekStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _weekStart,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: pickerColorScheme(
              primary: _navy, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _weekStart = picked;
      // Auto-set end to 6 days later if it's before start
      if (_weekEnd.isBefore(_weekStart)) {
        _weekEnd = _weekStart.add(const Duration(days: 6));
      }
    });
    _saveDraftToCache();
  }
  Future<void> _pickWeekEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _weekEnd.isBefore(_weekStart)
          ? _weekStart.add(const Duration(days: 6))
          : _weekEnd,
      firstDate: _weekStart,
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: pickerColorScheme(
              primary: _navy, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _weekEnd = picked);
    _saveDraftToCache();
  }
  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: TextStyle()),
      backgroundColor: Colors.red[700],
    ));
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
    widget.logger.i('📋 WeeklyForm: ${picked.length} image(s) added');
  }

  // ── Full-screen image viewer ──────────────────────────────────
  void _showImageViewer(List<_WImageItem> images, int initialIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => _WImageViewerDialog(
        images: images,
        initialIndex: initialIndex,
      ),
    );
  }
  // ─────────────────────────────────────────────────────────────
  // SAVE
  // ─────────────────────────────────────────────────────────────
  Future<WeeklyReportData> _buildReportData() async {
    // Upload local images
    final List<String> allUrls = List.from(_savedImageUrls);
    for (int i = 0; i < _localImages.length; i++) {
      final ref = FirebaseStorage.instance
          .ref()
          .child(widget.project.id)
          .child('Reports')
          .child('Weekly')
          .child('images')
          .child('${_reportId}_img_$i.jpg');
      await ref.putData(
          _localImages[i], SettableMetadata(contentType: 'image/jpeg'));
      allUrls.add(await ref.getDownloadURL());
    }
    return WeeklyReportData(
      id: _reportId,
      projectId: widget.project.id,
      projectName: widget.project.name,
      contractNumber: _contractCtrl.text.trim(),
      weekStart: _weekStart,
      weekEnd: _weekEnd,
      subContractors: List<String>.from(_selectedSubContractors),
      building: _buildingCtrl.text.trim(),
      slopedRoofRows: _slopedRows,
      notes: _notesCtrl.text.trim(),
      percentageDone: double.tryParse(_percentageCtrl.text) ?? 0,
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
            l10nNow.reportTitleDated(l10nNow.rptWeeklyReport, '${DateFormat.yMMMd().format(_weekStart)} → ${DateFormat.yMMMd().format(_weekEnd)}');
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
      _localImages.clear();
      widget.logger.i('✅ WeeklyForm: report saved id=$_reportId');
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.weeklyReportSaved,
              style: TextStyle()),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e, st) {
      widget.logger.e('❌ WeeklyForm: save failed', error: e, stackTrace: st);
      if (mounted) _showError(friendlyError(e, action: context.l10n.couldNotSaveReport));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
  // ─────────────────────────────────────────────────────────────
  // PDF GENERATION
  // ─────────────────────────────────────────────────────────────
  // Build a PDF table for the SLOPED ROOF section using pw.Table for proper cell borders
  pw.Widget _buildPdfTable(
    String label,
    List<ActivityRow> rows,
    pw.TextStyle headerStyle,
    pw.TextStyle cellStyle,
    PdfColor navyColor,
    PdfColor lightBlue,
  ) {
    final hasData = rows.any((r) =>
        r.activity.isNotEmpty ||
        r.progress.isNotEmpty ||
        r.comment.isNotEmpty);

    final tableRows = <pw.TableRow>[];

    // Header row
    tableRows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: navyColor),
      children: [l10nNow.colNumber, l10nNow.colActivity, l10nNow.colProgress, l10nNow.colComment].map((h) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Text(h, style: headerStyle),
        ),
      ).toList(),
    ));

    if (hasData) {
      for (int i = 0; i < rows.length; i++) {
        final r = rows[i];
        final bg = i.isEven ? PdfColors.white : PdfColor.fromHex('#F5F7FA');
        tableRows.add(pw.TableRow(
          decoration: pw.BoxDecoration(color: bg),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: pw.Text('${i + 1}', style: cellStyle),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: pw.Text(r.activity, style: cellStyle),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: pw.Text(r.progress, style: cellStyle),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: pw.Text(r.comment, style: cellStyle),
            ),
          ],
        ));
      }
    } else {
      // Empty form — blank rows sized for hand-writing after printing
      for (int i = 0; i < rows.length; i++) {
        final bg = i.isEven ? PdfColors.white : PdfColor.fromHex('#F5F7FA');
        tableRows.add(pw.TableRow(
          decoration: pw.BoxDecoration(color: bg),
          children: List.generate(4, (_) => pw.SizedBox(height: 26)),
        ));
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Sub-section label
        pw.Container(
          width: double.infinity,
          color: lightBlue,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              font: pw.Font.helveticaBold(),
              fontSize: 8.5,
              color: PdfColor.fromHex('#0A2E5A'),
              letterSpacing: 0.3,
            ),
          ),
        ),
        pw.Table(
          border: pw.TableBorder.all(
            color: PdfColors.blueGrey300,
            width: 0.5,
          ),
          columnWidths: {
            0: const pw.FixedColumnWidth(32),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(4),
          },
          children: tableRows,
        ),
      ],
    );
  }
  Future<void> _savePdfBytes(Uint8List bytes, String fileName) async {
    widget.logger.i(
        '📋 WeeklyForm: _savePdfBytes platform=${kIsWeb ? "web" : defaultTargetPlatform.name}');
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
            final base = idx > 0
                ? parts.sublist(0, idx).join('/')
                : ext.path;
            dirPath = '$base/Download';
          } else {
            dirPath = (await getApplicationDocumentsDirectory()).path;
          }
        }
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        dirPath = (await getApplicationDocumentsDirectory()).path;
      } else {
        final homeDir = Platform.environment['USERPROFILE']
            ?? Platform.environment['HOME'];
        if (homeDir != null && homeDir.isNotEmpty) {
          dirPath = '$homeDir${Platform.pathSeparator}Downloads';
        } else {
          dirPath = (await getApplicationDocumentsDirectory()).path;
        }
      }
      final dir = Directory(dirPath);
      if (!await dir.exists()) await dir.create(recursive: true);
      final filePath = '$dirPath${Platform.pathSeparator}$fileName';
      await File(filePath).writeAsBytes(bytes);
      widget.logger.i('✅ WeeklyForm: PDF saved → $filePath');
      await OpenFile.open(filePath);
      final currentContext = context;
      if (!currentContext.mounted) return;
      ScaffoldMessenger.of(currentContext).showSnackBar(SnackBar(
        content: Text(currentContext.l10n.pdfSavedToDownloads(fileName),
            style: TextStyle()),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ));
    } catch (e, st) {
      widget.logger.e('❌ WeeklyForm: PDF save failed – falling back to share',
          error: e, stackTrace: st);
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    }
  }
  // ── PDF 2-column image grid ───────────────────────────────────
  List<pw.Widget> _buildPdfImageGrid(List<pw.MemoryImage> images) {
    const double pageW  = 539.0;
    const double gap    = 8.0;
    const double colW2  = (pageW - gap) / 2;
    const double colH2  = colW2 * 0.68;
    const double soloW  = pageW * 0.55;
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

  Future<void> _downloadAsPdf() async {
    widget.logger.i('📋 WeeklyForm: _downloadAsPdf START');
    setState(() => _isGeneratingPdf = true);
    try {
      final report = await _buildReportData();
      final fileName =
          'Weekly_Report_${report.projectName.replaceAll(' ', '_')}_'
          '${DateFormat('yyyyMMdd').format(_weekStart)}.pdf';
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
              .getData(10 * 1024 * 1024);
          if (data != null) pdfImages.add(pw.MemoryImage(data));
        } catch (e) {
          widget.logger.w('⚠️ WeeklyForm: could not fetch image for PDF – $url – $e');
        }
      }
      // ── Styles ───────────────────────────────────────────────
      final navyColor = PdfColor.fromHex('#0A2E5A');
      final lightBlue = PdfColor.fromHex('#E8EEF6');
      final sectionHeaderStyle = pw.TextStyle(
        font: pw.Font.helveticaBold(),
        fontSize: 9.5,
        color: PdfColors.white,
        letterSpacing: 0.5,
      );
      final tableHeaderStyle = pw.TextStyle(
        font: pw.Font.helveticaBold(),
        fontSize: 8,
        color: PdfColors.white,
      );
      final cellStyle = pw.TextStyle(
        font: pw.Font.helvetica(),
        fontSize: 8.5,
        color: PdfColors.black,
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
      // ── Helpers ───────────────────────────────────────────────
      pw.Widget sectionBar(String label) => pw.Container(
            width: double.infinity,
            color: navyColor,
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 8, vertical: 5),
            child: pw.Text(label, style: sectionHeaderStyle),
          );
      // Meta cell (week dates, building, etc.)
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
      pw.Widget metaCellBlank(String label) => pw.Expanded(
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
                  pw.SizedBox(height: 20),
                ],
              ),
            ),
          );
      final isFilled = report.building.isNotEmpty ||
          report.slopedRoofRows.any((r) => r.activity.isNotEmpty);
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
                  l10nNow.pdfWeeklyFooter,
                  style: pw.TextStyle(
                      font: pw.Font.helvetica(),
                      fontSize: 7,
                      color: PdfColors.grey600),
                ),
                pw.Text(
                  l10nNow.pdfPageOf(ctx.pageNumber, ctx.pagesCount),
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
                l10nNow.rfWeeklyReportCaps,
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
                l10nNow.contractNoValue(report.contractNumber),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: pw.Font.helvetica(),
                  fontSize: 8.5,
                  color: PdfColor.fromHex('#FFFFFFB3'),
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            // ══ WEEK RANGE + BUILDING META ROW ═══════════════════
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                isFilled
                    ? metaCellFilled(l10nNow.rfWeekStartCaps,
                        DateFormat.yMMMEd().format(report.weekStart))
                    : metaCellBlank(l10nNow.rfWeekStartCaps),
                pw.SizedBox(width: 4),
                isFilled
                    ? metaCellFilled(l10nNow.rfWeekEndCaps,
                        DateFormat.yMMMEd().format(report.weekEnd))
                    : metaCellBlank(l10nNow.rfWeekEndCaps),
                pw.SizedBox(width: 4),
                isFilled
                    ? metaCellFilled(l10nNow.rfBuildingCaps, report.building)
                    : metaCellBlank(l10nNow.rfBuildingCaps),
              ],
            ),
            pw.SizedBox(height: 6),
            // ══ SUB-CONTRACTOR (multi-row) ════════════════════════
            ...[
              sectionBar(l10nNow.rfSubContractorCaps),
              pw.Container(
                width: double.infinity,
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(
                        color: PdfColors.blueGrey300, width: 0.5)),
                child: report.subContractors.isEmpty
                    ? pw.SizedBox(height: 60)
                    : pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: report.subContractors
                            .asMap()
                            .entries
                            .map((entry) {
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
                                    color: PdfColors.blueGrey200,
                                    width: 0.4),
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
                                      color: PdfColor.fromHex('#0A2E5A'),
                                    ),
                                  ),
                                ),
                                pw.Expanded(
                                  child: pw.Text(name,
                                      style: fieldValueStyle),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
              pw.SizedBox(height: 8),
            ],
            // ══ ACTIVITIES TEMPLATE ═══════════════════════════════
            sectionBar(l10nNow.rfActivitiesTemplateCaps),
            pw.SizedBox(height: 4),
            // SLOPED ROOF table
            _buildPdfTable(
              l10nNow.rfSlopedRoofCaps,
              report.slopedRoofRows,
              tableHeaderStyle,
              cellStyle,
              navyColor,
              lightBlue,
            ),
            pw.SizedBox(height: 8),
            // ══ NOTES ════════════════════════════════════════════
            sectionBar(l10nNow.rfNotesCaps),
            pw.Container(
              width: double.infinity,
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: PdfColors.blueGrey300, width: 0.5)),
              padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: report.notes.isEmpty
                  ? pw.SizedBox(height: 60)
                  : pw.Text(report.notes, style: fieldValueStyle),
            ),
            pw.SizedBox(height: 8),
            // ══ PERCENTAGE OF WORK DONE ═══════════════════════════
            pw.Container(
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: PdfColors.blueGrey300, width: 0.5)),
              child: pw.Row(
                children: [
                  pw.Container(
                    color: lightBlue,
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 10),
                    child: pw.Text(
                      l10nNow.rfPercentWorkDoneCaps,
                      style: pw.TextStyle(
                        font: pw.Font.helveticaBold(),
                        fontSize: 8.5,
                        color: navyColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    report.percentageDone > 0
                        ? '${report.percentageDone.toStringAsFixed(0)}%'
                        : '',
                    style: pw.TextStyle(
                      font: pw.Font.helveticaBold(),
                      fontSize: 12,
                      color: navyColor,
                    ),
                  ),
                  pw.Expanded(child: pw.SizedBox()),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            // ══ ATTACHED IMAGES ══════════════════════════════════
            if (pdfImages.isNotEmpty) ...[
              sectionBar(l10nNow.rfAttachedImagesCaps),
              pw.SizedBox(height: 8),
              ..._buildPdfImageGrid(pdfImages),
            ],
          ],
        ),
      );
      final bytes = await pdf.save();
      await _savePdfBytes(Uint8List.fromList(bytes), fileName);
      widget.logger.i('✅ WeeklyForm: PDF done $fileName');
    } catch (e, st) {
      widget.logger.e('❌ WeeklyForm: PDF failed', error: e, stackTrace: st);
      if (mounted) _showError(friendlyError(e, action: context.l10n.couldNotCreatePdf));
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }
  // ─────────────────────────────────────────────────────────────
  // NEW FORM
  // ─────────────────────────────────────────────────────────────
  Future<void> _addNewForm() async {
    await _saveReport(silent: true);
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(context.l10n.newWeeklyReport,
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
            context.l10n.newWeeklyReportBody,
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
    if (confirm != true || !mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => WeeklyReportFormScreen(
          project: widget.project,
          logger: widget.logger,
        ),
      ),
    );
  }
  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      floatingActionButton: _isReadOnly && !widget.isClientView
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _isReadOnly = false),
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.edit_rounded),
              label: Text(context.l10n.edit, style: TextStyle(fontWeight: FontWeight.w600)),
            )
          : null,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '${context.l10n.projectWeeklyReport(widget.project.name)}${_isReadOnly ? context.l10n.viewSuffix : ''}',
          style:
              TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () async {
            await _saveDraftToCache();

            // This uses context.mounted (the exact guard the linter wants for BuildContext after await)
            if (!context.mounted) return;

            Navigator.of(context).pop();
          },
        ),
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
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── HEADER BAND ──────────────────────────────
                  _buildFormHeader(),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: gap),
                        // ── WEEKLY REPORT TITLE ──────────────
                        _buildReportTypeTitle(),
                        const SizedBox(height: gap),
                        // ── WEEK DATE RANGE (2 columns) ──────
                        _buildWeekDateRow(contentW),
                        const SizedBox(height: gap),
                        // ── BUILDING ─────────────────────────
                        _buildBuildingField(),
                        const SizedBox(height: gap),
                        // ── SUB-CONTRACTOR ───────────────────
                        _buildSubContractorSection(contentW),
                        const SizedBox(height: gap),
                        // ── ACTIVITIES TEMPLATE ──────────────
                        _buildActivitiesTemplate(contentW),
                        const SizedBox(height: gap),
                        // ── NOTES ────────────────────────────
                        _buildNotesSection(),
                        const SizedBox(height: gap),
                        // ── PERCENTAGE ───────────────────────
                        _buildPercentageSection(),
                        const SizedBox(height: gap),
                        // ── IMAGES ───────────────────────────
                        _buildImageSection(contentW),
                        const SizedBox(height: 20),
                        // ── ACTION BUTTONS ───────────────────
                        _buildActionButtons(),
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
  // ═══════════════════════════════════════════════════════════════
  // WIDGET BUILDERS
  // ═══════════════════════════════════════════════════════════════
  // ── Form header (full-width navy band) ───────────────────────
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
            style: TextStyle(
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
              Text(context.l10n.contractNoLabel,
                  style: TextStyle(
                      color: Colors.white70, fontSize: 13)),
              SizedBox(
                width: 180,
                child: TextFormField(
                  controller: _contractCtrl,
                  readOnly: _isReadOnly,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: context.l10n.contractNoHint,
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
                  onChanged: _isReadOnly ? null : (_) => _saveDraftToCache(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  // ── "WEEKLY REPORT" centred subtitle ─────────────────────────
  Widget _buildReportTypeTitle() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          context.l10n.rfWeeklyReportCaps,
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
  // ── Week-start / Week-end date pickers (2 equal columns) ─────
  Widget _buildWeekDateRow(double aw) {
    const double labelFs = 10.0;
    const double valueFs = 12.5;
    const double iconSz = 15.0;
    const double cellRad = 6.0;
    Widget dateCell({
      required String label,
      required DateTime date,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: GestureDetector(
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
                horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  Icon(Icons.calendar_today_rounded,
                      color: AppColors.brandInk, size: iconSz),
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
                  DateFormat('EEE, MMM d, yyyy').format(date),
                  style: TextStyle(
                    fontSize: valueFs,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
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
          label: context.l10n.rfWeekStartCaps,
          date: _weekStart,
          onTap: _pickWeekStart),
      const SizedBox(width: 8),
      dateCell(
          label: context.l10n.rfWeekEndCaps,
          date: _weekEnd,
          onTap: _pickWeekEnd),
    ]);
  }
  // ── Building field ────────────────────────────────────────────
  Widget _buildBuildingField() {
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
            child: Text('BUILDING',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandInk,
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
                style: TextStyle(
                    fontSize: 13, color: AppColors.ink),
                decoration: InputDecoration(
                  hintText: context.l10n.buildingHint,
                  hintStyle: TextStyle(
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
  // ── Sub-contractor section (multi-select) ─────────────────────
  Widget _buildSubContractorSection(double aw) {
    const double radius  = 8.0;
    const double valueFs = 13.0;
    const double labelFs = 11.0;

    // Names still available to select (not yet chosen)
    final available = _subcontractorNames
        .where((n) => !_selectedSubContractors.contains(n))
        .toList();

    final bool canAddMore = !_isReadOnly && available.isNotEmpty;

    // ── Pre-build selected rows to avoid DDC web spread crash ──
    final List<Widget> selectedRows = <Widget>[];
    for (int i = 0; i < _selectedSubContractors.length; i++) {
      final String name = _selectedSubContractors[i];
      final int    idx  = i;
      selectedRows.add(
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
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
                  borderRadius: const BorderRadius.only(
                    topLeft:    Radius.circular(6),
                    bottomLeft: Radius.circular(6),
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
                        '📋 WeeklyForm: subContractor removed → "$name"');
                    setState(
                        () => _selectedSubContractors.removeAt(idx));
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
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.only(
                topLeft:  Radius.circular(radius),
                topRight: Radius.circular(radius),
              ),
            ),
            child: Row(
              children: [
                Text(context.l10n.rfSubContractorCaps,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
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
                          fontSize: 10,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── No sub-contractors on this project ─────────
                if (_subcontractorNames.isEmpty)
                  Text(
                    context.l10n.noSubcontractorsOnProject,
                    style: TextStyle(
                        color: Colors.grey[500], fontSize: valueFs),
                  )
                else ...[

                  // ── Dropdown — edit mode, un-selected only ──
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
                      // key forces rebuild so hint reappears after each pick
                      key: ValueKey(_selectedSubContractors.length),
                      initialValue: null,
                      hint: Text(context.l10n.selectSubContractor,
                          style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: valueFs)),
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide:
                              BorderSide(color: _fieldBorder, width: 1),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide:
                              BorderSide(color: _fieldBorder, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(
                              color: _navy, width: 1.5),
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
                            '📋 WeeklyForm: subContractor added → "$v"');
                        setState(
                            () => _selectedSubContractors.add(v));
                        _saveDraftToCache();
                      },
                    ),
                    if (_selectedSubContractors.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(
                            color: _fieldBorder,
                            thickness: 0.8,
                            height: 1),
                      ),
                  ],

                  // ── Selected list (pre-built rows) ─────────
                  if (_selectedSubContractors.isNotEmpty) ...[
                    if (!canAddMore && !_isReadOnly)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          context.l10n.allSubcontractorsSelected,
                          style: TextStyle(
                              color: AppColors.success,
                              fontSize: labelFs,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    if (!_isReadOnly ||
                        _selectedSubContractors.isNotEmpty)
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
                    // Rows pre-built above — safe on Flutter Web
                    ...selectedRows,
                  ],

                  // ── Edit-mode empty state ───────────────────
                  if (_selectedSubContractors.isEmpty && !_isReadOnly)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        context.l10n.noSubcontractorSelected,
                        style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: valueFs),
                      ),
                    ),

                  // ── Read-only empty state ───────────────────
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
  // ── Activities Template (SLOPED ROOF only) ───────────────────
  Widget _buildActivitiesTemplate(double aw) {
    const double radius = 8.0;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _fieldBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title
          _sectionTitleBar(context.l10n.rfActivitiesTemplateCaps, radius),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── SLOPED ROOF ──────────────────────────────
                _buildRoofSubHeader(context.l10n.rfSlopedRoofCaps),
                const SizedBox(height: 8),
                _WeeklyActivityTableWidget(
                  key: const ValueKey('sloped_activity_table'),
                  rows: _slopedRows,
                  readOnly: _isReadOnly,
                  onChanged: _onSlopedRowsChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  // Sub-header chip for the roof section
  Widget _buildRoofSubHeader(String label) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.brandInk,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
  // ── Notes section (max 4–5 lines) ─────────────────────────────
  Widget _buildNotesSection() {
    const double radius = 8.0;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _fieldBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitleBar(context.l10n.rfNotesCaps, radius),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextFormField(
              controller: _notesCtrl,
              readOnly: _isReadOnly,
              maxLines: 5,
              minLines: 3,
              maxLength: 800,
              style:
                  TextStyle(fontSize: 13, color: AppColors.ink),
              decoration: InputDecoration(
                hintText: context.l10n.additionalNotesHint,
                hintStyle: TextStyle(
                    color: Colors.grey[400], fontSize: 12),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: _fieldBorder, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: _fieldBorder, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: _navy, width: 1.5),
                ),
                counterStyle:
                    TextStyle(fontSize: 10, color: Colors.grey),
              ),
              onChanged: _isReadOnly ? null : (_) => _saveDraftToCache(),
            ),
          ),
        ],
      ),
    );
  }
  // ── Percentage of work done ────────────────────────────────────
  Widget _buildPercentageSection() {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _fieldBorder, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Label tab
          Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(6),
                bottomLeft: Radius.circular(6),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              context.l10n.rfPercentWorkDoneCaps,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.brandInk,
                letterSpacing: 0.3,
              ),
            ),
          ),
          // Value input
          SizedBox(
            width: 100,
            child: Center(
              child: TextFormField(
                controller: _percentageCtrl,
                readOnly: _isReadOnly,
                textAlign: TextAlign.center,
                textAlignVertical: TextAlignVertical.center,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,3}\.?\d{0,2}')),
                ],
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandInk,
                ),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: TextStyle(
                      color: Colors.grey[400], fontSize: 20),
                  suffixText: '%',
                  suffixStyle: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandInk,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 14),
                ),
                validator: (v) {
                  final val = double.tryParse(v ?? '');
                  if (val == null) return context.l10n.enterANumber;
                  if (val < 0 || val > 100) return '0–100';
                  return null;
                },
                onChanged: _isReadOnly ? null : (_) => _saveDraftToCache(),
              ),
            ),
          ),
        ],
      ),
    );
  }
  // ── Image attachments ─────────────────────────────────────────
  Widget _buildImageSection(double aw) {
    final allImages = [
      ..._localImages.map((b) => _WImageItem(bytes: b)),
      ..._savedImageUrls.map((u) => _WImageItem(url: u)),
    ];
    const double radius = 8.0;
    final double thumbW = ((aw - 32 - 8) / 2).clamp(100.0, 300.0);
    final double thumbH = thumbW * 0.70;

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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
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
                      fontSize: 12,
                      letterSpacing: 0.8)),
              const Spacer(),
              if (allImages.isNotEmpty)
                Text(context.l10n.imagesCount(allImages.length),
                    style: TextStyle(
                        color: Colors.white70, fontSize: 11)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (allImages.isNotEmpty) ...[
                  if (allImages.length == 1) ...[
                    // Single image: centred, wider
                    Center(
                      child: GestureDetector(
                        onTap: () => _showImageViewer(allImages, 0),
                        child: Stack(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
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
                        return GestureDetector(
                          onTap: () => _showImageViewer(allImages, i),
                          child: Stack(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
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
                                        size: 12, color: Colors.white),
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
                        Icons.add_photo_alternate_rounded, size: 18),
                    label: Text(
                      allImages.isEmpty ? context.l10n.attachImages : context.l10n.addMoreImages,
                      style: TextStyle(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brandInk,
                      side: const BorderSide(color: _navy, width: 1.5),
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
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white)))
                : Icon(icon, size: 16),
            label: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              disabledBackgroundColor: color.withValues(alpha: 0.5),
              disabledForegroundColor: Colors.white70,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
              padding: const EdgeInsets.symmetric(
                  vertical: 0, horizontal: 12),
              elevation: 2,
            ),
          ),
        ),
      );
    }
    return Row(children: [
      if (!_isReadOnly) ...[
      btn(
        label: context.l10n.saveReport,
        icon: Icons.save_rounded,
        color: _navy,
        isLoading: _isSaving,
        onTap: _saveReport,
      ),
      const SizedBox(width: 10),
      ],
      btn(
        label: context.l10n.downloadPdf,
        icon: Icons.picture_as_pdf_rounded,
        color: const Color(0xFF1B5E20),
        isLoading: _isGeneratingPdf,
        onTap: _downloadAsPdf,
      ),
      if (!_isReadOnly) ...[
      const SizedBox(width: 10),
      btn(
        label: context.l10n.newFormPlus,
        icon: Icons.add_circle_outline_rounded,
        color: const Color(0xFF6A1B9A),
        isLoading: false,
        onTap: _addNewForm,
      ),
      ],
    ]);
  }
  // ── Shared section title bar builder ──────────────────────────
  Widget _sectionTitleBar(String title, double radius) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius),
        ),
      ),
      child: Text(
        title,
        style: TextStyle(
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
// WEEKLY ACTIVITY TABLE WIDGET
// Custom multi-line editable table matching monthly report styling.
// Fixed columns: Activity, Progress, Comment (no delete, no add col).
// ══════════════════════════════════════════════════════════════════
class _WeeklyActivityTableWidget extends StatefulWidget {
  final List<ActivityRow> rows;
  final bool readOnly;
  final Function(List<ActivityRow>) onChanged;

  const _WeeklyActivityTableWidget({
    super.key,
    required this.rows,
    required this.readOnly,
    required this.onChanged,
  });

  @override
  State<_WeeklyActivityTableWidget> createState() =>
      _WeeklyActivityTableWidgetState();
}

class _WeeklyActivityTableWidgetState
    extends State<_WeeklyActivityTableWidget> {
  static const _navy = Color(0xFF0A2E5A);
  static const _fieldBorder = Color(0xFFB0BEC5);

  // Mutable column headers (user can rename via Edit Headers dialog)
  final List<String> _headers = [l10nNow.colActivity, l10nNow.colProgress, l10nNow.colComment];
  bool _showRowNumbers = false;

  // Cell controllers indexed [rowIndex][colIndex]
  late List<List<TextEditingController>> _controllers;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  @override
  void didUpdateWidget(_WeeklyActivityTableWidget old) {
    super.didUpdateWidget(old);
    // Re-init if rows were replaced externally (e.g. cache load)
    if (old.rows != widget.rows ||
        old.rows.length != _controllers.length) {
      _disposeControllers();
      _initControllers();
    }
  }

  void _initControllers() {
    _controllers = widget.rows.map((row) => [
          TextEditingController(text: row.activity),
          TextEditingController(text: row.progress),
          TextEditingController(text: row.comment),
        ]).toList();
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

  // ── Sync controllers → data model and notify parent ───────────
  void _notifyChanged() {
    for (int i = 0; i < widget.rows.length && i < _controllers.length; i++) {
      widget.rows[i].activity = _controllers[i][0].text;
      widget.rows[i].progress = _controllers[i][1].text;
      widget.rows[i].comment = _controllers[i][2].text;
    }
    widget.onChanged(widget.rows);
  }

  // ── Add a blank row ────────────────────────────────────────────
  void _addRow() {
    final newRow = ActivityRow();
    widget.rows.add(newRow);
    setState(() {
      _controllers.add([
        TextEditingController(),
        TextEditingController(),
        TextEditingController(),
      ]);
    });
    widget.onChanged(widget.rows);
  }

  // ── Remove last row ────────────────────────────────────────────
  void _removeLastRow() {
    if (widget.rows.isEmpty || widget.rows.length <= 1) return;
    widget.rows.removeLast();
    setState(() {
      final last = _controllers.removeLast();
      for (final c in last) {
        c.dispose();
      }
    });
    widget.onChanged(widget.rows);
  }

  // ── Toggle row-number column ───────────────────────────────────
  void _toggleRowNumbers() {
    setState(() => _showRowNumbers = !_showRowNumbers);
  }

  // ── Edit column headers dialog ─────────────────────────────────
  Future<void> _showEditHeadersDialog() async {
    final ctrls = _headers
        .map((h) => TextEditingController(text: h))
        .toList();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
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
                  const Icon(Icons.drive_file_rename_outline_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Text(context.l10n.editColumnHeaders,
                      style: TextStyle(
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
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brandInk)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: ctrls[i],
                            style: TextStyle(fontSize: 12),
                            autofocus: i == 0,
                            textInputAction: i < ctrls.length - 1
                                ? TextInputAction.next
                                : TextInputAction.done,
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: context.l10n.columnN(i + 1),
                              hintStyle: TextStyle(
                                  color: Colors.grey[400], fontSize: 11),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6)),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(
                                      color: _navy, width: 1.5)),
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
                      child: Text(context.l10n.cancel,
                          style: TextStyle(color: AppColors.brandInk, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: Text(context.l10n.apply,
                          style: TextStyle(
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

    setState(() {
      for (var i = 0; i < _headers.length; i++) {
        final v = ctrls[i].text.trim();
        if (v.isNotEmpty) _headers[i] = v;
      }
    });
    for (final c in ctrls) {
      c.dispose();
    }
  }

  // ── Toolbar action button ──────────────────────────────────────
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
                    : AppColors.border,
                width: 0.8),
          ),
          child: Icon(icon,
              size: 15,
              color: onTap != null ? color : Colors.grey[400]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rowCount = widget.rows.length;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _navy.withValues(alpha: 0.22), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Toolbar ────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: _navy.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(7), topRight: Radius.circular(7)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(children: [
              Icon(Icons.table_chart_rounded, color: AppColors.brandInk, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(context.l10n.activityTable,
                    style: TextStyle(
                        color: AppColors.brandInk, fontWeight: FontWeight.w600, fontSize: 12)),
              ),
              // Row-number toggle
              if (!widget.readOnly)
                Tooltip(
                  message: _showRowNumbers ? context.l10n.hideRowNumbers : context.l10n.showRowNumbers,
                  child: InkWell(
                    onTap: _toggleRowNumbers,
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: _showRowNumbers
                            ? _navy.withValues(alpha: 0.14)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _showRowNumbers
                                ? _navy.withValues(alpha: 0.45)
                                : Colors.grey.withValues(alpha: 0.35),
                            width: 0.9),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.format_list_numbered_rounded,
                            size: 13,
                            color: _showRowNumbers ? _navy : Colors.grey[500]),
                        const SizedBox(width: 3),
                        Text(' # ',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _showRowNumbers ? _navy : Colors.grey[500])),
                      ]),
                    ),
                  ),
                ),
              if (!widget.readOnly) ...[
                const SizedBox(width: 6),
                // Edit Headers button
                Tooltip(
                  message: context.l10n.editColumnHeaders,
                  child: InkWell(
                    onTap: _showEditHeadersDialog,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.35), width: 0.9),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.drive_file_rename_outline_rounded,
                            size: 13, color: AppColors.inkMuted),
                        const SizedBox(width: 3),
                        Text(context.l10n.headersButton,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.inkMuted)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _actionBtn(
                    icon: Icons.add_rounded,
                    tooltip: context.l10n.addRow,
                    color: Colors.green[700]!,
                    onTap: _addRow),
                const SizedBox(width: 4),
                _actionBtn(
                    icon: Icons.remove_rounded,
                    tooltip: context.l10n.removeLastRow,
                    color: Colors.orange[700]!,
                    onTap: rowCount > 1 ? _removeLastRow : null),
              ],
            ]),
          ),

          // ── Hint strip ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: AppColors.surfaceAlt,
            child: Row(children: [
              Icon(Icons.info_outline_rounded, size: 12, color: Colors.grey[450]),
              const SizedBox(width: 4),
              Text(context.l10n.headersTip,
                  style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            ]),
          ),

          // ── Table ───────────────────────────────────────────────
          ClipRRect(
            borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(7),
                bottomRight: Radius.circular(7)),
            child: _buildTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    return LayoutBuilder(builder: (context, constraints) {
      // Define column flex widths
      const double noW = 42.0;
      final availW = constraints.maxWidth;
      // Proportional widths for 3 data columns
      final dataW = _showRowNumbers ? availW - noW : availW;
      final colWidths = [dataW * 0.35, dataW * 0.25, dataW * 0.40];

      return Table(
        border: TableBorder.all(color: _fieldBorder, width: 0.8),
        columnWidths: {
          if (_showRowNumbers) 0: const FixedColumnWidth(42),
          if (_showRowNumbers) 1: FixedColumnWidth(colWidths[0]),
          if (_showRowNumbers) 2: FixedColumnWidth(colWidths[1]),
          if (_showRowNumbers) 3: FixedColumnWidth(colWidths[2]),
          if (!_showRowNumbers) 0: FixedColumnWidth(colWidths[0]),
          if (!_showRowNumbers) 1: FixedColumnWidth(colWidths[1]),
          if (!_showRowNumbers) 2: FixedColumnWidth(colWidths[2]),
        },
        children: [
          // Header row
          TableRow(
            decoration: const BoxDecoration(color: _navy),
            children: [
              if (_showRowNumbers)
                _headerCell('#'),
              ..._headers.map(_headerCell),
            ],
          ),
          // Data rows
          ...widget.rows.asMap().entries.map((entry) {
            final idx = entry.key;
            final bg = idx.isEven ? AppColors.surface : AppColors.surfaceAlt;
            return TableRow(children: [
              if (_showRowNumbers)
                Container(
                  color: bg,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('${idx + 1}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandInk.withValues(alpha: 0.55))),
                ),
              ...List.generate(3, (ci) => _dataCell(idx, ci, bg)),
            ]);
          }),
        ],
      );
    });
  }

  Widget _headerCell(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Text(text,
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 11)),
      );

  Widget _dataCell(int rowIdx, int colIdx, Color bg) {
    if (widget.readOnly) {
      return Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(
          _controllers[rowIdx][colIdx].text,
          style: TextStyle(fontSize: 12, color: AppColors.ink),
          softWrap: true,
        ),
      );
    }
    return Container(
      color: bg,
      child: TextFormField(
        controller: _controllers[rowIdx][colIdx],
        maxLines: null,
        minLines: 1,
        style: TextStyle(fontSize: 12, color: AppColors.ink),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          isDense: true,
        ),
        onChanged: (_) => _notifyChanged(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// HELPERS
// ══════════════════════════════════════════════════════════════════
class _WImageItem {
  final Uint8List? bytes;
  final String? url;
  _WImageItem({this.bytes, this.url});
}

// ══════════════════════════════════════════════════════════════════
//  FULL-SCREEN IMAGE VIEWER DIALOG
// ══════════════════════════════════════════════════════════════════

class _WImageViewerDialog extends StatefulWidget {
  final List<_WImageItem> images;
  final int initialIndex;
  const _WImageViewerDialog(
      {required this.images, required this.initialIndex});

  @override
  State<_WImageViewerDialog> createState() => _WImageViewerDialogState();
}

class _WImageViewerDialogState extends State<_WImageViewerDialog> {
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