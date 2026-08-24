import 'dart:io';
import 'dart:typed_data';

import 'package:almaworks/models/inventory/asset_booking_model.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Generates and downloads the printable handover form for an
/// [AssetBookingModel] delivered via Driver/Transporter — the driver has no
/// app account (same rationale as the Materials fabrication chain, see
/// fabrication_form_pdf.dart), so this is the physical record they sign at
/// pickup, and the recipient signs again at receipt before scanning it back
/// into the app alongside their in-app "Acknowledge Receipt" confirmation.
/// Unlike the fabrication form, there's no fabricator section — Assets and
/// Tools never go through fabrication, only certain Materials do.
///
/// Follows the same pw.MultiPage + navy-banner + cross-platform save
/// pattern used by fabrication_form_pdf.dart / daily_report_form_screen.dart.
const _navyColor = PdfColor.fromInt(0xFF0A2748);

Future<void> generateAndSaveHandoverForm({
  required BuildContext context,
  required Logger logger,
  required AssetBookingModel booking,
}) async {
  final doc = pw.Document();
  String dateFmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  pw.Widget sectionHeader(String title) => pw.Container(
        width: double.infinity,
        color: _navyColor,
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const pw.EdgeInsets.only(top: 14, bottom: 8),
        child: pw.Text(title,
            style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11)),
      );

  pw.Widget printedRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(children: [
          pw.SizedBox(width: 130, child: pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
          pw.Expanded(child: pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
        ]),
      );

  pw.Widget ackBox(String title) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 4),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.blueGrey300, width: 0.5)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(children: [
            pw.Text('Condition:  [ ] Good   [ ] Damaged', style: const pw.TextStyle(fontSize: 9)),
          ]),
          pw.SizedBox(height: 8),
          pw.Text('If damaged, describe:', style: const pw.TextStyle(fontSize: 9)),
          pw.Container(height: 24, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5)))),
          pw.SizedBox(height: 10),
          pw.Row(children: [
            pw.Text('Printed name: ', style: const pw.TextStyle(fontSize: 9)),
            pw.Expanded(child: pw.Container(height: 16, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5))))),
          ]),
          pw.SizedBox(height: 10),
          pw.Row(children: [
            pw.Expanded(
              child: pw.Row(children: [
                pw.Text('Signature: ', style: const pw.TextStyle(fontSize: 9)),
                pw.Expanded(child: pw.Container(height: 16, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5))))),
              ]),
            ),
            pw.SizedBox(width: 16),
            pw.Row(children: [
              pw.Text('Date: ', style: const pw.TextStyle(fontSize: 9)),
              pw.Container(width: 70, height: 16, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5)))),
            ]),
          ]),
        ]),
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 40),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text('Form ID: ${booking.id}  •  Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ),
      build: (ctx) => [
        pw.Container(
          width: double.infinity,
          color: _navyColor,
          padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('AlmaWorks — ${booking.itemType} Handover via Driver/Transporter',
                style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 14)),
            pw.SizedBox(height: 4),
            pw.Text('Form ID: ${booking.id}', style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
          ]),
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Scan and upload this completed form via the AlmaWorks app after the recipient section is signed.',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700, fontStyle: pw.FontStyle.italic),
        ),

        sectionHeader('1. Dispatch Details (office-filled)'),
        printedRow(booking.itemType, booking.assetName),
        printedRow('Date dispatched', dateFmt(booking.dispatchedAt ?? booking.createdAt)),
        printedRow('Dispatched by', booking.dispatchedByName ?? booking.createdByName),
        printedRow('Driver / Transporter', booking.driverName ?? '-'),
        printedRow('Recipient', booking.bookedForName),
        printedRow('Destination site', booking.projectName ?? '-'),

        sectionHeader('2. Driver/Transporter — Pickup Acknowledgment'),
        ackBox('Pickup'),

        sectionHeader('3. Recipient — Receipt Acknowledgment (on site)'),
        ackBox('Receipt'),

        pw.SizedBox(height: 16),
        pw.Text('Form ID: ${booking.id}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ],
    ),
  );

  final bytes = await doc.save();
  if (!context.mounted) return;
  await _savePdfBytes(context, logger, bytes, 'HandoverForm_${booking.assetName}_${booking.id.substring(0, 6)}.pdf');
}

/// Cross-platform PDF save — mirrors fabrication_form_pdf.dart's
/// _savePdfBytes / daily_report_form_screen.dart's.
Future<void> _savePdfBytes(BuildContext context, Logger logger, Uint8List bytes, String fileName) async {
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
          dirPath = idx > 0 ? parts.sublist(0, idx).join('/') : ext.path;
          dirPath = '$dirPath/Download';
        } else {
          dirPath = (await getApplicationDocumentsDirectory()).path;
        }
      }
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      dirPath = (await getApplicationDocumentsDirectory()).path;
    } else {
      final homeDir = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      dirPath = (homeDir != null && homeDir.isNotEmpty)
          ? '$homeDir${Platform.pathSeparator}Downloads'
          : (await getApplicationDocumentsDirectory()).path;
    }

    final dir = Directory(dirPath);
    if (!await dir.exists()) await dir.create(recursive: true);

    final filePath = '$dirPath${Platform.pathSeparator}$fileName';
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    logger.i('✅ AssetHandoverFormPdf: saved -> $filePath');

    await OpenFile.open(filePath);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Form saved to Downloads: $fileName', style: GoogleFonts.poppins()),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  } catch (e, st) {
    logger.e('❌ AssetHandoverFormPdf: save failed, falling back to share', error: e, stackTrace: st);
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }
}
