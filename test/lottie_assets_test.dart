import 'dart:convert';
import 'dart:typed_data';

import 'package:almaworks/utils/lottie_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

Uint8List _animation(List<Map<String, dynamic>> assets) => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'v': '5.7.4',
      'fr': 30,
      'ip': 0,
      'op': 30,
      'w': 100,
      'h': 100,
      'assets': assets,
      'layers': <dynamic>[],
    }),
  ),
);

void main() {
  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  );

  test('finds linked images, ignoring embedded images and precomps', () {
    final bytes = _animation([
      {'id': 'image_0', 'w': 1, 'h': 1, 'u': 'images/', 'p': 'img_0.png', 'e': 0},
      {'id': 'image_1', 'w': 1, 'h': 1, 'u': '', 'p': 'data:image/png;base64,AAAA', 'e': 1},
      {'id': 'comp_0', 'layers': <dynamic>[]},
    ]);
    final linked = lottieLinkedImages(bytes);
    expect(linked.map((l) => l.fileName), ['img_0.png']);
  });

  test('returns no linked images for invalid JSON', () {
    expect(lottieLinkedImages(Uint8List.fromList(utf8.encode('not json'))), isEmpty);
  });

  test('embeds matched images as data URIs and leaves the rest', () {
    final bytes = _animation([
      {'id': 'image_0', 'w': 1, 'h': 1, 'u': 'images/', 'p': 'img_0.png', 'e': 0},
      {'id': 'image_1', 'w': 1, 'h': 1, 'u': 'images/', 'p': 'photo.jpg', 'e': 0},
    ]);
    final embedded = embedLottieImages(bytes, {'img_0.png': pngBytes});
    final assets = (jsonDecode(utf8.decode(embedded)) as Map)['assets'] as List;
    expect(assets[0]['p'], 'data:image/png;base64,${base64Encode(pngBytes)}');
    expect(assets[0]['u'], '');
    expect(assets[0]['e'], 1);
    expect(assets[1]['p'], 'photo.jpg');
    expect(lottieLinkedImages(embedded).map((l) => l.fileName), ['photo.jpg']);
  });

  test('embedded animation parses with the image resolved from its data URI', () async {
    final bytes = _animation([
      {'id': 'image_0', 'w': 1, 'h': 1, 'u': 'images/', 'p': 'img_0.png', 'e': 0},
    ]);
    final composition = await LottieComposition.fromBytes(embedLottieImages(bytes, {'img_0.png': pngBytes}));
    expect(composition.images['image_0']!.fileName, startsWith('data:image/png;base64,'));
  });
}
