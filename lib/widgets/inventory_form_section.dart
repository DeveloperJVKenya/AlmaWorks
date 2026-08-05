import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const inventoryNavy = Color(0xFF0A2E5A);

/// A titled, card-style section used to group related fields on the
/// Inventory module's Add/Record forms — replaces the previous flat list of
/// unrelated fields with a clearer visual hierarchy. The icon renders as a
/// small tinted badge (matching the module's header/card treatment
/// elsewhere — e.g. PendingRequestsScreen) rather than a bare glyph, so each
/// section reads as a distinct, styled block instead of a plain label.
Widget inventoryFormSection({
  required String title,
  IconData? icon,
  String? subtitle,
  required List<Widget> children,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.grey.withValues(alpha: 0.10)),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.045), blurRadius: 14, offset: const Offset(0, 4))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: inventoryNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: inventoryNavy),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: inventoryNavy)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle, style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey[500])),
                    ),
                ],
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1),
        ),
        ...children,
      ],
    ),
  );
}

/// Shared, modern field style for every text/dropdown input across the
/// Inventory module — replaces the flat `filled: grey[50] + borderless
/// OutlineInputBorder` decoration that was repeated (with no focus state at
/// all) inline in every form screen. Gives fields a visible resting border,
/// a navy focus ring, an optional leading icon, and a red error state.
InputDecoration inventoryInputDecoration({
  String? label,
  String? hint,
  IconData? icon,
  bool isDense = false,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    labelText: label,
    isDense: isDense,
    hintText: hint,
    hintStyle: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey[400]),
    labelStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]),
    floatingLabelStyle: GoogleFonts.poppins(fontSize: 13, color: inventoryNavy, fontWeight: FontWeight.w600),
    prefixIcon: icon != null ? Icon(icon, size: 19, color: Colors.grey[500]) : null,
    filled: true,
    fillColor: const Color(0xFFFAFBFC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: border(Colors.grey.withValues(alpha: 0.22)),
    enabledBorder: border(Colors.grey.withValues(alpha: 0.22)),
    focusedBorder: border(inventoryNavy, 1.6),
    errorBorder: border(Colors.red.shade300),
    focusedErrorBorder: border(Colors.red.shade400, 1.6),
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
