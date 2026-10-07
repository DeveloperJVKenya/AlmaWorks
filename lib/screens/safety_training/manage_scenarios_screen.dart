import 'package:almaworks/models/safety_training/safety_scenario_model.dart';
import 'package:almaworks/screens/safety_training/add_scenario_screen.dart';
import 'package:almaworks/screens/safety_training/safety_training_providers.dart';
import 'package:almaworks/screens/safety_training/widgets/safety_widgets.dart';
import 'package:almaworks/widgets/modern/modern_ui.dart';
import 'package:almaworks/widgets/safety_training/hazard_scene_visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/theme/app_colors.dart';
import 'package:almaworks/core/errors/friendly_error.dart';

enum _ManageFilter { all, active, inactive, incomplete }

extension on _ManageFilter {
  String get label => switch (this) {
    _ManageFilter.all => l10nNow.all,
    _ManageFilter.active => l10nNow.visibleToWorkers,
    _ManageFilter.inactive => l10nNow.hidden,
    _ManageFilter.incomplete => l10nNow.needsFixing,
  };

  bool matches(SafetyScenarioModel s) => switch (this) {
    _ManageFilter.all => true,
    _ManageFilter.active => s.isActive,
    _ManageFilter.inactive => !s.isActive,
    _ManageFilter.incomplete => s.options.length < 2,
  };
}

/// Admin catalog of every scenario — visible or hidden — to edit or switch
/// on/off. Scenarios are never deleted (firestore.rules), since past
/// sessions reference them; hiding removes one from workers' catalog.
class ManageScenariosScreen extends ConsumerStatefulWidget {
  const ManageScenariosScreen({super.key, required this.logger});

  final Logger logger;

  @override
  ConsumerState<ManageScenariosScreen> createState() => _ManageScenariosScreenState();
}

class _ManageScenariosScreenState extends ConsumerState<ManageScenariosScreen> {
  final Set<String> _togglingIds = {};
  _ManageFilter _filter = _ManageFilter.all;
  String _query = '';

  Future<void> _setActive(SafetyScenarioModel scenario, bool isActive) async {
    setState(() => _togglingIds.add(scenario.id));
    try {
      await ref.read(safetyServiceProvider).setScenarioActive(scenario.id, isActive);
      if (mounted) {
        showSuccessSnack(
          context,
          isActive ? context.l10n.scenarioNowVisible(scenario.title) : context.l10n.scenarioNowHidden(scenario.title),
        );
      }
    } catch (e) {
      widget.logger.e('❌ ManageScenariosScreen: Failed to toggle ${scenario.id}: $e');
      if (mounted) {
        showErrorMessage(context, context.l10n.couldNotUpdateScenario(scenario.title));
      }
    } finally {
      if (mounted) setState(() => _togglingIds.remove(scenario.id));
    }
  }

