import 'package:almaworks/models/safety_training/safety_scenario_model.dart';
import 'package:almaworks/screens/safety_training/add_scenario_screen.dart';
import 'package:almaworks/screens/safety_training/safety_training_providers.dart';
import 'package:almaworks/screens/safety_training/widgets/safety_widgets.dart';
import 'package:almaworks/widgets/modern/modern_ui.dart';
import 'package:almaworks/widgets/safety_training/hazard_scene_visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

enum _ManageFilter { all, active, inactive, incomplete }

extension on _ManageFilter {
  String get label => switch (this) {
    _ManageFilter.all => 'All',
    _ManageFilter.active => 'Visible to workers',
    _ManageFilter.inactive => 'Hidden',
    _ManageFilter.incomplete => 'Needs fixing',
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
        showAppSnack(
          context,
          isActive ? '"${scenario.title}" is now visible to workers' : '"${scenario.title}" is hidden from workers',
        );
      }
    } catch (e) {
      widget.logger.e('❌ ManageScenariosScreen: Failed to toggle ${scenario.id}: $e');
      if (mounted) {
        showAppSnack(
          context,
          'Could not update "${scenario.title}". Open it with Edit and save to repair it.',
          error: true,
        );
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
      appBar: modernAppBar(context, title: 'Manage Scenarios', subtitle: 'Edit, publish or hide safety scenarios'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditor,
        backgroundColor: AppPalette.deepBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Author Scenario',
          style: appText(13.5, weight: FontWeight.w600, color: Colors.white),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          widget.logger.e('❌ ManageScenariosScreen: stream error: $e');
          return const EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Couldn\'t load scenarios',
            message: 'Check your connection and try again.',
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
                        StatTile(label: 'Scenarios', value: '${scenarios.length}', icon: Icons.layers_rounded),
                        StatTile(
                          label: 'Visible',
                          value: '$activeCount',
                          icon: Icons.visibility_rounded,
                          color: AppPalette.green,
                        ),
                        StatTile(
                          label: 'Hidden',
                          value: '${scenarios.length - activeCount}',
                          icon: Icons.visibility_off_rounded,
                          color: AppPalette.inkMuted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SearchField(hint: 'Search scenarios', onChanged: (v) => setState(() => _query = v)),
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
                      const EmptyState(
                        icon: Icons.health_and_safety_outlined,
                        title: 'No scenarios yet',
                        message: 'Tap "Author Scenario" to create the first one.',
                      )
                    else if (visible.isEmpty)
                      const EmptyState(
                        icon: Icons.filter_alt_off_rounded,
                        title: 'Nothing matches',
                        message: 'Try another search or filter.',
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
                  label: s.isActive ? 'Visible' : 'Hidden',
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
                          StatusPill(label: s.difficulty, color: difficultyColor(s.difficulty)),
                          StatusPill(label: '${s.points} pts', color: AppPalette.brightBlue),
                          StatusPill(label: s.category, color: AppPalette.violet),
                          if (s.options.length < 2) const StatusPill(label: 'Incomplete', color: AppPalette.coral),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Updated ${safetyDate.format(updated)}', style: appText(11.5, color: AppPalette.inkFaint)),
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
                        : Switch(value: s.isActive, activeThumbColor: AppPalette.deepBlue, onChanged: onToggle),
                    IconButton(
                      tooltip: 'Edit scenario',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_rounded, color: AppPalette.brightBlue),
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
