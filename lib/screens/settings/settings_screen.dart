import 'package:almaworks/core/errors/friendly_error.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/settings/app_font.dart';
import 'package:almaworks/core/settings/settings_providers.dart';
import 'package:almaworks/core/theme/app_colors.dart';
import 'package:almaworks/widgets/modern/modern_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The parts of Settings another screen can open straight to.
enum SettingsSection { appearance, accessibility, language, notifications, about }

/// Personal display preferences — theme, font, text size, accessibility,
/// language and on-device alerts. Every choice applies instantly (the live
/// preview shows it) and is remembered on this device.
///
/// Wide screens get a sticky section menu and the preview beside the
/// content; phones get one scrolling column with jump chips at the top.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.initialSection});

  final SettingsSection? initialSection;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _wideBreakpoint = 960.0;

  final _sectionKeys = {for (final s in SettingsSection.values) s: GlobalKey()};
  late SettingsSection _current = widget.initialSection ?? SettingsSection.appearance;

  @override
  void initState() {
    super.initState();
    if (widget.initialSection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(widget.initialSection!));
    }
  }

  void _jumpTo(SettingsSection section) {
    setState(() => _current = section);
    final ctx = _sectionKeys[section]!.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: modernAppBar(context, title: l.settings, subtitle: l.settingsSubtitle),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _wideBreakpoint;
          final sections = _sections(context, wide: wide);
          if (!wide) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _SectionChips(current: _current, onSelected: _jumpTo),
                const SizedBox(height: 16),
                ...sections,
              ],
            );
          }
          return ResponsiveCenter(
            maxWidth: 1180,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 300,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SectionMenu(current: _current, onSelected: _jumpTo),
                          const SizedBox(height: 16),
                          const _LivePreview(),
                          const SizedBox(height: 12),
                          _SavedNote(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: ListView(padding: const EdgeInsets.only(bottom: 32), children: sections),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _sections(BuildContext context, {required bool wide}) {
    Widget gap() => const SizedBox(height: 18);
    return [
      _AppearanceSection(key: _sectionKeys[SettingsSection.appearance], showPreview: !wide),
      gap(),
      _AccessibilitySection(key: _sectionKeys[SettingsSection.accessibility]),
      gap(),
      _LanguageSection(key: _sectionKeys[SettingsSection.language]),
      gap(),
      _NotificationsSection(key: _sectionKeys[SettingsSection.notifications]),
      gap(),
      _AboutSection(key: _sectionKeys[SettingsSection.about]),
      if (!wide) ...[const SizedBox(height: 12), _SavedNote()],
    ];
  }
}

// ── Section metadata ─────────────────────────────────────────────────────────

extension on SettingsSection {
  String label(AppLocalizations l) => switch (this) {
    SettingsSection.appearance => l.appearance,
    SettingsSection.accessibility => l.accessibility,
    SettingsSection.language => l.language,
    SettingsSection.notifications => l.notifications,
    SettingsSection.about => l.about,
  };

  IconData get icon => switch (this) {
    SettingsSection.appearance => Icons.palette_rounded,
    SettingsSection.accessibility => Icons.accessibility_new_rounded,
    SettingsSection.language => Icons.translate_rounded,
    SettingsSection.notifications => Icons.notifications_active_rounded,
    SettingsSection.about => Icons.info_rounded,
  };

  Color get color => switch (this) {
    SettingsSection.appearance => AppPalette.violet,
    SettingsSection.accessibility => AppPalette.teal,
    SettingsSection.language => AppPalette.brightBlue,
    SettingsSection.notifications => AppPalette.orange,
    SettingsSection.about => AppPalette.inkMuted,
  };
}

/// Phone: horizontally scrolling chips that jump to a section.
class _SectionChips extends StatelessWidget {
  const _SectionChips({required this.current, required this.onSelected});

  final SettingsSection current;
  final ValueChanged<SettingsSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChipBar<SettingsSection>(
      options: SettingsSection.values,
      selected: current,
      onSelected: onSelected,
      label: (s) => s.label(context.l10n),
      icon: (s) => s.icon,
    );
  }
}

