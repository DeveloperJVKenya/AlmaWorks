import 'package:flutter/material.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/theme/app_colors.dart';

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
  String? confirmLabel,
  bool isDestructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.cancel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDestructive ? AppColors.danger : AppColors.brand,
            foregroundColor: Colors.white,
          ),
          child: Text(confirmLabel ?? context.l10n.confirm),
        ),
      ],
    ),
  );
  return confirmed == true;
}
