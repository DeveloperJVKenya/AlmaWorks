import 'dart:async';

import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/models/safety_training/safety_scenario_model.dart';
import 'package:almaworks/screens/safety_training/safety_training_providers.dart';
import 'package:almaworks/services/safety_training_service.dart';
import 'package:almaworks/widgets/modern/modern_ui.dart';
import 'package:almaworks/widgets/safety_training/hazard_scene_visual.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

enum _Stage { question, reasoning, result }

/// Plays one scenario: observe the hazard scene, choose an answer, explain
/// the reasoning in your own words, then see the server-graded result.
/// Side-by-side on wide screens, stacked on phones.
class ScenarioPlayScreen extends ConsumerStatefulWidget {
  const ScenarioPlayScreen({super.key, required this.scenario, required this.project, required this.logger});

  final SafetyScenarioModel scenario;
  final ProjectModel project;
  final Logger logger;

  @override
  ConsumerState<ScenarioPlayScreen> createState() => _ScenarioPlayScreenState();
}

class _ScenarioPlayScreenState extends ConsumerState<ScenarioPlayScreen> {
  final _reasoningController = TextEditingController();
  final _stopwatch = Stopwatch()..start();

  // Must match SAFETY_REASONING_MIN/MAX_LENGTH in functions/safetyTraining.js
  // — a one-word answer gives a trainer nothing to review.
  static const _minReasoningLength = 20;
  static const _maxReasoningLength = 2000;

  _Stage _stage = _Stage.question;
  int? _selectedOption;
  bool _isSaving = false;
  String? _submitError;

  /// Generated on the first submit of an attempt and reused by any retry,
  /// so a retry after a lost response can't record the attempt twice.
  String? _attemptId;

  /// The server's grading — the client never holds the answer key.
  SafetyAttemptResult? _result;

  SafetyScenarioModel get _scenario => widget.scenario;

