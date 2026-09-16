import 'dart:io';
import 'dart:typed_data';

import 'package:almaworks/models/safety_training/safety_scenario_model.dart';
import 'package:almaworks/services/safety_training_service.dart';
import 'package:almaworks/utils/lottie_web_safety.dart';
import 'package:almaworks/widgets/safety_training/hazard_scene_visual.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart' as lottie;
import 'package:logger/logger.dart';

/// Which kind of scene media the admin has chosen for this scenario — only
/// one is shown at a time (matching HazardSceneVisual's Rive > Lottie >
/// photo > icon priority), so the form steers the admin toward picking one
/// rather than letting all three linger unused in state.
enum _SceneMediaKind { none, photo, lottieAnim, riveAnim }

/// Admin-only form to author a new safety-training scenario: the hazard
/// scene, an optional real site photo, a graded multiple-choice question,
/// and the free-text reasoning prompt workers will be asked to answer.
class AddScenarioScreen extends StatefulWidget {
  final Logger logger;
  final String createdByUid;
  final String createdByName;
  final String createdByRole;

  const AddScenarioScreen({
    super.key,
    required this.logger,
    required this.createdByUid,
    required this.createdByName,
    required this.createdByRole,
  });

  @override
  State<AddScenarioScreen> createState() => _AddScenarioScreenState();
}

