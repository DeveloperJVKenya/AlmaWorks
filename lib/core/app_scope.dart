import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

import 'l10n/l10n.dart';
import 'settings/settings_providers.dart';
import 'theme/app_colors.dart';

/// Sits in `MaterialApp.builder`, below the theme and translations and
/// above every route, dialog and sheet. It:
///   * applies the accessibility settings (text size, bold text, high
///     contrast, reduced motion) through MediaQuery, so every Text and
///     every animation that respects the platform setting follows them;
///   * keeps [AppColors] and [l10nNow] in step with what's on screen;
///   * when the appearance or language changes, rebuilds the whole tree in
///     place (no state is lost) so widgets that read AppColors / l10nNow
///     without a BuildContext dependency update too.
class AppearanceScope extends ConsumerStatefulWidget {
  const AppearanceScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppearanceScope> createState() => _AppearanceScopeState();
}

class _AppearanceScopeState extends ConsumerState<AppearanceScope> {
  String? _lastSignature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final highContrast = ref.watch(highContrastProvider);
    final boldText = ref.watch(boldTextProvider);
    final textScale = ref.watch(textScaleProvider);
    final reduceMotion = ref.watch(reduceMotionProvider);

    final dark = theme.brightness == Brightness.dark;
    AppColors.configure(dark: dark, highContrast: highContrast);
    setCurrentL10n(l10n);
    // DateFormat without an explicit locale follows the app language
    // ("12 ott 2026" in Italian).
    Intl.defaultLocale = l10n.localeName;

    final signature = '$dark|$highContrast|${l10n.localeName}|${theme.textTheme.bodyMedium?.fontFamily}';
    if (_lastSignature != null && _lastSignature != signature) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuildDescendants(context as Element);
      });
    }
    _lastSignature = signature;

    final media = MediaQuery.of(context);
    // The app's own size multiplies the device's text-size setting; the
    // clamp keeps the most extreme combinations from breaking layouts.
    final deviceScale = media.textScaler.scale(14) / 14;
    return MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.linear((deviceScale * textScale).clamp(0.8, 2.0)),
        boldText: media.boldText || boldText,
        highContrast: media.highContrast || highContrast,
        disableAnimations: media.disableAnimations || reduceMotion,
      ),
      child: widget.child,
    );
  }

  static void _rebuildDescendants(Element root) {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    root.visitChildren(mark);
  }
}

/// Saves the signed-in user's language on their Users doc
/// (`language: 'en' | 'it'`) so the push-notification Cloud Functions can
/// send each person notifications in their own language. Written only when
/// the user or the language changes.
class LanguageSync extends ConsumerStatefulWidget {
  const LanguageSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LanguageSync> createState() => _LanguageSyncState();
}

class _LanguageSyncState extends ConsumerState<LanguageSync> {
  static final _logger = Logger();
  late final StreamSubscription<User?> _authSub;
  String? _uid;
  String? _synced;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _uid = user?.uid;
      _sync(ref.read(languageProvider));
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  Future<void> _sync(AppLanguage language) async {
    final uid = _uid;
    if (uid == null) return;
    final key = '$uid:${language.code}';
    if (key == _synced) return;
    try {
      // Users docs are keyed by username, so find this user's by uid. (A
      // brand-new account's doc may not exist yet — then nothing is saved
      // and the next change or sign-in tries again.)
      final users = FirebaseFirestore.instance.collection('Users');
      final snap = await users.where('uid', isEqualTo: uid).limit(1).get();
      if (snap.docs.isEmpty) return;
      await snap.docs.first.reference.update({'language': language.code});
      _synced = key;
    } catch (e) {
      _logger.w('Could not save language preference', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(languageProvider, (_, next) => _sync(next));
    return widget.child;
  }
}
