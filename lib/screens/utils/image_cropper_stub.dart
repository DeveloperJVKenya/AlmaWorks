import 'dart:typed_data';

import 'package:flutter/material.dart' show BuildContext, Color;

// ─────────────────────────────────────────────────────────────────────────────
// CropAspectRatioPresetData  (abstract base)
// ─────────────────────────────────────────────────────────────────────────────
/// Abstract base that every aspect-ratio preset must implement.
/// Mirrors [image_cropper.CropAspectRatioPresetData].
abstract class CropAspectRatioPresetData {
  /// The (width, height) integer pair for the ratio, or null for "original".
  (int, int)? get data;
}

// ─────────────────────────────────────────────────────────────────────────────
// CropAspectRatioPreset  (built-in presets)
// ─────────────────────────────────────────────────────────────────────────────
/// Built-in aspect-ratio presets.
/// Mirrors [image_cropper.CropAspectRatioPreset].
class CropAspectRatioPreset implements CropAspectRatioPresetData {
  const CropAspectRatioPreset._(this.data);

  @override
  final (int, int)? data;

  /// Keeps the original aspect ratio of the image.
  static const CropAspectRatioPreset original  = CropAspectRatioPreset._(null);

  /// 1 : 1  (square)
  static const CropAspectRatioPreset square    = CropAspectRatioPreset._((1,  1));

  /// 3 : 2
  static const CropAspectRatioPreset ratio3x2  = CropAspectRatioPreset._((3,  2));

  /// 4 : 3
  static const CropAspectRatioPreset ratio4x3  = CropAspectRatioPreset._((4,  3));

  /// 5 : 3
  static const CropAspectRatioPreset ratio5x3  = CropAspectRatioPreset._((5,  3));

  /// 5 : 4
  static const CropAspectRatioPreset ratio5x4  = CropAspectRatioPreset._((5,  4));

  /// 7 : 5
  static const CropAspectRatioPreset ratio7x5  = CropAspectRatioPreset._((7,  5));

  /// 16 : 9
  static const CropAspectRatioPreset ratio16x9 = CropAspectRatioPreset._((16, 9));
}

// ─────────────────────────────────────────────────────────────────────────────
// CropStyle
// ─────────────────────────────────────────────────────────────────────────────
/// The shape of the crop area.
/// Mirrors [image_cropper.CropStyle].
enum CropStyle {
  /// Rectangular crop area (default).
  rectangle,

  /// Circular crop area.
  circle,
}

// ─────────────────────────────────────────────────────────────────────────────
// ImageCompressFormat
// ─────────────────────────────────────────────────────────────────────────────
/// Output file format of the cropped image.
/// Mirrors [image_cropper.ImageCompressFormat].
enum ImageCompressFormat {
  /// JPEG (lossy, smaller file).
  jpg,

  /// PNG (lossless).
  png,
}

// ─────────────────────────────────────────────────────────────────────────────
// CropAspectRatio  (fixed ratio helper)
// ─────────────────────────────────────────────────────────────────────────────
/// A fixed aspect ratio expressed as two doubles.
/// Mirrors [image_cropper.CropAspectRatio].
class CropAspectRatio {
  final double ratioX;
  final double ratioY;
  const CropAspectRatio({required this.ratioX, required this.ratioY});
}

// ─────────────────────────────────────────────────────────────────────────────
// PlatformUiSettings  (abstract base for all platform UI settings)
// ─────────────────────────────────────────────────────────────────────────────
/// Abstract base class for platform-specific UI customisation objects.
/// Mirrors [image_cropper.PlatformUiSettings].
abstract class PlatformUiSettings {}

