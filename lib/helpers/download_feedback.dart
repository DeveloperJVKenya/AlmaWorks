import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:almaworks/core/errors/friendly_error.dart';
import 'package:almaworks/core/l10n/l10n.dart';

/// Snackbar after [platformDownloadFile] succeeds. [result] is the saved
/// file path on mobile/desktop, or a ready-made message on web.
void showDownloadSuccess(BuildContext context, String result) {
  final l = context.l10n;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(kIsWeb ? result : l.downloadedTo(result)),
      backgroundColor: Colors.green,
      duration: const Duration(seconds: 4),
      action: kIsWeb
          ? null
          : SnackBarAction(
              label: l.open,
              textColor: Colors.white,
              onPressed: () => OpenFile.open(result),
            ),
    ),
  );
}

/// Snackbar for a failed download, in plain language. When storage access
/// was refused it offers a shortcut to the device settings.
void showDownloadError(BuildContext context, Object error) {
  final l = context.l10n;
  final denied = error is StoragePermissionException;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(denied ? error.message : friendlyError(error, action: l.couldNotDownload)),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 4),
      action: denied
          ? SnackBarAction(
              label: l.settings,
              textColor: Colors.white,
              onPressed: openAppSettings,
            )
          : null,
    ),
  );
}
