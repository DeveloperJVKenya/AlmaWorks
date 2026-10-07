import 'package:almaworks/models/safety_training/safety_scenario_model.dart';
import 'package:almaworks/models/safety_training/safety_training_review_model.dart';
import 'package:almaworks/widgets/modern/modern_ui.dart';
import 'package:almaworks/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:almaworks/core/l10n/l10n.dart';

/// Medium date in the app language ("12 ott 2026" / "Oct 12, 2026").
DateFormat get safetyDate => DateFormat.yMMMd();

/// How a worker's current determination reads *now* — a lapsed clearance
/// or overdue retraining shows as such, not as the status first recorded.
class StandingVisual {
  final String label;
  final Color color;
  final IconData icon;
  final String? detail;

  const StandingVisual(this.label, this.color, this.icon, [this.detail]);

  static StandingVisual get notReviewed =>
      StandingVisual(l10nNow.stNotReviewed, AppPalette.inkMuted, Icons.hourglass_empty_rounded);

  factory StandingVisual.of(SafetyTrainingReviewModel? review, RetrainingProgress? retraining, DateTime now) {
    if (review == null) return notReviewed;
    final l = l10nNow;
    if (review.isCleared) {
      return review.isClearanceExpired(now)
          ? StandingVisual(
              l.stClearanceExpired,
              AppPalette.orange,
              Icons.history_toggle_off_rounded,
              l.stClearanceLapsedOn(safetyDate.format(review.clearanceExpiresAt)),
            )
          : StandingVisual(
              l.stClearedToWork,
              AppPalette.green,
              Icons.verified_rounded,
              l.stValidUntil(safetyDate.format(review.clearanceExpiresAt)),
            );
    }
    if (review.isNeedsRetraining) {
      final overdue = retraining?.isOverdue(now) ?? false;
      final done = retraining != null && retraining.assigned.isNotEmpty && retraining.isComplete;
      final due = retraining?.dueAt;
      final detail = retraining == null || retraining.assigned.isEmpty
          ? null
          : done
          ? l.stAllAssignedDone(retraining.assigned.length)
          : l.stAssignedProgress(retraining.done, retraining.assigned.length) +
                (due == null
                    ? ''
                    : overdue
                    ? l.stOverdueSince(safetyDate.format(due))
                    : l.stDue(safetyDate.format(due)));
      if (overdue) return StandingVisual(l.stRetrainingOverdue, AppPalette.coral, Icons.alarm_rounded, detail);
      if (done) return StandingVisual(l.stRetrainingDone, AppPalette.teal, Icons.task_alt_rounded, detail);
      return StandingVisual(l.stNeedsRetraining, AppPalette.amber, Icons.replay_circle_filled_rounded, detail);
    }
    if (review.isEscalated) {
      final to = review.escalatedToName;
      return StandingVisual(
        l.stEscalated,
        AppPalette.coral,
        Icons.report_rounded,
        to == null || to.isEmpty ? l.stSupervisorFollowUp : l.stEscalatedTo(to),
      );
    }
    return StandingVisual(l.stStatusUnknown, AppPalette.inkMuted, Icons.help_outline_rounded);
  }
}

/// Display name for a stored difficulty ('Basic' / 'Intermediate' / 'Advanced').
String difficultyLabel(String difficulty) => switch (difficulty) {
  SafetyScenarioModel.difficultyAdvanced => l10nNow.difficultyAdvanced,
  SafetyScenarioModel.difficultyIntermediate => l10nNow.difficultyIntermediate,
  SafetyScenarioModel.difficultyBasic => l10nNow.difficultyBasic,
  _ => difficulty,
};

/// Categories are typed by admins; only the default one is translated.
String safetyCategoryLabel(String category) => category == 'General' ? l10nNow.categoryGeneral : category;

Color difficultyColor(String difficulty) => switch (difficulty) {
  SafetyScenarioModel.difficultyAdvanced => AppPalette.coral,
  SafetyScenarioModel.difficultyIntermediate => AppPalette.amber,
  _ => AppPalette.green,
};

/// Initials on a brand gradient.
class WorkerAvatar extends StatelessWidget {
  const WorkerAvatar({super.key, required this.name, this.size = 44});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.length == 1 ? parts.first.substring(0, 1) : '${parts.first[0]}${parts.last[0]}').toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppPalette.heroGradient),
      child: Text(
        initials,
        style: appText(size * 0.36, weight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

/// Rounded progress bar with a label row.
class LabeledProgress extends StatelessWidget {
  const LabeledProgress({
    super.key,
    required this.label,
    required this.value,
    required this.trailing,
    this.color = AppPalette.brightBlue,
    this.onDark = false,
  });

  final String label;
  final double value;
  final String trailing;
  final Color color;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final textColor = onDark ? Colors.white.withValues(alpha: 0.85) : AppPalette.inkMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: appText(12, color: textColor)),
            ),
            Text(
              trailing,
              style: appText(12, weight: FontWeight.w600, color: onDark ? Colors.white : AppPalette.ink),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: value.clamp(0, 1),
            minHeight: 8,
            backgroundColor: onDark ? Colors.white.withValues(alpha: 0.18) : AppPalette.border,
            valueColor: AlwaysStoppedAnimation(onDark ? Colors.white : color),
          ),
        ),
      ],
    );
  }
}

/// Circular percentage indicator, animated from zero.
class ScoreRing extends StatelessWidget {
  const ScoreRing({
    super.key,
    required this.value,
    this.size = 64,
    this.color = AppPalette.brightBlue,
    this.onDark = false,
  });

  final double value;
  final double size;
  final Color color;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: v,
              strokeWidth: size * 0.11,
              strokeCap: StrokeCap.round,
              backgroundColor: onDark ? Colors.white.withValues(alpha: 0.18) : AppPalette.border,
              valueColor: AlwaysStoppedAnimation(onDark ? Colors.white : color),
            ),
            Center(
              child: Text(
                '${(v * 100).round()}%',
                style: appText(size * 0.24, weight: FontWeight.w700, color: onDark ? Colors.white : AppPalette.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Search box in the shared style.
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.hint, required this.onChanged});

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      style: appText(14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: appText(13.5, color: AppPalette.inkFaint),
        prefixIcon: Icon(Icons.search_rounded, color: AppPalette.inkFaint),
        filled: true,
        fillColor: AppPalette.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppPalette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppPalette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.info, width: 1.5),
        ),
      ),
    );
  }
}

/// Lays out cards in a responsive grid (1–3 columns by width).
class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.maxColumns = 3,
    this.minItemWidth = 340,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final int maxColumns;
  final double minItemWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        final columns = (constraints.maxWidth / minItemWidth).floor().clamp(1, maxColumns);
        final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var i = 0; i < itemCount; i++)
              SizedBox(
                width: width,
                child: StaggeredEntrance(index: i, child: itemBuilder(context, i)),
              ),
          ],
        );
      },
    );
  }
}
