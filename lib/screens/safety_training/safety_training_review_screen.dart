import 'package:almaworks/models/safety_training/safety_scenario_model.dart';
import 'package:almaworks/models/safety_training/safety_training_review_model.dart';
import 'package:almaworks/models/safety_training/safety_worker_stats_model.dart';
import 'package:almaworks/screens/safety_training/safety_training_providers.dart';
import 'package:almaworks/screens/safety_training/training_history_screen.dart';
import 'package:almaworks/screens/safety_training/widgets/safety_widgets.dart';
import 'package:almaworks/services/safety_training_service.dart';
import 'package:almaworks/widgets/modern/modern_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// One roster entry: a worker, their server-maintained stats (null if they
/// have never completed a scenario) and their current determination.
class _Standing {
  final String uid;
  final String name;
  final String role;
  final SafetyWorkerStatsModel? stats;
  final SafetyTrainingReviewModel? review;
  final RetrainingProgress? retraining;

  const _Standing({
    required this.uid,
    required this.name,
    required this.role,
    required this.stats,
    required this.review,
    required this.retraining,
  });

  SafetyScoreSummary get summary => stats == null ? SafetyScoreSummary.empty : SafetyScoreSummary.fromStats(stats!);
  bool get hasTrained => summary.totalAttempts > 0;

  /// Attempts since the current determination was recorded.
  int get newAttempts => review == null ? 0 : (summary.totalAttempts - review!.totalAttempts).clamp(0, 1 << 30);

  /// Worth a reviewer's look now.
  bool needsAttention(DateTime now) {
    final r = review;
    if (r == null) return hasTrained;
    if (newAttempts > 0 || r.isClearanceExpired(now)) return true;
    final rt = retraining;
    return rt != null && (rt.isOverdue(now) || (rt.assigned.isNotEmpty && rt.isComplete));
  }
}

enum _RosterFilter { all, attention, notReviewed, neverTrained, cleared, retraining, escalated }

extension on _RosterFilter {
  String get label => switch (this) {
    _RosterFilter.all => 'All',
    _RosterFilter.attention => 'Needs attention',
    _RosterFilter.notReviewed => 'Not reviewed',
    _RosterFilter.neverTrained => 'Never trained',
    _RosterFilter.cleared => 'Cleared',
    _RosterFilter.retraining => 'Retraining',
    _RosterFilter.escalated => 'Escalated',
  };

  IconData get icon => switch (this) {
    _RosterFilter.all => Icons.groups_rounded,
    _RosterFilter.attention => Icons.priority_high_rounded,
    _RosterFilter.notReviewed => Icons.hourglass_empty_rounded,
    _RosterFilter.neverTrained => Icons.person_off_rounded,
    _RosterFilter.cleared => Icons.verified_rounded,
    _RosterFilter.retraining => Icons.replay_circle_filled_rounded,
    _RosterFilter.escalated => Icons.report_rounded,
  };

  bool matches(_Standing s, DateTime now) => switch (this) {
    _RosterFilter.all => true,
    _RosterFilter.attention => s.needsAttention(now),
    // Trained but awaiting a determination — never-trained workers have
    // nothing to review yet and are counted under "Never trained" instead.
    _RosterFilter.notReviewed => s.review == null && s.hasTrained,
    _RosterFilter.neverTrained => !s.hasTrained,
    _RosterFilter.cleared => s.review?.isCleared == true && !s.review!.isClearanceExpired(now),
    _RosterFilter.retraining => s.review?.isNeedsRetraining == true,
    _RosterFilter.escalated => s.review?.isEscalated == true,
  };
}

/// MainAdmin/SystemAdmin-only: every Technician (trained or not) plus
/// anyone else who has trained, with score, completion and current
/// standing — searchable and filterable — and actions to open a worker's
/// attempts or record a new determination (never about themselves).
///
/// Reads the per-worker SafetyTrainingWorkerStats docs rather than every
/// session ever recorded; the first time a reviewer opens it after stats
/// docs were introduced, the server builds them from history.
class SafetyTrainingReviewScreen extends ConsumerStatefulWidget {
  const SafetyTrainingReviewScreen({super.key, required this.logger});

  final Logger logger;