/// Wide screens: vertical section menu.
class _SectionMenu extends StatelessWidget {
  const _SectionMenu({required this.current, required this.onSelected});

  final SettingsSection current;
  final ValueChanged<SettingsSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          for (final s in SettingsSection.values)
            _MenuItem(section: s, selected: s == current, onTap: () => onSelected(s)),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.section, required this.selected, required this.onTap});

  final SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.brandTint : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                IconBadge(icon: section.icon, color: section.color, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.label(context.l10n),
                    style: appText(
                      14,
                      weight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.brandInk : AppColors.ink,
                    ),
                  ),
                ),
                if (selected) Icon(Icons.chevron_right_rounded, color: AppColors.brandInk),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.cloud_done_rounded, size: 16, color: AppColors.inkFaint),
        const SizedBox(width: 8),
        Expanded(
          child: Text(context.l10n.settingsSavedAutomatically, style: appText(12, color: AppColors.inkFaint)),
        ),
      ],
    );
  }
}

// ── Building blocks ──────────────────────────────────────────────────────────

/// A settings group: icon badge, title, one-line explanation, then content.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.section, required this.hint, required this.children});

  final SettingsSection section;
  final String hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(icon: section.icon, color: section.color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(section.label(context.l10n), style: appText(17, weight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 2),
                    Text(hint, style: appText(12.5, color: AppColors.inkMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

/// Small heading inside a card ("Theme", "Font", "Text size").
class _Label extends StatelessWidget {
  const _Label(this.text, {this.hint});

  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: appText(14, weight: FontWeight.w600)),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!, style: appText(12, color: AppColors.inkMuted)),
          ],
        ],
      ),
    );
  }
}

