import 'package:flutter/material.dart';

/// Theme-aware colors for screens that paint their own surfaces and text
/// instead of reading `Theme.of(context)` — which is most of AlmaWorks.
///
/// The getters follow the appearance chosen in Settings (light / dark /
/// high contrast). [AppearanceScope] (lib/core/app_scope.dart) calls
/// [configure] whenever that changes and then rebuilds the whole widget
/// tree, so even widgets that read these without a `BuildContext` pick up
/// the new values.
///
/// Rule of thumb when painting:
///   * page background → [canvas]; cards/sheets → [surface];
///     subtle fills (grey[50]/grey[100]) → [surfaceAlt] / [surfaceMuted]
///   * text → [ink] / [inkMuted] / [inkFaint]
///   * brand navy as a FILL (app bars, buttons, headers) → [brand];
///     as TEXT or an ICON on a surface → [brandInk]
///   * light status backgrounds → the matching `*Tint`
class AppColors {
  AppColors._();

  static bool _dark = false;
  static bool _highContrast = false;

  static bool get isDark => _dark;
  static bool get isHighContrast => _highContrast;

  /// Returns true when anything changed.
  static bool configure({required bool dark, required bool highContrast}) {
    if (_dark == dark && _highContrast == highContrast) return false;
    _dark = dark;
    _highContrast = highContrast;
    return true;
  }

  static Color _pick(Color light, Color dark, {Color? hcLight, Color? hcDark}) {
    if (_dark) return _highContrast ? (hcDark ?? dark) : dark;
    return _highContrast ? (hcLight ?? light) : light;
  }

  // ── Brand ────────────────────────────────────────────────────────────────
  /// The AlmaWorks navy, unchanged in every mode — for app bars, headers,
  /// footers and other large brand fills that always carry white content.
  static const Color navy = Color(0xFF0A2E5A);

  /// Brand fill for buttons, chips and selected states on a surface.
  static Color get brand => _pick(navy, const Color(0xFF2D63AE), hcDark: const Color(0xFF3B74C4));

  /// Brand color for text and icons drawn on [surface] / [canvas].
  static Color get brandInk =>
      _pick(navy, const Color(0xFF8FB8F5), hcLight: const Color(0xFF06204A), hcDark: const Color(0xFFB9D3FF));

  /// Pale brand wash behind brand-colored text (badges, selected rows).
  static Color get brandTint => _pick(const Color(0xFFE8EEF6), const Color(0xFF1A2A42));

  static const Color onBrand = Colors.white;

  // ── Surfaces ─────────────────────────────────────────────────────────────
  static Color get canvas => _pick(const Color(0xFFF3F6FC), const Color(0xFF0D1219), hcDark: Colors.black);
  static Color get surface => _pick(Colors.white, const Color(0xFF151C26), hcDark: const Color(0xFF0B0F14));
  static Color get surfaceAlt => _pick(const Color(0xFFF5F7FB), const Color(0xFF1B2430));
  static Color get surfaceMuted => _pick(const Color(0xFFECEFF4), const Color(0xFF232D3B));
  static Color get border =>
      _pick(const Color(0xFFE1E7F2), const Color(0xFF2A3546), hcLight: const Color(0xFF6E7A8E), hcDark: const Color(0xFF8C98AC));
  static Color get divider =>
      _pick(const Color(0xFFE6EAF0), const Color(0xFF253042), hcLight: const Color(0xFF8E98A8), hcDark: const Color(0xFF6E7A8E));

  /// Drop-shadow color — softer on dark, where shadows barely read.
  static Color get shadow => _dark ? Colors.black.withValues(alpha: 0.45) : navy.withValues(alpha: 0.08);

  // ── Text ─────────────────────────────────────────────────────────────────
  static Color get ink => _pick(const Color(0xFF14213D), const Color(0xFFE8EDF5), hcLight: Colors.black, hcDark: Colors.white);
  static Color get inkMuted =>
      _pick(const Color(0xFF5B6B85), const Color(0xFFA7B3C5), hcLight: const Color(0xFF2B3445), hcDark: const Color(0xFFD5DCE6));
  static Color get inkFaint =>
      _pick(const Color(0xFF8C99AE), const Color(0xFF7A879B), hcLight: const Color(0xFF4A5568), hcDark: const Color(0xFFB4BECC));

  // ── Status ───────────────────────────────────────────────────────────────
  static Color get success => _pick(const Color(0xFF1E8E55), const Color(0xFF4CC38A));
  static Color get danger => _pick(const Color(0xFFD93A3F), const Color(0xFFFF6B6E));
  static Color get warning => _pick(const Color(0xFFC77700), const Color(0xFFF5B240));
  static Color get info => _pick(const Color(0xFF2F6FD6), const Color(0xFF6FA3FF));

  static Color get successTint => _pick(const Color(0xFFE8F6EE), const Color(0xFF12301F));
  static Color get dangerTint => _pick(const Color(0xFFFDECEC), const Color(0xFF3A1A1C));
  static Color get warningTint => _pick(const Color(0xFFFFF4E0), const Color(0xFF3A2C10));
  static Color get infoTint => _pick(const Color(0xFFE8F1FF), const Color(0xFF15263F));
}
