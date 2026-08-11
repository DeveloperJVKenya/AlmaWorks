import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// A file the user picked, with its bytes already loaded and ready to
/// upload — on both web and native.
class PickedUploadFile {
  final String name;
  final Uint8List bytes;

  const PickedUploadFile({required this.name, required this.bytes});

  String get extension => name.contains('.') ? name.split('.').last.toLowerCase() : '';
}

/// Thrown when the platform file picker returned a file but its bytes
/// couldn't be read — the one failure mode this helper exists to prevent
/// from ever reaching an unguarded `!` again.
class FileBytesUnavailableException implements Exception {
  final String fileName;
  const FileBytesUnavailableException(this.fileName);

  @override
  String toString() => 'Could not read file data for "$fileName".';
}

/// Single entry point for "let the user pick one file and hand me its
/// bytes," used by every upload flow in the app (Documents, Drawings,
/// Reports, Financials, Quality & Safety, Schedule, Photo Gallery, etc.).
///
/// Why this exists: `FilePicker.pickFiles()` leaves `PlatformFile.bytes`
/// null on web unless `withData: true` is passed — every upload screen in
/// this app used to set that flag inline, by copying it from whichever
/// screen was written first. reports_screen.dart's upload flow was written
/// (or edited) without it at some point, which is exactly why every upload
/// across all five Reports tabs crashed with "Unexpected null value" on
/// `pickedFile.bytes!` — the flag isn't optional, but nothing enforced
/// that, so it silently regressed once. Routing every upload flow through
/// this one function means `withData: true` (and the web/native bytes
/// split below) only has to be correct in one place, permanently, instead
/// of being re-copied correctly by hand in every new upload screen.
///
/// Returns `null` if the user cancelled the picker. Throws
/// [FileBytesUnavailableException] if a file was picked but its bytes
/// still couldn't be read — callers should catch this specifically (or let
/// it fall into their existing broad `catch (e)`) and show the user a
/// "please try again" message rather than crash.
Future<PickedUploadFile?> pickFileForUpload({
  required List<String> allowedExtensions,
  bool allowMultiple = false,
}) async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
    allowMultiple: allowMultiple,
    withData: true,
  );

  if (result == null || result.files.isEmpty) return null;

  final picked = result.files.first;
  Uint8List? bytes = picked.bytes;

  // Defensive fallback: on native platforms, even if withData somehow
  // didn't populate bytes, the file's on-disk path can still be read
  // directly. On web there is no path to fall back to — bytes must come
  // from withData.
  if (bytes == null && !kIsWeb && picked.path != null) {
    bytes = await File(picked.path!).readAsBytes();
  }

  if (bytes == null) {
    throw FileBytesUnavailableException(picked.name);
  }

  return PickedUploadFile(name: picked.name, bytes: bytes);
}