/// A tappable card that shows a check when chosen.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.selected, required this.onTap, required this.child, this.semanticLabel});

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: semanticLabel,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandTint : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.brand : AppColors.border, width: selected ? 2 : 1),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Stack(
              children: [
                child,
                if (selected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(Icons.check_circle_rounded, size: 20, color: AppColors.brand),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon, title, explanation and a switch — the whole row is tappable.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              IconBadge(icon: icon, color: color, size: 38),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: appText(14, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(hint, style: appText(12, color: AppColors.inkMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Appearance ───────────────────────────────────────────────────────────────

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection({super.key, required this.showPreview});

  final bool showPreview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final mode = ref.watch(themeModeProvider);
    final font = ref.watch(appFontProvider);
    final setMode = ref.read(themeModeProvider.notifier).set;

    return _SettingsCard(
      section: SettingsSection.appearance,
      hint: l.appearanceHint,
      children: [
        if (showPreview) ...[const _LivePreview(), const SizedBox(height: 20)],
        _Label(l.theme),
        ResponsiveTiles(
          minTileWidth: 150,
          children: [
            for (final (m, title, hint) in [
              (ThemeMode.system, l.themeSystem, l.themeSystemHint),
              (ThemeMode.light, l.themeLight, l.themeLightHint),
              (ThemeMode.dark, l.themeDark, l.themeDarkHint),
            ])
              _ChoiceCard(
                selected: mode == m,
                onTap: () => setMode(m),
                semanticLabel: '$title. $hint',
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ThemeMockup(mode: m),
                      const SizedBox(height: 10),
                      Text(title, style: appText(14, weight: FontWeight.w600)),
                      Text(hint, style: appText(11.5, color: AppColors.inkMuted)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        _Label(l.font, hint: l.fontHint),
        ResponsiveTiles(
          minTileWidth: 200,
          children: [
            for (final f in AppFont.values)
              _ChoiceCard(
                selected: font == f,
                onTap: () => ref.read(appFontProvider.notifier).set(f),
                semanticLabel: '${f.label}. ${_fontDescription(l, f)}',
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 30, 12),
                  child: Row(
                    children: [
                      Text(
                        'Aa',
                        style: TextStyle(fontFamily: f.fontFamily, fontSize: 26, fontWeight: FontWeight.w600, color: AppColors.brandInk),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: f.fontFamily, fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.ink),
                            ),
                            Text(
                              _fontDescription(l, f),
                              style: TextStyle(fontFamily: f.fontFamily, fontSize: 11.5, color: AppColors.inkMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  static String _fontDescription(AppLocalizations l, AppFont f) => switch (f) {
    AppFont.poppins => l.fontPoppinsDesc,
    AppFont.inter => l.fontInterDesc,
    AppFont.roboto => l.fontRobotoDesc,
    AppFont.openSans => l.fontOpenSansDesc,
    AppFont.nunito => l.fontNunitoDesc,
    AppFont.atkinson => l.fontAtkinsonDesc,
    AppFont.merriweather => l.fontMerriweatherDesc,
  };
}

/// A tiny drawing of a screen in light, dark, or half-and-half (system).
class _ThemeMockup extends StatelessWidget {
  const _ThemeMockup({required this.mode});

  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    Widget half(bool dark) {
      final bg = dark ? const Color(0xFF0D1219) : const Color(0xFFF3F6FC);
      final card = dark ? const Color(0xFF1B2430) : Colors.white;
      final line = dark ? const Color(0xFF3A4658) : const Color(0xFFDCE3EE);
      return Container(
        color: bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 12, color: dark ? const Color(0xFF0B2240) : AppColors.navy),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(5)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 4, width: 34, color: line),
                    const SizedBox(height: 4),
                    Container(height: 4, width: 22, color: line),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 62,
          child: switch (mode) {
            ThemeMode.light => half(false),
            ThemeMode.dark => half(true),
            ThemeMode.system => Row(
              children: [
                Expanded(child: half(false)),
                Expanded(child: half(true)),
              ],
            ),
          },
        ),
      ),
    );
  }
}

/// Shows the current choices on a realistic card.
class _LivePreview extends StatelessWidget {
  const _LivePreview();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_rounded, size: 16, color: AppColors.inkMuted),
              const SizedBox(width: 6),
              Text(l.preview.toUpperCase(), style: appText(11, weight: FontWeight.w700, color: AppColors.inkMuted)),
            ],
          ),
          const SizedBox(height: 10),
          AppCard(
            padding: const EdgeInsets.all(14),
            accent: AppPalette.green,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const IconBadge(icon: Icons.construction_rounded, color: AppPalette.brightBlue, size: 36),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l.previewTitle, style: appText(14.5, weight: FontWeight.w600))),
                  ],
                ),
                const SizedBox(height: 10),
                Text(l.previewBody, style: appText(13, color: AppColors.inkMuted, height: 1.4)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusPill(label: l.previewStatus, color: AppPalette.green, icon: Icons.check_rounded),
                    FilledButton(
                      onPressed: () {},
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(l.previewAction),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Accessibility ────────────────────────────────────────────────────────────

class _AccessibilitySection extends ConsumerWidget {
  const _AccessibilitySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final scale = ref.watch(textScaleProvider);
    final setScale = ref.read(textScaleProvider.notifier).set;
    final presets = [
      (0.9, l.textSizeSmall),
      (TextScaleController.standard, l.textSizeDefault),
      (1.15, l.textSizeLarge),
      (1.3, l.textSizeExtraLarge),
    ];

    return _SettingsCard(
      section: SettingsSection.accessibility,
      hint: l.accessibilityHint,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _Label(l.textSize, hint: l.textSizeHint)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(20)),
              child: Text(
                '${(scale * 100).round()}%',
                style: appText(12.5, weight: FontWeight.w700, color: AppColors.brandInk),
              ),
            ),
          ],
        ),
        Row(
          children: [
            ExcludeSemantics(child: Text('A', style: appText(13, color: AppColors.inkMuted))),
            Expanded(
              child: Slider(
                value: scale,
                min: TextScaleController.min,
                max: TextScaleController.max,
                divisions: 11,
                label: '${(scale * 100).round()}%',
                semanticFormatterCallback: (v) => '${l.textSize} ${(v * 100).round()}%',
                onChanged: setScale,
              ),
            ),
            ExcludeSemantics(child: Text('A', style: appText(22, weight: FontWeight.w600, color: AppColors.inkMuted))),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (value, label) in presets)
              ChoiceChip(
                label: Text(label),
                selected: (scale - value).abs() < 0.001,
                onSelected: (_) => setScale(value),
                selectedColor: AppColors.brandTint,
                labelStyle: appText(12.5, weight: FontWeight.w600, color: AppColors.ink),
                side: BorderSide(color: (scale - value).abs() < 0.001 ? AppColors.brand : AppColors.border),
              ),
          ],
        ),
        Divider(height: 32, color: AppColors.divider),
        _SwitchRow(
          icon: Icons.format_bold_rounded,
          color: AppPalette.brightBlue,
          title: l.boldText,
          hint: l.boldTextHint,
          value: ref.watch(boldTextProvider),
          onChanged: ref.read(boldTextProvider.notifier).set,
        ),
        _SwitchRow(
          icon: Icons.contrast_rounded,
          color: AppPalette.violet,
          title: l.highContrast,
          hint: l.highContrastHint,
          value: ref.watch(highContrastProvider),
          onChanged: ref.read(highContrastProvider.notifier).set,
        ),
        _SwitchRow(
          icon: Icons.animation_rounded,
          color: AppPalette.teal,
          title: l.reduceMotion,
          hint: l.reduceMotionHint,
          value: ref.watch(reduceMotionProvider),
          onChanged: ref.read(reduceMotionProvider.notifier).set,
        ),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(l.resetDisplaySettings),
            onPressed: () {
              resetDisplaySettings(ref);
              showSuccessSnack(context, l.resetDisplaySettingsDone);
            },
          ),
        ),
      ],
    );
  }
}

