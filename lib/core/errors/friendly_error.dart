import 'dart:async';
import 'dart:io' show SocketException, HttpException;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_colors.dart';

/// An error whose message is already written for the person using the app
/// (and already translated) — e.g. "This tool is booked from 3 to 5 May".
/// [friendlyError] shows its message as-is.
class UserFacingException implements Exception {
  const UserFacingException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The device refused storage access, so a download couldn't be saved.
/// Screens offer an "Open settings" action for this one.
class StoragePermissionException extends UserFacingException {
  StoragePermissionException() : super(l10nNow.storagePermissionDenied);
}

/// Turns any error into a short, plain-language sentence for the screen.
/// Raw exception text (codes, stack details, "Exception: …") is never shown
/// — callers still log the original error for diagnosis.
///
/// With [action] ("Couldn't save the report.") the reason is appended:
/// "Couldn't save the report. Check your internet connection and try again."
String friendlyError(Object error, {String? action}) {
  final reason = _reason(error);
  if (action == null) return reason ?? l10nNow.errGeneric;
  return '$action ${reason ?? l10nNow.errTryAgain}';
}

String? _reason(Object error) {
  final l = l10nNow;
  if (error is UserFacingException) return error.message;

  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return l.errWrongCredentials;
      case 'invalid-email':
        return l.errInvalidEmail;
      case 'email-already-in-use':
        return l.errEmailInUse;
      case 'weak-password':
        return l.errWeakPassword;
      case 'too-many-requests':
        return l.errTooManyAttempts;
      case 'user-disabled':
        return l.errAccountDisabled;
      case 'network-request-failed':
        return l.errNetwork;
      case 'requires-recent-login':
        return l.errSignInAgain;
    }
  }

  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthorized':
        return l.errNoPermission;
      case 'unauthenticated':
      case 'unauthorized-app':
        return l.errSignInAgain;
      case 'unavailable':
      case 'network-request-failed':
        return l.errNetwork;
      case 'deadline-exceeded':
      case 'retry-limit-exceeded':
        return l.errTimeout;
      case 'not-found':
      case 'object-not-found':
        return l.errNotFound;
      case 'already-exists':
        return l.errAlreadyExists;
      case 'resource-exhausted':
        return l.errBusy;
      case 'quota-exceeded':
        return l.errStorageFull;
      case 'cancelled':
      case 'canceled':
        return l.errCancelled;
      case 'invalid-argument':
        return l.errInvalidData;
    }
  }

  if (error is TimeoutException) return l.errTimeout;
  if (error is SocketException || error is HttpException) return l.errNetwork;

  // Errors from packages that don't share a type (http, dio, platform
  // channels) are recognised by their text.
  final raw = error.toString().toLowerCase();
  if (raw.contains('permission-denied') || raw.contains('permission denied')) return l.errNoPermission;
  if (raw.contains('socketexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('network') ||
      raw.contains('connection')) {
    return l.errNetwork;
  }
  if (raw.contains('timeout') || raw.contains('timed out')) return l.errTimeout;
  return null;
}

// ── Snackbars ─────────────────────────────────────────────────────────────────

/// Error snackbar with a plain-language message for [error].
void showErrorSnack(BuildContext context, Object error, {String? action}) =>
    _show(context, friendlyError(error, action: action), _SnackKind.error);

/// Error snackbar with a message you've already written.
void showErrorMessage(BuildContext context, String message) => _show(context, message, _SnackKind.error);

void showSuccessSnack(BuildContext context, String message) => _show(context, message, _SnackKind.success);

void showInfoSnack(BuildContext context, String message) => _show(context, message, _SnackKind.info);

void showWarningSnack(BuildContext context, String message) => _show(context, message, _SnackKind.warning);

enum _SnackKind { success, error, info, warning }

void _show(BuildContext context, String message, _SnackKind kind) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final (icon, color) = switch (kind) {
    _SnackKind.success => (Icons.check_circle_rounded, const Color(0xFF1E8E55)),
    _SnackKind.error => (Icons.error_rounded, const Color(0xFFD93A3F)),
    _SnackKind.warning => (Icons.warning_amber_rounded, const Color(0xFFC77700)),
    _SnackKind.info => (Icons.info_rounded, AppColors.isDark ? const Color(0xFF2A3546) : const Color(0xFF14213D)),
  };
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: color,
        duration: Duration(seconds: kind == _SnackKind.error ? 5 : 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
}
