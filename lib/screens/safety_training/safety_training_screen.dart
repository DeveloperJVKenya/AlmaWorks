import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/models/safety_training/safety_scenario_model.dart';
import 'package:almaworks/models/safety_training/safety_training_review_model.dart';
import 'package:almaworks/screens/safety_training/add_scenario_screen.dart';
import 'package:almaworks/screens/safety_training/manage_scenarios_screen.dart';
import 'package:almaworks/screens/safety_training/safety_training_providers.dart';
import 'package:almaworks/screens/safety_training/safety_training_review_screen.dart';
import 'package:almaworks/screens/safety_training/scenario_play_screen.dart';
import 'package:almaworks/screens/safety_training/training_history_screen.dart';
import 'package:almaworks/screens/safety_training/widgets/safety_widgets.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/modern/modern_ui.dart';
import 'package:almaworks/widgets/safety_training/hazard_scene_visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

enum _ScenarioFilter { all, todo, passed, missed, assigned }

extension on _ScenarioFilter {
  String get label => switch (this) {
    _ScenarioFilter.all => 'All',
    _ScenarioFilter.todo => 'Not started',
    _ScenarioFilter.passed => 'Passed',
    _ScenarioFilter.missed => 'Missed',
    _ScenarioFilter.assigned => 'Assigned to me',
  };

  IconData get icon => switch (this) {
    _ScenarioFilter.all => Icons.apps_rounded,
    _ScenarioFilter.todo => Icons.radio_button_unchecked_rounded,
    _ScenarioFilter.passed => Icons.check_circle_rounded,
    _ScenarioFilter.missed => Icons.replay_rounded,
    _ScenarioFilter.assigned => Icons.assignment_late_rounded,
  };
}

/// Hub of the Safety Training section, laid out so the scenarios are in
/// view on first launch, on phones and tablets alike:
///   1. a pinned Safety Training toolbar right under the app bar — the
///      worker's standing (validity, retraining, notes in a sheet), history,
///      and for admins/reviewers their tools (review standing, manage
///      scenarios, all attempts, my attempts, new scenario);
///   2. a slim one-row score strip;
///   3. the searchable, filterable scenario grid (assigned retraining first).
///
/// Safety Training is company-wide, not project-scoped — [project] only
/// exists so BaseLayout can render its header/project-switcher chrome
/// (same as Inventory), and is recorded on sessions as where an attempt
/// was taken.
class SafetyTrainingScreen extends ConsumerStatefulWidget {
  const SafetyTrainingScreen({super.key, required this.project, required this.logger});

  final ProjectModel project;
  final Logger logger;

  @override
  ConsumerState<SafetyTrainingScreen> createState() => _SafetyTrainingScreenState();
}

class _SafetyTrainingScreenState extends ConsumerState<SafetyTrainingScreen> {
  _ScenarioFilter _filter = _ScenarioFilter.all;
  String _query = '';
  bool _searchOpen = false;
  bool _securedLegacy = false;

