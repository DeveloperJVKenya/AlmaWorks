import 'package:almaworks/models/safety_training/safety_training_feedback_model.dart';
import 'package:almaworks/models/safety_training/safety_training_session_model.dart';
import 'package:almaworks/models/safety_training/safety_worker_stats_model.dart';
import 'package:almaworks/screens/safety_training/safety_training_providers.dart';
import 'package:almaworks/screens/safety_training/widgets/safety_widgets.dart';
import 'package:almaworks/services/safety_training_service.dart';
import 'package:almaworks/widgets/modern/modern_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/theme/app_colors.dart';
import 'package:almaworks/core/errors/friendly_error.dart';

enum _HistoryFilter { all, correct, incorrect, scoring, practice, feedback }

extension on _HistoryFilter {
  String get label => switch (this) {
    _HistoryFilter.all => l10nNow.all,
    _HistoryFilter.correct => l10nNow.filterCorrect,
    _HistoryFilter.incorrect => l10nNow.filterIncorrect,
    _HistoryFilter.scoring => l10nNow.filterFirstAttempts,
    _HistoryFilter.practice => l10nNow.filterPractice,
    _HistoryFilter.feedback => l10nNow.filterWithFeedback,
  };

  IconData get icon => switch (this) {
    _HistoryFilter.all => Icons.list_rounded,
    _HistoryFilter.correct => Icons.check_circle_rounded,
    _HistoryFilter.incorrect => Icons.cancel_rounded,
    _HistoryFilter.scoring => Icons.star_rounded,
    _HistoryFilter.practice => Icons.replay_rounded,
    _HistoryFilter.feedback => Icons.rate_review_rounded,
  };
}

/// Attempt history with each answer, the reasoning given and any trainer
/// feedback. A worker sees their own; an admin sees everyone's — or one
/// worker's when opened with [workerUid] (e.g. from the review screen or a
/// "new attempt" notification) — and can comment on any answer except
/// their own. Loaded a page at a time.
class TrainingHistoryScreen extends ConsumerStatefulWidget {
  const TrainingHistoryScreen({super.key, required this.logger, this.workerUid, this.workerName});

  final Logger logger;

  /// Restricts the view to one worker.
  final String? workerUid;
  final String? workerName;

  @override
  ConsumerState<TrainingHistoryScreen> createState() => _TrainingHistoryScreenState();
}

