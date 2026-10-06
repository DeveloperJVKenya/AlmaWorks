import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:lottie/lottie.dart' show LottieImageAsset;

/// A raster image a Lottie (Bodymovin) animation references as a separate
/// file (`"u": "images/", "p": "img_0.png"`) instead of embedding it as a
/// `data:` URI.
class LinkedLottieImage {
  final String id;
  final String fileName;
  const LinkedLottieImage({required this.id, required this.fileName});
}

/// Lists the image assets [bytes] links to externally. Only the `.json` is
/// uploaded to Storage, and an uploaded animation's sibling files can't be
/// resolved from its tokenized download URL anyway — so any linked image
/// would silently never render. Returns an empty list for unparseable JSON
/// (which simply fails to load later).
List<LinkedLottieImage> lottieLinkedImages(Uint8List bytes) {
  try {
    final data = jsonDecode(utf8.decode(bytes));
    final assets = data is Map ? data['assets'] : null;
    if (assets is! List) return const [];
    return [
      for (final asset in assets)
        if (asset is Map && asset['p'] is String && !(asset['p'] as String).startsWith('data:'))
          LinkedLottieImage(id: '${asset['id']}', fileName: asset['p'] as String),
    ];
  } catch (_) {
    return const [];
  }
}

/// Rewrites [bytes] with every linked image whose file name is a key of
/// [filesByName] embedded as a base64 `data:` URI, so the animation is a
/// single self-contained file. Unmatched images are left as they were.
Uint8List embedLottieImages(Uint8List bytes, Map<String, Uint8List> filesByName) {
  final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  final assets = data['assets'];
  if (assets is List) {
    for (final asset in assets) {
      if (asset is! Map) continue;
      final fileName = asset['p'];
      if (fileName is! String || fileName.startsWith('data:')) continue;
      final fileBytes = filesByName[fileName];
      if (fileBytes == null) continue;
      asset['u'] = '';
      asset['p'] = 'data:${_imageMimeType(fileName)};base64,${base64Encode(fileBytes)}';
      asset['e'] = 1;
    }
  }
  return Uint8List.fromList(utf8.encode(jsonEncode(data)));
}

String _imageMimeType(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/png';
}

// 1×1 fully transparent PNG.
final _transparentPixel = MemoryImage(
  base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII='),
);

/// `imageProviderFactory` for scenario animations. Lottie resolves
/// embedded `data:` images itself before ever calling this, so it's only
/// reached for a *linked* image — which, for animations uploaded before
/// the author form started embedding them, doesn't exist anywhere
/// reachable. Render that layer blank rather than firing a doomed request
/// (Lottie.network) or a missing-asset lookup (Lottie.memory) per frame
/// load.
ImageProvider? unresolvedLottieImage(LottieImageAsset asset) => _transparentPixel;