  void _openEditor([SafetyScenarioModel? scenario]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddScenarioScreen(logger: widget.logger, existing: scenario),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allScenariosProvider);
    return Scaffold(
      backgroundColor: AppPalette.canvas,
      appBar: modernAppBar(context, title: context.l10n.manageScenarios, subtitle: context.l10n.manageScenariosSubtitle),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditor,
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          context.l10n.authorScenario,
          style: appText(13.5, weight: FontWeight.w600, color: Colors.white),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          widget.logger.e('❌ ManageScenariosScreen: stream error: $e');
          return EmptyState(
            icon: Icons.cloud_off_rounded,
            title: context.l10n.couldNotLoadScenarios,
            message: friendlyError(e),
          );
        },
        data: (scenarios) {
          final q = _query.trim().toLowerCase();
          final visible = scenarios
              .where(_filter.matches)
              .where((s) => q.isEmpty || '${s.title} ${s.category}'.toLowerCase().contains(q))
              .toList();
          final activeCount = scenarios.where((s) => s.isActive).length;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              Breakpoints.isCompact(context) ? 14 : 24,
              18,
              Breakpoints.isCompact(context) ? 14 : 24,
              96,
            ),
            children: [
              ResponsiveCenter(
                maxWidth: 1180,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ResponsiveTiles(
                      minTileWidth: 170,
                      children: [
                        StatTile(label: context.l10n.scenarios, value: '${scenarios.length}', icon: Icons.layers_rounded),
                        StatTile(
                          label: context.l10n.visible,
                          value: '$activeCount',
                          icon: Icons.visibility_rounded,
                          color: AppPalette.green,
                        ),
                        StatTile(
                          label: context.l10n.hiddenSingular,
                          value: '${scenarios.length - activeCount}',
                          icon: Icons.visibility_off_rounded,
                          color: AppPalette.inkMuted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SearchField(hint: context.l10n.searchScenarios, onChanged: (v) => setState(() => _query = v)),
                    const SizedBox(height: 12),
                    FilterChipBar<_ManageFilter>(
                      options: [
                        for (final f in _ManageFilter.values)
                          if (f != _ManageFilter.incomplete || scenarios.any(f.matches)) f,
                      ],
                      selected: _filter,
                      onSelected: (f) => setState(() => _filter = f),
                      label: (f) => f.label,
                      count: (f) => f == _ManageFilter.all ? 0 : scenarios.where(f.matches).length,
                    ),
                    const SizedBox(height: 18),
                    if (scenarios.isEmpty)
                      EmptyState(
                        icon: Icons.health_and_safety_outlined,
                        title: context.l10n.noScenariosYet,
                        message: context.l10n.noScenariosAuthorHint,
                      )
                    else if (visible.isEmpty)
                      EmptyState(
                        icon: Icons.filter_alt_off_rounded,
                        title: context.l10n.nothingMatches,
                        message: context.l10n.tryDifferentSearch,
                      )
                    else
                      ResponsiveCardGrid(
                        itemCount: visible.length,
                        minItemWidth: 340,
                        itemBuilder: (context, i) => _ManageCard(
                          scenario: visible[i],
                          toggling: _togglingIds.contains(visible[i].id),
                          onToggle: (v) => _setActive(visible[i], v),
                          onEdit: () => _openEditor(visible[i]),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ManageCard extends StatelessWidget {
  const _ManageCard({required this.scenario, required this.toggling, required this.onToggle, required this.onEdit});

  final SafetyScenarioModel scenario;
  final bool toggling;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final s = scenario;
    final updated = s.updatedAt ?? s.createdAt;
    return AppCard(
      onTap: onEdit,
      padding: EdgeInsets.zero,
      accent: s.options.length < 2 ? AppPalette.coral : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Opacity(
                opacity: s.isActive ? 1 : 0.45,
                child: TickerMode(
                  enabled: false,
                  child: HazardSceneVisual(
                    visualKey: s.visualKey,
                    imageUrl: s.imageUrl,
                    lottieUrl: s.lottieUrl,
                    riveUrl: s.riveUrl,
                    height: 120,
                  ),
                ),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: StatusPill(
                  label: s.isActive ? context.l10n.visible : context.l10n.hiddenSingular,
                  color: s.isActive ? AppPalette.green : AppPalette.inkMuted,
                  icon: s.isActive ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  solid: true,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: appText(15, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          StatusPill(label: difficultyLabel(s.difficulty), color: difficultyColor(s.difficulty)),
                          StatusPill(label: context.l10n.pointsShort(s.points), color: AppPalette.brightBlue),
                          StatusPill(label: safetyCategoryLabel(s.category), color: AppPalette.violet),
                          if (s.options.length < 2) StatusPill(label: context.l10n.incomplete, color: AppPalette.coral),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(context.l10n.updatedOn(safetyDate.format(updated)), style: appText(11.5, color: AppPalette.inkFaint)),
                    ],
                  ),
                ),
                Column(
                  children: [
                    toggling
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : Switch(value: s.isActive, onChanged: onToggle),
                    IconButton(
                      tooltip: context.l10n.editScenario,
                      onPressed: onEdit,
                      icon: Icon(Icons.edit_rounded, color: AppColors.info),
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
