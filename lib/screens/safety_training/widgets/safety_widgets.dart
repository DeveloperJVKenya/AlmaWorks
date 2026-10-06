import 'package:almaworks/models/safety_training/safety_scenario_model.dart';
import 'package:almaworks/models/safety_training/safety_training_review_model.dart';
import 'package:almaworks/widgets/modern/modern_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final safetyDate = DateFormat('MMM d, yyyy');

/// How a worker's current determination reads *now* — a lapsed clearance
/// or overdue retraining shows as such, not as the status first recorded.
class StandingVisual {
  final String label;
  final Color color;
  final IconData icon;
  final String? detail;

  const StandingVisual(this.label, this.color, this.icon, [this.detail]);

  static const notReviewed = StandingVisual('Not Reviewed', AppPalette.inkMuted, Icons.hourglass_empty_rounded);

  factory StandingVisual.of(SafetyTrainingReviewModel? review, RetrainingProgress? retraining, DateTime now) {
    if (review == null) return notReviewed;
    if (review.isCleared) {
      return review.isClearanceExpired(now)
          ? StandingVisual(
              'Clearance Expired',
              AppPalette.orange,
              Icons.history_toggle_off_rounded,
              'Lapsed on ${safetyDate.format(review.clearanceExpiresAt)} — a new review is needed.',
            )
          : StandingVisual(
              'Cleared to Work',
              AppPalette.green,
              Icons.verified_rounded,
              'Valid until ${safetyDate.format(review.clearanceExpiresAt)}',
            );
    }
    if (review.isNeedsRetraining) {
      final overdue = retraining?.isOverdue(now) ?? false;
      final done = retraining != null && retraining.assigned.isNotEmpty && retraining.isComplete;
      final due = retraining?.dueAt;
      final detail = retraining == null || retraining.assigned.isEmpty
          ? null
          : done
          ? 'All ${retraining.assigned.length} assigned scenarios done — awaiting a new review.'
          : '${retraining.done} of ${retraining.assigned.length} assigned scenarios done'
                '${due == null
                    ? ''
                    : overdue
                    ? ' · overdue since ${safetyDate.format(due)}'
                    : ' · due ${safetyDate.format(due)}'}';
      if (overdue) return StandingVisual('Retraining Overdue', AppPalette.coral, Icons.alarm_rounded, detail);
      if (done) return StandingVisual('Retraining Done', AppPalette.teal, Icons.task_alt_rounded, detail);
      return StandingVisual('Needs Retraining', AppPalette.amber, Icons.replay_circle_filled_rounded, detail);
    }
    if (review.isEscalated) {
      final to = review.escalatedToName;
      return StandingVisual(
        'Escalated',
        AppPalette.coral,
        Icons.report_rounded,
        to == null || to.isEmpty ? 'A supervisor will follow up.' : 'Escalated to $to for follow-up.',
      );
    }
    return const StandingVisual('Status Unknown', AppPalette.inkMuted, Icons.help_outline_rounded);
  }
}

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
        prefixIcon: const Icon(Icons.search_rounded, color: AppPalette.inkFaint),
        filled: true,
        fillColor: AppPalette.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppPalette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppPalette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppPalette.brightBlue, width: 1.5),
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