  @override
  ConsumerState<SafetyTrainingReviewScreen> createState() => _SafetyTrainingReviewScreenState();
}

class _SafetyTrainingReviewScreenState extends ConsumerState<SafetyTrainingReviewScreen> {
  _RosterFilter _filter = _RosterFilter.all;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(safetyUserProvider).valueOrNull;
    return Scaffold(
      backgroundColor: AppPalette.canvas,
      appBar: modernAppBar(
        context,
        title: 'Worker Safety Standing',
        subtitle: 'Review training results and decide next steps',
      ),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : !user.isReviewer
          ? const EmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Reviewers only',
              message: 'Only MainAdmin and SystemAdmin accounts can review worker standing.',
            )
          : _buildRoster(user),
    );
  }

  Widget _buildRoster(SafetyUser reviewer) {
    final build = ref.watch(ensureStatsBuiltProvider);
    final traineesAsync = ref.watch(traineesProvider);
    final statsAsync = ref.watch(allWorkerStatsProvider);
    final reviewsAsync = ref.watch(allReviewsProvider);
    final latest = ref.watch(latestReviewByWorkerProvider);
    final active = ref.watch(activeScenariosProvider).valueOrNull;
    final activeIds = active?.map((s) => s.id).toSet();

    if ((traineesAsync.isLoading && !traineesAsync.hasValue) || (statsAsync.isLoading && !statsAsync.hasValue)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (traineesAsync.hasError || statsAsync.hasError) {
      widget.logger.e('❌ SafetyTrainingReviewScreen: roster error: ${traineesAsync.error ?? statsAsync.error}');
      return const EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn\'t load workers',
        message: 'Check your connection and try again.',
      );
    }

    final now = DateTime.now();
    final roster = _buildStandings(traineesAsync.value!, statsAsync.value!, latest, activeIds);
    final q = _query.trim().toLowerCase();
    final visible = roster
        .where((s) => q.isEmpty || '${s.name} ${s.role}'.toLowerCase().contains(q))
        .where((s) => _filter.matches(s, now))
        .toList();
    int count(_RosterFilter f) => roster.where((s) => f.matches(s, now)).length;
    final compact = Breakpoints.isCompact(context);

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 24, vertical: 18),
      children: [
        ResponsiveCenter(
          maxWidth: 1180,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (build.isLoading)
                _notice(
                  'Building training statistics from past attempts…',
                  AppPalette.brightBlue,
                  Icons.hourglass_top_rounded,
                ),
              if (build.hasError)
                _notice(
                  'Couldn\'t build training statistics from past attempts — some workers may show no results.',
                  AppPalette.orange,
                  Icons.warning_amber_rounded,
                  action: TextButton(
                    onPressed: () => ref.invalidate(ensureStatsBuiltProvider),
                    child: const Text('Retry'),
                  ),
                ),
              if (reviewsAsync.hasError)
                _notice(
                  'Couldn\'t load past determinations — statuses below may be missing.',
                  AppPalette.orange,
                  Icons.warning_amber_rounded,
                ),
              HeroPanel(
                padding: const EdgeInsets.all(18),
                child: ResponsiveTiles(
                  minTileWidth: 150,
                  children: [
                    StatTile(onDark: true, label: 'Workers', value: '${roster.length}', icon: Icons.groups_rounded),
                    StatTile(
                      onDark: true,
                      label: 'Need attention',
                      value: '${count(_RosterFilter.attention)}',
                      icon: Icons.priority_high_rounded,
                    ),
                    StatTile(
                      onDark: true,
                      label: 'Never trained',
                      value: '${count(_RosterFilter.neverTrained)}',
                      icon: Icons.person_off_rounded,
                    ),
                    StatTile(
                      onDark: true,
                      label: 'Cleared',
                      value: '${count(_RosterFilter.cleared)}',
                      icon: Icons.verified_rounded,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SearchField(hint: 'Search workers', onChanged: (v) => setState(() => _query = v)),
              const SizedBox(height: 12),
              FilterChipBar<_RosterFilter>(
                options: _RosterFilter.values,
                selected: _filter,
                onSelected: (f) => setState(() => _filter = f),
                label: (f) => f.label,
                icon: (f) => f.icon,
                count: (f) => f == _RosterFilter.all ? 0 : count(f),
              ),
              const SizedBox(height: 18),
              if (roster.isEmpty)
                const EmptyState(
                  icon: Icons.groups_rounded,
                  title: 'No workers yet',
                  message: 'Technicians and anyone who has trained will appear here.',
                )
              else if (visible.isEmpty)
                const EmptyState(
                  icon: Icons.filter_alt_off_rounded,
                  title: 'No workers match',
                  message: 'Try another search or filter.',
                )
              else
                ResponsiveCardGrid(
                  itemCount: visible.length,
                  minItemWidth: 360,
                  itemBuilder: (context, i) => _WorkerCard(
                    standing: visible[i],
                    activeIds: activeIds,
                    isSelf: visible[i].uid == reviewer.uid,
                    reviewsLoading: reviewsAsync.isLoading && !reviewsAsync.hasValue,
                    onAttempts: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TrainingHistoryScreen(
                          logger: widget.logger,
                          workerUid: visible[i].uid,
                          workerName: visible[i].name,
                        ),
                      ),
                    ),
                    onReview: () => _openReviewSheet(reviewer, visible[i], active ?? const []),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Every Technician plus anyone else with attempts; trained workers
  /// first (most recent attempt first), then never-trained alphabetically.
  List<_Standing> _buildStandings(
    List<SafetyTrainee> trainees,
    List<SafetyWorkerStatsModel> stats,
    Map<String, SafetyTrainingReviewModel> latest,
    Set<String>? activeIds,
  ) {
    final statsByUid = {for (final s in stats) s.workerUid: s};
    final traineeByUid = {for (final t in trainees) t.uid: t};
    final uids = {...traineeByUid.keys, ...statsByUid.keys.where((uid) => statsByUid[uid]!.totalAttempts > 0)};
    final standings = [
      for (final uid in uids)
        () {
          final st = statsByUid[uid];
          final review = latest[uid];
          return _Standing(
            uid: uid,
            name: traineeByUid[uid]?.name ?? st?.workerName ?? '',
            role: traineeByUid[uid]?.role ?? st?.workerRole ?? '',
            stats: st,
            review: review,
            retraining: review != null && review.isNeedsRetraining
                ? RetrainingProgress.of(review, st?.lastAttemptAtByScenario ?? const {}, activeScenarioIds: activeIds)
                : null,
          );
        }(),
    ];
    standings.sort((a, b) {
      final aAt = a.stats?.lastAttemptAt, bAt = b.stats?.lastAttemptAt;
      if (aAt != null && bAt != null) return bAt.compareTo(aAt);
      if (aAt != null) return -1;
      if (bAt != null) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return standings;
  }

  Widget _notice(String message, Color color, IconData icon, {Widget? action}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: appText(12.5, color: color)),
          ),
          ?action,
        ],
      ),
    );
  }

  Future<void> _openReviewSheet(
    SafetyUser reviewer,
    _Standing standing,
    List<SafetyScenarioModel> activeScenarios,
  ) async {
    final decision = await showModalBottomSheet<_ReviewDecision>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppPalette.surface,
      constraints: const BoxConstraints(maxWidth: 680),
      builder: (_) => _ReviewSheet(standing: standing, activeScenarios: activeScenarios, reviewerUid: reviewer.uid),
    );
    if (decision == null) return;

    final reviewedAt = DateTime.now();
    final summary = standing.summary;
    try {
      await ref
          .read(safetyServiceProvider)
          .recordReview(
            SafetyTrainingReviewModel(
              id: '',
              workerUid: standing.uid,
              workerName: standing.name,
              workerRole: standing.role,
              status: decision.status,
              notes: decision.notes,
              totalAttempts: summary.totalAttempts,
              scenariosAttempted: summary.scenariosAttempted,
              firstTryCorrect: summary.firstTryCorrect,
              totalPoints: summary.totalPoints,
              expiresAt: decision.status == SafetyTrainingReviewModel.statusCleared
                  ? reviewedAt.add(SafetyTrainingReviewModel.clearanceValidity)
                  : null,
              assignedScenarioIds: decision.assignedScenarioIds,
              dueAt: decision.dueAt,
              escalatedToUid: decision.escalatedTo?.uid,
              escalatedToName: decision.escalatedTo?.name,
              reviewedByUid: reviewer.uid,
              reviewedByName: reviewer.name,
              reviewedByRole: reviewer.role ?? '',
              reviewedAt: reviewedAt,
            ),
          );
      if (mounted) showAppSnack(context, 'Determination recorded — ${standing.name} has been notified');
    } catch (e) {
      widget.logger.e('❌ SafetyTrainingReviewScreen: Error recording review: $e');
      if (mounted) showAppSnack(context, 'Failed to record determination', error: true);
    }
  }
}

class _WorkerCard extends StatelessWidget {
  const _WorkerCard({
    required this.standing,
    required this.activeIds,
    required this.isSelf,
    required this.reviewsLoading,
    required this.onAttempts,
    required this.onReview,
  });

  final _Standing standing;
  final Set<String>? activeIds;
  final bool isSelf;
  final bool reviewsLoading;
  final VoidCallback onAttempts;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final s = standing;
    final summary = s.summary;
    // A worker with no attempts and no review shows as never trained, not
    // as "Not Reviewed" — there's nothing for a reviewer to assess yet.
    final visual = s.review == null && !s.hasTrained
        ? const StandingVisual('Never Trained', AppPalette.orange, Icons.person_off_rounded)
        : StandingVisual.of(s.review, s.retraining, now);
    final total = activeIds?.length;
    final completed = activeIds == null ? 0 : summary.completedOf(activeIds!);
    final attention = s.needsAttention(now);

    return AppCard(
      accent: attention ? AppPalette.orange : null,
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              WorkerAvatar(name: s.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name.isEmpty ? 'Unknown worker' : s.name, style: appText(15, weight: FontWeight.w700)),
                    Text(s.role, style: appText(12, color: AppPalette.inkMuted)),
                  ],
                ),
              ),
              if (reviewsLoading)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else
                StatusPill(label: visual.label, color: visual.color, icon: visual.icon),
            ],
          ),
          const SizedBox(height: 14),
          if (s.hasTrained)
            Row(
              children: [
                ScoreRing(
                  value: summary.accuracy,
                  size: 58,
                  color: visual.color == AppPalette.inkMuted ? AppPalette.brightBlue : visual.color,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${summary.totalPoints} pts · ${summary.firstTryCorrect}/${summary.scenariosAttempted} first try',
                        style: appText(13, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      if (total != null && total > 0)
                        LabeledProgress(
                          label: 'Scenarios completed',
                          value: completed / total,
                          trailing: '$completed/$total',
                        ),
                    ],
                  ),
                ),
              ],
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppPalette.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_off_rounded, size: 18, color: AppPalette.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Has never completed a scenario',
                      style: appText(12.5, weight: FontWeight.w500, color: AppPalette.orange),
                    ),
                  ),
                ],
              ),
            ),
          if (visual.detail != null) ...[
            const SizedBox(height: 10),
            Text(visual.detail!, style: appText(12.5, color: AppPalette.inkMuted)),
          ],
          if (s.newAttempts > 0) ...[
            const SizedBox(height: 8),
            StatusPill(
              label: '${s.newAttempts} new attempt${s.newAttempts == 1 ? '' : 's'} since last review',
              color: AppPalette.brightBlue,
              icon: Icons.fiber_new_rounded,
            ),
          ],
          if (s.review != null) ...[
            const SizedBox(height: 8),
            Text(
              'Reviewed by ${s.review!.reviewedByName} on ${safetyDate.format(s.review!.reviewedAt)}',
              style: appText(11.5, color: AppPalette.inkFaint),
            ),
          ],
          const Divider(height: 22, color: AppPalette.border),
          Row(
            children: [
              if (s.hasTrained)
                TextButton.icon(
                  onPressed: onAttempts,
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: Text(
                    'Attempts',
                    style: appText(13, weight: FontWeight.w600, color: AppPalette.brightBlue),
                  ),
                ),
              const Spacer(),
              // A reviewer can't determine their own standing (also
              // enforced by firestore.rules).
              if (isSelf)
                Text('Reviewed by another reviewer', style: appText(11.5, color: AppPalette.inkFaint))
              else
                FilledButton.icon(
                  onPressed: onReview,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppPalette.deepBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.fact_check_rounded, size: 18),
                  label: Text(
                    'Review',
                    style: appText(13, weight: FontWeight.w600, color: Colors.white),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewDecision {
  final String status;
  final String notes;
  final List<String> assignedScenarioIds;
  final DateTime? dueAt;
  final SafetyTrainee? escalatedTo;

  const _ReviewDecision({
    required this.status,
    required this.notes,
    this.assignedScenarioIds = const [],
    this.dueAt,
    this.escalatedTo,
  });
}

/// The determination form. Each status asks for what gives it a
/// consequence: retraining needs scenarios and a due date, an escalation
/// needs a named MainAdmin/SystemAdmin, and a clearance shows when it will
/// lapse. Nothing is pre-selected — clearing a worker must be deliberate.
class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({required this.standing, required this.activeScenarios, required this.reviewerUid});

  final _Standing standing;
  final List<SafetyScenarioModel> activeScenarios;
  final String reviewerUid;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  static const _defaultRetrainingPeriod = Duration(days: 14);

  final _notesController = TextEditingController();
  String? _status;
  late final Set<String> _assigned;
  DateTime _dueDate = DateUtils.dateOnly(DateTime.now()).add(_defaultRetrainingPeriod);
  SafetyTrainee? _escalateTo;

  @override
  void initState() {
    super.initState();
    // Default retraining set: missed on the first try, or never attempted.
    final results = widget.standing.stats?.firstAttemptResults ?? const {};
    _assigned = {
      for (final s in widget.activeScenarios)
        if (!(results[s.id]?.correct ?? false)) s.id,
    };
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  bool get _canSave => switch (_status) {
    SafetyTrainingReviewModel.statusCleared => true,
    SafetyTrainingReviewModel.statusNeedsRetraining => _assigned.isNotEmpty,
    SafetyTrainingReviewModel.statusEscalated => _escalateTo != null,
    _ => false,
  };

  Future<void> _pickDueDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: today.add(const Duration(days: 1)),
      lastDate: today.add(const Duration(days: 180)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  void _save() {
    final status = _status!;
    final retraining = status == SafetyTrainingReviewModel.statusNeedsRetraining;
    Navigator.pop(
      context,
      _ReviewDecision(
        status: status,
        notes: _notesController.text.trim(),
        assignedScenarioIds: retraining
            ? [
                for (final s in widget.activeScenarios)
                  if (_assigned.contains(s.id)) s.id,
              ]
            : const [],
        // Due at the end of the chosen day.
        dueAt: retraining ? DateTime(_dueDate.year, _dueDate.month, _dueDate.day, 23, 59) : null,
        escalatedTo: status == SafetyTrainingReviewModel.statusEscalated ? _escalateTo : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.standing;
    final summary = s.summary;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  WorkerAvatar(name: s.name, size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Review ${s.name}', style: appText(18, weight: FontWeight.w700)),
                        Text(
                          s.hasTrained
                              ? '${summary.firstTryCorrect}/${summary.scenariosAttempted} correct first try · '
                                    '${(summary.accuracy * 100).round()}% · ${summary.totalPoints} pts'
                              : 'Has not completed any scenario yet',
                          style: appText(12.5, color: AppPalette.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'NEXT STEP',
                style: appText(11, weight: FontWeight.w700, color: AppPalette.brightBlue),
              ),
              const SizedBox(height: 10),
              ResponsiveTiles(
                minTileWidth: 170,
                spacing: 10,
                children: [
                  _statusOption(
                    SafetyTrainingReviewModel.statusCleared,
                    Icons.verified_rounded,
                    AppPalette.green,
                    'Fit to work for 90 days',
                  ),
                  _statusOption(
                    SafetyTrainingReviewModel.statusNeedsRetraining,
                    Icons.replay_circle_filled_rounded,
                    AppPalette.amber,
                    'Assign scenarios to redo',
                  ),
                  _statusOption(
                    SafetyTrainingReviewModel.statusEscalated,
                    Icons.report_rounded,
                    AppPalette.coral,
                    'Hand to a senior admin',
                  ),
                ],
              ),
              if (_status == SafetyTrainingReviewModel.statusCleared) ...[
                const SizedBox(height: 12),
                Text(
                  'Clearance will be valid until '
                  '${safetyDate.format(DateTime.now().add(SafetyTrainingReviewModel.clearanceValidity))}.',
                  style: appText(12.5, color: AppPalette.inkMuted),
                ),
                if (!s.hasTrained)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'This worker hasn\'t completed any scenario — clearing them isn\'t backed by any training results.',
                      style: appText(12.5, color: AppPalette.orange),
                    ),
                  ),
              ],
              if (_status == SafetyTrainingReviewModel.statusNeedsRetraining) ..._retrainingFields(),
              if (_status == SafetyTrainingReviewModel.statusEscalated) ..._escalationFields(),
              const SizedBox(height: 18),
              TextField(
                controller: _notesController,
                minLines: 2,
                maxLines: 4,
                maxLength: 2000,
                style: appText(13.5),
                decoration: InputDecoration(
                  labelText: 'Notes (optional — shown to the worker)',
                  labelStyle: appText(13, color: AppPalette.inkMuted),
                  filled: true,
                  fillColor: AppPalette.canvas,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 6),
              PrimaryButton(
                label: _status == null ? 'Choose a next step' : 'Save determination',
                icon: Icons.check_rounded,
                expand: true,
                onPressed: _canSave ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusOption(String status, IconData icon, Color color, String hint) {
    final selected = _status == status;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.1) : AppPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? color : AppPalette.border, width: selected ? 2 : 1),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _status = status),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(SafetyTrainingReviewModel.statusLabel(status), style: appText(13, weight: FontWeight.w700)),
                      Text(hint, style: appText(11.5, color: AppPalette.inkMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _retrainingFields() {
    final results = widget.standing.stats?.firstAttemptResults ?? const {};
    return [
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: Text('Scenarios to retrain on', style: appText(13.5, weight: FontWeight.w700)),
          ),
          OutlinedButton.icon(
            onPressed: _pickDueDate,
            icon: const Icon(Icons.event_rounded, size: 18),
            label: Text(
              'Due ${safetyDate.format(_dueDate)}',
              style: appText(12.5, weight: FontWeight.w600, color: AppPalette.deepBlue),
            ),
            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (widget.activeScenarios.isEmpty)
        Text('There are no active scenarios to assign.', style: appText(12.5, color: AppPalette.orange)),
      for (final scenario in widget.activeScenarios)
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: AppPalette.deepBlue,
          value: _assigned.contains(scenario.id),
          onChanged: (v) => setState(() => v == true ? _assigned.add(scenario.id) : _assigned.remove(scenario.id)),
          title: Text(scenario.title, style: appText(13.5)),
          secondary: switch (results[scenario.id]) {
            null => const StatusPill(label: 'Never attempted', color: AppPalette.inkMuted),
            (correct: true, points: _) => const StatusPill(label: 'Passed', color: AppPalette.green),
            _ => const StatusPill(label: 'Missed', color: AppPalette.coral),
          },
        ),
    ];
  }

  List<Widget> _escalationFields() {
    final async = ref.watch(reviewersProvider);
    // Not the reviewer themself, and not the worker being reviewed.
    final candidates = [
      for (final r in async.valueOrNull ?? const <SafetyTrainee>[])
        if (r.uid != widget.reviewerUid && r.uid != widget.standing.uid) r,
    ];
    return [
      const SizedBox(height: 16),
      if (async.hasError)
        Text('Couldn\'t load reviewers', style: appText(12.5, color: AppPalette.coral))
      else if (async.hasValue && candidates.isEmpty)
        Text('There\'s no other MainAdmin/SystemAdmin to escalate to.', style: appText(12.5, color: AppPalette.orange))
      else
        DropdownButtonFormField<String>(
          initialValue: _escalateTo?.uid,
          decoration: InputDecoration(
            labelText: 'Escalate to',
            labelStyle: appText(13, color: AppPalette.inkMuted),
            filled: true,
            fillColor: AppPalette.canvas,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
          items: [
            for (final r in candidates)
              DropdownMenuItem(
                value: r.uid,
                child: Text('${r.name} (${r.role})', style: appText(13.5)),
              ),
          ],
          onChanged: (uid) => setState(() => _escalateTo = candidates.where((r) => r.uid == uid).firstOrNull),
        ),
    ];
  }
}