class _TrainingHistoryScreenState extends ConsumerState<TrainingHistoryScreen> {
  static const _pageSize = 25;
  int _limit = _pageSize;
  _HistoryFilter _filter = _HistoryFilter.all;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(safetyUserProvider);
    return userAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppPalette.canvas,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppPalette.canvas,
        appBar: modernAppBar(context, title: context.l10n.safetyHistory),
        body: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: context.l10n.couldNotLoadAccount,
          message: friendlyError(e),
        ),
      ),
      data: (user) {
        if (user == null) return const Scaffold(body: SizedBox.shrink());
        // Non-admins only ever see their own history.
        final workerUid = widget.workerUid ?? (user.isAdmin ? null : user.uid);
        final own = workerUid == user.uid;
        final l = context.l10n;
        final title = own
            ? l.mySafetyHistory
            : (workerUid == null ? l.allAttempts : l.workersHistory(widget.workerName ?? l.worker));
        return Scaffold(
          backgroundColor: AppPalette.canvas,
          appBar: modernAppBar(
            context,
            title: title,
            subtitle: workerUid == null
                ? l.everyWorkersAnswers
                : l.answersReasoningFeedback,
          ),
          body: _buildBody(user, workerUid),
        );
      },
    );
  }

  Widget _buildBody(SafetyUser user, String? workerUid) {
    final sessionsAsync = ref.watch(historySessionsProvider((workerUid: workerUid, limit: _limit)));
    final feedback = ref.watch(feedbackProvider(workerUid)).valueOrNull ?? const [];
    final stats = workerUid != null
        ? [?ref.watch(workerStatsProvider(workerUid)).valueOrNull]
        : (ref.watch(allWorkerStatsProvider).valueOrNull ?? const <SafetyWorkerStatsModel>[]);
    final feedbackBySession = <String, List<SafetyTrainingFeedbackModel>>{};
    for (final f in feedback) {
      feedbackBySession.putIfAbsent(f.sessionId, () => []).add(f);
    }
    for (final list in feedbackBySession.values) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    return sessionsAsync.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) {
        widget.logger.e('❌ TrainingHistoryScreen: stream error: $e');
        return EmptyState(
          icon: Icons.cloud_off_rounded,
          title: context.l10n.couldNotLoadHistory,
          message: friendlyError(e),
        );
      },
      data: (sessions) {
        final firstIds = _firstAttemptIds(sessions, stats);
        final q = _query.trim().toLowerCase();
        final visible = sessions.where((s) {
          if (q.isNotEmpty && !'${s.scenarioTitle} ${s.workerName} ${s.category}'.toLowerCase().contains(q)) {
            return false;
          }
          return switch (_filter) {
            _HistoryFilter.all => true,
            _HistoryFilter.correct => s.isCorrect,
            _HistoryFilter.incorrect => !s.isCorrect,
            _HistoryFilter.scoring => firstIds.contains(s.id),
            _HistoryFilter.practice => !firstIds.contains(s.id),
            _HistoryFilter.feedback => feedbackBySession.containsKey(s.id),
          };
        }).toList();
        final mayHaveMore = sessions.length >= _limit;

        return ListView(
          padding: EdgeInsets.symmetric(horizontal: Breakpoints.isCompact(context) ? 14 : 24, vertical: 18),
          children: [
            ResponsiveCenter(
              maxWidth: 900,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (workerUid != null) ...[
                    _WorkerSummary(uid: workerUid, name: widget.workerName ?? (workerUid == user.uid ? user.name : '')),
                    const SizedBox(height: 18),
                  ],
                  SearchField(
                    hint: workerUid == null ? context.l10n.searchScenarioOrWorker : context.l10n.searchByScenario,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 12),
                  FilterChipBar<_HistoryFilter>(
                    options: _HistoryFilter.values,
                    selected: _filter,
                    onSelected: (f) => setState(() => _filter = f),
                    label: (f) => f.label,
                    icon: (f) => f.icon,
                  ),
                  const SizedBox(height: 16),
                  if (sessions.isEmpty)
                    EmptyState(
                      icon: Icons.history_rounded,
                      title: context.l10n.noAttemptsYet,
                      message: context.l10n.noAttemptsHint,
                    )
                  else if (visible.isEmpty)
                    EmptyState(
                      icon: Icons.filter_alt_off_rounded,
                      title: context.l10n.nothingMatches,
                      message: context.l10n.tryDifferentSearch,
                    )
                  else
                    for (var i = 0; i < visible.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: StaggeredEntrance(
                          index: i,
                          child: _AttemptCard(
                            session: visible[i],
                            isFirstAttempt: firstIds.contains(visible[i].id),
                            showWorker: workerUid == null,
                            feedback: feedbackBySession[visible[i].id] ?? const [],
                            // Trainers comment on others' answers, never their
                            // own (also enforced by firestore.rules).
                            canGiveFeedback: user.isAdmin && visible[i].workerUid != user.uid,
                            onAddFeedback: () => _addFeedback(user, visible[i]),
                          ),
                        ),
                      ),
                  if (mayHaveMore)
                    Center(
                      child: TextButton.icon(
                        onPressed: () => setState(() => _limit += _pageSize),
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text(
                          context.l10n.loadOlderAttempts,
                          style: appText(13, weight: FontWeight.w600, color: AppColors.info),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Which loaded sessions are their worker's first (scoring) attempt.
  /// Server stats are exact even though only a page is loaded; then the
  /// session's own flag; then order within what's loaded (old sessions of
  /// a worker whose stats aren't built yet).
  Set<String> _firstAttemptIds(List<SafetyTrainingSessionModel> sessions, List<SafetyWorkerStatsModel> stats) {
    final statsByWorker = {for (final s in stats) s.workerUid: s};
    final byWorker = <String, List<SafetyTrainingSessionModel>>{};
    for (final s in sessions) {
      byWorker.putIfAbsent(s.workerUid, () => []).add(s);
    }
    final ids = <String>{};
    for (final entry in byWorker.entries) {
      final ws = statsByWorker[entry.key];
      if (ws != null && ws.firstAttemptSessionIds.isNotEmpty) {
        ids.addAll(entry.value.where((s) => ws.firstAttemptSessionIds[s.scenarioId] == s.id).map((s) => s.id));
        continue;
      }
      final derived = SafetyScoreSummary.fromSessions(
        entry.value,
      ).firstAttemptByScenario.values.map((s) => s.id).toSet();
      ids.addAll(entry.value.where((s) => s.isFirstAttempt ?? derived.contains(s.id)).map((s) => s.id));
    }
    return ids;
  }

  Future<void> _addFeedback(SafetyUser user, SafetyTrainingSessionModel s) async {
    final comment = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppPalette.surface,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => _FeedbackSheet(session: s),
    );
    if (comment == null || comment.isEmpty) return;
    try {
      await ref
          .read(safetyServiceProvider)
          .addFeedback(
            SafetyTrainingFeedbackModel(
              id: '',
              sessionId: s.id,
              workerUid: s.workerUid,
              scenarioTitle: s.scenarioTitle,
              comment: comment,
              byUid: user.uid,
              byName: user.name,
              byRole: user.role ?? '',
              createdAt: DateTime.now(),
            ),
          );
      if (mounted) showSuccessSnack(context, context.l10n.feedbackSentTo(s.workerName));
    } catch (e) {
      widget.logger.e('❌ TrainingHistoryScreen: Failed to add feedback: $e');
      if (mounted) showErrorSnack(context, e, action: context.l10n.couldNotSendFeedback);
    }
  }
}

class _WorkerSummary extends ConsumerWidget {
  const _WorkerSummary({required this.uid, required this.name});

  final String uid;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(workerProgressProvider(uid)).valueOrNull ?? WorkerProgress.empty;
    final summary = progress.summary;
    final active = ref.watch(activeScenariosProvider).valueOrNull;
    final completed = active == null ? null : summary.completedOf(active.map((s) => s.id));
    return HeroPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              WorkerAvatar(name: name, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? context.l10n.worker : name,
                      style: appText(17, weight: FontWeight.w700, color: Colors.white),
                    ),
                    Text(
                      context.l10n.pointsCount(summary.totalPoints),
                      style: appText(13, color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
              ScoreRing(value: summary.accuracy, size: 60, onDark: true),
            ],
          ),
          const SizedBox(height: 14),
          ResponsiveTiles(
            minTileWidth: 140,
            children: [
              StatTile(
                onDark: true,
                label: context.l10n.passedFirstTry,
                value: '${summary.firstTryCorrect}/${summary.scenariosAttempted}',
                icon: Icons.emoji_events_rounded,
              ),
              StatTile(
                onDark: true,
                label: context.l10n.completed,
                value: completed == null ? '—' : '$completed/${active!.length}',
                icon: Icons.task_alt_rounded,
              ),
              StatTile(onDark: true, label: context.l10n.attempts, value: '${summary.totalAttempts}', icon: Icons.replay_rounded),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttemptCard extends StatelessWidget {
  const _AttemptCard({
    required this.session,
    required this.isFirstAttempt,
    required this.showWorker,
    required this.feedback,
    required this.canGiveFeedback,
    required this.onAddFeedback,
  });

  final SafetyTrainingSessionModel session;
  final bool isFirstAttempt;
  final bool showWorker;
  final List<SafetyTrainingFeedbackModel> feedback;
  final bool canGiveFeedback;
  final VoidCallback onAddFeedback;

  static String _duration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    if (m < 60) return '${m}m ${(seconds % 60).toString().padLeft(2, '0')}s';
    return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    final color = s.isCorrect ? AppPalette.green : AppPalette.coral;
    final options = s.options;
    String? describe(int? i) => options != null && i != null && i >= 0 && i < options.length
        ? '${String.fromCharCode(65 + i)}. ${options[i]}'
        : null;
    final answered = describe(s.selectedOptionIndex);
    final correct = s.isCorrect ? null : describe(s.correctOptionIndex);

    return AppCard(
      accent: color,
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon: s.isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded, color: color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.scenarioTitle, style: appText(15, weight: FontWeight.w700)),
                    if (showWorker)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            WorkerAvatar(name: s.workerName, size: 20),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${s.workerName} · ${roleLabel(s.workerRole)}',
                                overflow: TextOverflow.ellipsis,
                                style: appText(12.5, weight: FontWeight.w500, color: AppPalette.inkMuted),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              isFirstAttempt
                  ? StatusPill(
                      label: '+${context.l10n.pointsShort(s.pointsEarned)}',
                      color: s.pointsEarned > 0 ? AppPalette.green : AppPalette.inkMuted,
                      icon: Icons.star_rounded,
                    )
                  : StatusPill(label: context.l10n.filterPractice, color: AppPalette.brightBlue, icon: Icons.replay_rounded),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _meta(Icons.schedule_rounded, '${DateFormat.yMMMd().format(s.completedAt)} · ${DateFormat.Hm().format(s.completedAt)}'),
              if (s.timeTakenSeconds > 0) _meta(Icons.timer_outlined, context.l10n.tookDuration(_duration(s.timeTakenSeconds))),
              if ((s.projectName ?? '').isNotEmpty) _meta(Icons.apartment_rounded, s.projectName!),
            ],
          ),
          if (answered != null) ...[
            const SizedBox(height: 12),
            _answerRow(context.l10n.answered, answered, s.isCorrect ? AppPalette.green : AppPalette.coral),
          ],
          if (correct != null) ...[
            const SizedBox(height: 6),
            _answerRow(context.l10n.correctAnswer, correct, AppPalette.green),
          ],
          if (s.reasoningAnswer.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppPalette.canvas, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.reasoningLabel,
                    style: appText(10.5, weight: FontWeight.w700, color: AppPalette.inkFaint),
                  ),
                  const SizedBox(height: 4),
                  Text('“${s.reasoningAnswer}”', style: appText(13.5, height: 1.5)),
                ],
              ),
            ),
          ],
          for (final f in feedback) _FeedbackBubble(feedback: f),
          if (canGiveFeedback)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TextButton.icon(
                  onPressed: onAddFeedback,
                  icon: const Icon(Icons.rate_review_rounded, size: 18),
                  label: Text(
                    context.l10n.giveFeedback,
                    style: appText(13, weight: FontWeight.w600, color: AppPalette.violet),
                  ),
                  style: TextButton.styleFrom(foregroundColor: AppPalette.violet),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: AppPalette.inkFaint),
      const SizedBox(width: 4),
      Text(text, style: appText(12, color: AppPalette.inkMuted)),
    ],
  );

  Widget _answerRow(String label, String value, Color color) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 96,
        child: Text(
          label,
          style: appText(12, weight: FontWeight.w600, color: AppPalette.inkMuted),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: appText(13, weight: FontWeight.w500, color: color),
        ),
      ),
    ],
  );
}

