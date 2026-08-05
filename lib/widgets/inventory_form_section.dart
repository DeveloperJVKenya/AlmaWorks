import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const inventoryNavy = Color(0xFF0A2E5A);

/// A titled, card-style section used to group related fields on the
/// Inventory module's Add/Record forms — replaces the previous flat list of
/// unrelated fields with a clearer visual hierarchy.
Widget inventoryFormSection({
  required String title,
  IconData? icon,
  required List<Widget> children,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: inventoryNavy),
              const SizedBox(width: 6),
            ],
            Text(title, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: inventoryNavy)),
          ],
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
}

/// Wraps form content in a centered, width-capped column so the form
/// doesn't stretch edge-to-edge on wide desktop/web viewports.
Widget inventoryFormMaxWidth({required Widget child}) {
  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: child,
    ),
  );
}

/// Primary submit button for Inventory forms — hugs its content instead of
/// stretching to the full available width, dark navy background with light
/// text/icon per the module's visual convention.
Widget inventoryPrimaryButton({
  required String label,
  required bool isLoading,
  required VoidCallback? onPressed,
  IconData? icon,
  Color? color,
}) {
  return Align(
    alignment: Alignment.centerRight,
    child: ElevatedButton.icon(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? inventoryNavy,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: isLoading
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Icon(icon ?? Icons.check, size: 18),
      label: Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
    ),
  );
}
