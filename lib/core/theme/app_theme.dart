import 'package:flutter/material.dart';

/// Builds the light and dark themes from the Settings choices (font, high
/// contrast, reduced motion). Colors match [AppColors] so widgets that read
/// the theme and widgets that read AppColors agree.
class AppTheme {
  AppTheme._();

  static const Color navy = Color(0xFF0A2E5A);

  static ThemeData light({required String fontFamily, bool highContrast = false, bool reduceMotion = false}) {
    final scheme = ColorScheme.fromSeed(seedColor: navy, brightness: Brightness.light).copyWith(
      primary: navy,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFDCE7F7),
      onPrimaryContainer: const Color(0xFF06204A),
      secondary: const Color(0xFF1652A8),
      surface: Colors.white,
      onSurface: highContrast ? Colors.black : const Color(0xFF14213D),
      onSurfaceVariant: highContrast ? const Color(0xFF2B3445) : const Color(0xFF5B6B85),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF5F7FB),
      surfaceContainer: const Color(0xFFEFF2F8),
      surfaceContainerHigh: const Color(0xFFE8ECF3),
      surfaceContainerHighest: const Color(0xFFE1E6EF),
      outline: highContrast ? const Color(0xFF4A5568) : const Color(0xFFC5CEDC),
      outlineVariant: highContrast ? const Color(0xFF6E7A8E) : const Color(0xFFE1E7F2),
      error: const Color(0xFFD93A3F),
    );
    return _build(scheme, fontFamily, const Color(0xFFF3F6FC), reduceMotion);
  }

  static ThemeData dark({required String fontFamily, bool highContrast = false, bool reduceMotion = false}) {
    final scheme = ColorScheme.fromSeed(seedColor: navy, brightness: Brightness.dark).copyWith(
      primary: const Color(0xFF8FB8F5),
      onPrimary: const Color(0xFF06204A),
      primaryContainer: const Color(0xFF1A3A66),
      onPrimaryContainer: const Color(0xFFDCE7F7),
      secondary: const Color(0xFF9EC3FF),
      surface: highContrast ? const Color(0xFF0B0F14) : const Color(0xFF151C26),
      onSurface: highContrast ? Colors.white : const Color(0xFFE8EDF5),
      onSurfaceVariant: highContrast ? const Color(0xFFD5DCE6) : const Color(0xFFA7B3C5),
      surfaceContainerLowest: const Color(0xFF0D1219),
      surfaceContainerLow: const Color(0xFF1B2430),
      surfaceContainer: const Color(0xFF1F2936),
      surfaceContainerHigh: const Color(0xFF253041),
      surfaceContainerHighest: const Color(0xFF2C384A),
      outline: highContrast ? const Color(0xFFB4BECC) : const Color(0xFF3A4658),
      outlineVariant: highContrast ? const Color(0xFF8C98AC) : const Color(0xFF2A3546),
      error: const Color(0xFFFF6B6E),
    );
    return _build(scheme, fontFamily, highContrast ? Colors.black : const Color(0xFF0D1219), reduceMotion);
  }

  static ThemeData _build(ColorScheme scheme, String fontFamily, Color canvas, bool reduceMotion) {
    final isDark = scheme.brightness == Brightness.dark;
    final rounded14 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);
    final brandFill = isDark ? const Color(0xFF2D63AE) : navy;

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: canvas,
      canvasColor: scheme.surface,
      dividerColor: scheme.outlineVariant,
      pageTransitionsTheme: reduceMotion
          ? PageTransitionsTheme(
              builders: {for (final p in TargetPlatform.values) p: const _NoTransitionsBuilder()},
            )
          : const PageTransitionsTheme(),
      appBarTheme: AppBarTheme(
        // Navy in both modes: it's the AlmaWorks brand bar, and it always
        // carries white content.
        backgroundColor: isDark ? const Color(0xFF0B2240) : navy,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: isDark ? 0 : 1.5,
        shadowColor: navy.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: isDark ? BorderSide(color: scheme.outlineVariant) : BorderSide.none,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2A3546) : const Color(0xFF14213D),
        contentTextStyle: TextStyle(fontFamily: fontFamily, color: Colors.white, fontSize: 14),
        actionTextColor: const Color(0xFF9EC3FF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandFill,
          foregroundColor: Colors.white,
          shape: rounded14,
          padding: buttonPadding,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brandFill,
          foregroundColor: Colors.white,
          shape: rounded14,
          padding: buttonPadding,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? scheme.primary : navy,
          side: BorderSide(color: isDark ? scheme.outline : navy),
          shape: rounded14,
          padding: buttonPadding,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: isDark ? scheme.primary : navy),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1B2430) : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: scheme.outline)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? brandFill : null),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: brandFill,
        thumbColor: brandFill,
        inactiveTrackColor: scheme.outlineVariant,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: isDark ? scheme.primary : navy),
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C384A) : const Color(0xFF14213D),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(fontFamily: fontFamily, color: Colors.white, fontSize: 12),
      ),
    );
  }
}

class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
