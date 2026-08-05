import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared confirmation dialog. Matches the inline `showDialog<bool>` +
/// `AlertDialog` pattern already used throughout the app (see
/// lib/screens/drawings_screen.dart's delete confirmation), extracted here
/// because the Inventory module needs this exact shape at multiple call
/// sites (add asset, checkout, return) and will keep needing it in later
/// phases.
///
/// Returns true if confirmed, false/null if cancelled or dismissed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool isDestructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      content: Text(message, style: GoogleFonts.poppins()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: GoogleFonts.poppins()),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDestructive ? Colors.red : const Color(0xFF0A2E5A),
            foregroundColor: Colors.white,
          ),
          child: Text(confirmLabel, style: GoogleFonts.poppins()),
        ),
      ],
    ),
  );
  return confirmed == true;
}