class _AddScenarioScreenState extends State<AddScenarioScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = SafetyTrainingService();

  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _sceneController = TextEditingController();
  final _questionController = TextEditingController();
  final _explanationController = TextEditingController();
  final _reasoningPromptController = TextEditingController(
      text: 'Explain why this could lead to injury and how to prevent it.');
  final List<TextEditingController> _optionControllers =
      List.generate(4, (_) => TextEditingController());

  String _visualKey = SafetyScenarioModel.visualGeneric;
  String _difficulty = SafetyScenarioModel.difficultyBasic;
  int _correctIndex = 0;
  int _points = 10;
  XFile? _pickedImage;
  _SceneMediaKind _mediaKind = _SceneMediaKind.none;
  Uint8List? _pickedLottieBytes;
  String? _pickedLottieName;
  Uint8List? _pickedRiveBytes;
  String? _pickedRiveName;
  bool _isSaving = false;

  static const _visualOptions = <String, String>{
    SafetyScenarioModel.visualFallingObject: 'Falling object',
    SafetyScenarioModel.visualMissingPpe: 'Missing PPE',
    SafetyScenarioModel.visualExposedWiring: 'Exposed wiring',
    SafetyScenarioModel.visualUnguardedEdge: 'Unguarded edge',
    SafetyScenarioModel.visualWetFloor: 'Wet floor / slip',
    SafetyScenarioModel.visualUnsecuredLadder: 'Unsecured ladder',
    SafetyScenarioModel.visualGeneric: 'Generic hazard',
  };

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _sceneController.dispose();
    _questionController.dispose();
    _explanationController.dispose();
    _reasoningPromptController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      setState(() {
        _pickedImage = picked;
        _mediaKind = _SceneMediaKind.photo;
      });
    }
  }

  Future<void> _pickLottie() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (bytes == null) return;

    if (kIsWeb && lottieHasUnsafeWebShapes(bytes)) {
      if (!mounted) return;
      final proceedAnyway = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('This animation may not render on web', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Text(
            'This file uses a "Trim Path" or "Merge Paths" shape, which crashes Flutter Web\'s renderer '
            '(a known Lottie/CanvasKit compatibility issue) — it will still work fine on Android/iOS. '
            'Pick a different animation, or continue only if this scenario won\'t be viewed in a web browser.',
            style: GoogleFonts.poppins(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Pick another file', style: GoogleFonts.poppins())),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Use it anyway', style: GoogleFonts.poppins())),
          ],
        ),
      );
      if (proceedAnyway != true) return;
    }

    setState(() {
      _pickedLottieBytes = bytes;
      _pickedLottieName = file!.name;
      _mediaKind = _SceneMediaKind.lottieAnim;
    });
  }

  Future<void> _pickRive() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['riv'],
      withData: true,
    );
    final file = result?.files.single;
    if (file?.bytes == null) return;
    setState(() {
      _pickedRiveBytes = file!.bytes;
      _pickedRiveName = file.name;
      _mediaKind = _SceneMediaKind.riveAnim;
    });
  }

  void _clearMedia() {
    setState(() {
      _mediaKind = _SceneMediaKind.none;
      _pickedImage = null;
      _pickedLottieBytes = null;
      _pickedLottieName = null;
      _pickedRiveBytes = null;
      _pickedRiveName = null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final options = _optionControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    if (options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Add at least two answer options', style: GoogleFonts.poppins())),
      );
      return;
    }
    if (_correctIndex >= options.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Select which option is correct', style: GoogleFonts.poppins())),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final scenario = SafetyScenarioModel(
        id: '',
        title: _titleController.text.trim(),
        category: _categoryController.text.trim().isEmpty ? 'General' : _categoryController.text.trim(),
        sceneDescription: _sceneController.text.trim(),
        visualKey: _visualKey,
        question: _questionController.text.trim(),
        options: options,
        correctOptionIndex: _correctIndex,
        explanation: _explanationController.text.trim(),
        reasoningPrompt: _reasoningPromptController.text.trim(),
        difficulty: _difficulty,
        points: _points,
        createdByUid: widget.createdByUid,
        createdByName: widget.createdByName,
        createdByRole: widget.createdByRole,
        createdAt: DateTime.now(),
      );
      final scenarioId = await _service.createScenario(scenario);

      switch (_mediaKind) {
        case _SceneMediaKind.photo:
          final picked = _pickedImage;
          if (picked != null) {
            String imageUrl;
            if (kIsWeb) {
              final bytes = await picked.readAsBytes();
              imageUrl = await _service.uploadScenarioImage(scenarioId: scenarioId, bytes: bytes);
            } else {
              imageUrl = await _service.uploadScenarioImage(scenarioId: scenarioId, file: File(picked.path));
            }
            await _service.setScenarioImage(scenarioId, imageUrl);
          }
          break;
        case _SceneMediaKind.lottieAnim:
          final bytes = _pickedLottieBytes;
          if (bytes != null) {
            final lottieUrl = await _service.uploadScenarioLottie(scenarioId: scenarioId, bytes: bytes);
            await _service.setScenarioAnimation(scenarioId, lottieUrl: lottieUrl);
          }
          break;
        case _SceneMediaKind.riveAnim:
          final bytes = _pickedRiveBytes;
          if (bytes != null) {
            final riveUrl = await _service.uploadScenarioRive(scenarioId: scenarioId, bytes: bytes);
            await _service.setScenarioAnimation(scenarioId, riveUrl: riveUrl);
          }
          break;
        case _SceneMediaKind.none:
          break;
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      widget.logger.e('❌ AddScenarioScreen: Failed to save scenario: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save scenario: $e', style: GoogleFonts.poppins())),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: Text('Author Safety Scenario', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF0A2E5A),
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _FormSection(
              icon: Icons.movie_creation_outlined,
              title: 'Scene Media',
              subtitle: 'Optional — falls back to a built-in animated icon if none is set',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMediaPreview(),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _mediaChip(
                        icon: Icons.movie_creation_outlined,
                        label: _pickedRiveName ?? 'Rive (.riv)',
                        active: _mediaKind == _SceneMediaKind.riveAnim,
                        onTap: _pickRive,
                      ),
                      _mediaChip(
                        icon: Icons.animation,
                        label: _pickedLottieName ?? 'Lottie (.json)',
                        active: _mediaKind == _SceneMediaKind.lottieAnim,
                        onTap: _pickLottie,
                      ),
                      _mediaChip(
                        icon: Icons.image_outlined,
                        label: _pickedImage == null ? 'Real photo' : 'Photo selected',
                        active: _mediaKind == _SceneMediaKind.photo,
                        onTap: _pickImage,
                      ),
                      if (_mediaKind != _SceneMediaKind.none)
                        _mediaChip(icon: Icons.close, label: 'Clear', active: false, onTap: _clearMedia, isDestructive: true),
                    ],
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _visualKey,
                    decoration: _inputDecoration('Fallback illustration'),
                    items: _visualOptions.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: GoogleFonts.poppins(fontSize: 14))))
                        .toList(),
                    onChanged: (v) => setState(() => _visualKey = v ?? SafetyScenarioModel.visualGeneric),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _FormSection(
              icon: Icons.description_outlined,
              title: 'Scenario Details',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(_titleController, 'Scenario title', required: true),
                  _field(_categoryController, 'Category (e.g. Falling Objects, PPE, Electrical)'),
                  _field(_sceneController, 'Scene description (what the worker sees)', maxLines: 3, required: true),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _FormSection(
              icon: Icons.quiz_outlined,
              title: 'Answer Options',
              subtitle: 'Select the radio button beside the correct answer',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(_questionController, 'Question (e.g. "What is the hazard here?")', required: true, topPadding: 0),
                  const SizedBox(height: 12),
                  RadioGroup<int>(
                    groupValue: _correctIndex,
                    onChanged: (v) => setState(() => _correctIndex = v ?? 0),
                    child: Column(
                      children: List.generate(4, (i) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Radio<int>(value: i),
                              Expanded(
                                child: TextFormField(
                                  controller: _optionControllers[i],
                                  style: GoogleFonts.poppins(fontSize: 14),
                                  decoration: _inputDecoration(i < 2 ? 'Option ${i + 1} (required)' : 'Option ${i + 1} (optional)'),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _FormSection(
              icon: Icons.lightbulb_outline,
              title: 'Feedback & Scoring',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(_explanationController, 'Explanation shown after answering', maxLines: 3, required: true, topPadding: 0),
                  _field(_reasoningPromptController, 'Free-text reasoning prompt', maxLines: 2, required: true),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _difficulty,
                          decoration: _inputDecoration('Difficulty'),
                          items: [SafetyScenarioModel.difficultyBasic, SafetyScenarioModel.difficultyIntermediate, SafetyScenarioModel.difficultyAdvanced]
                              .map((d) => DropdownMenuItem(value: d, child: Text(d, style: GoogleFonts.poppins(fontSize: 14))))
                              .toList(),
                          onChanged: (v) => setState(() => _difficulty = v ?? SafetyScenarioModel.difficultyBasic),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          initialValue: '$_points',
                          style: GoogleFonts.poppins(fontSize: 14),
                          decoration: _inputDecoration('Points'),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => _points = int.tryParse(v) ?? 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSaving ? null : () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    foregroundColor: const Color(0xFF5A6472),
                  ),
                  child: Text('Cancel', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A2E5A),
                    disabledBackgroundColor: const Color(0xFF0A2E5A).withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Save Scenario', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaChip({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? const Color(0xFFC62828) : const Color(0xFF0A2E5A);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: active ? color.withValues(alpha: 0.1) : const Color(0xFFF7F8FA),
          border: Border.all(color: active ? color : const Color(0xFFE0E4EA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.poppins(fontSize: 12.5, color: color, fontWeight: active ? FontWeight.w600 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]),
      filled: true,
      fillColor: const Color(0xFFF7F8FA),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF0A2E5A), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Widget _buildMediaPreview() {
    switch (_mediaKind) {
      case _SceneMediaKind.lottieAnim:
        final bytes = _pickedLottieBytes;
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 160,
            width: double.infinity,
            color: const Color(0xFFECEFF1),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(12),
            child: bytes == null
                ? const SizedBox()
                : lottie.Lottie.memory(
                    bytes,
                    // contain, not cover — matches HazardSceneVisual, so what
                    // the admin previews here is what workers will actually
                    // see (no crop the upload flow hides from them).
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Text('Could not preview this file — is it a valid Lottie JSON?',
                          style: GoogleFonts.poppins(fontSize: 12), textAlign: TextAlign.center),
                    ),
                  ),
          ),
        );
      case _SceneMediaKind.riveAnim:
        // rive's runtime needs an async RiveFile.import step to render from
        // raw bytes, so — unlike Lottie — there's no cheap synchronous
        // in-memory preview here; confirm the pick and defer actual
        // rendering to HazardSceneVisual.network after upload on Save.
        return Container(
          height: 160,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF0A2E5A).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF0A2E5A).withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.movie_creation_outlined, size: 40, color: Color(0xFF0A2E5A)),
              const SizedBox(height: 8),
              Text('${_pickedRiveName ?? "Rive file"} selected',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
              Text('Preview available after saving', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[600])),
            ],
          ),
        );
      case _SceneMediaKind.photo:
        final picked = _pickedImage;
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: picked == null
              ? const SizedBox(height: 160)
              : kIsWeb
                  ? FutureBuilder<Uint8List>(
                      future: picked.readAsBytes(),
                      builder: (context, snap) => snap.hasData
                          ? Image.memory(snap.data!, height: 160, width: double.infinity, fit: BoxFit.cover)
                          : const SizedBox(height: 160),
                    )
                  : Image.file(File(picked.path), height: 160, width: double.infinity, fit: BoxFit.cover),
        );
      case _SceneMediaKind.none:
        return HazardSceneVisual(visualKey: _visualKey, height: 160);
    }
  }

  Widget _field(TextEditingController controller, String label, {int maxLines = 1, bool required = false, double topPadding = 12}) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        style: GoogleFonts.poppins(fontSize: 14),
        decoration: _inputDecoration(label),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
      ),
    );
  }
}

/// Card chrome for one logical group of fields on this form — gives the
/// screen a clear visual hierarchy (Scene Media / Scenario Details / Answer
/// Options / Feedback & Scoring) instead of one long undifferentiated list.
class _FormSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  const _FormSection({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A2E5A).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFF0A2E5A), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 42),
              child: Text(subtitle!, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
