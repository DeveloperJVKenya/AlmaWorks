import 'dart:io';
import 'dart:typed_data';
import 'package:almaworks/models/project_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

// ══════════════════════════════════════════════════════════════════
// ENUMS
// ══════════════════════════════════════════════════════════════════

enum TaskRowType { project, category, phase, task }

enum DayStatus { none, done, completed, holiday, badWeather }

extension DayStatusX on DayStatus {
  String get code {
    switch (this) {
      case DayStatus.done:       return '✓';
      case DayStatus.completed:  return '✓';
      case DayStatus.holiday:    return 'H';
      case DayStatus.badWeather: return 'W';
      default:                   return '';
    }
  }

  // Storage codes (single ASCII char, backward-compat)
  String get storageCode {
    switch (this) {
      case DayStatus.done:       return 'D';
      case DayStatus.completed:  return 'X';
      case DayStatus.holiday:    return 'H';
      case DayStatus.badWeather: return 'W';
      default:                   return '';
    }
  }

  String get label {
    switch (this) {
      case DayStatus.done:       return 'Work Done – Ongoing ✓';
      case DayStatus.completed:  return 'Work Done – Completed ✓';
      case DayStatus.holiday:    return 'Holiday (H)';
      case DayStatus.badWeather: return 'Bad Weather (W)';
      default:                   return 'Not Set';
    }
  }

  Color get color {
    switch (this) {
      case DayStatus.done:       return const Color(0xFF2E7D32);
      case DayStatus.completed:  return const Color(0xFF2E7D32);
      case DayStatus.holiday:    return const Color(0xFF6A1B9A);
      case DayStatus.badWeather: return const Color(0xFF00838F);
      default:                   return Colors.grey;
    }
  }

  Color get bgColor {
    switch (this) {
      case DayStatus.done:       return const Color(0xFFE8F5E9);
      case DayStatus.completed:  return const Color(0xFFE8F5E9);
      case DayStatus.holiday:    return const Color(0xFFF3E5F5);
      case DayStatus.badWeather: return const Color(0xFFE0F7FA);
      default:                   return Colors.white;
    }
  }

  bool get countsAsWorked => this == DayStatus.done || this == DayStatus.completed;

  static DayStatus fromCode(String? code) {
    switch (code) {
      // New codes
      case 'D': return DayStatus.done;
      case 'X': return DayStatus.completed;
      case 'H': return DayStatus.holiday;
      case 'W': return DayStatus.badWeather;
      // Legacy migration – treat old started/ongoing/completed as done
      case 'S': return DayStatus.done;
      case 'O': return DayStatus.done;
      case 'C': return DayStatus.done;
      default:  return DayStatus.none;
    }
  }
}

// ══════════════════════════════════════════════════════════════════
// ISOLATE HELPERS (top-level – required by compute())
// ══════════════════════════════════════════════════════════════════

/// Converts an Excel cell to a plain string. Must be top-level for isolate use.
String _cellStrIsolate(Data? cell) {
  if (cell == null || cell.value == null) return '';
  final v = cell.value!;
  if (v is TextCellValue)   return v.value.toString();
  if (v is IntCellValue)    return v.value.toString();
  if (v is DoubleCellValue) return v.value.toStringAsFixed(0);
  if (v is DateCellValue)   return '${v.month}/${v.day}/${v.year}';
  if (v is BoolCellValue)   return v.value.toString();
  return v.toString();
}

/// Counts leading ASCII spaces.
int _countLeadingSpacesIsolate(String s) {
  int n = 0;
  for (final c in s.runes) {
    if (c == 32) {
      n++;
    } else {
      break;
    }
  }
  return n;
}

int _indentLevelIsolate(String rawName) =>
    (_countLeadingSpacesIsolate(rawName) / 3).floor().clamp(0, 5);

String _detectTypeIsolate(String rawName) {
  final spaces  = _countLeadingSpacesIsolate(rawName);
  final trimmed = rawName.trim().toLowerCase();
  if (spaces == 0)            return 'project';
  if (spaces < 6)             return 'category';
  if (trimmed.startsWith('phase')) return 'phase';
  if (spaces < 9)             return 'category';
  return 'task';
}

DateTime? _parseExcelDateIsolate(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  for (final fmt in [
    'EEE M/d/yy', 'EEE M/d/yyyy',
    'M/d/yy', 'M/d/yyyy',
    'd/M/yy', 'd/M/yyyy',
  ]) {
    try { return DateFormat(fmt).parse(t); } catch (_) {}
  }
  return null;
}

/// Parsed row data returned from the isolate.
class _ExcelParseResult {
  final List<Map<String, dynamic>> rows;
  const _ExcelParseResult(this.rows);
}

/// Entry point for compute() – runs in a separate isolate.
_ExcelParseResult _parseExcelInIsolate(Uint8List bytes) {
  final excel     = Excel.decodeBytes(bytes);
  final sheetName = excel.tables.keys.first;
  final sheet     = excel.tables[sheetName]!;

  final results        = <Map<String, dynamic>>[];
  String? currentPhaseId;
  int idx = 0;

  for (int r = 0; r < sheet.rows.length; r++) {
    final row = sheet.rows[r];
    if (row.isEmpty) continue;

    final rawName = _cellStrIsolate(row.elementAtOrNull(0));
    if (rawName.isEmpty) continue;
    if (r == 0 && rawName.trim().toLowerCase() == 'task name') continue;

    final startStr = _cellStrIsolate(row.elementAtOrNull(2));
    final endStr   = _cellStrIsolate(row.elementAtOrNull(3));
    final type     = _detectTypeIsolate(rawName);

    final id = const Uuid().v4();
    if (type == 'phase') currentPhaseId = id;

    final startDate = _parseExcelDateIsolate(startStr);
    final endDate   = _parseExcelDateIsolate(endStr);

    results.add({
      'id'           : id,
      'rowIndex'     : idx++,
      'rawName'      : rawName,
      'startMs'      : startDate?.millisecondsSinceEpoch,
      'endMs'        : endDate?.millisecondsSinceEpoch,
      'type'         : type,
      'parentPhaseId': type == 'task' ? currentPhaseId : null,
      'indentLevel'  : _indentLevelIsolate(rawName),
    });
  }
  return _ExcelParseResult(results);
}

// ══════════════════════════════════════════════════════════════════
// DATA MODEL
// ══════════════════════════════════════════════════════════════════

class TaskProgressRowData {
  String id;
  int rowIndex;
  String taskName;
  DateTime? startDate;
  DateTime? endDate;
  TaskRowType type;
  String? parentPhaseId;
  int indentLevel;

  TaskProgressRowData({
    required this.id,
    required this.rowIndex,
    required this.taskName,
    this.startDate,
    this.endDate,
    required this.type,
    this.parentPhaseId,
    this.indentLevel = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'rowIndex': rowIndex,
        'taskName': taskName,
        'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
        'endDate'  : endDate   != null ? Timestamp.fromDate(endDate!)   : null,
        'type'     : type.name,
        'parentPhaseId': parentPhaseId,
        'indentLevel'  : indentLevel,
      };

  factory TaskProgressRowData.fromMap(Map<String, dynamic> m) =>
      TaskProgressRowData(
        id: m['id'] as String? ?? const Uuid().v4(),
        rowIndex: (m['rowIndex'] as num?)?.toInt() ?? 0,
        taskName: m['taskName'] as String? ?? '',
        startDate: (m['startDate'] as Timestamp?)?.toDate(),
        endDate  : (m['endDate']   as Timestamp?)?.toDate(),
        type: TaskRowType.values.firstWhere(
          (t) => t.name == m['type'],
          orElse: () => TaskRowType.task,
        ),
        parentPhaseId: m['parentPhaseId'] as String?,
        indentLevel  : (m['indentLevel']  as num?)?.toInt() ?? 0,
      );
}

// ══════════════════════════════════════════════════════════════════
// SCREEN
// ══════════════════════════════════════════════════════════════════

class TaskProgressMonitorScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;

  const TaskProgressMonitorScreen({
    super.key,
    required this.project,
    required this.logger,
  });

  @override
  State<TaskProgressMonitorScreen> createState() =>
      _TaskProgressMonitorScreenState();
}