class _FeedbackBubble extends StatelessWidget {
  const _FeedbackBubble({required this.feedback});

  final SafetyTrainingFeedbackModel feedback;

  @override
  Widget build(BuildContext context) {
    final f = feedback;
    final by = f.byName.isEmpty ? context.l10n.trainer : f.byName;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.violet.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.violet.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkerAvatar(name: by, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$by · ${DateFormat('d MMM, HH:mm').format(f.createdAt)}',
                  style: appText(11.5, weight: FontWeight.w700, color: AppPalette.violet),
                ),
                const SizedBox(height: 2),
                Text(f.comment, style: appText(13, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Owns its controller so it's disposed with the sheet, after the close
/// animation.
class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet({required this.session});

  final SafetyTrainingSessionModel session;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.feedbackFor(widget.session.workerName), style: appText(17, weight: FontWeight.w700)),
          Text(widget.session.scenarioTitle, style: appText(12.5, color: AppPalette.inkMuted)),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: SafetyTrainingFeedbackModel.maxLength,
            style: appText(14, height: 1.45),
            decoration: InputDecoration(
              hintText: context.l10n.feedbackHint,
              hintStyle: appText(13, color: AppPalette.inkFaint),
              filled: true,
              fillColor: AppPalette.canvas,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            label: context.l10n.sendFeedback,
            icon: Icons.send_rounded,
            color: AppPalette.violet,
            expand: true,
            onPressed: text.isEmpty ? null : () => Navigator.pop(context, text),
          ),
        ],
      ),
    );
  }
}