// ── Language ─────────────────────────────────────────────────────────────────

class _LanguageSection extends ConsumerWidget {
  const _LanguageSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final current = ref.watch(languageProvider);

    return _SettingsCard(
      section: SettingsSection.language,
      hint: l.languageHint,
      children: [
        ResponsiveTiles(
          minTileWidth: 220,
          children: [
            for (final lang in AppLanguage.values)
              _ChoiceCard(
                selected: current == lang,
                semanticLabel: lang.nativeName,
                onTap: () {
                  if (current == lang) return;
                  ref.read(languageProvider.notifier).set(lang);
                  // Confirm in the language just picked.
                  showSuccessSnack(context, l10nFor(lang).languageChanged(lang.nativeName));
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 34, 14),
                  child: Row(
                    children: [
                      ExcludeSemantics(child: Text(lang.flag, style: const TextStyle(fontSize: 30))),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(lang.nativeName, style: appText(15, weight: FontWeight.w600)),
                            Text(
                              lang.code.toUpperCase(),
                              style: appText(11.5, weight: FontWeight.w600, color: AppColors.inkFaint),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.infoTint, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Icon(Icons.notifications_rounded, size: 18, color: AppColors.info),
              const SizedBox(width: 10),
              Expanded(child: Text(l.languageNotificationNote, style: appText(12.5, color: AppColors.ink))),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Notifications ────────────────────────────────────────────────────────────

class _NotificationsSection extends ConsumerWidget {
  const _NotificationsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return _SettingsCard(
      section: SettingsSection.notifications,
      hint: l.notificationsHint,
      children: [
        _SwitchRow(
          icon: Icons.phone_iphone_rounded,
          color: AppPalette.orange,
          title: l.deviceNotifications,
          hint: l.deviceNotificationsHint,
          value: ref.watch(deviceNotificationsProvider),
          onChanged: ref.read(deviceNotificationsProvider.notifier).set,
        ),
      ],
    );
  }
}

// ── About ────────────────────────────────────────────────────────────────────

class _AboutSection extends StatelessWidget {
  const _AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return _SettingsCard(
      section: SettingsSection.about,
      hint: l.aboutAppHint,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset('assets/icon.png', width: 48, height: 48, fit: BoxFit.cover),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AlmaWorks', style: appText(15, weight: FontWeight.w700)),
                  Text(l.aboutApp, style: appText(12.5, color: AppColors.inkMuted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(l.copyrightFooter, style: appText(11.5, color: AppColors.inkFaint)),
      ],
    );
  }
}
