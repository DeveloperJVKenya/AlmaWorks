import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared building blocks for the modernized screens (Notifications and
/// Safety Training): a brighter palette anchored on the app's deep blue,
/// plus responsive layout helpers, cards, pills, stat tiles and empty
/// states — the same patterns as the BrightBrush project (cards with a
/// hairline border and soft shadow, staggered entrances, tinted icon
/// badges), kept in one place so every screen reads as one system.
class AppPalette {
  AppPalette._();

  // Brand — the deep blue used across AlmaWorks, plus brighter steps of it.
  static const deepBlue = Color(0xFF0A2E5A);
  static const royalBlue = Color(0xFF1652A8);
  static const brightBlue = Color(0xFF2F7BF6);
  static const skyBlue = Color(0xFFE8F1FF);

  // Accents — used for categories and statuses, never for large fills.
  static const teal = Color(0xFF0EA5A0);
  static const green = Color(0xFF1E9E61);
  static const amber = Color(0xFFF29F05);
  static const orange = Color(0xFFF2711C);
  static const coral = Color(0xFFE5484D);
  static const violet = Color(0xFF7C5CFF);
  static const pink = Color(0xFFDB3D8B);

  // Neutrals — a light, slightly blue-tinted canvas instead of flat grey.
  static const canvas = Color(0xFFF3F6FC);
  static const surface = Colors.white;
  static const border = Color(0xFFE1E7F2);
  static const ink = Color(0xFF14213D);
  static const inkMuted = Color(0xFF5B6B85);
  static const inkFaint = Color(0xFF8C99AE);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [deepBlue, royalBlue, Color(0xFF2563EB)],
  );
}

/// Screen-width breakpoints shared by the modern screens.
class Breakpoints {
  Breakpoints._();
  static const compact = 600.0;
  static const medium = 900.0;
  static const expanded = 1200.0;

  static bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < compact;

  /// How many columns a card grid should use at [width].
  static int columnsFor(double width, {int max = 3}) {
    if (width >= expanded) return max;
    if (width >= medium) return max >= 2 ? 2 : 1;
    return 1;
  }
}

TextStyle appText(double size, {FontWeight weight = FontWeight.w400, Color color = AppPalette.ink, double? height}) =>
    GoogleFonts.poppins(fontSize: size, fontWeight: weight, color: color, height: height);

/// Centers content at a comfortable reading width on large screens.
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({super.key, required this.child, this.maxWidth = 1100});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// A modern app bar: deep blue with white text, flat, optional subtitle.
PreferredSizeWidget modernAppBar(
  BuildContext context, {
  required String title,
  String? subtitle,
  List<Widget>? actions,
  PreferredSizeWidget? bottom,
}) {
  return AppBar(
    backgroundColor: AppPalette.deepBlue,
    foregroundColor: Colors.white,
    elevation: 0,
    scrolledUnderElevation: 0,
    titleSpacing: 4,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: appText(17, weight: FontWeight.w600, color: Colors.white),
        ),
        if (subtitle != null) Text(subtitle, style: appText(11.5, color: Colors.white.withValues(alpha: 0.75))),
      ],
    ),
    actions: actions,
    bottom: bottom,
  );
}

/// White rounded card with a hairline border and a soft shadow that lifts
/// on hover (desktop/web) — the base surface for every list item.
class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.accent,
    this.highlighted = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Optional colored strip along the left edge (status/category).
  final Color? accent;

  /// Tinted background, e.g. for unread items.
  final bool highlighted;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final lifted = interactive && _hovered;
    return MouseRegion(
      onEnter: interactive ? (_) => setState(() => _hovered = true) : null,
      onExit: interactive ? (_) => setState(() => _hovered = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.translationValues(0, lifted ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: widget.highlighted ? AppPalette.skyBlue : AppPalette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: lifted ? AppPalette.brightBlue.withValues(alpha: 0.35) : AppPalette.border),
          boxShadow: [
            BoxShadow(
              color: AppPalette.deepBlue.withValues(alpha: lifted ? 0.12 : 0.05),
              blurRadius: lifted ? 22 : 12,
              offset: Offset(0, lifted ? 8 : 4),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  Padding(padding: widget.padding, child: widget.child),
                  if (widget.accent != null)
                    Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 4, color: widget.accent)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded square icon on a tint of its own color.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, required this.color, this.size = 42});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// Small rounded status label.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.icon, this.solid = false});

  final String label;
  final Color color;
  final IconData? icon;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final fg = solid ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      // One rich-text run (not a Row with a Flexible): safe inside any
      // parent, and truncates with an ellipsis when space is bounded.
      child: Text.rich(
        TextSpan(
          children: [
            if (icon != null)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(icon, size: 13, color: fg),
                ),
              ),
            TextSpan(text: label),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: appText(11, weight: FontWeight.w600, color: fg),
      ),
    );
  }
}