  void _push(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  /// Scenarios authored before answer keys were split out still carry the
  /// correct answer where Technicians can read it; the first admin to open
  /// the hub moves those into the admin-only collection (no-op afterwards).
  void _secureLegacyOnce(SafetyUser user) {
    if (_securedLegacy || !user.isAdmin) return;
    _securedLegacy = true;
    ref.read(safetyServiceProvider).secureLegacyScenarios(adminUid: user.uid).then((secured) {
      if (secured > 0) widget.logger.i('🔒 SafetyTrainingScreen: Secured answer keys for $secured legacy scenario(s)');
    }, onError: (Object e) => widget.logger.e('❌ SafetyTrainingScreen: Error securing legacy scenarios: $e'));
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(safetyUserProvider);
    final user = userAsync.valueOrNull;
    if (user != null) _secureLegacyOnce(user);

    return BaseLayout(
      title: 'Safety Training',
      project: widget.project,
      logger: widget.logger,
      selectedMenuItem: 'Safety Training',
      onMenuItemSelected: (_) {},
      child: ColoredBox(
        color: AppPalette.canvas,
        child: userAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Couldn\'t load your account',
            message: 'Check your connection and try again.',
            action: OutlinedButton(onPressed: () => ref.invalidate(safetyUserProvider), child: const Text('Retry')),
          ),
          data: (user) {
            if (user == null || user.roleMissing) {
              return const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Safety Training isn\'t available yet',
                message: 'Your account\'s access role hasn\'t been set up. Please contact an administrator.',
              );
            }
            return _buildBody(user);
          },
        ),
      ),
    );
  }

  Widget _buildBody(SafetyUser user) {
    final progressAsync = ref.watch(workerProgressProvider(user.uid));
    final progress = progressAsync.valueOrNull ?? WorkerProgress.empty;
    final scenariosAsync = ref.watch(activeScenariosProvider);
    final scenarios = scenariosAsync.valueOrNull;
    final review = ref.watch(latestReviewProvider(user.uid)).valueOrNull;
    final activeIds = scenarios?.map((s) => s.id).toSet();
    final retraining = review != null && review.isNeedsRetraining
        ? RetrainingProgress.of(review, progress.lastAttemptAtByScenario, activeScenarioIds: activeIds)
        : null;
    final assigned = retraining?.assigned.toSet() ?? const <String>{};

    // Incomplete scenarios (fewer than 2 options — only possible via a
    // console edit) are hidden from workers and flagged for admins.
    final playable = [
      for (final s in scenarios ?? const <SafetyScenarioModel>[])
        if (user.isAdmin || s.options.length >= 2) s,
    ];
    final ordered = [
      ...playable.where((s) => assigned.contains(s.id)),
      ...playable.where((s) => !assigned.contains(s.id)),
    ];
    bool inFilter(SafetyScenarioModel s, _ScenarioFilter f) {
      final first = progress.firstAttemptResults[s.id];
      return switch (f) {
        _ScenarioFilter.all => true,
        _ScenarioFilter.todo => first == null,
        _ScenarioFilter.passed => first?.correct == true,
        _ScenarioFilter.missed => first != null && !first.correct,
        _ScenarioFilter.assigned => assigned.contains(s.id),
      };
    }

    final q = _query.trim().toLowerCase();
    final visible = ordered
        .where((s) => q.isEmpty || '${s.title} ${s.category} ${s.sceneDescription}'.toLowerCase().contains(q))
        .where((s) => inFilter(s, _filter))
        .toList();

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(latestReviewProvider(user.uid));
        ref.invalidate(activeScenariosProvider);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < Breakpoints.compact;
          final pad = compact ? 12.0 : 20.0;
          final contentWidth = constraints.maxWidth.clamp(0, 1180).toDouble();
          final sidePad = pad + (constraints.maxWidth > 1180 ? (constraints.maxWidth - 1180) / 2 : 0);
          final columns = (contentWidth / 320).floor().clamp(1, 3);

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── 1. Safety Training toolbar, pinned under the app bar ──
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedBar(
                  height: 58,
                  child: _SafetyToolbar(
                    user: user,
                    review: review,
                    retraining: retraining,
                    horizontalPadding: sidePad,
                    onStanding: () => _showStanding(review, retraining),
                    onMyHistory: () =>
                        _push(TrainingHistoryScreen(logger: widget.logger, workerUid: user.uid, workerName: user.name)),
                    onAllAttempts: () => _push(TrainingHistoryScreen(logger: widget.logger)),
                    onReview: () => _push(SafetyTrainingReviewScreen(logger: widget.logger)),
                    onManage: () => _push(ManageScenariosScreen(logger: widget.logger)),
                    onNewScenario: () => _push(AddScenarioScreen(logger: widget.logger)),
                  ),
                ),
              ),
              // ── 2. Slim score strip + 3. scenario header ──
              SliverPadding(
                padding: EdgeInsets.fromLTRB(sidePad, pad, sidePad, 10),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ScoreStrip(progress: progress, activeIds: activeIds, failed: progressAsync.hasError),
                      SizedBox(height: compact ? 14 : 18),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Safety Scenarios${scenarios == null ? '' : ' (${playable.length})'}',
                              style: appText(compact ? 16 : 17, weight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            tooltip: _searchOpen ? 'Close search' : 'Search scenarios',
                            onPressed: () => setState(() {
                              _searchOpen = !_searchOpen;
                              if (!_searchOpen) _query = '';
                            }),
                            icon: Icon(
                              _searchOpen ? Icons.close_rounded : Icons.search_rounded,
                              color: AppPalette.deepBlue,
                            ),
                          ),
                        ],
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        child: _searchOpen
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: SearchField(
                                  hint: 'Search by title, category or scene',
                                  onChanged: (v) => setState(() => _query = v),
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                      FilterChipBar<_ScenarioFilter>(
                        options: [
                          for (final f in _ScenarioFilter.values)
                            if (f != _ScenarioFilter.assigned || assigned.isNotEmpty) f,
                        ],
                        selected: _filter,
                        onSelected: (f) => setState(() => _filter = f),
                        label: (f) => f.label,
                        icon: (f) => f.icon,
                        count: (f) => f == _ScenarioFilter.all ? 0 : ordered.where((s) => inFilter(s, f)).length,
                      ),
                    ],
                  ),
                ),
              ),
              if (scenariosAsync.isLoading && scenarios == null)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (scenariosAsync.hasError)
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: 'Couldn\'t load scenarios',
                    message: 'Pull down to try again.',
                  ),
                )
              else if (visible.isEmpty)
                SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.health_and_safety_outlined,
                    title: playable.isEmpty ? 'No scenarios yet' : 'No scenarios match',
                    message: playable.isEmpty
                        ? (user.isAdmin
                              ? 'Tap "New scenario" in the toolbar to create the first one.'
                              : 'Safety scenarios will appear here once an admin publishes them.')
                        : 'Try a different search or filter.',
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: sidePad),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: compact ? 12 : 16,
                      crossAxisSpacing: 16,
                      mainAxisExtent: compact ? 288 : 312,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final s = visible[i];
                      return StaggeredEntrance(
                        index: i,
                        child: _ScenarioCard(
                          scenario: s,
                          thumbnailHeight: compact ? 116 : 132,
                          firstAttempt: progress.firstAttemptResults[s.id],
                          retraining: assigned.contains(s.id) ? retraining : null,
                          onTap: () =>
                              _push(ScenarioPlayScreen(scenario: s, project: widget.project, logger: widget.logger)),
                        ),
                      );
                    },
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }

  void _showStanding(SafetyTrainingReviewModel? review, RetrainingProgress? retraining) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppPalette.surface,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: _StandingDetails(review: review, retraining: retraining),
        ),
      ),
    );
  }
}

