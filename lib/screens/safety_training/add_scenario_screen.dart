import 'dart:io';
import 'dart:typed_data';

import 'package:almaworks/models/safety_training/safety_scenario_model.dart';
import 'package:almaworks/screens/safety_training/safety_training_providers.dart';
import 'package:almaworks/services/safety_training_service.dart';
import 'package:almaworks/utils/lottie_assets.dart';
import 'package:almaworks/utils/lottie_web_safety.dart';
import 'package:almaworks/widgets/modern/modern_ui.dart';
import 'package:almaworks/widgets/safety_training/hazard_scene_visual.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart' as lottie;
import 'package:logger/logger.dart';

/// Which kind of scene media the admin has chosen for this scenario — only
/// one is shown at a time (matching HazardSceneVisual's Rive > Lottie >
/// photo > icon priority), so the form steers the admin toward picking one
/// rather than letting all three linger unused in state.
/// `existing` means the scenario's already-uploaded media is kept as is
/// (edit mode only).
enum _SceneMediaKind { none, existing, photo, lottieAnim, riveAnim }

/// Admin-only form to author a new safety-training scenario — or edit one,
/// when [existing] is given: the hazard scene, an optional real site photo,
/// a graded multiple-choice question, and the free-text reasoning prompt
/// workers will be asked to answer. The author/editor is the signed-in
/// user (safetyUserProvider).
class AddScenarioScreen extends ConsumerStatefulWidget {
  final Logger logger;
  final SafetyScenarioModel? existing;

  const AddScenarioScreen({super.key, required this.logger, this.existing});

  @override
  ConsumerState<AddScenarioScreen> createState() => _AddScenarioScreenState();
}

class _AddScenarioScreenState extends ConsumerState<AddScenarioScreen> {
  final _formKey = GlobalKey<FormState>();
  SafetyTrainingService get _service => ref.read(safetyServiceProvider);

  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _sceneController = TextEditingController();
  final _questionController = TextEditingController();
  final _explanationController = TextEditingController();
  final _reasoningPromptController = TextEditingController(
    text: 'Explain why this could lead to injury and how to prevent it.',
  );
  final List<TextEditingController> _optionControllers = List.generate(4, (_) => TextEditingController());

  String _visualKey = SafetyScenarioModel.visualGeneric;
  String _difficulty = SafetyScenarioModel.difficultyBasic;
  int _correctIndex = 0;
  int _points = 10;
  XFile? _pickedImage;
  _SceneMediaKind _mediaKind = _SceneMediaKind.none;
  String _pickedImageContentType = 'image/jpeg';
  Uint8List? _pickedLottieBytes;
  String? _pickedLottieName;

  /// Previewing a web-unsafe Lottie with Lottie.memory on web would take the
  /// whole page's renderer down, so the preview is skipped for those.
  bool _pickedLottieWebUnsafe = false;
  Uint8List? _pickedRiveBytes;
  String? _pickedRiveName;
  bool _isSaving = false;

  /// Reserved up front for a new scenario, so a retry after a failed save
  /// reuses the same id (and Storage path) instead of creating a duplicate.
  late final String _scenarioId;
  bool get _isEditing => widget.existing != null;
  bool _isLoadingAnswerKey = false;

  /// Set when the existing answer key couldn't be loaded — saving is
  /// blocked, since it would overwrite the real answer with the form's
  /// default (option A).
  String? _answerKeyError;

  /// The scenario exists but has no answer key at all; the admin must
  /// choose one, which saving will create.
  bool _answerKeyMissing = false;

