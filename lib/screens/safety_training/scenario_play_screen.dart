import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/models/safety_training/safety_scenario_model.dart';
import 'package:almaworks/models/safety_training/safety_training_session_model.dart';
import 'package:almaworks/services/safety_training_service.dart';
import 'package:almaworks/widgets/safety_training/hazard_scene_visual.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';

/// Plays a single scenario: the animated hazard scene, a graded
/// multiple-choice hazard question, then a free-text reasoning prompt
/// ("explain why / how to prevent it") before recording the session.
class ScenarioPlayScreen extends StatefulWidget {
  final SafetyScenarioModel scenario;
  final ProjectModel project;
  final Logger logger;
  final String workerUid;
  final String workerName;
  final String workerRole;

  const ScenarioPlayScreen({
    super.key,
    required this.scenario,
    required this.project,
    required this.logger,
    required this.workerUid,
    required this.workerName,
    required this.workerRole,
  });

  @override
  State<ScenarioPlayScreen> createState() => _ScenarioPlayScreenState();
}

enum _Stage { question, reasoning, result }

class _ScenarioPlayScreenState extends State<ScenarioPlayScreen> {
  final SafetyTrainingService _service = SafetyTrainingService();
  final _reasoningController = TextEditingController();
  final _stopwatch = Stopwatch()..start();

  _Stage _stage = _Stage.question;
  int? _selectedOption;
  bool _isSaving = false;

  bool get _isCorrect => _selectedOption == widget.scenario.correctOptionIndex;

  @override
  void dispose() {
    _reasoningController.dispose();
    super.dispose();
  }

  void _submitAnswer() {
    if (_selectedOption == null) return;
    setState(() => _stage = _Stage.reasoning);
  }

  Future<void> _submitReasoning() async {
    setState(() => _isSaving = true);
    final session = SafetyTrainingSessionModel(
      id: '',
      scenarioId: widget.scenario.id,
      scenarioTitle: widget.scenario.title,
      category: widget.scenario.category,
      projectId: widget.project.id,
      projectName: widget.project.name,
      workerUid: widget.workerUid,
      workerName: widget.workerName,
      workerRole: widget.workerRole,
      selectedOptionIndex: _selectedOption!,
      isCorrect: _isCorrect,
      reasoningAnswer: _reasoningController.text.trim(),
      pointsEarned: _isCorrect ? widget.scenario.points : 0,
      timeTakenSeconds: _stopwatch.elapsed.inSeconds,
      completedAt: DateTime.now(),
    );
    try {
      await _service.recordSession(session);
      if (!mounted) return;
      setState(() {
        _stage = _Stage.result;
        _isSaving = false;
      });
    } catch (e) {
      widget.logger.e('❌ ScenarioPlayScreen: Failed to record session: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save your result. Please try again.', style: GoogleFonts.poppins())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scenario = widget.scenario;
    return Scaffold(
      appBar: AppBar(
        title: Text(scenario.title, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF0A2E5A),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF4F6F9),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HazardSceneVisual(
              visualKey: scenario.visualKey,
              imageUrl: scenario.imageUrl,
              lottieUrl: scenario.lottieUrl,
              riveUrl: scenario.riveUrl,
            ),
            const SizedBox(height: 16),
            _SectionCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A2E5A).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.visibility_outlined, color: Color(0xFF0A2E5A), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(scenario.sceneDescription, style: GoogleFonts.poppins(fontSize: 14, height: 1.5)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: switch (_stage) {
                _Stage.question => _buildQuestionStage(),
                _Stage.reasoning => _buildReasoningStage(),
                _Stage.result => _buildResultStage(),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionStage() {
    final scenario = widget.scenario;
    return _SectionCard(
      key: const ValueKey('question'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(scenario.question, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, height: 1.3)),
          const SizedBox(height: 16),
          ...List.generate(scenario.options.length, (i) {
            final selected = _selectedOption == i;
            final letter = String.fromCharCode(65 + i);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _selectedOption = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: selected ? const Color(0xFF0A2E5A).withValues(alpha: 0.06) : Colors.white,
                    border: Border.all(
                      color: selected ? const Color(0xFF0A2E5A) : const Color(0xFFE0E4EA),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? const Color(0xFF0A2E5A) : const Color(0xFFF1F3F6),
                        ),
                        child: selected
                            ? const Icon(Icons.check, color: Colors.white, size: 18)
                            : Text(letter,
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF5A6472))),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          scenario.options[i],
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            height: 1.35,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                            color: selected ? const Color(0xFF0A2E5A) : const Color(0xFF2B2F36),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 4),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _selectedOption == null ? null : _submitAnswer,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2E5A),
                disabledBackgroundColor: const Color(0xFF0A2E5A).withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('Continue', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReasoningStage() {
    return _SectionCard(
      key: const ValueKey('reasoning'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.scenario.reasoningPrompt,
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, height: 1.3)),
          const SizedBox(height: 6),
          Text(
            'In your own words — this helps your trainer see how well you understand the risk.',
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600], height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reasoningController,
            maxLines: 5,
            style: GoogleFonts.poppins(fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF7F8FA),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF0A2E5A), width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(14),
              hintText: 'Explain the cause and how to prevent it...',
              hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[500]),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: (_isSaving || _reasoningController.text.trim().isEmpty) ? null : _submitReasoning,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2E5A),
                disabledBackgroundColor: const Color(0xFF0A2E5A).withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Submit', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultStage() {
    final scenario = widget.scenario;
    final accent = _isCorrect ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    return _SectionCard(
      key: const ValueKey('result'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            builder: (context, value, child) => Transform.scale(scale: value, child: child),
            child: Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: 0.12)),
                child: Icon(
                  _isCorrect ? Icons.check_circle : Icons.cancel,
                  color: accent,
                  size: 56,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              _isCorrect ? 'Correct! +${scenario.points} pts' : 'Not quite right',
              style: GoogleFonts.poppins(fontSize: 19, fontWeight: FontWeight.bold, color: accent),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lightbulb_outline, size: 18, color: Color(0xFF0A2E5A)),
                    const SizedBox(width: 8),
                    Text('Why it matters', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(scenario.explanation, style: GoogleFonts.poppins(fontSize: 13.5, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2E5A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('Done', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared card chrome for every stage below the hazard scene — gives the
/// screen a consistent, breathable rhythm instead of raw text/buttons
/// sitting directly on the scaffold background.
class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}