/// Fixed-height pinned header for a [SliverPersistentHeader].
class _PinnedBar extends SliverPersistentHeaderDelegate {
  _PinnedBar({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  bool shouldRebuild(_PinnedBar oldDelegate) => oldDelegate.child != child || oldDelegate.height != height;
}

/// The Safety Training tab strip: standing + history for everyone, tools for
/// admins/reviewers — scrolls horizontally so it's one row on any width.
class _SafetyToolbar extends StatelessWidget {
  const _SafetyToolbar({
    required this.user,
    required this.review,
    required this.retraining,
    required this.horizontalPadding,
    required this.onStanding,
    required this.onMyHistory,
    required this.onAllAttempts,
    required this.onReview,
    required this.onManage,
    required this.onNewScenario,
  });

  final SafetyUser user;
  final SafetyTrainingReviewModel? review;
  final RetrainingProgress? retraining;
  final double horizontalPadding;
  final VoidCallback onStanding;
  final VoidCallback onMyHistory;
  final VoidCallback onAllAttempts;
  final VoidCallback onReview;
  final VoidCallback onManage;
  final VoidCallback onNewScenario;

  @override
  Widget build(BuildContext context) {
    final standing = StandingVisual.of(review, retraining, DateTime.now());
    final items = <Widget>[
      _ToolChip(
        icon: standing.icon,
        color: standing.color,
        label: review == null
            ? 'Not reviewed'
            : review!.isCleared && !review!.isClearanceExpired(DateTime.now())
            ? 'Cleared · until ${safetyDate.format(review!.clearanceExpiresAt)}'
            : standing.label,
        emphasized: true,
        onTap: onStanding,
        tooltip: 'My standing',
      ),
      _ToolChip(
        icon: Icons.history_rounded,
        color: AppPalette.teal,
        label: user.isAdmin ? 'My attempts' : 'My history',
        onTap: onMyHistory,
      ),
      if (user.isReviewer)
        _ToolChip(
          icon: Icons.fact_check_rounded,
          color: AppPalette.brightBlue,
          label: 'Review standing',
          onTap: onReview,
        ),
      if (user.isAdmin) ...[
        _ToolChip(icon: Icons.groups_rounded, color: AppPalette.orange, label: 'All attempts', onTap: onAllAttempts),
        _ToolChip(icon: Icons.dashboard_customize_rounded, color: AppPalette.violet, label: 'Manage', onTap: onManage),
        _ToolChip(icon: Icons.add_circle_rounded, color: AppPalette.green, label: 'New scenario', onTap: onNewScenario),
      ],
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surface,
        border: const Border(bottom: BorderSide(color: AppPalette.border)),
        boxShadow: [
          BoxShadow(color: AppPalette.deepBlue.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 9),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(width: 8), items[i]],
          ],
        ),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.emphasized = false,
    this.tooltip,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool emphasized;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final chip = Material(
      color: emphasized ? color.withValues(alpha: 0.12) : AppPalette.canvas,
      shape: StadiumBorder(side: BorderSide(color: emphasized ? color.withValues(alpha: 0.5) : AppPalette.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 7),
              Text(
                label,
                style: appText(12.5, weight: FontWeight.w600, color: emphasized ? color : AppPalette.ink),
              ),
              if (emphasized) ...[const SizedBox(width: 2), Icon(Icons.expand_more_rounded, size: 16, color: color)],
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

/// One-row score summary: points, first-try accuracy, completion.
class _ScoreStrip extends StatelessWidget {
  const _ScoreStrip({required this.progress, required this.activeIds, required this.failed});

  final WorkerProgress progress;
  final Set<String>? activeIds;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final summary = progress.summary;
    final ids = activeIds;
    final total = ids?.length ?? 0;
    final completed = ids == null ? 0 : summary.completedOf(ids);
    final compact = Breakpoints.isCompact(context);

    Widget metric(String value, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            failed ? '—' : value,
            maxLines: 1,
            style: appText(compact ? 18 : 21, weight: FontWeight.w800, color: Colors.white, height: 1.1),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appText(11, color: Colors.white.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );

    return Tooltip(
      message: 'Only your first attempt at each scenario counts toward your score — replays are practice.',
      child: HeroPanel(
        padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20, vertical: compact ? 12 : 14),
        child: Row(
          children: [
            const Icon(Icons.shield_rounded, color: Colors.white, size: 26),
            SizedBox(width: compact ? 10 : 16),
            metric('${summary.totalPoints}', 'Points'),
            metric('${(summary.accuracy * 100).round()}%', 'First-try accuracy'),
            metric(total == 0 ? '—' : '$completed/$total', 'Completed'),
            if (total > 0 && !compact) ScoreRing(value: completed / total, size: 46, onDark: true),
          ],
        ),
      ),
    );
  }
}

/// Everything about the worker's current determination, for the
/// "My standing" sheet.
class _StandingDetails extends StatelessWidget {
  const _StandingDetails({required this.review, required this.retraining});

  final SafetyTrainingReviewModel? review;
  final RetrainingProgress? retraining;

  @override
  Widget build(BuildContext context) {
    final r = review;
    final standing = StandingVisual.of(r, retraining, DateTime.now());
    final rt = retraining;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconBadge(icon: standing.icon, color: standing.color, size: 50),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('My safety standing', style: appText(12.5, color: AppPalette.inkMuted)),
                  Text(
                    standing.label,
                    style: appText(19, weight: FontWeight.w800, color: standing.color),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (r == null)
          Text(
            'A reviewer hasn\'t assessed your training yet. Keep working through the scenarios — your first '
            'attempts are what they\'ll look at.',
            style: appText(13.5, height: 1.5),
          )
        else ...[
          if (standing.detail != null)
            Text(standing.detail!, style: appText(14, weight: FontWeight.w500, height: 1.45)),
          if (r.isCleared) ...[
            const SizedBox(height: 14),
            LabeledProgress(
              label: 'Clearance validity',
              value: _validityLeft(r),
              trailing: r.isClearanceExpired(DateTime.now())
                  ? 'Expired'
                  : '${r.clearanceExpiresAt.difference(DateTime.now()).inDays} days left',
              color: standing.color,
            ),
          ],
          if (rt != null && rt.assigned.isNotEmpty) ...[
            const SizedBox(height: 14),
            LabeledProgress(
              label: 'Retraining progress',
              value: rt.done / rt.assigned.length,
              trailing: '${rt.done}/${rt.assigned.length}',
              color: standing.color,
            ),
            const SizedBox(height: 6),
            Text(
              'Assigned scenarios are listed first on the Safety Training screen.',
              style: appText(12, color: AppPalette.inkMuted),
            ),
          ],
          if (r.notes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppPalette.canvas, borderRadius: BorderRadius.circular(14)),
              child: Text('“${r.notes}”', style: appText(13.5, color: AppPalette.inkMuted, height: 1.45)),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Reviewed by ${r.reviewedByName.isEmpty ? 'a reviewer' : r.reviewedByName} on ${safetyDate.format(r.reviewedAt)}',
            style: appText(12, color: AppPalette.inkFaint),
          ),
        ],
      ],
    );
  }

  static double _validityLeft(SafetyTrainingReviewModel r) {
    final total = r.clearanceExpiresAt.difference(r.reviewedAt).inMinutes;
    if (total <= 0) return 0;
    return r.clearanceExpiresAt.difference(DateTime.now()).inMinutes / total;
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({
    required this.scenario,
    required this.thumbnailHeight,
    required this.firstAttempt,
    required this.retraining,
    required this.onTap,
  });

  final SafetyScenarioModel scenario;
  final double thumbnailHeight;
  final ({bool correct, int points})? firstAttempt;

  /// Set when this scenario is assigned to the worker for retraining.
  final RetrainingProgress? retraining;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final incomplete = scenario.options.length < 2;
    final r = retraining;
    final retrainingDone = r != null && !r.remaining.contains(scenario.id);
    final first = firstAttempt;

    final (statusLabel, statusColor, statusIcon) = switch (first) {
      _ when incomplete => ('Incomplete — fix in Manage', AppPalette.coral, Icons.error_outline_rounded),
      _ when r != null && !retrainingDone => (
        'Retraining${r.dueAt == null ? '' : ' · due ${safetyDate.format(r.dueAt!)}'}',
        AppPalette.orange,
        Icons.assignment_late_rounded,
      ),
      _ when retrainingDone => ('Retraining done', AppPalette.teal, Icons.task_alt_rounded),
      null => ('Not started', AppPalette.brightBlue, Icons.play_circle_rounded),
      (correct: true, points: final p) => ('Passed · +$p pts', AppPalette.green, Icons.check_circle_rounded),
      _ => ('Missed · practise again', AppPalette.amber, Icons.replay_rounded),
    };

    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      accent: r != null && !retrainingDone ? AppPalette.orange : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              // Frozen thumbnails — a grid of looping animations wastes
              // battery; the play screen runs the scene in full.
              TickerMode(
                enabled: false,
                child: HazardSceneVisual(
                  visualKey: scenario.visualKey,
                  imageUrl: scenario.imageUrl,
                  lottieUrl: scenario.lottieUrl,
                  riveUrl: scenario.riveUrl,
                  height: thumbnailHeight,
                ),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: StatusPill(label: scenario.difficulty, color: difficultyColor(scenario.difficulty), solid: true),
              ),
              Positioned(
                right: 10,
                top: 10,
                child: StatusPill(
                  label: '${scenario.points} pts',
                  color: AppPalette.deepBlue,
                  solid: true,
                  icon: Icons.star_rounded,
                ),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scenario.category.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appText(10.5, weight: FontWeight.w700, color: AppPalette.inkFaint),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    scenario.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: appText(15, weight: FontWeight.w700, height: 1.25),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Text(
                      scenario.sceneDescription,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: appText(12.5, color: AppPalette.inkMuted, height: 1.35),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: StatusPill(label: statusLabel, color: statusColor, icon: statusIcon),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        first == null ? 'Start' : 'Practice',
                        style: appText(13, weight: FontWeight.w700, color: AppPalette.brightBlue),
                      ),
                      const Icon(Icons.arrow_forward_rounded, size: 18, color: AppPalette.brightBlue),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
