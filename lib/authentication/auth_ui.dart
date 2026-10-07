// auth_ui.dart
//
// Shared modern UI building blocks for the Login/Registration screens —
// pulled into one file so both screens render with the exact same look,
// motion, and interaction feel, matching the navy brand color already used
// everywhere else in the app (dashboard, communication, inventory:
// Color(0xFF0A2E5A)) rather than the separate, largely-unused AppTheme
// primary color.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:almaworks/core/settings/settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/theme/app_colors.dart';

/// Brand palette — matches base_layout.dart / dashboard_screen.dart / the
/// Communication module, so auth screens feel like the same product rather
/// than a bolted-on template.
class AuthColors {
  AuthColors._();
  static const Color navy = Color(0xFF0A2E5A);
  static const Color navyDeep = Color(0xFF071F3D);
  static const Color accent = Color(0xFF1565C0);
  static const Color accentLight = Color(0xFF4C8DD9);
  static const Color canvas = Color(0xFFDDE2E8);
}

/// Width the form content is capped at regardless of viewport — this is the
/// concrete fix for "input fields too wide on desktop/laptop": every field,
/// button, and heading inside an [AuthFormShell] lives inside this max
/// width, never stretching edge-to-edge on large screens.
const double kAuthFormMaxWidth = 420;

/// Viewport width above which the decorative brand panel appears alongside
/// the form (a two-pane "modern SaaS login" layout on desktop/laptop) rather
/// than stacking above it (phones/narrow tablets).
const double kAuthSplitBreakpoint = 900;

/// Top-level responsive frame shared by Login and Registration: a navy
/// gradient brand panel on wide screens (desktop/laptop), and just the form
/// — centered, width-capped — on narrow ones. Handles the fade+slide
/// entrance animation itself so neither screen has to duplicate an
/// AnimationController.
class AuthResponsiveShell extends StatefulWidget {
  final String brandHeadline;
  final String brandSubtext;
  final IconData brandIcon;
  final Widget form;

  const AuthResponsiveShell({
    super.key,
    required this.brandHeadline,
    required this.brandSubtext,
    required this.brandIcon,
    required this.form,
  });

  @override
  State<AuthResponsiveShell> createState() => _AuthResponsiveShellState();
}

class _AuthResponsiveShellState extends State<AuthResponsiveShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= kAuthSplitBreakpoint;

    final animatedForm = FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.form),
    );

    return Scaffold(
      backgroundColor: AppColors.isDark ? AppColors.canvas : AuthColors.canvas,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _content(isWide, animatedForm)),
            // Language can be changed before signing in, too.
            const Positioned(top: 10, right: 12, child: AuthLanguageSwitcher()),
          ],
        ),
      ),
    );
  }

  Widget _content(bool isWide, Widget animatedForm) {
    return isWide
            ? Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: _BrandPanel(
                      headline: widget.brandHeadline,
                      subtext: widget.brandSubtext,
                      icon: widget.brandIcon,
                    ),
                  ),
                  Expanded(
                    flex: 6,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
                        child: animatedForm,
                      ),
                    ),
                  ),
                ],
              )
            : LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(child: animatedForm),
                  ),
                ),
              );
  }
}