  static const _maxOptions = 4;
  static const _maxPoints = 1000;

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
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) {
      _scenarioId = _service.newScenarioId();
      return;
    }
    _scenarioId = existing.id;
    _titleController.text = existing.title;
    _categoryController.text = existing.category;
    _sceneController.text = existing.sceneDescription;
    _questionController.text = existing.question;
    _reasoningPromptController.text = existing.reasoningPrompt;
    for (var i = 0; i < existing.options.length && i < _maxOptions; i++) {
      _optionControllers[i].text = existing.options[i];
    }
    _visualKey = _visualOptions.containsKey(existing.visualKey)
        ? existing.visualKey
        : SafetyScenarioModel.visualGeneric;
    _difficulty =
        const [
          SafetyScenarioModel.difficultyBasic,
          SafetyScenarioModel.difficultyIntermediate,
          SafetyScenarioModel.difficultyAdvanced,
        ].contains(existing.difficulty)
        ? existing.difficulty
        : SafetyScenarioModel.difficultyBasic;
    _points = existing.points;
    final hasMedia = [existing.imageUrl, existing.lottieUrl, existing.riveUrl].any((u) => u != null && u.isNotEmpty);
    _mediaKind = hasMedia ? _SceneMediaKind.existing : _SceneMediaKind.none;
    _isLoadingAnswerKey = true;
    _loadAnswerKey();
  }

  void _retryLoadAnswerKey() {
    setState(() {
      _isLoadingAnswerKey = true;
      _answerKeyError = null;
    });
    _loadAnswerKey();
  }

  Future<void> _loadAnswerKey() async {
    try {
      final key = await _service.fetchAnswerKey(_scenarioId);
      if (!mounted) return;
      setState(() {
        if (key == null) {
          _answerKeyMissing = true;
        } else {
          final optionCount = widget.existing!.options.length;
          _correctIndex = (key.correctOptionIndex >= 0 && key.correctOptionIndex < optionCount)
              ? key.correctOptionIndex
              : 0;
          _explanationController.text = key.explanation;
        }
        _isLoadingAnswerKey = false;
      });
    } catch (e) {
      widget.logger.e('❌ AddScenarioScreen: Failed to load answer key: $e');
      if (mounted) {
        setState(() {
          _isLoadingAnswerKey = false;
          _answerKeyError = 'Could not load this scenario\'s answer key.';
        });
      }
    }
  }

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
    if (picked == null) return;
    final contentType = SafetyMediaLimits.imageContentType(fileName: picked.name, mimeType: picked.mimeType);
    if (contentType == null) {
      if (mounted) _showSnack('Unsupported photo type — use a JPEG, PNG, WebP or GIF image');
      return;
    }
    if (await picked.length() > SafetyMediaLimits.maxImageBytes) {
      if (mounted) {
        _showSnack('Photo is too large — the limit is ${SafetyMediaLimits.describe(SafetyMediaLimits.maxImageBytes)}');
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _pickedImage = picked;
      _pickedImageContentType = contentType;
      _mediaKind = _SceneMediaKind.photo;
    });
  }

  Future<void> _pickLottie() async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
    final file = result?.files.single;
    var bytes = file?.bytes;
    if (file == null || bytes == null) return;

    // Checked on every platform, not just web: the scenario will be viewed
    // from browsers regardless of where the admin uploads it from.
    final webUnsafe = lottieHasUnsafeWebShapes(bytes);
    if (webUnsafe) {
      if (!mounted) return;
      final proceedAnyway = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'This animation won\'t play in web browsers',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'This file uses a "Trim Path" or "Merge Paths" shape, which crashes Flutter Web\'s renderer '
            '(a known Lottie/CanvasKit compatibility issue). It plays fine on Android/iOS, but anyone viewing '
            'this scenario in a browser will see the fallback illustration instead.',
            style: GoogleFonts.poppins(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Pick another file', style: GoogleFonts.poppins()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Use it anyway', style: GoogleFonts.poppins()),
            ),
          ],
        ),
      );
      if (proceedAnyway != true) return;
    }

    final linked = lottieLinkedImages(bytes);
    if (linked.isNotEmpty) {
      final embedded = await _embedLinkedLottieImages(bytes, linked);
      if (embedded == null) return;
      bytes = embedded;
    }
    // Checked after embedding, since embedded images add to the size.
    if (bytes.length > SafetyMediaLimits.maxLottieBytes) {
      if (mounted) {
        _showSnack(
          'Animation is too large — the limit is ${SafetyMediaLimits.describe(SafetyMediaLimits.maxLottieBytes)}',
        );
      }
      return;
    }
    if (!mounted) return;

    setState(() {
      _pickedLottieBytes = bytes;
      _pickedLottieName = file.name;
      _pickedLottieWebUnsafe = webUnsafe;
      _mediaKind = _SceneMediaKind.lottieAnim;
    });
  }

  /// Only the animation's `.json` is uploaded, so images it links to as
  /// separate files would never render. Asks the admin for those files and
  /// embeds them into the JSON; returns null if they cancel or any is
  /// missing.
  Future<Uint8List?> _embedLinkedLottieImages(Uint8List bytes, List<LinkedLottieImage> linked) async {
    if (!mounted) return null;
    final names = linked.map((l) => l.fileName).toSet();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select this animation\'s images', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(
          'This animation uses ${names.length} separate image file${names.length == 1 ? '' : 's'} '
          '(${names.join(', ')}) that aren\'t inside the .json. Select ${names.length == 1 ? 'it' : 'them'} '
          '— usually in the "images" folder exported next to it — to embed them into the animation.',
          style: GoogleFonts.poppins(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Select images', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    if (proceed != true) return null;

    final picked = await FilePicker.pickFiles(type: FileType.image, allowMultiple: true, withData: true);
    if (picked == null) return null;
    final filesByName = <String, Uint8List>{
      for (final f in picked.files)
        if (f.bytes != null && names.contains(f.name)) f.name: f.bytes!,
    };
    final missing = names.where((n) => !filesByName.containsKey(n)).toList();
    if (missing.isNotEmpty) {
      if (mounted) {
        _showSnack('Missing image${missing.length == 1 ? '' : 's'}: ${missing.join(', ')} — animation not added');
      }
      return null;
    }
    try {
      return embedLottieImages(bytes, filesByName);
    } catch (e) {
      widget.logger.e('❌ AddScenarioScreen: Failed to embed Lottie images: $e');
      if (mounted) _showSnack('Could not embed the images into this animation');
      return null;
    }
  }

  Future<void> _pickRive() async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['riv'], withData: true);
    final file = result?.files.single;
    if (file?.bytes == null) return;
    if (file!.bytes!.length > SafetyMediaLimits.maxRiveBytes) {
      if (mounted) {
        _showSnack(
          'Animation is too large — the limit is ${SafetyMediaLimits.describe(SafetyMediaLimits.maxRiveBytes)}',
        );
      }
      return;
    }
    setState(() {
      _pickedRiveBytes = file.bytes;
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
      _pickedLottieWebUnsafe = false;
      _pickedRiveBytes = null;
      _pickedRiveName = null;
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: GoogleFonts.poppins())));
  }

  /// Uploads newly picked media (if any) to this scenario's Storage path
  /// and returns the URLs the scenario should point at.
  Future<SafetyScenarioMedia> _resolveMedia() async {
    switch (_mediaKind) {
      case _SceneMediaKind.none:
        return SafetyScenarioMedia.none;
      case _SceneMediaKind.existing:
        final existing = widget.existing!;
        return SafetyScenarioMedia(
          imageUrl: existing.imageUrl,
          lottieUrl: existing.lottieUrl,
          riveUrl: existing.riveUrl,
        );
      case _SceneMediaKind.photo:
        final picked = _pickedImage!;
        final imageUrl = kIsWeb
            ? await _service.uploadScenarioImage(
                scenarioId: _scenarioId,
                contentType: _pickedImageContentType,
                bytes: await picked.readAsBytes(),
              )
            : await _service.uploadScenarioImage(
                scenarioId: _scenarioId,
                contentType: _pickedImageContentType,
                file: File(picked.path),
              );
        return SafetyScenarioMedia(imageUrl: imageUrl);
      case _SceneMediaKind.lottieAnim:
        final lottieUrl = await _service.uploadScenarioLottie(scenarioId: _scenarioId, bytes: _pickedLottieBytes!);
        return SafetyScenarioMedia(lottieUrl: lottieUrl);
      case _SceneMediaKind.riveAnim:
        final riveUrl = await _service.uploadScenarioRive(scenarioId: _scenarioId, bytes: _pickedRiveBytes!);
        return SafetyScenarioMedia(riveUrl: riveUrl);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isLoadingAnswerKey || _answerKeyError != null) return;

    // The radio group selects a *box* (0–3), but empty boxes are dropped
    // from the saved options — so translate the selected box into its
    // position among the filled ones. Saving the raw box index would point
    // the answer key at the wrong option whenever an earlier box is blank.
    final filledSlots = [
      for (var i = 0; i < _maxOptions; i++)
        if (_optionControllers[i].text.trim().isNotEmpty) i,
    ];
    if (filledSlots.length < 2) {
      _showSnack('Add at least two answer options');
      return;
    }
    if (!filledSlots.contains(_correctIndex)) {
      _showSnack('The option marked correct is empty — fill it in or mark a different option');
      return;
    }
    final options = [for (final i in filledSlots) _optionControllers[i].text.trim()];
    final correctOptionIndex = filledSlots.indexOf(_correctIndex);
    final user = ref.read(safetyUserProvider).valueOrNull;
    if (user == null || !user.isAdmin) {
      _showSnack('Only admins can save scenarios.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final media = await _resolveMedia();
      final existing = widget.existing;
      final category = _categoryController.text.trim();
      final scenario = SafetyScenarioModel(
        id: _scenarioId,
        title: _titleController.text.trim(),
        category: category.isEmpty ? 'General' : category,
        sceneDescription: _sceneController.text.trim(),
        visualKey: _visualKey,
        imageUrl: media.imageUrl,
        lottieUrl: media.lottieUrl,
        riveUrl: media.riveUrl,
        question: _questionController.text.trim(),
        options: options,
        reasoningPrompt: _reasoningPromptController.text.trim(),
        difficulty: _difficulty,
        points: _points,
        isActive: existing?.isActive ?? true,
        createdByUid: existing?.createdByUid ?? user.uid,
        createdByName: existing?.createdByName ?? user.name,
        createdByRole: existing?.createdByRole ?? user.role!,
        createdAt: existing?.createdAt ?? DateTime.now(),
      );
      final answerKey = SafetyScenarioAnswerKey(
        correctOptionIndex: correctOptionIndex,
        explanation: _explanationController.text.trim(),
      );

      if (existing == null) {
        await _service.createScenario(scenarioId: _scenarioId, scenario: scenario, answerKey: answerKey);
      } else {
        await _service.updateScenario(scenario: scenario, answerKey: answerKey, editedByUid: user.uid);
      }

      // Only once the scenario points at its new media: drop files left
      // behind by a previous media choice (e.g. photo replaced by Lottie).
      if (_mediaKind != _SceneMediaKind.existing) {
        await _service.deleteUnusedScenarioMedia(_scenarioId, media);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      widget.logger.e('❌ AddScenarioScreen: Failed to save scenario: $e');
      if (mounted) _showSnack('Failed to save scenario: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaSection = _FormSection(
      icon: Icons.movie_creation_rounded,
      color: AppPalette.violet,
      title: 'Scene media',
      subtitle: 'Optional — falls back to a built-in animated illustration',
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
                icon: Icons.animation_rounded,
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
                _mediaChip(
                  icon: Icons.close_rounded,
                  label: 'Clear',
                  active: false,
                  onTap: _clearMedia,
                  isDestructive: true,
                ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _visualKey,
            decoration: _inputDecoration('Fallback illustration'),
            items: _visualOptions.entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value, style: appText(14)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _visualKey = v ?? SafetyScenarioModel.visualGeneric),
          ),
        ],
      ),
    );

    final detailsSection = _FormSection(
      icon: Icons.description_rounded,
      color: AppPalette.brightBlue,
      title: 'Scenario details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(_titleController, 'Scenario title *', required: true, topPadding: 0),
          _field(_categoryController, 'Category (e.g. Falling Objects, PPE, Electrical)'),
          _field(_sceneController, 'Scene description — what the worker sees *', maxLines: 3, required: true),
        ],
      ),
    );

    final questionSection = _FormSection(
      icon: Icons.quiz_rounded,
      color: AppPalette.teal,
      title: 'Question & answers',
      subtitle: 'Mark the correct answer with the radio button',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(_questionController, 'Question (e.g. "What is the hazard here?") *', required: true, topPadding: 0),
          const SizedBox(height: 12),
          RadioGroup<int>(
            groupValue: _correctIndex,
            onChanged: (v) => setState(() => _correctIndex = v ?? 0),
            child: Column(
              children: List.generate(_maxOptions, (i) {
                final isCorrect = _correctIndex == i;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                  decoration: BoxDecoration(
                    color: isCorrect ? AppPalette.green.withValues(alpha: 0.07) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isCorrect ? AppPalette.green.withValues(alpha: 0.5) : Colors.transparent),
                  ),
                  child: Row(
                    children: [
                      Radio<int>(value: i, activeColor: AppPalette.green),
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: isCorrect ? AppPalette.green : AppPalette.canvas,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          String.fromCharCode(65 + i),
                          style: appText(
                            12.5,
                            weight: FontWeight.w700,
                            color: isCorrect ? Colors.white : AppPalette.inkMuted,
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextFormField(
                          controller: _optionControllers[i],
                          style: appText(14),
                          decoration: _inputDecoration(i < 2 ? 'Option ${i + 1} *' : 'Option ${i + 1} (optional)'),
                        ),
                      ),
                      if (isCorrect) ...[
                        const SizedBox(width: 8),
                        const StatusPill(label: 'Correct', color: AppPalette.green, icon: Icons.check_rounded),
                      ],
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );

    final scoringSection = _FormSection(
      icon: Icons.lightbulb_rounded,
      color: AppPalette.amber,
      title: 'Feedback & scoring',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(
            _explanationController,
            'Explanation shown after answering *',
            maxLines: 3,
            required: true,
            topPadding: 0,
          ),
          _field(_reasoningPromptController, 'Free-text reasoning prompt *', maxLines: 2, required: true),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _difficulty,
                  decoration: _inputDecoration('Difficulty'),
                  items:
                      const [
                            SafetyScenarioModel.difficultyBasic,
                            SafetyScenarioModel.difficultyIntermediate,
                            SafetyScenarioModel.difficultyAdvanced,
                          ]
                          .map(
                            (d) => DropdownMenuItem(
                              value: d,
                              child: Text(d, style: appText(14)),
                            ),
                          )
                          .toList(),
                  onChanged: (v) => setState(() => _difficulty = v ?? SafetyScenarioModel.difficultyBasic),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: '$_points',
                  style: appText(14),
                  decoration: _inputDecoration('Points (1–$_maxPoints)'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _points = int.tryParse(v.trim()) ?? 0,
                  validator: (v) {
                    final points = int.tryParse(v?.trim() ?? '');
                    if (points == null || points < 1 || points > _maxPoints) return '1–$_maxPoints';
                    return null;
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final notices = <Widget>[
      if (_isLoadingAnswerKey)
        _buildNotice(
          color: AppPalette.brightBlue,
          icon: Icons.hourglass_top_rounded,
          message: 'Loading this scenario\'s answer key…',
        )
      else if (_answerKeyError != null)
        _buildNotice(
          color: AppPalette.coral,
          icon: Icons.error_outline_rounded,
          message: '$_answerKeyError Saving is disabled so the current answer isn\'t overwritten.',
          action: TextButton(onPressed: _retryLoadAnswerKey, child: const Text('Retry')),
        )
      else if (_answerKeyMissing)
        _buildNotice(
          color: AppPalette.orange,
          icon: Icons.warning_amber_rounded,
          message: 'This scenario has no answer key yet. Mark the correct option and add an explanation, then save.',
        ),
    ];

    return Scaffold(
      backgroundColor: AppPalette.canvas,
      appBar: modernAppBar(
        context,
        title: _isEditing ? 'Edit Scenario' : 'Author Scenario',
        subtitle: 'Fields marked * are required',
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: AppPalette.surface,
            border: const Border(top: BorderSide(color: AppPalette.border)),
            boxShadow: [
              BoxShadow(
                color: AppPalette.deepBlue.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: ResponsiveCenter(
            maxWidth: 1180,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSaving ? null : () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: appText(14, weight: FontWeight.w600, color: AppPalette.inkMuted),
                  ),
                ),
                const SizedBox(width: 10),
                PrimaryButton(
                  label: _isSaving ? 'Saving…' : (_isEditing ? 'Save changes' : 'Publish scenario'),
                  icon: Icons.check_rounded,
                  loading: _isSaving,
                  onPressed: (_isLoadingAnswerKey || _answerKeyError != null) ? null : _save,
                ),
              ],
            ),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1000;
            final pad = constraints.maxWidth < Breakpoints.compact ? 14.0 : 24.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(pad, pad, pad, 32),
              child: ResponsiveCenter(
                maxWidth: 1180,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...notices,
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [mediaSection, const SizedBox(height: 18), detailsSection],
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [questionSection, const SizedBox(height: 18), scoringSection],
                            ),
                          ),
                        ],
                      )
                    else ...[
                      mediaSection,
                      const SizedBox(height: 16),
                      detailsSection,
                      const SizedBox(height: 16),
                      questionSection,
                      const SizedBox(height: 16),
                      scoringSection,
                    ],
                  ],
                ),
              ),
            );
          },
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
    final color = isDestructive ? AppPalette.coral : AppPalette.violet;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: active ? color.withValues(alpha: 0.12) : AppPalette.canvas,
            border: Border.all(color: active ? color : AppPalette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: appText(12.5, weight: active ? FontWeight.w700 : FontWeight.w500, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: appText(13, color: AppPalette.inkMuted),
      filled: true,
      fillColor: AppPalette.canvas,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppPalette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppPalette.brightBlue, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
                : (kIsWeb && _pickedLottieWebUnsafe)
                ? Text(
                    'Preview unavailable in the browser for this animation — it will play on Android/iOS.',
                    style: GoogleFonts.poppins(fontSize: 12),
                    textAlign: TextAlign.center,
                  )
                : lottie.Lottie.memory(
                    bytes,
                    // contain, not cover — matches HazardSceneVisual, so what
                    // the admin previews here is what workers will actually
                    // see (no crop the upload flow hides from them).
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Text(
                        'Could not preview this file — is it a valid Lottie JSON?',
                        style: GoogleFonts.poppins(fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
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
              Text('${_pickedRiveName ?? "Rive file"} selected', style: appText(13, weight: FontWeight.w600)),
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
      case _SceneMediaKind.existing:
        final existing = widget.existing!;
        return HazardSceneVisual(
          visualKey: _visualKey,
          imageUrl: existing.imageUrl,
          lottieUrl: existing.lottieUrl,
          riveUrl: existing.riveUrl,
          height: 160,
        );
      case _SceneMediaKind.none:
        return HazardSceneVisual(visualKey: _visualKey, height: 160);
    }
  }

  Widget _buildNotice({required Color color, required IconData icon, required String message, Widget? action}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
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
            child: Text(message, style: appText(12.5, color: color, height: 1.4)),
          ),
          ?action,
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    bool required = false,
    double topPadding = 12,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        style: appText(14),
        decoration: _inputDecoration(label),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
      ),
    );
  }
}

/// Card chrome for one logical group of fields (Scene media / Scenario
/// details / Question & answers / Feedback & scoring).
class _FormSection extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget child;

  const _FormSection({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(icon: icon, color: color, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: appText(15.5, weight: FontWeight.w700)),
                    if (subtitle != null) Text(subtitle!, style: appText(12, color: AppPalette.inkMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