// ─────────────────────────────────────────────────────────────────────────────
// AndroidUiSettings
// ─────────────────────────────────────────────────────────────────────────────
/// Stub that mirrors [image_cropper.AndroidUiSettings].
///
/// Constructor parameters are accepted and silently discarded — they are never
/// used at runtime on web / desktop.
///
/// Parameter notes (image_cropper ≥ 8.x):
///   • [statusBarColor] is deprecated; use [statusBarLight] instead.
///   • [aspectRatioPresets] is now on AndroidUiSettings (not on cropImage()).
class AndroidUiSettings extends PlatformUiSettings {
  // ignore: use_super_parameters
  AndroidUiSettings({
    String?                         toolbarTitle,
    Color?                          toolbarColor,
    /// Deprecated in image_cropper ≥ 8.x; kept here for source compatibility.
    @Deprecated(
      "This property is deprecated and no longer in use. "
      "Please use 'statusBarLight' instead.",
    )
    Color?                          statusBarColor,
    bool?                           statusBarLight,
    bool?                           navBarLight,
    Color?                          toolbarWidgetColor,
    Color?                          backgroundColor,
    Color?                          activeControlsWidgetColor,
    Color?                          dimmedLayerColor,
    Color?                          cropFrameColor,
    Color?                          cropGridColor,
    int?                            cropFrameStrokeWidth,
    int?                            cropGridRowCount,
    int?                            cropGridColumnCount,
    int?                            cropGridStrokeWidth,
    bool?                           showCropGrid,
    bool?                           lockAspectRatio,
    bool?                           hideBottomControls,
    CropAspectRatioPresetData?      initAspectRatio,
    CropStyle                       cropStyle = CropStyle.rectangle,
    List<CropAspectRatioPresetData> aspectRatioPresets = const [],
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// IOSUiSettings
// ─────────────────────────────────────────────────────────────────────────────
/// Stub that mirrors [image_cropper.IOSUiSettings].
///
/// Constructor parameters are accepted and silently discarded.
class IOSUiSettings extends PlatformUiSettings {
  // ignore: use_super_parameters
  IOSUiSettings({
    String?                         title,
    String?                         doneButtonTitle,
    String?                         cancelButtonTitle,
    bool?                           resetAspectRatioEnabled,
    bool?                           aspectRatioPickerButtonHidden,
    bool?                           rotateButtonsHidden,
    bool?                           rotateClockwiseButtonHidden,
    bool?                           hidesNavigationBar,
    bool?                           showActivitySheetOnDone,
    bool?                           showCancelConfirmationDialog,
    double?                         minimumAspectRatio,
    double?                         rectX,
    double?                         rectY,
    double?                         rectWidth,
    double?                         rectHeight,
    List<CropAspectRatioPresetData> aspectRatioPresets = const [],
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// WebUiSettings
// ─────────────────────────────────────────────────────────────────────────────
/// Stub that mirrors [image_cropper.WebUiSettings].
///
/// Included for completeness; not used by the screen (the in-app
/// _CropDialog is used for web instead).
class WebUiSettings extends PlatformUiSettings {
  // ignore: use_super_parameters
  WebUiSettings({BuildContext? context});
}

// ─────────────────────────────────────────────────────────────────────────────
// CroppedFile
// ─────────────────────────────────────────────────────────────────────────────
/// Stub that mirrors [image_cropper.CroppedFile].
///
/// [readAsBytes] returns an empty [Uint8List]; it is never called on
/// web / desktop because [ImageCropper.cropImage] returns null.
class CroppedFile {
  final String path;
  const CroppedFile(this.path);

  Future<Uint8List> readAsBytes() async => Uint8List(0);
}

// ─────────────────────────────────────────────────────────────────────────────
// ImageCropper
// ─────────────────────────────────────────────────────────────────────────────
/// Stub that mirrors [image_cropper.ImageCropper].
///
/// [cropImage] always returns null on web / desktop; it is guarded by the
/// platform check in _MonthlyReportFormScreenState._cropImage() and will
/// never be reached at runtime.
class ImageCropper {
  /// Stub implementation — always returns null.
  Future<CroppedFile?> cropImage({
    required String sourcePath,
    List<PlatformUiSettings>? uiSettings,
    CropStyle cropStyle          = CropStyle.rectangle,
    ImageCompressFormat compressFormat = ImageCompressFormat.jpg,
    int compressQuality          = 90,
    int? maxWidth,
    int? maxHeight,
    CropAspectRatio? aspectRatio,
  }) async {
    // On web/desktop _cropImage() routes to _showInAppCropper() before
    // reaching here, so this method is dead code on those platforms.
    return null;
  }
}