/// Metric tile — icon, big value, label.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppPalette.brightBlue,
    this.onDark = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  /// Rendered on a dark/gradient background (glass style).
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.12) : AppPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: onDark ? Colors.white.withValues(alpha: 0.18) : AppPalette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: onDark ? Colors.white.withValues(alpha: 0.18) : color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: onDark ? Colors.white : color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appText(18, weight: FontWeight.w700, color: onDark ? Colors.white : AppPalette.ink),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appText(11.5, color: onDark ? Colors.white.withValues(alpha: 0.8) : AppPalette.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lays [children] out in equal-width columns that wrap responsively.
class ResponsiveTiles extends StatelessWidget {
  const ResponsiveTiles({super.key, required this.children, this.minTileWidth = 170, this.spacing = 12});

  final List<Widget> children;
  final double minTileWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = (constraints.maxWidth / (minTileWidth + spacing)).floor().clamp(1, children.length);
        final width = (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final c in children) SizedBox(width: width, child: c)],
        );
      },
    );
  }
}

/// Section heading with optional trailing widget.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: appText(17, weight: FontWeight.w700)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: appText(12.5, color: AppPalette.inkMuted)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Empty / error state for lists.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(color: AppPalette.skyBlue, shape: BoxShape.circle),
                child: Icon(icon, size: 36, color: AppPalette.brightBlue),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: appText(16, weight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: appText(13, color: AppPalette.inkMuted, height: 1.4),
              ),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Fades and slides a list item in, staggered by [index]. Only the first
/// screenful animates; skipped when the platform asks for reduced motion.
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  static const animatedItems = 10;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null || widget.index >= StaggeredEntrance.animatedItems) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    final controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    _controller = controller;
    Future.delayed(Duration(milliseconds: 40 * widget.index), () {
      if (mounted) controller.forward();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;
    final curve = CurvedAnimation(parent: controller, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) => controller.isCompleted
          ? child!
          : FadeTransition(
              opacity: curve,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.05), end: Offset.zero).animate(curve),
                child: child,
              ),
            ),
      child: widget.child,
    );
  }
}

/// Horizontally scrolling choice chips with optional counts.
class FilterChipBar<T> extends StatelessWidget {
  const FilterChipBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.label,
    this.count,
    this.icon,
  });

  final List<T> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final String Function(T) label;
  final int Function(T)? count;
  final IconData Function(T)? icon;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final option in options) Padding(padding: const EdgeInsets.only(right: 8), child: _chip(option)),
        ],
      ),
    );
  }

  Widget _chip(T option) {
    final isSelected = option == selected;
    final n = count?.call(option);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: isSelected ? AppPalette.deepBlue : AppPalette.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: isSelected ? AppPalette.deepBlue : AppPalette.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () => onSelected(option),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon!(option), size: 15, color: isSelected ? Colors.white : AppPalette.inkMuted),
                  const SizedBox(width: 6),
                ],
                Text(
                  label(option),
                  style: appText(12.5, weight: FontWeight.w600, color: isSelected ? Colors.white : AppPalette.ink),
                ),
                if (n != null && n > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white.withValues(alpha: 0.22) : AppPalette.skyBlue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$n',
                      style: appText(
                        11,
                        weight: FontWeight.w700,
                        color: isSelected ? Colors.white : AppPalette.royalBlue,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Primary filled button in the brand blue.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.color = AppPalette.deepBlue,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final Color color;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        disabledBackgroundColor: color.withValues(alpha: 0.35),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          else if (icon != null)
            Icon(icon, size: 18),
          if (loading || icon != null) const SizedBox(width: 10),
          Text(
            label,
            style: appText(14, weight: FontWeight.w600, color: Colors.white),
          ),
        ],
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Gradient hero banner (deep blue → bright blue) with soft decorative
/// circles, used at the top of hub screens.
class HeroPanel extends StatelessWidget {
  const HeroPanel({super.key, required this.child, this.padding = const EdgeInsets.all(22)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppPalette.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: AppPalette.royalBlue.withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(right: -40, top: -50, child: _circle(170, 0.08)),
            Positioned(right: 60, bottom: -70, child: _circle(140, 0.06)),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }

  Widget _circle(double size, double alpha) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: alpha),
    ),
  );
}

/// Shows a floating snackbar in the shared style.
void showAppSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppPalette.coral : AppPalette.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(message, style: appText(13, color: Colors.white)),
      ),
    );
}