class _TaskProgressMonitorScreenState
    extends State<TaskProgressMonitorScreen> {
  // ── Design constants ────────────────────────────────────────────
  static const _navy       = Color(0xFF0A2E5A);
  static const _navyLight  = Color(0xFF1A3C6A);
  static const _navyMid    = Color(0xFF0D3060);
  static const _fieldBorder = Color(0xFFB0BEC5);
  static const _sectionBg  = Color(0xFFF5F7FA);

  // Week-boundary separator (darker, thicker)
  static const _weekBorderColor = Color(0xFF78909C);
  static const double _weekBorderWidth = 1.8;

  // ── Fixed column widths ─────────────────────────────────────────
  static const double _kNoW   = 38.0;
  static const double _kNameW = 234.0;
  static const double _kDateW = 86.0;
  static const double _kDayW  = 42.0;

  // ── Base row heights (minimum) ──────────────────────────────────
  static const double _kHeaderH    = 84.0;
  static const double _kProjectH   = 46.0;
  static const double _kCategoryH  = 44.0;
  static const double _kPhaseH     = 52.0;
  static const double _kTaskH      = 46.0;

  // ── State ───────────────────────────────────────────────────────
  final List<TaskProgressRowData> _rows = [];
  final Map<String, String> _dailyStatuses = {};
  final Map<String, TextEditingController> _nameCtrlMap = {};

  bool _showRowNumbers = true;
  bool _isSaving    = false;
  bool _isLoading   = true;
  bool _isImporting = false;
  String _importStep    = '';
  double _importProgress = 0.0; // 0.0 – 1.0

  // ── Phase-columns cache (avoid recomputing every build frame) ───
  List<_PhaseColumnData>? _cachedPhaseColumns;

  // ── Name column width (set by LayoutBuilder, used for height calc)
  double _nameColW = _kNameW;

  // ── Scroll controllers ──────────────────────────────────────────
  final _hScrollHeader = ScrollController();
  final _hScrollData   = ScrollController();
  final _vScrollData   = ScrollController();   // vertical data rows scroll
  bool _syncingH = false;

  // ── Smart period auto-scroll ─────────────────────────────────────
  // ID of the last row that drove an auto-scroll so we only animate when
  // the topmost visible row actually changes – not on every scroll pixel.
  String _lastAutoScrollRowId = '';
  // When false the user has manually dragged the period; re-enabled whenever
  // the topmost row changes (i.e. they scroll to a new task/phase).
  bool _periodAutoScroll = true;

  // ── Formatters ──────────────────────────────────────────────────
  final _dfDisplay = DateFormat('d MMM yy');
  final _dfKey     = DateFormat('yyyyMMdd');

  // ─────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _hScrollHeader.addListener(_syncHeaderToData);
    _hScrollData.addListener(_syncDataToHeader);
    // Smart period auto-scroll: re-enable auto-scroll whenever the user
    // moves the period panel manually (they're taking control).
    _hScrollData.addListener(_onHorizontalManualScroll);
    _vScrollData.addListener(_onVerticalScroll);
    _loadFromFirestore();
  }

  @override
  void dispose() {
    _hScrollHeader.removeListener(_syncHeaderToData);
    _hScrollData.removeListener(_syncDataToHeader);
    _hScrollData.removeListener(_onHorizontalManualScroll);
    _vScrollData.removeListener(_onVerticalScroll);
    _hScrollHeader.dispose();
    _hScrollData.dispose();
    _vScrollData.dispose();
    for (final c in _nameCtrlMap.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Scroll sync ─────────────────────────────────────────────────
  void _syncHeaderToData() {
    if (_syncingH) return;
    _syncingH = true;
    if (_hScrollData.hasClients) _hScrollData.jumpTo(_hScrollHeader.offset);
    _syncingH = false;
  }

  void _syncDataToHeader() {
    if (_syncingH) return;
    _syncingH = true;
    if (_hScrollHeader.hasClients) _hScrollHeader.jumpTo(_hScrollData.offset);
    _syncingH = false;
  }

  // ── Smart period auto-scroll ──────────────────────────────────────
  //
  // When the user scrolls vertically to a new row we detect which task /
  // phase is now at the top of the viewport and smoothly slide the period
  // panel so that row's start date appears near the left edge.  The user
  // can still drag the period panel freely at any time; doing so suspends
  // auto-scroll until the next row boundary is crossed.
  // ─────────────────────────────────────────────────────────────────

  /// Called whenever the period panel is scrolled by the *user* (touch /
  /// mouse drag).  We detect this by checking whether the scroll position
  /// is currently being driven by the user (not our own [_smartScrollPeriod]
  /// animation) using the [ScrollPosition.isScrollingNotifier].
  void _onHorizontalManualScroll() {
    if (!_hScrollData.hasClients) return;
    // If the scroll activity is user-initiated (drag), pause auto-scroll.
    // _syncingH writes are never user-initiated so we ignore those.
    if (_syncingH) return;
    final pos = _hScrollData.position;
    // AxisDirection activity from user: velocity is non-zero OR it is being
    // held (drag in progress).  We simply mark auto-scroll as paused here;
    // it re-enables automatically the next time the topmost row changes.
    if (pos.isScrollingNotifier.value) {
      _periodAutoScroll = false;
    }
  }

  /// Main listener on [_vScrollData].  Fires on every vertical scroll pixel
  /// but only acts when the topmost row changes.
  void _onVerticalScroll() {
    if (!_vScrollData.hasClients) return;
    final vOffset = _vScrollData.offset;

    // ── 1. Identify the topmost fully-or-partially-visible row ──────
    final topRow = _topmostRowAtOffset(vOffset);
    if (topRow == null) return;

    // ── 2. Re-enable auto-scroll when we cross a new row boundary ───
    if (topRow.id != _lastAutoScrollRowId) {
      _lastAutoScrollRowId = topRow.id;
      _periodAutoScroll = true;   // crossing a boundary re-arms auto-scroll
    } else {
      // Same row, still scrolling within it – honour the user's manual choice.
      if (!_periodAutoScroll) return;
    }

    // ── 3. Resolve the target date for this row ──────────────────────
    final targetDate = _targetDateForRow(topRow);
    if (targetDate == null) return;

    // ── 4. Compute the horizontal pixel offset for that date ─────────
    final targetH = _hOffsetForDate(targetDate);
    if (targetH == null) return;

    // ── 5. Only animate when we'd actually move a meaningful amount ──
    final currentH = _hScrollData.hasClients ? _hScrollData.offset : 0.0;
    if ((targetH - currentH).abs() < _kDayW) return;

    _smartScrollPeriod(targetH);
  }

  /// Returns the [TaskProgressRowData] whose vertical span contains [vOffset].
  TaskProgressRowData? _topmostRowAtOffset(double vOffset) {
    double accumulated = 0;
    for (final row in _rows) {
      final h = _computeRowH(row, effectiveNameW: _nameColW);
      if (accumulated + h > vOffset) return row;
      accumulated += h;
    }
    return _rows.isNotEmpty ? _rows.last : null;
  }

  /// Returns the best "jump-to" date for [row]:
  ///   • task   → task.startDate (falls back to parent phase start)
  ///   • phase  → phase.startDate
  ///   • category / project → start date of the first phase/task below it
  DateTime? _targetDateForRow(TaskProgressRowData row) {
    switch (row.type) {
      case TaskRowType.task:
        if (row.startDate != null) return row.startDate;
        // Fall back to the parent phase start date.
        if (row.parentPhaseId != null) {
          for (final r in _rows) {
            if (r.id == row.parentPhaseId) return r.startDate;
          }
        }
        return null;

      case TaskRowType.phase:
        return row.startDate;

      case TaskRowType.category:
      case TaskRowType.project:
        // Walk forward from this row to find the first dated phase or task.
        final rowIdx = _rows.indexOf(row);
        for (int i = rowIdx; i < _rows.length; i++) {
          final r = _rows[i];
          if (r.startDate != null &&
              (r.type == TaskRowType.phase || r.type == TaskRowType.task)) {
            return r.startDate;
          }
        }
        return null;
    }
  }

  /// Converts [date] to the corresponding x-offset in the scrollable period
  /// panel (sum of preceding phase widths + day index × [_kDayW]).
  /// Returns the offset of the closest day on or after [date], or `null` if
  /// the date lies outside all phase columns.
  double? _hOffsetForDate(DateTime date) {
    final target = DateTime(date.year, date.month, date.day);
    double offset = 0;
    for (final pc in _phaseColumns) {
      for (int i = 0; i < pc.days.length; i++) {
        if (!pc.days[i].isBefore(target)) {
          // Subtract one day-width so the target column isn't flush against
          // the left edge – showing one day of context before it.
          return (offset + i * _kDayW - _kDayW).clamp(0.0, double.infinity);
        }
      }
      offset += pc.days.length * _kDayW;
    }
    // Date is beyond all columns → scroll to the very end.
    return offset > 0 ? offset : null;
  }

  /// Smoothly scrolls both the period header and data panel to [hOffset].
  /// Uses [animateTo] so the user can interrupt at any time by touching the
  /// scroll view, which Flutter cancels the animation naturally.
  void _smartScrollPeriod(double hOffset) {
    if (!_hScrollData.hasClients) return;
    final maxExtent = _hScrollData.position.maxScrollExtent;
    final clamped   = hOffset.clamp(0.0, maxExtent);

    // Animate both in parallel; the existing _syncDataToHeader listener will
    // keep the sticky header in sync, but we animate it explicitly too for
    // a perfectly smooth result.
    _hScrollData.animateTo(
      clamped,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
    if (_hScrollHeader.hasClients) {
      final maxH = _hScrollHeader.position.maxScrollExtent;
      _hScrollHeader.animateTo(
        clamped.clamp(0.0, maxH),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // ── Phase cache ─────────────────────────────────────────────────
  void _invalidatePhaseCache() {
    _cachedPhaseColumns    = null;
    _lastAutoScrollRowId   = '';   // re-arm auto-scroll after data changes
    _periodAutoScroll      = true;
  }

  List<_PhaseColumnData> get _phaseColumns =>
      _cachedPhaseColumns ??= _buildPhaseColumns();

  List<_PhaseColumnData> _buildPhaseColumns() {
    return _rows
        .where((r) =>
            r.type == TaskRowType.phase &&
            r.startDate != null &&
            r.endDate != null)
        .map((phase) {
          // Find the latest date among all tasks in this phase (may exceed phase.endDate)
          DateTime effectiveEnd = phase.endDate!;
          for (final row in _rows) {
            if (row.type == TaskRowType.task &&
                row.parentPhaseId == phase.id &&
                row.endDate != null &&
                row.endDate!.isAfter(effectiveEnd)) {
              effectiveEnd = row.endDate!;
            }
          }
          // Also check if any done-marks exist past effectiveEnd for any task
          final prefix = RegExp(r'^([^_]+)_(\d{8})$');
          for (final entry in _dailyStatuses.entries) {
            final m = prefix.firstMatch(entry.key);
            if (m == null) continue;
            final taskId  = m.group(1)!;
            final dateStr = m.group(2)!;
            final taskInPhase = _rows.any((r) =>
                r.id == taskId &&
                r.type == TaskRowType.task &&
                r.parentPhaseId == phase.id);
            if (!taskInPhase) continue;
            try {
              final d = DateTime(
                int.parse(dateStr.substring(0, 4)),
                int.parse(dateStr.substring(4, 6)),
                int.parse(dateStr.substring(6, 8)),
              );
              if (d.isAfter(effectiveEnd)) effectiveEnd = d;
            } catch (_) {}
          }

          final days  = _workingDays(phase.startDate!, effectiveEnd);
          final weeks = _groupWeeks(days);
          return _PhaseColumnData(phase: phase, days: days, weeks: weeks);
        })
        .toList();
  }

  // ─────────────────────────────────────────────────────────────────
  // CONTROLLER HELPERS
  // ─────────────────────────────────────────────────────────────────
  TextEditingController _nameCtrl(String id) =>
      _nameCtrlMap.putIfAbsent(id, () => TextEditingController());

  void _syncNameControllers() {
    for (final row in _rows) {
      _nameCtrl(row.id).text = row.taskName;
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // FIRESTORE
  // ─────────────────────────────────────────────────────────────────
  DocumentReference get _docRef => FirebaseFirestore.instance
      .collection('TaskProgressMonitor')
      .doc(widget.project.id);

  Future<void> _loadFromFirestore() async {
    try {
      final snap = await _docRef.get();
      if (!snap.exists) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final data      = snap.data() as Map<String, dynamic>;
      final rawRows   = data['rows'] as List<dynamic>? ?? [];
      final rawStatus = Map<String, dynamic>.from(data['dailyStatuses'] as Map? ?? {});

      if (mounted) {
        setState(() {
          _rows.clear();
          _rows.addAll(rawRows
              .map((e) => TaskProgressRowData.fromMap(
                  Map<String, dynamic>.from(e as Map)))
              .toList()
            ..sort((a, b) => a.rowIndex.compareTo(b.rowIndex)));
          _dailyStatuses.clear();
          rawStatus.forEach((k, v) => _dailyStatuses[k] = v.toString());
          _isLoading = false;
          _invalidatePhaseCache();
        });
        _syncNameControllers();
      }
    } catch (e, st) {
      widget.logger.e('TaskProgressMonitor: load failed', error: e, stackTrace: st);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveToFirestore() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    // Flush name controllers into row data
    for (final row in _rows) {
      row.taskName = _nameCtrl(row.id).text;
    }
    for (int i = 0; i < _rows.length; i++) {
      _rows[i].rowIndex = i;
    }

    try {
      await _docRef.set({
        'projectId'   : widget.project.id,
        'projectName' : widget.project.name,
        'updatedAt'   : Timestamp.now(),
        'rows'        : _rows.map((r) => r.toMap()).toList(),
        'dailyStatuses': _dailyStatuses,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Progress monitor saved!', style: GoogleFonts.poppins()),
          backgroundColor: Colors.green[700],
        ));
      }
    } catch (e) {
      widget.logger.e('TaskProgressMonitor: save failed', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Save failed: $e', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red[700],
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _autosaveStatus(String key, String? value) async {
    try {
      if (value == null) {
        await _docRef.update({'dailyStatuses.$key': FieldValue.delete()});
      } else {
        await _docRef.set(
          {'dailyStatuses': {key: value}},
          SetOptions(merge: true),
        );
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────
  // EXCEL IMPORT  (heavy work in isolate via compute())
  // ─────────────────────────────────────────────────────────────────
  Future<void> _importFromExcel() async {
    /// Updates both the overlay text and deterministic progress bar.
    void step(String msg, double progress) {
      if (mounted) {
        setState(() {
          _isImporting    = true;
          _importStep     = msg;
          _importProgress = progress;
        });
      }
    }

    step('Opening file picker…', 0.05);

    try {
      // ── 1. Pick file ────────────────────────────────────────────
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() { _isImporting = false; _importProgress = 0; });
        return;
      }

      step('Reading file bytes…', 0.15);
      Uint8List? bytes = result.files.first.bytes;
      if (bytes == null && result.files.first.path != null && !kIsWeb) {
        bytes = await File(result.files.first.path!).readAsBytes();
      }
      if (bytes == null) {
        if (mounted) setState(() { _isImporting = false; _importProgress = 0; });
        return;
      }

      // ── 2. Parse in background isolate (non-blocking) ───────────
      step('Parsing Excel file…', 0.30);
      // compute() runs _parseExcelInIsolate in a separate isolate so the
      // UI thread stays responsive and the progress overlay animates freely.
      final parseResult = await compute(_parseExcelInIsolate, bytes);
      final rawParsed   = parseResult.rows;

      step('Processing ${rawParsed.length} rows…', 0.60);
      // Allow a frame to render the updated step text.
      await Future.delayed(const Duration(milliseconds: 30));

      // Convert isolate maps → TaskProgressRowData objects
      final newRows = rawParsed.map((m) {
        final type = TaskRowType.values.firstWhere(
          (t) => t.name == (m['type'] as String),
          orElse: () => TaskRowType.task,
        );
        final startMs = m['startMs'] as int?;
        final endMs   = m['endMs']   as int?;
        return TaskProgressRowData(
          id           : m['id']            as String,
          rowIndex     : m['rowIndex']       as int,
          taskName     : m['rawName']        as String,
          startDate    : startMs != null ? DateTime.fromMillisecondsSinceEpoch(startMs) : null,
          endDate      : endMs   != null ? DateTime.fromMillisecondsSinceEpoch(endMs)   : null,
          type         : type,
          parentPhaseId: m['parentPhaseId']  as String?,
          indentLevel  : m['indentLevel']    as int,
        );
      }).toList();

      if (newRows.isEmpty) {
        if (mounted) {
          setState(() { _isImporting = false; _importProgress = 0; });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No rows found in the Excel file.',
                style: GoogleFonts.poppins()),
            backgroundColor: Colors.orange[700],
          ));
        }
        return;
      }

      // ── 3. Confirm replace ──────────────────────────────────────
      step('Found ${newRows.length} rows — awaiting confirmation…', 0.70);
      if (!mounted) return;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('Import from Excel',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          content: Text(
            'Found ${newRows.length} rows.\nThis will replace the current table. Continue?',
            style: GoogleFonts.poppins(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _navy, foregroundColor: Colors.white),
              child: Text('Import', style: GoogleFonts.poppins()),
            ),
          ],
        ),
      );

      if (confirm != true || !mounted) {
        setState(() { _isImporting = false; _importProgress = 0; });
        return;
      }

      // ── 4. Apply to state ────────────────────────────────────────
      step('Saving ${newRows.length} rows to database…', 0.85);
      await Future.delayed(const Duration(milliseconds: 30));

      for (final c in _nameCtrlMap.values) {
        c.dispose();
      }
      _nameCtrlMap.clear();

      setState(() {
        _rows.clear();
        _rows.addAll(newRows);
        _invalidatePhaseCache();
      });
      _syncNameControllers();

      // ── 5. Persist ───────────────────────────────────────────────
      step('Writing to Firestore…', 0.95);
      await _saveToFirestore();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Text('Imported ${newRows.length} rows successfully!',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ]),
          backgroundColor: Colors.green[700],
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e, st) {
      widget.logger.e('Excel import failed', error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.error_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Import failed: $e',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            ),
          ]),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 5),
        ));
      }
    } finally {
      if (mounted) setState(() { _isImporting = false; _importProgress = 0; _importStep = ''; });
    }
  }
  
  // ─────────────────────────────────────────────────────────────────
  // ROW MANIPULATION
  // ─────────────────────────────────────────────────────────────────
  void _addRow() {
    String? phaseId;
    for (int i = _rows.length - 1; i >= 0; i--) {
      if (_rows[i].type == TaskRowType.phase) {
        phaseId = _rows[i].id;
        break;
      }
    }
    final id = const Uuid().v4();
    setState(() {
      _rows.add(TaskProgressRowData(
        id           : id,
        rowIndex     : _rows.length,
        taskName     : '         New Task',
        type         : TaskRowType.task,
        parentPhaseId: phaseId,
        indentLevel  : 3,
      ));
      _invalidatePhaseCache();
    });
    _nameCtrl(id).text = '         New Task';
  }

  void _removeLastRow() {
    if (_rows.isEmpty) return;
    for (int i = _rows.length - 1; i >= 0; i--) {
      if (_rows[i].type == TaskRowType.task) {
        final id = _rows[i].id;
        setState(() {
          _rows.removeAt(i);
          _invalidatePhaseCache();
        });
        _nameCtrlMap.remove(id)?.dispose();
        return;
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // STATUS
  // ─────────────────────────────────────────────────────────────────
  String _statusKey(String rowId, DateTime date) =>
      '${rowId}_${_dfKey.format(date)}';

  DayStatus _getStatus(String rowId, DateTime date) =>
      DayStatusX.fromCode(_dailyStatuses[_statusKey(rowId, date)]);

  void _setStatus(String rowId, DateTime date, DayStatus status) {
    final key = _statusKey(rowId, date);
    setState(() {
      if (status == DayStatus.none) {
        _dailyStatuses.remove(key);
      } else {
        _dailyStatuses[key] = status.storageCode;
      }
    });
    _autosaveStatus(key, status == DayStatus.none ? null : status.storageCode);
  }

  // ─────────────────────────────────────────────────────────────────
  // WORKING DAYS & WEEKS
  // ─────────────────────────────────────────────────────────────────
  List<DateTime> _workingDays(DateTime start, DateTime end) {
    final days = <DateTime>[];
    DateTime cur = DateTime(start.year, start.month, start.day);
    final endN   = DateTime(end.year,   end.month,   end.day);
    while (!cur.isAfter(endN)) {
      if (cur.weekday != DateTime.sunday) days.add(cur);
      cur = cur.add(const Duration(days: 1));
    }
    return days;
  }

  List<List<DateTime>> _groupWeeks(List<DateTime> days) {
    final weeks = <List<DateTime>>[];
    List<DateTime> cur = [];
    for (final d in days) {
      if (d.weekday == DateTime.monday && cur.isNotEmpty) {
        weeks.add(cur);
        cur = [];
      }
      cur.add(d);
      if (d.weekday == DateTime.saturday && cur.isNotEmpty) {
        weeks.add(cur);
        cur = [];
      }
    }
    if (cur.isNotEmpty) weeks.add(cur);
    return weeks;
  }

  // ─────────────────────────────────────────────────────────────────
  // PROGRESS  –  day-count based (not task-completion based)
  //
  // Task %  = checkedDays / expectedWorkDays
  //           where expectedWorkDays = working days (no Sundays) between
  //           task.startDate and task.endDate (inclusive).
  //           checkedDays = days marked [done] on or before today
  //           (days past the planned endDate count too – shown in orange).
  //
  // Phase % = sum(checkedDays for all tasks in phase)
  //         / sum(expectedWorkDays for all tasks in phase)
  //
  // Project % = same aggregation across all phases / all tasks.
  // ─────────────────────────────────────────────────────────────────

  /// Working days (Mon-Sat, no Sundays) between [start] and [end] inclusive.
  int _countWorkDays(DateTime start, DateTime end) {
    int count = 0;
    DateTime cur = DateTime(start.year, start.month, start.day);
    final endN   = DateTime(end.year,   end.month,   end.day);
    while (!cur.isAfter(endN)) {
      if (cur.weekday != DateTime.sunday) count++;
      cur = cur.add(const Duration(days: 1));
    }
    return count;
  }

  /// Count of [done] checkmarks for [task] across ALL dates (including past planned end).
  int _checkedDaysForTask(TaskProgressRowData task) {
    if (task.startDate == null) return 0;
    int count = 0;
    // Scan all keys that belong to this task
    final prefix = '${task.id}_';
    for (final entry in _dailyStatuses.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      if (DayStatusX.fromCode(entry.value).countsAsWorked) count++;
    }
    return count;
  }

  /// Expected working days for a task (Mon-Sat, no Sundays).
  int _expectedDaysForTask(TaskProgressRowData task) {
    if (task.startDate == null || task.endDate == null) return 0;
    return _countWorkDays(task.startDate!, task.endDate!);
  }

  /// 0.0–1.0 progress for a single task.
  /// If any day on this task is marked [DayStatus.completed] the task is
  /// considered 100 % done regardless of how many days were checked.
  double _taskProgress(TaskProgressRowData task) {
    final prefix = '${task.id}_';
    for (final entry in _dailyStatuses.entries) {
      if (entry.key.startsWith(prefix) &&
          DayStatusX.fromCode(entry.value) == DayStatus.completed) {
        return 1.0;
      }
    }
    final expected = _expectedDaysForTask(task);
    if (expected == 0) return 0.0;
    final checked  = _checkedDaysForTask(task);
    return (checked / expected).clamp(0.0, 1.0);
  }

  /// 0.0–1.0 progress for a phase (weighted by expected work days).
  /// Routes through [_taskProgress] so a task marked [DayStatus.completed]
  /// contributes its full weight at 100 % to the phase total.
  double _phaseProgress(TaskProgressRowData phase) {
    if (phase.startDate == null || phase.endDate == null) return 0.0;
    final tasks = _rows
        .where((r) => r.type == TaskRowType.task && r.parentPhaseId == phase.id)
        .toList();
    if (tasks.isEmpty) return 0.0;

    double weightedSum = 0.0;
    int    totalWeight = 0;
    for (final t in tasks) {
      // Use at least 1 day of weight so tasks without dates still count.
      final weight = _expectedDaysForTask(t).clamp(1, 1 << 30);
      weightedSum += _taskProgress(t) * weight;
      totalWeight += weight;
    }
    if (totalWeight == 0) return 0.0;
    return (weightedSum / totalWeight).clamp(0.0, 1.0);
  }

  /// 0.0–1.0 project-level progress (equal-weight average across phases).
  /// Each phase contributes an equal 1/N share to the project total,
  /// regardless of how many tasks or work days it contains.
  /// e.g. 4 phases → each phase = 25 %; a phase at 50 % adds 12.5 % to the project.
  double get _projectProgress {
    final phases = _rows.where((r) => r.type == TaskRowType.phase).toList();
    if (phases.isEmpty) return 0.0;
    double total = 0.0;
    for (final phase in phases) {
      total += _phaseProgress(phase);
    }
    return (total / phases.length).clamp(0.0, 1.0);
  }

  // ─────────────────────────────────────────────────────────────────
  // ROW HEIGHT  –  base + dynamic extension for long task names
  // ─────────────────────────────────────────────────────────────────
  double _baseRowH(TaskRowType t) {
    switch (t) {
      case TaskRowType.project:  return _kProjectH;
      case TaskRowType.category: return _kCategoryH;
      case TaskRowType.phase:    return _kPhaseH;
      case TaskRowType.task:     return _kTaskH;
    }
  }

  /// Computes the actual row height, expanding vertically when the task name
  /// is too long to fit on a single line in the name column.
  ///
  /// [effectiveNameW] is the *actual* rendered name-cell width supplied by the
  /// LayoutBuilder in [_buildTable].  When omitted the cached [_nameColW] is
  /// used as a fallback, but callers should always supply the real width to
  /// avoid the 1-frame stale-value race that causes bottom overflows.
  ///
  /// Both the fixed panel and the period panel call this method so they always
  /// agree on height – no alignment drift.
  double _computeRowH(TaskProgressRowData row, {double? effectiveNameW}) {
    final base  = _baseRowH(row.type);
    // Prefer the caller-supplied width; fall back to the cached state value.
    final colW  = effectiveNameW ?? _nameColW;
    final name  = row.taskName.trim();

    if (name.isEmpty) {
      // Even empty task rows need space for the progress badge + padding.
      return row.type == TaskRowType.task ? base + 22.0 : base;
    }

    // ── Horizontal space consumed by badge chip + indent + cell padding ──
    const badgeWidths = {
      TaskRowType.task    : 0.0,
      TaskRowType.phase   : 30.0,
      TaskRowType.project : 38.0,
      TaskRowType.category: 38.0,
    };
    final badgeW = badgeWidths[row.type]!;
    final indent = row.indentLevel.clamp(0, 5) * 10.0;
    // left: indent+6, right: 4  → 10px consumed; add 18px safety for sub-pixel
    // differences, border widths, and the badge gap.
    final availW = (colW - indent - badgeW - 28.0).clamp(30.0, double.infinity);

    // Poppins 11 px – use a slightly conservative char-width (6.8 px) so we
    // never undercount lines on narrow columns.
    final charsPerLine = (availW / 6.8).floor().clamp(5, 500);
    final linesNeeded  = (name.length / charsPerLine).ceil().clamp(1, 10);

    // 11 px font × 1.45 line-height = 15.95 px; add 2 px for EditableText
    // baseline offset and font-metric headroom → 18 px per line.
    const lineH = 18.0;

    // Badge section (task rows only):
    //   4 px SizedBox gap + 3 px indicator track + ~13 px stat-text row
    //   + 6 px headroom for font metrics & touch area = 26 px total.
    const badgeH = 26.0;

    // Actual vertical padding in the name cell:
    //   top: 6 px; bottom: 8 px for tasks, 6 px for others.
    final padV = row.type == TaskRowType.task ? 14.0 : 12.0;

    final textH      = linesNeeded * lineH;
    final extraBadge = row.type == TaskRowType.task ? badgeH : 0.0;

    // +1 px so sub-pixel rounding never triggers a 0.5 px overflow.
    final computed = padV + textH + extraBadge + 1.0;

    return computed.clamp(base, double.infinity);
  }

  // ─────────────────────────────────────────────────────────────────
  // STATUS PICKER
  // ─────────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────────
  // STATUS PICKER  –  instant response: close sheet first, then apply
  // ─────────────────────────────────────────────────────────────────
  void _showStatusPicker(TaskProgressRowData row, DateTime day) {
    final current = _getStatus(row.id, day);
    if (!mounted) return;

    // Helper: dismiss the sheet and immediately apply status in the same frame.
    // We pop first so Flutter can start the close animation while setState
    // runs – the user sees the cell update with zero perceived lag.
    void pick(BuildContext ctx, DayStatus s) {
      Navigator.of(ctx).pop();        // start sheet close animation
      _setStatus(row.id, day, s);     // update cell immediately
    }

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: false,        // avoids extra navigator overhead
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 38, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '${row.taskName.trim()}  ·  ${DateFormat('EEE d MMM yyyy').format(day)}',
                style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w700, color: _navy),
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(height: 1),
            // ── Clear ──────────────────────────────────────────────
            _pickerTile(
              ctx: ctx,
              status: DayStatus.none,
              current: current,
              label: 'Clear / Not Set',
              labelColor: Colors.grey[500]!,
              onPick: pick,
            ),
            // ── Work Done – Ongoing ────────────────────────────────
            _pickerTile(
              ctx: ctx,
              status: DayStatus.done,
              current: current,
              label: DayStatus.done.label,
              labelColor: Colors.black87,
              onPick: pick,
            ),
            // ── Work Done – Completed (forces task to 100 %) ───────
            _pickerTile(
              ctx: ctx,
              status: DayStatus.completed,
              current: current,
              label: DayStatus.completed.label,
              labelColor: Colors.black87,
              onPick: pick,
            ),
            // ── Holiday ────────────────────────────────────────────
            _pickerTile(
              ctx: ctx,
              status: DayStatus.holiday,
              current: current,
              label: DayStatus.holiday.label,
              labelColor: Colors.black87,
              onPick: pick,
            ),
            // ── Bad Weather ────────────────────────────────────────
            _pickerTile(
              ctx: ctx,
              status: DayStatus.badWeather,
              current: current,
              label: DayStatus.badWeather.label,
              labelColor: Colors.black87,
              onPick: pick,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Single option tile in the status picker.
  Widget _pickerTile({
    required BuildContext ctx,
    required DayStatus status,
    required DayStatus current,
    required String label,
    required Color labelColor,
    required void Function(BuildContext, DayStatus) onPick,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onPick(ctx, status),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _statusChip(status),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label,
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: labelColor)),
              ),
              if (status == current)
                Icon(Icons.check_circle_rounded,
                    color: Colors.green[700], size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(DayStatus s) {
    if (s == DayStatus.none) {
      return Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(6)),
        child: const Icon(Icons.remove_rounded, size: 12, color: Colors.grey),
      );
    }
    return Container(
      width: 26, height: 26,
      decoration: BoxDecoration(
          color: s.bgColor,
          border: Border.all(color: s.color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(6)),
      child: Center(
        child: (s == DayStatus.done || s == DayStatus.completed)
            ? Icon(Icons.check_rounded, size: 14, color: s.color)
            : Text(s.code,
                style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w800, color: s.color)),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          // ── Main content ────────────────────────────────────────
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildProjectHeader(),
                    _buildToolbar(),
                    Expanded(child: _buildTable()),
                  ],
                ),

          // ── Import progress overlay ─────────────────────────────
          if (_isImporting) _buildImportOverlay(),
        ],
      ),
    );
  }

  // ── Import overlay with real progress bar ───────────────────────
  Widget _buildImportOverlay() {
    // Named import steps in order with display labels
    final steps = [
      'Opening file picker…',
      'Reading file bytes…',
      'Parsing Excel file…',
      'Processing rows…',
      'Awaiting confirmation…',
      'Saving rows to database…',
      'Writing to Firestore…',
    ];

    // Determine which step index is active
    final currentIdx = steps.indexWhere((s) {
      final stepLower = _importStep.toLowerCase();
      return stepLower.contains(s.replaceAll('…','').toLowerCase().split(' ').first);
    });

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.50),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header row ─────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: _navy.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(_navy),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Importing Excel',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: _navy)),
                        Text('Please wait…',
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.grey[500])),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Deterministic progress bar ──────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: _importProgress,
                            minHeight: 8,
                            backgroundColor: const Color(0xFFE8EEF6),
                            valueColor: const AlwaysStoppedAnimation(_navy),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${(_importProgress * 100).toStringAsFixed(0)}%',
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _navy),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Text(
                      _importStep,
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[600]),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),

                // ── Step list ───────────────────────────────────────
                ...steps.asMap().entries.map((e) {
                  final i      = e.key;
                  final label  = e.value;
                  // Mark steps before current as done, current as active
                  final isDone   = i < currentIdx;
                  final isActive = i == currentIdx;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(children: [
                      SizedBox(
                        width: 20, height: 20,
                        child: isDone
                            ? Icon(Icons.check_circle_rounded,
                                size: 16, color: Colors.green[600])
                            : isActive
                                ? const SizedBox(
                                    width: 14, height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 1.8,
                                        valueColor: AlwaysStoppedAnimation(_navy)))
                                : Container(
                                    width: 8, height: 8,
                                    margin: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[300],
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        label.replaceAll('…', ''),
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isDone
                              ? Colors.green[700]
                              : isActive
                                  ? _navy
                                  : Colors.grey[400],
                        ),
                      ),
                    ]),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── AppBar ───────────────────────────────────────────────────────
  AppBar _buildAppBar() => AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '${widget.project.name} — Task Progress Monitor',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)),
              ),
            )
          else
            IconButton(
              onPressed: _saveToFirestore,
              icon: const Icon(Icons.save_rounded),
              tooltip: 'Save',
            ),
        ],
      );

  // ── Project header with progress ─────────────────────────────────
  Widget _buildProjectHeader() {
    final progress = _projectProgress;
    return Container(
      color: _navy,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.project.name,
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'Project: ${(progress * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(
                progress >= 1.0 ? Colors.greenAccent : Colors.cyanAccent,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_phaseColumns.isNotEmpty)
            SizedBox(
              height: 26,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _phaseColumns.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final pc = _phaseColumns[i];
                  final pp = _phaseProgress(pc.phase);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        pc.phase.taskName.trim(),
                        style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${(pp * 100).toStringAsFixed(0)}%',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800),
                      ),
                    ]),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // ── Toolbar ──────────────────────────────────────────────────────
  Widget _buildToolbar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _fieldBorder, width: 0.8)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(children: [
        _toolBtn(
          icon: Icons.format_list_numbered_rounded,
          label: '# Rows',
          active: _showRowNumbers,
          onTap: () => setState(() => _showRowNumbers = !_showRowNumbers),
        ),
        const SizedBox(width: 6),
        _toolBtn(
          icon: Icons.add_box_outlined,
          label: 'Add Row',
          color: Colors.green[700],
          onTap: _addRow,
        ),
        const SizedBox(width: 6),
        _toolBtn(
          icon: Icons.indeterminate_check_box_outlined,
          label: 'Remove Last',
          color: Colors.orange[700],
          onTap: _removeLastRow,
        ),
        const Spacer(),
        _legendChip(DayStatus.done),
        const SizedBox(width: 4),
        _legendChip(DayStatus.holiday),
        const SizedBox(width: 4),
        _legendChip(DayStatus.badWeather),
        const SizedBox(width: 8),
        SizedBox(
          height: 32,
          child: ElevatedButton.icon(
            onPressed: _isImporting ? null : _importFromExcel,
            icon: _isImporting
                ? const SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white)))
                : const Icon(Icons.upload_file_rounded, size: 14),
            label: Text('Import Excel',
                style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7)),
              elevation: 1,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _toolBtn({
    required IconData icon,
    required String label,
    Color? color,
    bool active = false,
    required VoidCallback onTap,
  }) {
    final c = color ?? _navy;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? c.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: active
                  ? c.withValues(alpha: 0.45)
                  : Colors.grey.withValues(alpha: 0.3),
              width: 0.9),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: active ? c : Colors.grey[600]),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: active ? c : Colors.grey[600])),
        ]),
      ),
    );
  }

  Widget _legendChip(DayStatus s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
            color: s.bgColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: s.color.withValues(alpha: 0.4))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (s == DayStatus.done)
            Icon(Icons.check_rounded, size: 10, color: s.color)
          else
            Text(s.code,
                style: GoogleFonts.poppins(
                    fontSize: 9, fontWeight: FontWeight.w800, color: s.color)),
          const SizedBox(width: 3),
          Text(
            s == DayStatus.done ? 'Done' : s == DayStatus.holiday ? 'Holiday' : 'Bad Weather',
            style: GoogleFonts.poppins(
                fontSize: 8, fontWeight: FontWeight.w600, color: s.color),
          ),
        ]),
      );

  // ═════════════════════════════════════════════════════════════════
  // TABLE
  // ═════════════════════════════════════════════════════════════════
  Widget _buildTable() {
    if (_rows.isEmpty) return _buildEmptyState();

    return LayoutBuilder(
      builder: (context, outerConstraints) {
        const double minPeriodArea = 200.0;
        final newNameColW = (outerConstraints.maxWidth
                - (_showRowNumbers ? _kNoW : 0)
                - _kDateW * 2
                - minPeriodArea)
            .clamp(100.0, _kNameW);
        // Update cached name column width when layout changes
        if ((newNameColW - _nameColW).abs() > 0.5) {
          // Schedule post-frame to avoid setState during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _nameColW = newNameColW);
          });
        }
        final effectiveNameColW = newNameColW;
        final fixedW = (_showRowNumbers ? _kNoW : 0) + effectiveNameColW + _kDateW * 2;

        return Column(
          children: [
            // ── Sticky header ─────────────────────────────────────
            SizedBox(
              height: _kHeaderH,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildFixedHeader(fixedW: fixedW),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      controller: _hScrollHeader,
                      physics: const ClampingScrollPhysics(),
                      child: _buildPeriodHeader(),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: _fieldBorder.withValues(alpha: 0.6)),

            // ── Data rows (vertical scroll) ───────────────────────
            Expanded(
              child: LayoutBuilder(
                builder: (context, innerConstraints) {
                  final periodWidth = _phaseColumns.fold(
                      0.0, (acc, pc) => acc + pc.days.length * _kDayW);

                  // Use a ScrollController for vertical scroll
                  return SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    controller: _vScrollData,
                    physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics()),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Fixed left panel ──────────────────────
                        SizedBox(
                          width: fixedW,
                          child: Column(
                            children: _rows.asMap().entries.map((e) =>
                              RepaintBoundary(
                                child: _buildFixedRow(
                                  e.value,
                                  rowNumber: e.key + 1,
                                  fixedW: fixedW,
                                  effectiveNameW: effectiveNameColW,
                                ),
                              ),
                            ).toList(),
                          ),
                        ),

                        // ── Scrollable period panel ───────────────
                        SizedBox(
                          width: (innerConstraints.maxWidth - fixedW)
                              .clamp(0.0, double.infinity),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            controller: _hScrollData,
                            physics: const ClampingScrollPhysics(),
                            child: SizedBox(
                              width: periodWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _rows.map((r) =>
                                  RepaintBoundary(child: _buildPeriodRow(r, effectiveNameW: effectiveNameColW)),
                                ).toList(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // FIXED HEADER
  // ─────────────────────────────────────────────────────────────────
  Widget _buildFixedHeader({required double fixedW}) {
    return Container(
      width: fixedW,
      height: _kHeaderH,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        color: _navy,
        border: Border(
          right : BorderSide(color: Colors.white24, width: 1),
          bottom: BorderSide(color: Colors.white24, width: 1),
        ),
      ),
      child: Row(
        children: [
          if (_showRowNumbers) _fixedHdrCell('#', _kNoW, center: true),
          Expanded(child: _fixedHdrCell('Task Name', null)),
          _fixedHdrCell('Start Date',  _kDateW, center: true),
          _fixedHdrCell('Finish Date', _kDateW, center: true),
        ],
      ),
    );
  }

  Widget _fixedHdrCell(String label, double? w, {bool center = false}) =>
      Container(
        width: w,
        height: _kHeaderH,
        alignment: center ? Alignment.center : Alignment.centerLeft,
        padding: EdgeInsets.only(left: center ? 4 : 8, right: center ? 4 : 4),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Colors.white24, width: 0.5)),
        ),
        child: Text(
          label,
          textAlign: center ? TextAlign.center : TextAlign.left,
          softWrap: true,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.3),
        ),
      );

  // ─────────────────────────────────────────────────────────────────
  // PERIOD HEADER (phase → weeks → day labels)
  // ─────────────────────────────────────────────────────────────────
  Widget _buildPeriodHeader() {
    final phaseData = _phaseColumns;
    if (phaseData.isEmpty) {
      return Container(
        width: 320,
        height: _kHeaderH,
        color: _navyMid,
        alignment: Alignment.center,
        child: Text(
          'No phases with start/end dates defined',
          style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11),
        ),
      );
    }

    return SizedBox(
      height: _kHeaderH,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: phaseData.map((pc) {
          final phaseW = pc.days.length * _kDayW;
          return SizedBox(
            width: phaseW,
            child: Column(
              children: [
                // Row 1: Phase name
                Container(
                  height: 28,
                  width: double.infinity,
                  color: _navyMid,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text('PHASE',
                          style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 7,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5)),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        pc.phase.taskName.trim(),
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${(_phaseProgress(pc.phase) * 100).toStringAsFixed(0)}%',
                      style: GoogleFonts.poppins(
                          color: Colors.cyanAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 6),
                  ]),
                ),

                // Row 2+3: Week groups
                Expanded(
                  child: Row(
                    children: pc.weeks.map((week) {
                      final weekW        = week.length * _kDayW;
                      final isLastWeek   = week == pc.weeks.last;
                      // A week header is "overrun" if ALL its days are past the phase end
                      final phaseEndDay  = DateTime(
                          pc.phase.endDate!.year,
                          pc.phase.endDate!.month,
                          pc.phase.endDate!.day);
                      final weekIsOverrun = week.first.isAfter(phaseEndDay);
                      return SizedBox(
                        width: weekW,
                        child: Column(
                          children: [
                            // Week date range
                            Container(
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: weekIsOverrun
                                    ? const Color(0xFF7B3A10)
                                    : _navyLight,
                                border: Border(
                                  right: isLastWeek
                                      ? BorderSide(
                                          color: Colors.white38,
                                          width: _weekBorderWidth)
                                      : BorderSide(
                                          color: _weekBorderColor,
                                          width: _weekBorderWidth),
                                ),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (weekIsOverrun) ...[
                                      const Icon(Icons.warning_amber_rounded,
                                          size: 8, color: Color(0xFFFFB74D)),
                                      const SizedBox(width: 2),
                                    ],
                                    Text(
                                      '${DateFormat('MMM d').format(week.first)} – '
                                      '${DateFormat('MMM d').format(week.last)}',
                                      style: GoogleFonts.poppins(
                                          color: weekIsOverrun
                                              ? const Color(0xFFFFB74D)
                                              : Colors.white70,
                                          fontSize: 8,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Day name cells
                            Expanded(
                              child: Row(
                                children: week.asMap().entries.map((de) {
                                  final day       = de.value;
                                  final isWeekEnd = de.key == week.length - 1;
                                  final dayIsOverrun = day.isAfter(phaseEndDay);
                                  return Container(
                                    width: _kDayW,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: dayIsOverrun
                                          ? const Color(0xFF6D3010)
                                          : const Color(0xFF0B3070),
                                      border: Border(
                                        right: isWeekEnd
                                            ? BorderSide(
                                                color: _weekBorderColor,
                                                width: _weekBorderWidth)
                                            : const BorderSide(
                                                color: Colors.white24,
                                                width: 0.5),
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          DateFormat('EEE').format(day).substring(0, 2),
                                          style: GoogleFonts.poppins(
                                              color: dayIsOverrun
                                                  ? const Color(0xFFFFB74D)
                                                  : Colors.white60,
                                              fontSize: 7.5,
                                              fontWeight: FontWeight.w600),
                                        ),
                                        Text(
                                          DateFormat('d').format(day),
                                          style: GoogleFonts.poppins(
                                              color: dayIsOverrun
                                                  ? const Color(0xFFFF9800)
                                                  : Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // FIXED ROW (task name + dates – left sticky panel)
  // ─────────────────────────────────────────────────────────────────
  Widget _buildFixedRow(TaskProgressRowData row,
      {required int rowNumber, required double fixedW, double? effectiveNameW}) {
    final h              = _computeRowH(row, effectiveNameW: effectiveNameW);
    final (bg, fg, accent) = _rowColors(row.type);

    // Use SizedBox(height: h) — a concrete finite height that Row(stretch)
    // can work with. _computeRowH already accounts for text wrap + badge.
    return SizedBox(
      width: fixedW,
      height: h,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            bottom: BorderSide(color: _fieldBorder.withValues(alpha: 0.5), width: 0.5),
            right : BorderSide(color: _fieldBorder.withValues(alpha: 0.4), width: 0.7),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Row number
            if (_showRowNumbers)
              Container(
                width: _kNoW,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.08),
                  border: Border(
                      right: BorderSide(
                          color: _fieldBorder.withValues(alpha: 0.4),
                          width: 0.5)),
                ),
                child: Text(
                  '$rowNumber',
                  style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: accent.withValues(alpha: 0.6)),
                ),
              ),

            // Task name cell
            Expanded(child: _buildNameCell(row, fg, accent)),

            // Start date
            _buildDateCell(row, isStart: true, fg: fg, accent: accent),

            // Finish date
            _buildDateCell(row, isStart: false, fg: fg, accent: accent),
          ],
        ),
      ),
    );
  }

  (Color, Color, Color) _rowColors(TaskRowType t) {
    switch (t) {
      case TaskRowType.project:
        return (const Color(0xFFE8EEF6), _navy, _navy);
      case TaskRowType.category:
        return (const Color(0xFFF0F4F9),
            const Color(0xFF1A3C6A), const Color(0xFF1A3C6A));
      case TaskRowType.phase:
        return (const Color(0xFFE3ECF8), _navy, _navy);
      case TaskRowType.task:
        return (Colors.white, Colors.black87, _navy);
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // NAME CELL – fully content-driven height, never clips
  // ─────────────────────────────────────────────────────────────────
  Widget _buildNameCell(
      TaskProgressRowData row, Color fg, Color accent) {
    final indent = (row.indentLevel.clamp(0, 5) * 10.0);
    // Extra bottom padding for task rows to ensure badge never overflows
    final bottomPad = row.type == TaskRowType.task ? 8.0 : 6.0;

    return Container(
      padding: EdgeInsets.only(left: indent + 6, right: 4, top: 6, bottom: bottomPad),
      decoration: BoxDecoration(
        border: Border(
            right: BorderSide(
                color: _fieldBorder.withValues(alpha: 0.4), width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type badge
          if (row.type == TaskRowType.phase) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1, right: 5),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                    color: _navy, borderRadius: BorderRadius.circular(3)),
                child: Text('PH',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 7,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3)),
              ),
            ),
          ] else if (row.type == TaskRowType.project) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1, right: 5),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                    color: const Color(0xFF1565C0),
                    borderRadius: BorderRadius.circular(3)),
                child: Text('PRJ',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 7,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ] else if (row.type == TaskRowType.category) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1, right: 5),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                    color: const Color(0xFF37474F),
                    borderRadius: BorderRadius.circular(3)),
                child: Text('GRP',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 7,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ],

          // Editable task name – softWraps freely, no line limit
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameCtrl(row.id),
                  onChanged: (v) {
                    row.taskName = v;
                    // Trigger rebuild so _computeRowH re-evaluates
                    setState(() {});
                  },
                  maxLines: null,
                  minLines: 1,
                  keyboardType: TextInputType.multiline,
                  style: GoogleFonts.poppins(
                      fontSize: row.type == TaskRowType.task ? 11 : 11.5,
                      fontWeight: row.type == TaskRowType.task
                          ? FontWeight.w400
                          : FontWeight.w700,
                      color: fg,
                      height: 1.45),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                // Per-task progress mini bar (tasks only)
                if (row.type == TaskRowType.task) ...[
                  const SizedBox(height: 4),
                  _buildTaskProgressBadge(row),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Mini progress pill shown below a task name in the fixed panel.
  Widget _buildTaskProgressBadge(TaskProgressRowData task) {
    final expected = _expectedDaysForTask(task);
    final checked  = _checkedDaysForTask(task);
    final pct      = _taskProgress(task);   // uses _taskProgress so it's referenced
    final isOver   = checked > expected && expected > 0;

    final barColor = isOver
        ? const Color(0xFFE65100)   // orange – overrun
        : pct >= 1.0
            ? const Color(0xFF2E7D32)  // green – complete
            : const Color(0xFF1565C0); // blue – in progress

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 3,
              backgroundColor: const Color(0xFFE0E6EF),
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '$checked/$expected d · ${(pct * 100).toStringAsFixed(0)}%',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: GoogleFonts.poppins(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: barColor),
          ),
        ),
      ],
    );
  }

  Widget _buildDateCell(
      TaskProgressRowData row,
      {required bool isStart,
      required Color fg,
      required Color accent}) {
    final date = isStart ? row.startDate : row.endDate;
    return GestureDetector(
      onTap: row.type == TaskRowType.task || row.type == TaskRowType.phase
          ? () => _pickDate(row, isStart: isStart)
          : null,
      child: Container(
        width: _kDateW,
        // No height/minHeight needed – the parent Row(stretch)+SizedBox(height:h)
        // already gives this cell a finite, exact height.
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
              right: BorderSide(
                  color: _fieldBorder.withValues(alpha: 0.4), width: 0.5)),
        ),
        child: date != null
            ? Text(
                _dfDisplay.format(date),
                style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: fg),
                textAlign: TextAlign.center,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              )
            : Icon(Icons.edit_calendar_rounded,
                size: 13, color: Colors.grey[350]),
      ),
    );
  }

  Future<void> _pickDate(TaskProgressRowData row,
      {required bool isStart}) async {
    final initial = isStart
        ? (row.startDate ?? DateTime.now())
        : (row.endDate ?? (row.startDate ?? DateTime.now()));
    final first = isStart
        ? DateTime(2020)
        : (row.startDate ?? DateTime(2020));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme:
              const ColorScheme.light(primary: _navy, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        row.startDate = picked;
        if (row.endDate != null && row.endDate!.isBefore(picked)) {
          row.endDate = picked;
        }
      } else {
        row.endDate = picked;
      }
      _invalidatePhaseCache(); // date changes rebuild phase columns
    });
  }

  // ─────────────────────────────────────────────────────────────────
  // PERIOD ROW (status cells – right scrollable panel)
  // ─────────────────────────────────────────────────────────────────
  Widget _buildPeriodRow(TaskProgressRowData row, {double? effectiveNameW}) {
    final phaseData = _phaseColumns;
    final h         = _computeRowH(row, effectiveNameW: effectiveNameW);

    if (phaseData.isEmpty) {
      return SizedBox(width: 320, height: h, child: ColoredBox(color: _sectionBg));
    }

    return SizedBox(
      height: h,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: phaseData.map((pc) {
          final phaseW = pc.days.length * _kDayW;

          // Project / Category – greyed-out band
          if (row.type == TaskRowType.project ||
              row.type == TaskRowType.category) {
            return SizedBox(
              width: phaseW, height: h,
              child: ColoredBox(
                color: row.type == TaskRowType.project
                    ? const Color(0xFFE8EEF6)
                    : const Color(0xFFF0F4F9),
                child: const Divider(height: 1, thickness: 0.3),
              ),
            );
          }

          // Phase row – progress bar for own phase
          if (row.type == TaskRowType.phase) {
            if (row.id == pc.phase.id) {
              return _buildPhaseProgressRow(row, pc, phaseW, h);
            }
            return SizedBox(
              width: phaseW, height: h,
              child: const ColoredBox(color: Color(0xFFF5F7FA)),
            );
          }

          // Task row – day cells only for its parent phase
          final inPhase = row.parentPhaseId == pc.phase.id;
          if (!inPhase) {
            return SizedBox(
              width: phaseW, height: h,
              child: const ColoredBox(
                color: Color(0xFFF9FAFB),
                child: Center(
                  child: Divider(
                      color: Color(0xFFE0E4EA), thickness: 0.5, height: 1),
                ),
              ),
            );
          }

          // Build day cells – each cell gets the exact height h
          return SizedBox(
            width: phaseW,
            height: h,
            child: Row(
              // Use start alignment: each _buildDayCell sets its own height: h
              crossAxisAlignment: CrossAxisAlignment.start,
              children: pc.days.asMap().entries.map((de) {
                final dayIdx    = de.key;
                final day       = de.value;
                final status    = _getStatus(row.id, day);
                final taskStart = row.startDate;
                final taskEnd   = row.endDate;

                final inPlannedRange = taskStart == null || taskEnd == null
                    ? true
                    : !day.isBefore(DateTime(
                            taskStart.year, taskStart.month, taskStart.day)) &&
                      !day.isAfter(DateTime(
                            taskEnd.year, taskEnd.month, taskEnd.day));

                final isOverrun = taskStart != null && taskEnd != null &&
                    day.isAfter(DateTime(taskEnd.year, taskEnd.month, taskEnd.day)) &&
                    !day.isBefore(DateTime(
                            taskStart.year, taskStart.month, taskStart.day));

                final isActive    = inPlannedRange || isOverrun;
                final isBeforeTask = taskStart != null &&
                    day.isBefore(DateTime(
                            taskStart.year, taskStart.month, taskStart.day));

                final isWeekEnd = _isLastDayOfWeek(pc, dayIdx);

                return GestureDetector(
                  onTap: isActive && !isBeforeTask
                      ? () => _showStatusPicker(row, day)
                      : null,
                  child: _buildDayCell(
                    status,
                    isActive && !isBeforeTask,
                    h,
                    isWeekEnd: isWeekEnd,
                    isOverrun: isOverrun,
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Returns true if the day at [dayIndex] in [pc.days] is the last day
  /// of its week bucket (i.e. the boundary between two weeks).
  bool _isLastDayOfWeek(_PhaseColumnData pc, int dayIndex) {
    int count = 0;
    for (final week in pc.weeks) {
      count += week.length;
      if (dayIndex == count - 1) return true;
      if (dayIndex < count) return false;
    }
    return false;
  }

  Widget _buildDayCell(DayStatus status, bool active, double h,
      {bool isWeekEnd = false, bool isOverrun = false}) {
    // Overrun done-marks are orange; in-range done is green
    final effectiveColor = (isOverrun && (status == DayStatus.done || status == DayStatus.completed))
        ? const Color(0xFFE65100)
        : status.color;
    final effectiveBg = (isOverrun && (status == DayStatus.done || status == DayStatus.completed))
        ? const Color(0xFFFFF3E0)
        : (active ? status.bgColor : const Color(0xFFF3F5F7));

    return Container(
      width: _kDayW,
      height: h,
      decoration: BoxDecoration(
        color: effectiveBg,
        border: Border(
          right: isWeekEnd
              ? BorderSide(
                  color: _weekBorderColor, width: _weekBorderWidth)
              : BorderSide(
                  color: _fieldBorder.withValues(alpha: 0.35), width: 0.5),
          bottom: BorderSide(
              color: _fieldBorder.withValues(alpha: 0.25), width: 0.3),
          // Light orange left border to hint overrun zone
          left: isOverrun
              ? const BorderSide(color: Color(0xFFFF9800), width: 0.8)
              : BorderSide.none,
        ),
      ),
      child: active
          ? Center(
              child: status == DayStatus.none
                  ? Icon(Icons.add_rounded,
                      size: 11, color: Colors.grey[300])
                  : (status == DayStatus.done || status == DayStatus.completed)
                      ? Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: effectiveColor,
                        )
                      : Text(
                          status.code,
                          style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: status.color),
                        ),
            )
          : null,
    );
  }

  Widget _buildPhaseProgressRow(TaskProgressRowData row,
      _PhaseColumnData pc, double phaseW, double h) {
    final progress = _phaseProgress(row);

    // Aggregate day counts for display
    final tasks = _rows
        .where((r) => r.type == TaskRowType.task && r.parentPhaseId == row.id)
        .toList();
    final totalExpected = tasks.fold(0, (s, t) => s + _expectedDaysForTask(t));
    final totalChecked  = tasks.fold(0, (s, t) => s + _checkedDaysForTask(t));

    return Container(
      width: phaseW,
      height: h,
      color: const Color(0xFFE3ECF8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Text(
              '$totalChecked / $totalExpected work days',
              style: GoogleFonts.poppins(
                  fontSize: 9, color: _navy.withValues(alpha: 0.6)),
            ),
            const Spacer(),
            Text(
              '${(progress * 100).toStringAsFixed(0)}% complete',
              style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: progress >= 1.0 ? Colors.green[700] : _navy),
            ),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.6),
              valueColor: AlwaysStoppedAnimation(
                progress >= 1.0
                    ? Colors.green[600]!
                    : const Color(0xFF1565C0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // EMPTY STATE
  // ─────────────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.table_chart_outlined, size: 56, color: Colors.grey[300]),
          const SizedBox(height: 14),
          Text('No tasks defined yet',
              style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500])),
          const SizedBox(height: 6),
          Text(
            'Use "Import Excel" to load from a file,\nor "Add Row" to create tasks manually.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[400]),
          ),
          const SizedBox(height: 20),
          Row(mainAxisSize: MainAxisSize.min, children: [
            ElevatedButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add_rounded, size: 15),
              label: Text('Add Row',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _isImporting ? null : _importFromExcel,
              icon: const Icon(Icons.upload_file_rounded, size: 15),
              label: Text('Import Excel',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _navy,
                side: BorderSide(color: _navy),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// HELPER MODEL – phase column data (pre-computed & cached)
// ══════════════════════════════════════════════════════════════════
class _PhaseColumnData {
  final TaskProgressRowData phase;
  final List<DateTime> days;
  final List<List<DateTime>> weeks;

  const _PhaseColumnData({
    required this.phase,
    required this.days,
    required this.weeks,
  });
}