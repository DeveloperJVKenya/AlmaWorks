import 'dart:typed_data';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/models/report_model.dart';
import 'package:almaworks/screens/reports/safety_form_screen.dart';
import 'package:almaworks/screens/reports/daily_report_form_screen.dart';
import 'package:almaworks/screens/reports/weekly_report_form_screen.dart';
import 'package:almaworks/screens/reports/monthly_report_form_screen.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';
import 'package:almaworks/services/file_pick_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:almaworks/helpers/download_helper.dart';

import 'dart:io' show Directory, File, Platform;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReportsScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;

  /// When [isClient] is true the screen enforces client-only RBAC:
  /// – only the Weekly and Monthly saved-report tabs are visible
  /// – the upload / create FAB is hidden
  /// – Edit and Delete actions are removed from every report card
  final bool isClient;

  const ReportsScreen({
    super.key,
    required this.project,
    required this.logger,
    this.isClient = false,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  bool _isLoading = false;

  // Full tab list – admin / main-admin see all five tabs.
  static const _allTabs = [
    {'label': 'Daily', 'type': 'Daily'},
    {'label': 'Weekly', 'type': 'Weekly'},
    {'label': 'Monthly', 'type': 'Monthly'},
    {'label': 'Safety Meetings', 'type': 'Safety'},
    {'label': 'Quality', 'type': 'Quality'},
  ];

  // Clients only see saved Weekly and Monthly reports.
  static const _clientTabs = [
    {'label': 'Weekly', 'type': 'Weekly'},
    {'label': 'Monthly', 'type': 'Monthly'},
  ];

  List<Map<String, String>> get _tabs =>
      widget.isClient ? _clientTabs : _allTabs;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    widget.logger.i(
        '📊 ReportsScreen: Initialized for project: ${widget.project.name} (ID: ${widget.project.id})');
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─────────────────────────── BUILD ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return BaseLayout(
      title: '${widget.project.name} - Reports',
      project: widget.project,
      logger: widget.logger,
      selectedMenuItem: 'Reports',
      onMenuItemSelected: (_) {},
      // Clients cannot create or upload reports — hide the FAB entirely.
      floatingActionButton: widget.isClient
          ? null
          : FloatingActionButton(
              onPressed: _isLoading ? null : _handleUploadAction,
              backgroundColor: const Color(0xFF0A2E5A),
              foregroundColor: Colors.white,
              child: _isLoading
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
      child: Column(
        children: [
          // ── Tab Bar: fills evenly on wide screens, scrollable on mobile ──
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Breakpoint: ≥600 px → desktop/tablet mode (fill evenly)
                //             <600 px → mobile (scroll, show ~4 tabs at a time)
                final isMobile = constraints.maxWidth < 600;
                return TabBar(
                  controller: _tabController,
                  isScrollable: isMobile,
                  tabAlignment: isMobile
                      ? TabAlignment.start
                      : TabAlignment.fill,
                  labelColor: const Color(0xFF0A2E5A),
                  unselectedLabelColor: Colors.grey[600],
                  indicatorColor: const Color(0xFF0A2E5A),
                  labelStyle: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  unselectedLabelStyle: GoogleFonts.poppins(
                      fontWeight: FontWeight.w400, fontSize: 13),
                  tabs: _tabs.map((t) => Tab(text: t['label'])).toList(),
                );
              },
            ),
          ),

          // ── Tab Views (built dynamically so client-only tabs work) ──
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _tabs.map((t) {
                final type = t['type']!;
                return type == 'Safety'
                    ? _buildSafetyTab()
                    : _buildDocumentTab(type);
              }).toList(),
            ),
          ),

          _buildFooter(context),
        ],
      ),
    );
  }

  // ─────────────────────────── FOOTER ───────────────────────────

  Widget _buildFooter(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      color: const Color(0xFF0A2E5A),
      child: Text(
        '© 2026 JV Alma C.I.S Site Management System',
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: isMobile ? 12 : 14,
          fontWeight: FontWeight.w400,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ─────────────────────── DOCUMENT TAB (Daily / Weekly / Monthly / Quality) ───

  Widget _buildDocumentTab(String type) {
    widget.logger.d(
        '📊 ReportsScreen: Fetching Reports (type: $type, projectId: ${widget.project.id})');
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Reports')
          .where('projectId', isEqualTo: widget.project.id)
          .where('type', isEqualTo: type)
          // No orderBy — allows fetching legacy docs that lack 'uploadedAt'.
          // Sorting is done client-side below using whichever timestamp exists.
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          widget.logger.e(
              '❌ ReportsScreen: Error loading Reports ($type)',
              error: snapshot.error,
              stackTrace: snapshot.stackTrace);
          return Center(
            child: Text(
              'Error loading documents: ${snapshot.error}',
              style: GoogleFonts.poppins(color: Colors.red[600]),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final rawDocs = snapshot.data!.docs;
        widget.logger
            .i('📊 ReportsScreen: Loaded ${rawDocs.length} Reports ($type)');

        // Sort client-side: prefer uploadedAt, fall back to savedAt, then epoch.
        final documents = List.of(rawDocs)..sort((a, b) {
          DateTime tsOf(QueryDocumentSnapshot doc) {
            final d = doc.data() as Map<String, dynamic>;
            final ts = d['uploadedAt'] ?? d['savedAt'];
            return ts is Timestamp ? ts.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          }
          return tsOf(b).compareTo(tsOf(a)); // descending
        });

        if (documents.isEmpty) {
          return _buildEmptyState(type);
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionHeader('$type Reports'),
            const SizedBox(height: 16),
            ...documents.map((doc) {
              try {
                final data = doc.data() as Map<String, dynamic>;
                // ── Form-filled report (has savedAt, no file url) ──
                final isFormReport = data['savedAt'] != null &&
                    (data['url'] == null || data['url'] == '');
                if (isFormReport) {
                  return _buildFormReportItem(doc.id, data, type);
                }
                // ── Uploaded file report ───────────────────────────
                final report = ReportModel.fromMap(doc.id, data);
                return _buildReportItem(report);
              } catch (e, st) {
                widget.logger.e(
                    '❌ ReportsScreen: Error parsing Report ${doc.id} ($type)',
                    error: e,
                    stackTrace: st);
                return const SizedBox.shrink();
              }
            }),
          ],
        );
      },
    );
  }

  // ─────────────────────── SAFETY MEETINGS TAB ───────────────────

  Widget _buildSafetyTab() {
    widget.logger.d(
        '📊 ReportsScreen: Fetching Safety Reports (projectId: ${widget.project.id})');
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Reports')
          .where('projectId', isEqualTo: widget.project.id)
          .where('type', whereIn: ['SafetyWeekly', 'SafetyMonthly', 'Safety'])
          // No orderBy — fetch all, sort client-side for legacy compatibility.
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          widget.logger.e(
              '❌ ReportsScreen: Error loading Safety Reports',
              error: snapshot.error,
              stackTrace: snapshot.stackTrace);
          return Center(
            child: Text(
              'Error loading safety reports: ${snapshot.error}',
              style: GoogleFonts.poppins(color: Colors.red[600]),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final rawReports = snapshot.data!.docs;
        widget.logger
            .i('📊 ReportsScreen: Loaded ${rawReports.length} Safety Reports');

        // Sort client-side descending by uploadedAt → savedAt → epoch
        final reports = List.of(rawReports)..sort((a, b) {
          DateTime tsOf(QueryDocumentSnapshot doc) {
            final d = doc.data() as Map<String, dynamic>;
            final ts = d['uploadedAt'] ?? d['savedAt'];
            return ts is Timestamp ? ts.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          }
          return tsOf(b).compareTo(tsOf(a));
        });

        if (reports.isEmpty) {
          return _buildEmptyState('Safety Meeting');
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionHeader('Safety Meeting Reports'),
            const SizedBox(height: 16),
            ...reports.map((doc) {
              try {
                final data = doc.data() as Map<String, dynamic>;
                // Form-filled safety report (has savedAt, no uploaded file url)
                final isFormReport = data['savedAt'] != null &&
                    (data['url'] == null || data['url'] == '');
                if (isFormReport) {
                  return _buildSafetyFormReportItem(doc.id, data);
                }
                final report = ReportModel.fromMap(doc.id, data);
                return _buildReportItem(report);
              } catch (e, st) {
                widget.logger.e(
                    '❌ ReportsScreen: Error parsing Safety Report ${doc.id}',
                    error: e,
                    stackTrace: st);
                return const SizedBox.shrink();
              }
            }),
          ],
        );
      },
    );
  }

  // ─────────────────────── SHARED UI HELPERS ───────────────────

  Widget _buildEmptyState(String type) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_outlined,
              size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No $type reports added yet',
            style: GoogleFonts.poppins(
                color: Colors.grey[600], fontSize: 16),
          ),
          const SizedBox(height: 8),
          // Clients cannot create reports — show a neutral message instead.
          if (!widget.isClient)
            Text(
              'Tap the upload button to add one',
              style: GoogleFonts.poppins(
                  color: Colors.grey[400], fontSize: 13),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A2E5A).withValues(alpha: 0.05),
        border: Border.all(color: Colors.grey[300]!, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        title,
        style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF0A2E5A)),
      ),
    );
  }

  Widget _buildReportItem(ReportModel report) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor:
              (report.fileType != null
                      ? _getFileIconColor(report.fileType!)
                      : const Color(0xFF0A2E5A))
                  .withValues(alpha: 0.12),
          child: Icon(
            report.fileType != null
                ? _getDocumentIcon(report.fileType!)
                : Icons.security,
            color: report.fileType != null
                ? _getFileIconColor(report.fileType!)
                : const Color(0xFF0A2E5A),
            size: 22,
          ),
        ),
        title: Text(
          report.name,
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              'Uploaded: ${_dateFormat.format(report.uploadedAt)}',
              style: GoogleFonts.poppins(
                  color: Colors.grey[600], fontSize: 13),
            ),
            ...[
            const SizedBox(height: 2),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color:
                    const Color(0xFF0A2E5A).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                report.type,
                style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: const Color(0xFF0A2E5A),
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleReportAction(value, report),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          itemBuilder: (context) {
            // A safety form-filled report has a fileUrl (PDF) but no legacy 'url' field,
            // OR it has safetyFormData. Either way we can view the form itself.
            final isSafetyFormReport = report.type == 'SafetyWeekly' ||
                report.type == 'SafetyMonthly' ||
                report.safetyFormData != null;

            return [
              if (report.url != null)
                _popupItem('view', Icons.visibility, Colors.blue[600]!, 'View File'),
              if (isSafetyFormReport)
                _popupItem(
                    'view_form', Icons.assignment, Colors.blue[600]!, 'View / Edit Form'),
              _popupItem(
                  'download', Icons.download, Colors.green[600]!, 'Download PDF'),
              // Clients cannot delete reports.
              if (!widget.isClient)
                _popupItem('delete', Icons.delete, Colors.red[600]!, 'Delete'),
            ];
          },
        ),
      ),
    );
  }

  PopupMenuItem<String> _popupItem(
      String value, IconData icon, Color color, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Text(label, style: GoogleFonts.poppins()),
        ],
      ),
    );
  }

  // ─────────────────────── FORM REPORT ITEM ────────────────────

  /// Builds a list tile for a form-filled report (Daily / Weekly / Monthly).
  Widget _buildFormReportItem(
      String docId, Map<String, dynamic> data, String type) {
    // ── Derive the bold title from the date filled in the form ──
    // Daily forms store 'date'; Weekly forms store 'weekStart'+'weekEnd'.
    // Using these raw Timestamp fields means both old and new records
    // always display the correct work period — no database edits needed.
    final formDateRaw   = data['date'];
    final weekStartRaw  = data['weekStart'];
    final weekEndRaw    = data['weekEnd'];
    final monthStartRaw = data['monthStart'];

    final DateTime? formDate   = formDateRaw   is Timestamp ? formDateRaw.toDate()   : null;
    final DateTime? weekStart  = weekStartRaw  is Timestamp ? weekStartRaw.toDate()  : null;
    final DateTime? weekEnd    = weekEndRaw    is Timestamp ? weekEndRaw.toDate()     : null;
    final DateTime? monthStart = monthStartRaw is Timestamp ? monthStartRaw.toDate() : null;

    // savedAt is always needed for the "Saved:" subtitle line.
    final DateTime savedAt = data['savedAt'] != null
        ? (data['savedAt'] as Timestamp).toDate()
        : (data['uploadedAt'] != null
            ? (data['uploadedAt'] as Timestamp).toDate()
            : DateTime.now());

    final String displayName;
    if (formDate != null) {
      // Daily (and any form that stores a single 'date' field)
      displayName =
          '$type Report – ${DateFormat('dd MMM yyyy').format(formDate)}';
    } else if (weekStart != null) {
      // Weekly (stores weekStart + weekEnd instead of a single date)
      final endPart = weekEnd != null
          ? ' → ${DateFormat('dd MMM yyyy').format(weekEnd)}'
          : '';
      displayName =
          '$type Report – ${DateFormat('dd MMM yyyy').format(weekStart)}$endPart';
    } else if (monthStart != null) {
      // Monthly (stores monthStart — show as full month name + year)
      displayName =
          '$type Report – ${DateFormat('MMMM yyyy').format(monthStart)}';
    } else {
      // Fallback for any legacy doc that lacks both 'date' and 'weekStart':
      // use the stored name, or derive from savedAt as a last resort.
      final storedName = data['name'] as String?;
      displayName = storedName != null && storedName.isNotEmpty
          ? storedName
          : '$type Report – ${DateFormat('dd MMM yyyy, hh:mm a').format(savedAt)}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openFormReport(docId, data, type, readOnly: true),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(
            backgroundColor:
                const Color(0xFF0A2E5A).withValues(alpha: 0.12),
            child: const Icon(
              Icons.description_rounded,
              color: Color(0xFF0A2E5A),
              size: 22,
            ),
          ),
          title: Text(
            displayName,
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, fontSize: 15),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(
                'Saved: ${_dateFormat.format(savedAt)}',
                style:
                    GoogleFonts.poppins(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 2),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A2E5A).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$type Form',
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: const Color(0xFF0A2E5A),
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            onSelected: (action) =>
                _handleFormReportAction(action, docId, data, type),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            itemBuilder: (context) => [
              _popupItem('open', Icons.visibility_rounded,
                  Colors.blue[700]!, 'Open'),
              // Clients are view-only — Edit and Delete are hidden.
              if (!widget.isClient) ...[
                _popupItem('edit', Icons.edit_rounded,
                    const Color(0xFF0A2E5A), 'Edit'),
                _popupItem('delete', Icons.delete_rounded,
                    Colors.red[600]!, 'Delete'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /*Future<void> _handleReportAction(
      String action, ReportModel report) async {
    switch (action) {
      case 'view':
        await _viewDocument(
            report.url!, report.fileType ?? 'pdf', report.name);
        break;

      case 'view_form':
        // Open the safety form in read-only mode so the user can inspect
        // all filled data and switch to edit mode via the FAB if needed.
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SafetyFormScreen(
              project: widget.project,
              logger: widget.logger,
              isClientView: widget.isClient,
              // Pass the raw Firestore data so the form can pre-populate.
              existingReportId: report.id,
              isReadOnly: true,
            ),
          ),
        );
        break;

      case 'download':
        // If the report already has a stored PDF url use it directly,
        // otherwise fall back to building one from safetyFormData.
        if (report.url != null && report.url!.isNotEmpty) {
          await _downloadDocument(report.url!, '${report.name}.pdf');
        } else {
          await _downloadSafetyReport(report);
        }
        break;

      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text('Delete Report',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600)),
            content: Text(
                'Are you sure you want to delete "${report.name}"?',
                style: GoogleFonts.poppins()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel', style: GoogleFonts.poppins()),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white),
                child: Text('Delete', style: GoogleFonts.poppins()),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          // Delete both any uploaded file AND the generated PDF URL
          // so Storage is kept clean.
          final urlToDelete = report.url ?? '';
          await _deleteDocument(report.id, urlToDelete, 'Reports');
        }
        break;
    }
  }*/

  void _openFormReport(
      String docId, Map<String, dynamic> data, String type,
      {required bool readOnly}) {
    // Clients are always view-only — override the flag defensively.
    final effectiveReadOnly = widget.isClient ? true : readOnly;
    widget.logger.i(
        '📊 ReportsScreen: Opening form report $docId (readOnly=$effectiveReadOnly, type=$type)');
    try {
      if (type == 'Daily') {
        final report = DailyReportData.fromMap({...data, 'id': docId});
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DailyReportFormScreen(
              project: widget.project,
              logger: widget.logger,
              existingReport: report,
              isReadOnly: effectiveReadOnly,
            ),
          ),
        );
      } else if (type == 'Weekly') {
        final report = WeeklyReportData.fromMap({...data, 'id': docId});
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WeeklyReportFormScreen(
              project: widget.project,
              logger: widget.logger,
              existingReport: report,
              isReadOnly: effectiveReadOnly,
              isClientView: widget.isClient,
            ),
          ),
        );
      } else if (type == 'Monthly') {
        final report = MonthlyReportData.fromMap({...data, 'id': docId});
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MonthlyReportFormScreen(
              project: widget.project,
              logger: widget.logger,
              existingReport: report,
              isReadOnly: effectiveReadOnly,
              isClientView: widget.isClient,
            ),
          ),
        );
      } else if (type == 'Safety' ||
          type == 'SafetyWeekly' ||
          type == 'SafetyMonthly') {
        _openSafetyFormReport(docId, data,
            readOnly: effectiveReadOnly);
      } else {
        widget.logger.w(
            '⚠️ ReportsScreen: No form viewer for type=$type');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('In-app viewer not available for $type reports.',
                style: GoogleFonts.poppins()),
          ));
        }
      }
    } catch (e, st) {
      widget.logger.e('❌ ReportsScreen: Error opening form report',
          error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error opening report: $e',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ─────────────────────── SAFETY FORM REPORT ITEM ────────────────

  /// Builds a list tile for a form-filled safety meeting report.
  /// Mirrors [_buildFormReportItem] but is Safety-specific:
  /// – uses [reportDate] (not 'date'/'weekStart') for the display name
  /// – Delete is always hidden from clients (enforced via [widget.isClient])
  Widget _buildSafetyFormReportItem(String docId, Map<String, dynamic> data) {
    final reportDateRaw = data['reportDate'];
    final DateTime reportDate = reportDateRaw is Timestamp
        ? reportDateRaw.toDate()
        : DateTime.now();

    final savedAtRaw = data['savedAt'];
    final DateTime savedAt =
        savedAtRaw is Timestamp ? savedAtRaw.toDate() : DateTime.now();

    final String safetyType =
        data['type'] as String? ?? 'SafetyWeekly';
    final String meetingLabel = safetyType == 'SafetyMonthly'
        ? 'Monthly Safety Meeting'
        : 'Weekly Safety Meeting';

    final displayName =
        '$meetingLabel – ${DateFormat('dd MMM yyyy').format(reportDate)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openSafetyFormReport(docId, data, readOnly: true),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(
            backgroundColor:
                const Color(0xFF0A2E5A).withValues(alpha: 0.12),
            child: const Icon(
              Icons.security_rounded,
              color: Color(0xFF0A2E5A),
              size: 22,
            ),
          ),
          title: Text(
            displayName,
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, fontSize: 15),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(
                'Saved: ${_dateFormat.format(savedAt)}',
                style: GoogleFonts.poppins(
                    color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A2E5A).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Safety Form',
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: const Color(0xFF0A2E5A),
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            onSelected: (action) =>
                _handleFormReportAction(action, docId, data, 'Safety'),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            itemBuilder: (context) => [
              _popupItem('open', Icons.visibility_rounded,
                  Colors.blue[700]!, 'Open'),
              // Edit and Delete are hidden from clients.
              if (!widget.isClient) ...[
                _popupItem('edit', Icons.edit_rounded,
                    const Color(0xFF0A2E5A), 'Edit'),
                _popupItem('delete', Icons.delete_rounded,
                    Colors.red[600]!, 'Delete'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────── FORM REPORT ACTION HANDLER ──────────

  /// Handles popup-menu actions for all form-filled reports
  /// (Daily / Weekly / Monthly / Safety).
  Future<void> _handleFormReportAction(
      String action,
      String docId,
      Map<String, dynamic> data,
      String type) async {
    switch (action) {
      case 'open':
        if (type == 'Safety') {
          _openSafetyFormReport(docId, data, readOnly: true);
        } else {
          _openFormReport(docId, data, type, readOnly: true);
        }
        break;

      case 'edit':
        if (type == 'Safety') {
          _openSafetyFormReport(docId, data, readOnly: false);
        } else {
          _openFormReport(docId, data, type, readOnly: false);
        }
        break;

      case 'download':
        await _downloadSafetyFormData(docId, data);
        break;

      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text('Delete Report',
                style:
                    GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            content: Text(
                'Are you sure you want to delete this safety report?',
                style: GoogleFonts.poppins()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel', style: GoogleFonts.poppins()),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white),
                child: Text('Delete', style: GoogleFonts.poppins()),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          // Delete all Storage images attached to the safety form.
          final imageUrls =
              List<String>.from(data['imageUrls'] ?? []);
          for (final url in imageUrls) {
            try {
              await FirebaseStorage.instance.refFromURL(url).delete();
            } catch (_) {}
          }
          // Also delete the pre-generated PDF if one was stored.
          final fileUrl = data['fileUrl'] as String?;
          if (fileUrl != null && fileUrl.isNotEmpty) {
            try {
              await FirebaseStorage.instance
                  .refFromURL(fileUrl)
                  .delete();
            } catch (_) {}
          }
          await FirebaseFirestore.instance
              .collection('Reports')
              .doc(docId)
              .delete();
          widget.logger.i(
              '✅ ReportsScreen: Safety form report $docId deleted');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Report deleted successfully',
                  style: GoogleFonts.poppins()),
              backgroundColor: Colors.green,
            ));
          }
        }
        break;
    }
  }

  // ─────────────────────── OPEN SAFETY FORM REPORT ─────────────

  /// Pushes [SafetyFormScreen] pre-populated from [data] (raw Firestore map).
  /// Clients are always forced into read-only mode.
  void _openSafetyFormReport(
      String docId, Map<String, dynamic> data,
      {required bool readOnly}) {
    final effectiveReadOnly = widget.isClient ? true : readOnly;
    widget.logger.i(
        '📊 ReportsScreen: Opening safety form report $docId '
        '(readOnly=$effectiveReadOnly)');
    try {
      final report = SafetyReportData.fromMap({...data, 'id': docId});
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SafetyFormScreen(
            project: widget.project,
            logger: widget.logger,
            existingReport: report,
            isReadOnly: effectiveReadOnly,
          ),
        ),
      );
    } catch (e, st) {
      widget.logger.e(
          '❌ ReportsScreen: Error opening safety form report',
          error: e,
          stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error opening report: $e',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ─────────────────────── DOWNLOAD SAFETY FORM DATA ───────────

  /// Downloads a form-filled safety report as a PDF.
  ///
  /// Path 1 — if [data] contains a `fileUrl` (PDF generated by
  /// [SafetyFormScreen] at save time), it is fetched directly from
  /// Firebase Storage so we never regenerate an identical document.
  ///
  /// Path 2 — if no `fileUrl` exists (legacy or draft records), a styled
  /// A4 PDF is built on-the-fly from the stored [SafetyReportData] fields,
  /// mirroring the layout in [_downloadSafetyReport].
  Future<void> _downloadSafetyFormData(
      String docId, Map<String, dynamic> data) async {
    // Show progress snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 14),
          Text('Preparing PDF…', style: GoogleFonts.poppins()),
        ]),
        duration: const Duration(seconds: 30),
      ));
    }

    try {
      final SafetyReportData safetyData =
          SafetyReportData.fromMap({...data, 'id': docId});
      final dateStr =
          DateFormat('yyyyMMdd').format(safetyData.reportDate);
      final fileName = 'Safety_Report_$dateStr.pdf';

      final fileUrl = data['fileUrl'] as String?;

      if (fileUrl != null && fileUrl.isNotEmpty) {
        // ── Path 1: fetch pre-generated PDF from Storage ──────────
        final storageData = await FirebaseStorage.instance
            .refFromURL(fileUrl)
            .getData(50 * 1024 * 1024);
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (storageData != null) {
          await _savePdfBytesLocally(
              Uint8List.fromList(storageData), fileName);
        }
        return;
      }

      // ── Path 2: generate PDF on the fly ───────────────────────
      final pdf = pw.Document();
      final navyColor = PdfColor.fromHex('#0A2E5A');
      final meetingTitle = safetyData.type == 'SafetyMonthly'
          ? 'MONTHLY SAFETY MEETING REPORT'
          : 'WEEKLY SAFETY MEETING REPORT';

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
                    '© JV Almacis Site Management System - Safety Report',
                    style: pw.TextStyle(
                        font: pw.Font.helvetica(),
                        fontSize: 7,
                        color: PdfColors.grey600)),
                pw.Text(
                    'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                    style: pw.TextStyle(
                        font: pw.Font.helvetica(),
                        fontSize: 7,
                        color: PdfColors.grey600)),
              ],
            ),
          ),
          build: (ctx) => [
            // Header band
            pw.Container(
              width: double.infinity,
              color: navyColor,
              padding:
                  const pw.EdgeInsets.fromLTRB(16, 14, 16, 12),
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
                  pw.Text(meetingTitle,
                      style: pw.TextStyle(
                          font: pw.Font.helveticaBold(),
                          fontSize: 10,
                          color: PdfColor.fromHex('#FFFFFFB3'),
                          letterSpacing: 1.5)),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            // Content block
            pw.Container(
              width: double.infinity,
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: PdfColors.blueGrey200, width: 0.5)),
              padding: const pw.EdgeInsets.all(12),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _pdfLabelValue('Date',
                      DateFormat('dd MMM yyyy').format(safetyData.reportDate)),
                  if (safetyData.contractNumber.isNotEmpty)
                    _pdfLabelValue(
                        'Contract No.', safetyData.contractNumber),
                  if (safetyData.building.isNotEmpty)
                    _pdfLabelValue(
                        'Building/Area', safetyData.building),
                  pw.SizedBox(height: 8),
                  // Safety checklist
                  pw.Text('Safety Checklist',
                      style: pw.TextStyle(
                          font: pw.Font.helveticaBold(),
                          fontSize: 10)),
                  pw.SizedBox(height: 4),
                  ...safetyData.checklistItems.map(
                    (item) => pw.Padding(
                      padding:
                          const pw.EdgeInsets.only(bottom: 2),
                      child: pw.Row(children: [
                        pw.Text(
                            item.checked ? '[X]' : '[ ]',
                            style: pw.TextStyle(
                                font: pw.Font.helvetica(),
                                fontSize: 9)),
                        pw.SizedBox(width: 6),
                        pw.Text(item.label,
                            style: pw.TextStyle(
                                font: pw.Font.helvetica(),
                                fontSize: 9)),
                      ]),
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  // JV Alma attendance
                  if (safetyData.jvAlmaRows.isNotEmpty) ...[
                    pw.Text('JV Alma CIS Attendance',
                        style: pw.TextStyle(
                            font: pw.Font.helveticaBold(),
                            fontSize: 10)),
                    pw.SizedBox(height: 4),
                    ...safetyData.jvAlmaRows.map(
                      (r) => pw.Padding(
                        padding:
                            const pw.EdgeInsets.only(bottom: 2),
                        child: pw.Text(
                            '• ${r.name} – ${r.title}',
                            style: pw.TextStyle(
                                font: pw.Font.helvetica(),
                                fontSize: 9)),
                      ),
                    ),
                    pw.SizedBox(height: 8),
                  ],
                  // Sub-contractor attendance (weekly only)
                  if (safetyData.subContractorRows.isNotEmpty) ...[
                    pw.Text('Sub-Contractor Attendance',
                        style: pw.TextStyle(
                            font: pw.Font.helveticaBold(),
                            fontSize: 10)),
                    pw.SizedBox(height: 4),
                    ...safetyData.subContractorRows.map(
                      (r) => pw.Padding(
                        padding:
                            const pw.EdgeInsets.only(bottom: 2),
                        child: pw.Text(
                            '• ${r.companyName ?? ''} – ${r.name} (${r.title})',
                            style: pw.TextStyle(
                                font: pw.Font.helvetica(),
                                fontSize: 9)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

      final bytes = Uint8List.fromList(await pdf.save());
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await _savePdfBytesLocally(bytes, fileName);
    } catch (e) {
      widget.logger.e(
          '❌ Error downloading safety form data as PDF',
          error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error generating PDF: $e',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  /// Renders a bold-label + plain-value row inside the PDF.
  pw.Widget _pdfLabelValue(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('$label: ',
              style: pw.TextStyle(
                  font: pw.Font.helveticaBold(), fontSize: 9)),
          pw.Expanded(
            child: pw.Text(value,
                style: pw.TextStyle(
                    font: pw.Font.helvetica(), fontSize: 9)),
          ),
        ],
      ),
    );
  }

  /*Future<void> _deleteFormReport(
      String docId, Map<String, dynamic> data) async {
    widget.logger.i('🗑️ ReportsScreen: Deleting form report: $docId');
    try {
      // Delete all associated images from Firebase Storage
      final imageUrls = List<String>.from(data['imageUrls'] ?? []);
      for (final url in imageUrls) {
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
          widget.logger.d('🗑️ ReportsScreen: Deleted image $url');
        } catch (imgErr) {
          widget.logger.w('⚠️ ReportsScreen: Could not delete image $url – $imgErr');
        }
      }
      // Delete the Firestore document
      await FirebaseFirestore.instance.collection('Reports').doc(docId).delete();
      widget.logger.i('✅ ReportsScreen: Form report $docId deleted');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Report deleted successfully',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e, st) {
      widget.logger.e('❌ ReportsScreen: Error deleting form report',
          error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error deleting report: $e',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ));
      }
    }
  }*/

  // ─────────────────────── FAB LOGIC ───────────────────────────

  void _handleUploadAction() {
    // Map tab index → report type
    const typeMap = {
      0: 'Daily',
      1: 'Weekly',
      2: 'Monthly',
      3: 'Safety',
      4: 'Quality',
    };
    final type = typeMap[_tabController.index] ?? 'Daily';

    if (type == 'Daily') {
      _showDailyOptions();
    } else if (type == 'Weekly') {
      _showWeeklyOptions();        // ← NEW
    } else if (type == 'Monthly') {
      _showMonthlyOptions();
    } else if (type == 'Safety') {
      _showSafetyOptions();
    } else {
      _uploadReport(type);
    }
  }

  void _showDailyOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Daily Report',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: const Color(0xFF0A2E5A)),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F0FB),
                child: Icon(Icons.edit_note_rounded, color: Color(0xFF0A2E5A)),
              ),
              title: Text('Fill Daily Report Form', style: GoogleFonts.poppins()),
              subtitle: Text(
                'Complete the structured form within the app',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
              ),
              onTap: () {
                Navigator.pop(context);
                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DailyReportFormScreen(
                        project: widget.project,
                        logger: widget.logger,
                      ),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F5E9),
                child: Icon(Icons.upload_file_rounded, color: Colors.green),
              ),
              title: Text('Upload Daily Report File', style: GoogleFonts.poppins()),
              subtitle: Text(
                'PDF, DOCX, PPTX, or TXT file from your device',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
              ),
              onTap: () {
                Navigator.pop(context);
                _uploadReport('Daily');
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showWeeklyOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Weekly Report',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: const Color(0xFF0A2E5A)),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F0FB),
                child: Icon(Icons.edit_note_rounded, color: Color(0xFF0A2E5A)),
              ),
              title: Text('Fill Weekly Report Form', style: GoogleFonts.poppins()),
              subtitle: Text(
                'Complete the structured form within the app',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
              ),
              onTap: () {
                Navigator.pop(context);
                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WeeklyReportFormScreen(
                        project: widget.project,
                        logger: widget.logger,
                      ),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F5E9),
                child: Icon(Icons.upload_file_rounded, color: Colors.green),
              ),
              title: Text('Upload Weekly Report File', style: GoogleFonts.poppins()),
              subtitle: Text(
                'PDF, DOCX, PPTX, or TXT file from your device',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
              ),
              onTap: () {
                Navigator.pop(context);
                _uploadReport('Weekly');
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showMonthlyOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Monthly Report',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: const Color(0xFF0A2E5A)),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F0FB),
                child: Icon(Icons.edit_note_rounded, color: Color(0xFF0A2E5A)),
              ),
              title: Text('Fill Monthly Report Form', style: GoogleFonts.poppins()),
              subtitle: Text(
                'Complete the structured form within the app',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
              ),
              onTap: () {
                Navigator.pop(context);
                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MonthlyReportFormScreen(
                        project: widget.project,
                        logger: widget.logger,
                      ),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F5E9),
                child: Icon(Icons.upload_file_rounded, color: Colors.green),
              ),
              title: Text('Upload Monthly Report File', style: GoogleFonts.poppins()),
              subtitle: Text(
                'PDF, DOCX, PPTX, or TXT file from your device',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
              ),
              onTap: () {
                Navigator.pop(context);
                _uploadReport('Monthly');
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showSafetyOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Safety Meeting Report',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: const Color(0xFF0A2E5A)),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F0FB),
                child:
                    Icon(Icons.edit_note, color: Color(0xFF0A2E5A)),
              ),
              title:
                  Text('Fill Safety Form', style: GoogleFonts.poppins()),
              subtitle: Text('Complete the form within the app',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey[600])),
              onTap: () {
                Navigator.pop(context);
                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SafetyFormScreen(
                        project: widget.project,
                        logger: widget.logger,
                      ),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F5E9),
                child: Icon(Icons.upload_file, color: Colors.green),
              ),
              title: Text('Upload Safety File',
                  style: GoogleFonts.poppins()),
              subtitle: Text('PDF, DOCX, PPTX, or TXT file',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey[600])),
              onTap: () {
                Navigator.pop(context);
                _uploadReport('Safety');
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ─────────────────────── UPLOAD ──────────────────────────────

  Future<void> _uploadReport(String type) async {
    try {
      // 1. Pick file — routed through pickFileForUpload (file_pick_helper.dart)
      // rather than calling FilePicker directly: that helper is what
      // guarantees `withData: true` (required for bytes on web) is never
      // missing again. This exact call used to set withData itself and
      // lost it at some point, which is what made every upload across all
      // five Reports tabs fail identically (they all funnel through this
      // one shared method) with "Unexpected null value".
      final picked = await pickFileForUpload(
        allowedExtensions: ['pdf', 'docx', 'doc', 'pptx', 'ppt', 'txt'],
      );
      if (picked == null) {
        widget.logger.d('📤 ReportsScreen: File selection cancelled');
        return;
      }

      final originalFileName = picked.name;
      final extension = picked.extension;
      widget.logger
          .i('📤 ReportsScreen: File selected: $originalFileName');

      // 2. Ask for title (pre-filled)
      final title = await _showTextInputDialog(
        dialogTitle: 'Enter Report Title',
        contentText: 'Enter a title for this report:',
        hintText: 'Enter report title',
        prefill: originalFileName.split('.').first,
        fileName: originalFileName,
        showFileName: true,
      );
      if (title == null || title.trim().isEmpty) {
        widget.logger.d('📤 ReportsScreen: Title input cancelled');
        return;
      }

      final finalFileName = '$title.$extension';
      final fileBytes = picked.bytes;

      setState(() => _isLoading = true);

      // 4. Progress dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text('Uploading Report',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('Uploading $finalFileName...',
                    style: GoogleFonts.poppins()),
              ],
            ),
          ),
        );
      }

      // 5. Upload to Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child(widget.project.id)
          .child('Reports')
          .child(type) // organise by type in storage too
          .child(finalFileName);

      final uploadTask = storageRef.putData(
        fileBytes,
        SettableMetadata(contentType: _getContentType(extension)),
      );
      final snapshot = await uploadTask.whenComplete(() {});
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // 6. Save to Firestore
      final docRef =
          await FirebaseFirestore.instance.collection('Reports').add({
        'name': title.trim(),
        'url': downloadUrl,
        'projectId': widget.project.id,
        'projectName': widget.project.name,
        'uploadedAt': Timestamp.now(),
        'type': type,
        'fileType': extension,
      });
      widget.logger
          .i('✅ ReportsScreen: Report saved (ID: ${docRef.id})');

      if (mounted) {
        Navigator.pop(context); // close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Report uploaded successfully',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e, st) {
      widget.logger.e('❌ ReportsScreen: Error uploading report',
          error: e, stackTrace: st);
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error uploading report: $e',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─────────────────────── DIALOGS ─────────────────────────────

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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          dialogTitle,
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF0A2E5A)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(contentText,
                style: GoogleFonts.poppins(color: Colors.grey[700])),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              style: GoogleFonts.poppins(),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle:
                    GoogleFonts.poppins(color: Colors.grey[500]),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderSide:
                      const BorderSide(color: Color(0xFF0A2E5A)),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            if (showFileName && fileName != null) ...[
              const SizedBox(height: 8),
              Text('File: $fileName',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey[600])),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style:
                    GoogleFonts.poppins(color: const Color(0xFF800000))),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Title cannot be empty',
                      style: GoogleFonts.poppins()),
                ));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0A2E5A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Confirm', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── ACTIONS ─────────────────────────────

  Future<void> _handleReportAction(
      String action, ReportModel report) async {
    switch (action) {
      case 'view':
        await _viewDocument(
            report.url!, report.fileType ?? 'pdf', report.name);
        break;
      case 'view_form':
        await _viewSafetyForm(report);
        break;
      case 'download':
        if (report.url != null) {
          await _downloadDocument(report.url!, report.name);
        } else {
          await _downloadSafetyReport(report);
        }
        break;
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text('Delete Report',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600)),
            content: Text(
                'Are you sure you want to delete "${report.name}"?',
                style: GoogleFonts.poppins()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel', style: GoogleFonts.poppins()),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white),
                child: Text('Delete', style: GoogleFonts.poppins()),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await _deleteDocument(report.id, report.url ?? '', 'Reports');
        }
        break;
    }
  }

  // ─────────────────────── VIEW ────────────────────────────────

  Future<void> _viewDocument(
      String url, String type, String name) async {
    widget.logger.i('👀 ReportsScreen: Viewing document: $name ($type)');
    final connectivityResult =
        await Connectivity().checkConnectivity();
    final isOnline =
        connectivityResult.any((r) => r != ConnectivityResult.none);

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
                title: Text(name, style: GoogleFonts.poppins()),
                content: SingleChildScrollView(
                  child: SelectableText(content,
                      style: GoogleFonts.poppins()),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child:
                        Text('Close', style: GoogleFonts.poppins()),
                  ),
                ],
              ),
            );
          }
        } else if (kIsWeb) {
          final viewerUrl = _getViewerUrl(url, type);
          final uri = Uri.parse(viewerUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri,
                mode: LaunchMode.externalApplication);
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Could not open document viewer',
                  style: GoogleFonts.poppins()),
            ));
          }
        } else {
          final result = await OpenFile.open(localPath);
          if (result.type != ResultType.done && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Could not open file: ${result.message}',
                  style: GoogleFonts.poppins()),
              action: SnackBarAction(
                label: 'Download instead',
                onPressed: () => _downloadDocument(url, name),
              ),
            ));
          }
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No internet and no cache available',
              style: GoogleFonts.poppins()),
        ));
      }
    } catch (e) {
      widget.logger.e('Error viewing document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Error viewing document: $e', style: GoogleFonts.poppins()),
        ));
      }
    }
  }

  // ─────────────────────── DOWNLOAD ────────────────────────────

  Future<void> _downloadDocument(String url, String name) async {
    widget.logger.i('⬇️ ReportsScreen: Downloading: $name');
    try {
      final response = await Dio().get(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final Uint8List bytes = response.data;
      final result = await platformDownloadFile(bytes, name);

      if (!mounted) return;
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Downloaded successfully!\nLocation: $result',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Open',
            textColor: Colors.white,
            onPressed: () async => await OpenFile.open(result),
          ),
        ));
      }
    } catch (e) {
      widget.logger.e('❌ Error downloading', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
        ));
      }
    }
  }

  // ─────────────────────── DELETE ──────────────────────────────

  Future<void> _deleteDocument(
      String docId, String url, String collection) async {
    widget.logger.i('🗑️ ReportsScreen: Deleting document: $docId');
    try {
      if (url.isNotEmpty) {
        final ref = FirebaseStorage.instance.refFromURL(url);
        await ref.delete();
      }
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(docId)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Document deleted successfully',
              style: GoogleFonts.poppins()),
        ));
      }
    } catch (e) {
      widget.logger.e('❌ ReportsScreen: Error deleting document',
          error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error deleting: $e',
              style: GoogleFonts.poppins()),
        ));
      }
    }
  }

  // ─────────────────────── SAFETY FORM HELPERS ─────────────────

  Future<void> _viewSafetyForm(ReportModel report) async {
    final content = _generateSafetyReportContent(report);
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(report.name, style: GoogleFonts.poppins()),
          content: SingleChildScrollView(
            child:
                SelectableText(content, style: GoogleFonts.poppins()),
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
  }

  String _generateSafetyReportContent(ReportModel report) {
    final buffer = StringBuffer();
    buffer.writeln(report.type == 'SafetyWeekly'
        ? 'Weekly Safety Meeting Form'
        : 'Monthly Safety Meeting Form');
    buffer.writeln('Date: ${_dateFormat.format(report.uploadedAt)}');
    buffer.writeln('\nItems:');
    for (var item in (report.safetyFormData!['items']
            as Map<String, dynamic>)
        .entries) {
      buffer.writeln('| ${item.key} | ${item.value ? 'X' : ' '} |');
    }
    buffer.writeln('\nObservations and Comments:');
    buffer.writeln(report.safetyFormData!['observations'] ?? '');
    buffer.writeln('\nActions Taken:');
    buffer.writeln(report.safetyFormData!['actions'] ?? '');
    buffer.writeln('\nJV Alma CIS Attendance:');
    for (var attendee
        in (report.safetyFormData!['jvAlmaAttendance'] ?? []) as List) {
      buffer.writeln(
          '- Name: ${attendee['name']}, Title: ${attendee['title']}, Signature: ${attendee['signature']}');
    }
    if (report.type == 'SafetyWeekly') {
      buffer.writeln('\nSub-Contractor Attendance:');
      for (var attendee in (report.safetyFormData![
              'subContractorAttendance'] ??
          []) as List) {
        buffer.writeln(
            '- Company: ${attendee['companyName']}, Name: ${attendee['name']}, Title: ${attendee['title']}, Signature: ${attendee['signature']}');
      }
    }
    return buffer.toString();
  }

  /// Downloads the safety form report as a proper PDF.
  /// If the report already has a `fileUrl` (generated at save-time by
  /// SafetyFormScreen), it fetches that PDF from Firebase Storage so we
  /// never regenerate an identical document.  Otherwise it falls back to
  /// the plain-text approach for legacy records that pre-date PDF generation.
  Future<void> _downloadSafetyReport(ReportModel report) async {
    if (report.safetyFormData == null && report.url == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No form data or file available for download.',
              style: GoogleFonts.poppins()),
        ));
      }
      return;
    }

    // show a progress indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 14),
          Text('Preparing PDF…', style: GoogleFonts.poppins()),
        ]),
        duration: const Duration(seconds: 30),
      ));
    }

    try {
      // ── Path 1: report has a stored PDF URL ──────────────────────
      // This covers all reports saved by the updated SafetyFormScreen,
      // which uploads a PDF and writes 'fileUrl' to Firestore at save-time.
      if (report.url != null && report.url!.isNotEmpty) {
        final fileName = '${report.name.replaceAll(' ', '_')}.pdf';
        final data = await FirebaseStorage.instance
            .refFromURL(report.url!)
            .getData(50 * 1024 * 1024);
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (data != null) {
          await _savePdfBytesLocally(
              Uint8List.fromList(data), fileName);
        }
        return;
      }

      // ── Path 2: legacy record — generate PDF on the fly ──────────
      // Builds a simple but styled PDF from the stored safetyFormData map
      // so older records that pre-date the fileUrl field are still
      // downloadable as PDF (not just .txt).
      final content = _generateSafetyReportContent(report);
      final navyColor = PdfColor.fromHex('#0A2E5A');
      //final lightBlue = PdfColor.fromHex('#E8EEF6');

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
                    '© JV Almacis Site Management System - Safety Report',
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
            // Header band
            pw.Container(
              width: double.infinity,
              color: navyColor,
              padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 12),
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
                  pw.Text(
                    report.type == 'SafetyWeekly'
                        ? 'WEEKLY SAFETY MEETING REPORT'
                        : 'MONTHLY SAFETY MEETING REPORT',
                    style: pw.TextStyle(
                        font: pw.Font.helveticaBold(),
                        fontSize: 10,
                        color: PdfColor.fromHex('#FFFFFFB3'),
                        letterSpacing: 1.5),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            // Content block
            pw.Container(
              width: double.infinity,
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: PdfColors.blueGrey200, width: 0.5)),
              padding: const pw.EdgeInsets.all(12),
              child: pw.Text(
                content,
                style: pw.TextStyle(
                    font: pw.Font.helvetica(),
                    fontSize: 9,
                    color: PdfColors.black),
              ),
            ),
          ],
        ),
      );

      final bytes = Uint8List.fromList(await pdf.save());
      final fileName =
          '${report.name.replaceAll(' ', '_')}.pdf';

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await _savePdfBytesLocally(bytes, fileName);
    } catch (e) {
      widget.logger.e('❌ Error downloading safety report as PDF', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error generating PDF: $e',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  /// Saves [bytes] as [fileName] to the platform Downloads folder,
  /// opens it with OpenFile, and shows a success snackbar.
  /// Falls back to Printing.sharePdf when direct file access fails.
  /// Mirrors MonthlyReportFormScreen._savePdfBytes exactly.
  Future<void> _savePdfBytesLocally(
      Uint8List bytes, String fileName) async {
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('PDF saved: $fileName', style: GoogleFonts.poppins()),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Open',
          textColor: Colors.white,
          onPressed: () async => await OpenFile.open(filePath),
        ),
      ));
    } catch (e) {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    }
  }

  // ─────────────────────── UTILITIES ───────────────────────────

  String _getViewerUrl(String url, String type) {
    final encodedUrl = Uri.encodeComponent(url);
    return type.toLowerCase() == 'pdf'
        ? url
        : 'https://view.officeapps.live.com/op/view.aspx?src=$encodedUrl';
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
}