/// Compact language pill (flag + code) with a menu of every language.
class AuthLanguageSwitcher extends ConsumerWidget {
  const AuthLanguageSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(languageProvider);
    return PopupMenuButton<AppLanguage>(
      tooltip: context.l10n.chooseLanguage,
      initialValue: current,
      onSelected: ref.read(languageProvider.notifier).set,
      position: PopupMenuPosition.under,
      itemBuilder: (_) => [
        for (final lang in AppLanguage.values)
          PopupMenuItem(
            value: lang,
            child: Row(
              children: [
                Text(lang.flag, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Text(lang.nativeName),
                if (lang == current) ...[
                  const Spacer(),
                  Icon(Icons.check_rounded, size: 18, color: AppColors.brandInk),
                ],
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(current.flag, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(
              current.code.toUpperCase(),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            Icon(Icons.expand_more_rounded, size: 18, color: AppColors.inkMuted),
          ],
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  final String headline;
  final String subtext;
  final IconData icon;

  const _BrandPanel({required this.headline, required this.subtext, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AuthColors.navyDeep, AuthColors.navy, AuthColors.accent],
        ),
      ),
      child: Stack(
        children: [
          // Soft decorative circles — purely visual, gives the panel depth
          // instead of a flat fill.
          Positioned(
            top: -60,
            right: -60,
            child: _softCircle(220, Colors.white.withValues(alpha: 0.06)),
          ),
          Positioned(
            bottom: -80,
            left: -40,
            child: _softCircle(260, Colors.white.withValues(alpha: 0.05)),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(icon, size: 42, color: Colors.white),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    headline,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    subtext,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.82),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _softCircle(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

/// Width-capped white card that hosts the actual form — this is what keeps
/// fields from stretching edge-to-edge on desktop even inside the wide
/// right-hand pane of [AuthResponsiveShell].
class AuthFormCard extends StatelessWidget {
  final Widget child;
  const AuthFormCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kAuthFormMaxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AuthColors.navy.withValues(alpha: 0.08),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// Text field with an animated focus state — border color, subtle glow, and
/// icon tint all transition smoothly instead of snapping, which is what
/// gives the form its "interactive feel" on both touch and pointer input.
class AuthTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final void Function(String)? onFieldSubmitted;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.validator,
    this.textInputAction,
    this.onFieldSubmitted,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  final _focusNode = FocusNode();

  Color get _accent => AppColors.isDark ? AppColors.brandInk : AuthColors.accent;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() => _focused = _focusNode.hasFocus));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AuthColors.accent.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [],
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        validator: widget.validator,
        textInputAction: widget.textInputAction,
        onFieldSubmitted: widget.onFieldSubmitted,
        style: TextStyle(fontSize: 14.5, color: AppColors.ink),
        cursorColor: AuthColors.accent,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          labelStyle: TextStyle(
            fontSize: 13.5,
            color: _focused ? _accent : AppColors.inkMuted,
            fontWeight: FontWeight.w500,
          ),
          hintStyle: TextStyle(fontSize: 13, color: AppColors.inkFaint),
          prefixIcon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              widget.icon,
              key: ValueKey(_focused),
              color: _focused ? _accent : AppColors.inkFaint,
              size: 21,
            ),
          ),
          suffixIcon: widget.suffixIcon,
          filled: true,
          fillColor: _focused ? AppColors.surface : AppColors.surfaceAlt,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: _accent, width: 1.6),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.red.shade300),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.red.shade400, width: 1.6),
          ),
        ),
      ),
    );
  }
}

/// Primary call-to-action button — scales down under a finger/click (touch
/// feedback), lifts slightly on desktop hover, and cross-fades into a
/// spinner while loading instead of being replaced outright.
class AuthPrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  State<AuthPrimaryButton> createState() => _AuthPrimaryButtonState();
}

class _AuthPrimaryButtonState extends State<AuthPrimaryButton> {
  bool _pressed = false;
  bool _hovered = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: _enabled
                    ? [AuthColors.accent, AuthColors.navy]
                    : [Colors.grey.shade400, Colors.grey.shade400],
              ),
              boxShadow: _enabled && _hovered && !_pressed
                  ? [
                      BoxShadow(
                        color: AuthColors.accent.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : [],
            ),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: widget.isLoading
                  ? const SizedBox(
                      key: ValueKey('loading'),
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      widget.label,
                      key: const ValueKey('label'),
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline error banner — slides/fades in rather than popping into existence,
/// used identically by both screens.
class AuthErrorBanner extends StatelessWidget {
  final String message;
  const AuthErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, (1 - value) * -6), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.dangerTint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A text button that gives a light tactile press-feedback (opacity dip)
/// instead of relying solely on the platform ripple — reads better on both
/// touch and desktop hover.
class AuthLinkButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  const AuthLinkButton({super.key, required this.text, required this.onPressed});

  @override
  State<AuthLinkButton> createState() => _AuthLinkButtonState();
}

class _AuthLinkButtonState extends State<AuthLinkButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onPressed();
        },
        child: AnimatedOpacity(
          opacity: _pressed ? 0.55 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Text(
            widget.text,
            style: TextStyle(
              color: AppColors.isDark ? AppColors.brandInk : AuthColors.accent,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }
}