  @override
  void dispose() {
    _reasoningController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final service = ref.read(safetyServiceProvider);
    _attemptId ??= service.newAttemptId();
    setState(() {
      _isSaving = true;
      _submitError = null;
    });
    try {
      final result = await service.submitAttempt(
        attemptId: _attemptId!,
        scenarioId: _scenario.id,
        selectedOptionIndex: _selectedOption!,
        reasoningAnswer: _reasoningController.text.trim(),
        timeTakenSeconds: _stopwatch.elapsed.inSeconds,
        projectId: widget.project.id,
        projectName: widget.project.name,
      );
      _stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _result = result;
        _stage = _Stage.result;
        _isSaving = false;
      });
    } on FirebaseFunctionsException catch (e) {
      widget.logger.e('❌ ScenarioPlayScreen: Grading failed: ${e.code} ${e.message}');
      const userFacing = {'invalid-argument', 'failed-precondition', 'not-found', 'permission-denied'};
      _fail(
        userFacing.contains(e.code) && e.message != null
            ? e.message!
            : 'Your answer couldn\'t be submitted. Check your connection and tap Retry.',
      );
    } on TimeoutException {
      widget.logger.w('⚠️ ScenarioPlayScreen: Attempt $_attemptId not confirmed in time');
      _fail(
        'We couldn\'t confirm your answer was saved. Check your connection and tap Retry — '
        'it won\'t be counted twice.',
      );
    } catch (e) {
      widget.logger.e('❌ ScenarioPlayScreen: Failed to submit attempt: $e');
      _fail('Your answer couldn\'t be submitted. Tap Retry to try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _submitError = message;
    });
  }

  void _practiceAgain() {
    setState(() {
      _stage = _Stage.question;
      _selectedOption = null;
      _result = null;
      _attemptId = null;
      _submitError = null;
      _reasoningController.clear();
      _stopwatch
        ..reset()
        ..start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _scenario;
    return Scaffold(
      backgroundColor: AppPalette.canvas,
      appBar: modernAppBar(context, title: s.title, subtitle: '${s.category} · ${s.difficulty} · ${s.points} pts'),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= Breakpoints.medium;
          final pad = constraints.maxWidth < Breakpoints.compact ? 14.0 : 24.0;
          final scene = _SceneColumn(scenario: s, sceneHeight: wide ? 320 : 220);
          final panel = s.options.length < 2
              ? AppCard(
                  child: Row(
                    children: [
                      const IconBadge(icon: Icons.error_outline_rounded, color: AppPalette.coral),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This scenario is incomplete and can\'t be answered yet. Please let an admin know.',
                          style: appText(14, color: AppPalette.coral),
                        ),
                      ),
                    ],
                  ),
                )
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0.03, 0), end: Offset.zero).animate(animation),
                      child: child,
                    ),
                  ),
                  child: switch (_stage) {
                    _Stage.question => _buildQuestion(),
                    _Stage.reasoning => _buildReasoning(),
                    _Stage.result => _buildResult(),
                  },
                );

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 40),
            child: ResponsiveCenter(
              maxWidth: 1180,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StepIndicator(current: _stage.index + 1),
                  const SizedBox(height: 18),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: scene),
                        const SizedBox(width: 22),
                        Expanded(flex: 6, child: panel),
                      ],
                    )
                  else ...[
                    scene,
                    const SizedBox(height: 16),
                    panel,
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Stage 1: choose an answer ─────────────────────────────────────────────

  Widget _buildQuestion() {
    return AppCard(
      key: const ValueKey('question'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'QUESTION',
            style: appText(11, weight: FontWeight.w700, color: AppPalette.brightBlue),
          ),
          const SizedBox(height: 6),
          Text(_scenario.question, style: appText(17, weight: FontWeight.w700, height: 1.35)),
          const SizedBox(height: 18),
          for (var i = 0; i < _scenario.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _OptionTile(
                index: i,
                text: _scenario.options[i],
                selected: _selectedOption == i,
                onTap: () => setState(() => _selectedOption = i),
              ),
            ),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            expand: true,
            onPressed: _selectedOption == null ? null : () => setState(() => _stage = _Stage.reasoning),
          ),
        ],
      ),
    );
  }

  // ── Stage 2: explain ──────────────────────────────────────────────────────

  Widget _buildReasoning() {
    final trimmed = _reasoningController.text.trim().length;
    final short = trimmed < _minReasoningLength;
    final i = _selectedOption!;
    return AppCard(
      key: const ValueKey('reasoning'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppPalette.skyBlue, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                _LetterBadge(index: i, selected: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your answer', style: appText(11, color: AppPalette.inkMuted)),
                      Text(_scenario.options[i], style: appText(13.5, weight: FontWeight.w600)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _isSaving ? null : () => setState(() => _stage = _Stage.question),
                  child: Text(
                    'Change',
                    style: appText(12.5, weight: FontWeight.w600, color: AppPalette.brightBlue),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'EXPLAIN YOUR THINKING',
            style: appText(11, weight: FontWeight.w700, color: AppPalette.brightBlue),
          ),
          const SizedBox(height: 6),
          Text(_scenario.reasoningPrompt, style: appText(16, weight: FontWeight.w700, height: 1.35)),
          const SizedBox(height: 4),
          Text(
            'In your own words — this helps your trainer see how well you understand the risk.',
            style: appText(12.5, color: AppPalette.inkMuted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _reasoningController,
            enabled: !_isSaving,
            minLines: 4,
            maxLines: 8,
            maxLength: _maxReasoningLength,
            buildCounter: (context, {required currentLength, required isFocused, maxLength}) => Text(
              short ? '${_minReasoningLength - trimmed} more characters needed' : '$currentLength / $maxLength',
              style: appText(11.5, color: short ? AppPalette.orange : AppPalette.inkFaint),
            ),
            style: appText(14, height: 1.45),
            decoration: InputDecoration(
              hintText: 'Explain the cause and how to prevent it…',
              hintStyle: appText(13.5, color: AppPalette.inkFaint),
              filled: true,
              fillColor: AppPalette.canvas,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppPalette.brightBlue, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppPalette.coral.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppPalette.coral.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppPalette.coral, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_submitError!, style: appText(12.5, color: AppPalette.coral, height: 1.35)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          PrimaryButton(
            label: _isSaving ? 'Submitting your answer…' : (_submitError != null ? 'Retry' : 'Submit answer'),
            icon: _submitError != null ? Icons.refresh_rounded : Icons.send_rounded,
            loading: _isSaving,
            expand: true,
            onPressed: short ? null : _submit,
          ),
        ],
      ),
    );
  }

  // ── Stage 3: result ───────────────────────────────────────────────────────

  Widget _buildResult() {
    final result = _result!;
    final correct = result.isCorrect;
    final accent = correct ? AppPalette.green : AppPalette.coral;
    final ci = result.correctOptionIndex;
    final hasCorrect = ci >= 0 && ci < _scenario.options.length;
    return AppCard(
      key: const ValueKey('result'),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, v, child) => Transform.scale(scale: v, child: child),
            child: Center(
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [accent.withValues(alpha: 0.18), accent.withValues(alpha: 0.06)]),
                ),
                child: Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded, color: accent, size: 60),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            correct ? 'Correct — well spotted!' : 'Not quite right',
            textAlign: TextAlign.center,
            style: appText(21, weight: FontWeight.w800, color: accent),
          ),
          const SizedBox(height: 8),
          Center(
            child: result.isFirstAttempt
                ? StatusPill(
                    label: correct ? '+${result.pointsEarned} points' : 'No points this time',
                    color: correct ? AppPalette.green : AppPalette.inkMuted,
                    icon: Icons.star_rounded,
                  )
                : const StatusPill(
                    label: 'Practice attempt — only your first attempt scores',
                    color: AppPalette.brightBlue,
                    icon: Icons.replay_rounded,
                  ),
          ),
          if (!correct && hasCorrect) ...[
            const SizedBox(height: 18),
            _AnswerLine(label: 'Correct answer', index: ci, text: _scenario.options[ci], color: AppPalette.green),
          ],
          if (_selectedOption != null) ...[
            const SizedBox(height: 8),
            _AnswerLine(
              label: 'Your answer',
              index: _selectedOption!,
              text: _scenario.options[_selectedOption!],
              color: correct ? AppPalette.green : AppPalette.coral,
            ),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppPalette.skyBlue, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lightbulb_rounded, size: 19, color: AppPalette.amber),
                    const SizedBox(width: 8),
                    Text('Why it matters', style: appText(13.5, weight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  result.explanation.isEmpty ? 'No explanation was provided for this scenario.' : result.explanation,
                  style: appText(13.5, height: 1.55),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _practiceAgain,
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: Text(
                  'Practice again',
                  style: appText(13.5, weight: FontWeight.w600, color: AppPalette.deepBlue),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  side: const BorderSide(color: AppPalette.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              PrimaryButton(
                label: 'Back to scenarios',
                icon: Icons.grid_view_rounded,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SceneColumn extends StatelessWidget {
  const _SceneColumn({required this.scenario, required this.sceneHeight});

  final SafetyScenarioModel scenario;
  final double sceneHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(8),
          child: HazardSceneVisual(
            visualKey: scenario.visualKey,
            imageUrl: scenario.imageUrl,
            lottieUrl: scenario.lottieUrl,
            riveUrl: scenario.riveUrl,
            height: sceneHeight,
          ),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconBadge(icon: Icons.visibility_rounded, color: AppPalette.brightBlue, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WHAT YOU SEE',
                      style: appText(11, weight: FontWeight.w700, color: AppPalette.brightBlue),
                    ),
                    const SizedBox(height: 4),
                    Text(scenario.sceneDescription, style: appText(14, height: 1.55)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Observe → Answer → Explain → Result.
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current});

  /// 1 = answering, 2 = explaining, 3 = result (observing is always done).
  final int current;

  static const _steps = ['Observe', 'Answer', 'Explain', 'Result'];

  @override
  Widget build(BuildContext context) {
    final compact = Breakpoints.isCompact(context);
    return Row(
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: i <= current ? AppPalette.brightBlue : AppPalette.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          _step(i, compact),
        ],
      ],
    );
  }

  Widget _step(int i, bool compact) {
    final done = i < current;
    final active = i == current;
    final color = done || active ? AppPalette.brightBlue : AppPalette.inkFaint;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? AppPalette.brightBlue : (active ? AppPalette.skyBlue : AppPalette.surface),
            border: Border.all(color: color, width: 1.5),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
              : Text(
                  '${i + 1}',
                  style: appText(12, weight: FontWeight.w700, color: color),
                ),
        ),
        if (!compact) ...[
          const SizedBox(width: 6),
          Text(
            _steps[i],
            style: appText(12.5, weight: active ? FontWeight.w700 : FontWeight.w500, color: color),
          ),
        ],
      ],
    );
  }
}

class _LetterBadge extends StatelessWidget {
  const _LetterBadge({required this.index, required this.selected});

  final int index;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? AppPalette.deepBlue : AppPalette.canvas,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        String.fromCharCode(65 + index),
        style: appText(13.5, weight: FontWeight.w700, color: selected ? Colors.white : AppPalette.inkMuted),
      ),
    );
  }
}

class _OptionTile extends StatefulWidget {
  const _OptionTile({required this.index, required this.text, required this.selected, required this.onTap});

  final int index;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<_OptionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected ? AppPalette.skyBlue : (_hovered ? AppPalette.canvas : AppPalette.surface),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppPalette.brightBlue
                : (_hovered ? AppPalette.brightBlue.withValues(alpha: 0.4) : AppPalette.border),
            width: selected ? 2 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _LetterBadge(index: widget.index, selected: selected),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.text,
                      style: appText(14, weight: selected ? FontWeight.w600 : FontWeight.w400, height: 1.35),
                    ),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: selected ? 1 : 0,
                    child: const Icon(Icons.check_circle_rounded, color: AppPalette.brightBlue),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnswerLine extends StatelessWidget {
  const _AnswerLine({required this.label, required this.index, required this.text, required this.color});

  final String label;
  final int index;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
            child: Text(
              String.fromCharCode(65 + index),
              style: appText(12.5, weight: FontWeight.w700, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: appText(11, color: AppPalette.inkMuted)),
                Text(
                  text,
                  style: appText(13.5, weight: FontWeight.w600, color: AppPalette.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
