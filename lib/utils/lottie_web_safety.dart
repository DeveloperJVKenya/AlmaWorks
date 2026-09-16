import 'dart:convert';
import 'dart:typed_data';

/// Bodymovin shape-type codes known to crash Flutter Web's CanvasKit
/// path-extraction code (lazy_path.dart) with an unrecoverable native
/// `Aborted()` — not a catchable Dart error, so `errorBuilder` never fires
/// and the whole page's renderer goes down mid-paint:
///   - `tm` (Trim Path)
///   - `mm` (Merge Paths)
/// Mobile/desktop Skia rendering isn't affected by either.
const _unsafeWebShapeTypes = {'tm', 'mm'};

/// Scans a Lottie (Bodymovin) JSON file for shape types known to crash
/// Flutter Web's CanvasKit renderer. Returns `false` (safe) if the bytes
/// aren't valid/parseable JSON, since a malformed file will simply fail to
/// load rather than crash the renderer.
bool lottieHasUnsafeWebShapes(Uint8List bytes) {
  try {
    final data = jsonDecode(utf8.decode(bytes));
    bool found = false;
    void walk(dynamic node) {
      if (found) return;
      if (node is List) {
        for (final item in node) {
          walk(item);
        }
      } else if (node is Map) {
        if (_unsafeWebShapeTypes.contains(node['ty'])) {
          found = true;
          return;
        }
        for (final value in node.values) {
          walk(value);
        }
      }
    }
    walk(data);
    return found;
  } catch (_) {
    return false;
  }
}
