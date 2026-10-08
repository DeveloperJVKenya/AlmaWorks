import 'package:flutter/material.dart';

/// Width from which a screen with a section menu shows it as a permanent
/// sidebar; narrower windows (phones, small tablets, split-screen) get a
/// drawer so the content keeps enough room.
const double kSidebarBreakpoint = 900;

/// Width from which the wide (desktop) arrangement is used.
const double kDesktopBreakpoint = 1200;

/// Picks a layout from the space actually available.
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget tablet;
  final Widget desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    required this.tablet,
    required this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < kSidebarBreakpoint) {
          return mobile;
        } else if (constraints.maxWidth < kDesktopBreakpoint) {
          return tablet;
        } else {
          return desktop;
        }
      },
    );
  }
}

/// Gives the content next to a sidebar a MediaQuery whose width is the space
/// it actually has (window minus sidebar). Widgets below choose their
/// phone / tablet / desktop arrangement from `MediaQuery.size.width`, so
/// without this a 1000px window with a 300px sidebar would get a desktop
/// arrangement squeezed into 700px. Dialogs and sheets use the app-level
/// MediaQuery and are unaffected.
class ContentWidthScope extends StatelessWidget {
  const ContentWidthScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(size: Size(constraints.maxWidth, media.size.height)),
        child: child,
      );
    });
  }
}
