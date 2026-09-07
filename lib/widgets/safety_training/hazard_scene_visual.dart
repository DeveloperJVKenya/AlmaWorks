import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart' as lottie;
import 'package:rive/rive.dart' as rive;

import 'package:almaworks/models/safety_training/safety_scenario_model.dart';

/// The animated "scene" a worker sees before answering a scenario's
/// question. Renders the richest thing available, in order:
///   1. [riveUrl] — a real Rive (.riv) state-machine animation, if uploaded.
///   2. [lottieUrl] — a real Lottie (Bodymovin .json) animation, if uploaded.
///   3. [imageUrl] — a real site photo, shown with a slow Ken-Burns drift
///      and a pulsing hazard hotspot overlay.
///   4. A small built-in icon animation keyed by
///      [SafetyScenarioModel.visualKey] (looping transform animations, no
///      network or asset dependency) — the permanent fallback, so a scenario
///      is always visually alive even before any real illustration exists,
///      and stays that way if a network animation fails to load.
class HazardSceneVisual extends StatefulWidget {
  final String visualKey;
  final String? imageUrl;
  final String? lottieUrl;
  final String? riveUrl;
  final double height;

  const HazardSceneVisual({
    super.key,
    required this.visualKey,
    this.imageUrl,
    this.lottieUrl,
    this.riveUrl,
    this.height = 240,
  });

  @override
  State<HazardSceneVisual> createState() => _HazardSceneVisualState();
}

class _HazardSceneVisualState extends State<HazardSceneVisual> with TickerProviderStateMixin {
  late final AnimationController _loopController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _loopController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  }

  @override
  void dispose() {
    _loopController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  static const _visualStyles = <String, _VisualStyle>{
    SafetyScenarioModel.visualFallingObject: _VisualStyle(Icons.arrow_downward_rounded, Colors.deepOrange, Icons.engineering),
    SafetyScenarioModel.visualMissingPpe: _VisualStyle(Icons.sports_motorsports, Colors.redAccent, Icons.person),
    SafetyScenarioModel.visualExposedWiring: _VisualStyle(Icons.bolt, Colors.amber, Icons.electrical_services),
    SafetyScenarioModel.visualUnguardedEdge: _VisualStyle(Icons.warning_amber_rounded, Colors.orange, Icons.height),
    SafetyScenarioModel.visualWetFloor: _VisualStyle(Icons.water_drop, Colors.lightBlue, Icons.accessibility_new),
    SafetyScenarioModel.visualUnsecuredLadder: _VisualStyle(Icons.priority_high, Colors.deepOrange, Icons.stairs),
    SafetyScenarioModel.visualGeneric: _VisualStyle(Icons.warning_amber_rounded, Colors.redAccent, Icons.construction),
  };

  @override
  Widget build(BuildContext context) {
    final riveUrl = widget.riveUrl;
    final lottieUrl = widget.lottieUrl;
    final imageUrl = widget.imageUrl;

    Widget scene;
    if (riveUrl != null && riveUrl.isNotEmpty) {
      scene = _buildRiveScene(riveUrl);
    } else if (lottieUrl != null && lottieUrl.isNotEmpty) {
      scene = _buildLottieScene(lottieUrl);
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      scene = _buildImageScene(imageUrl);
    } else {
      scene = _buildIconScene();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: scene,
      ),
    );
  }

  Widget _buildRiveScene(String riveUrl) {
    // rive's RiveAnimation.network has no errorBuilder — an async load
    // failure (bad file, network error) just leaves placeHolder showing
    // forever instead of crashing, so the icon-scene fallback there is the
    // permanent safety net rather than a transient loading state.
    //
    // BoxFit.contain (not cover) here and in _buildLottieScene: uploaded
    // animations come in wildly different native aspect ratios (a tall
    // 2500x3000 lifting figure vs. a square 32x32 warning glyph) and this
    // widget's box is short and wide — cover would zoom to fill height and
    // crop the top/bottom off, which is exactly what cut animations in half
    // and made the visible sliver collide with the scene text below it.
    // contain always shows the whole animation, letterboxed on a neutral
    // ground instead of cropped.
    return Container(
      color: const Color(0xFFECEFF1),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: rive.RiveAnimation.network(
        riveUrl,
        fit: BoxFit.contain,
        placeHolder: _buildIconScene(),
      ),
    );
  }

  Widget _buildLottieScene(String lottieUrl) {
    return Container(
      color: const Color(0xFFECEFF1),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: lottie.Lottie.network(
        lottieUrl,
        fit: BoxFit.contain,
        repeat: true,
        frameRate: lottie.FrameRate.max,
        errorBuilder: (context, error, stackTrace) => _buildIconScene(),
      ),
    );
  }

  Widget _buildImageScene(String imageUrl) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final scale = 1.05 + (0.05 * _pulseController.value);
            return Transform.scale(scale: scale, child: child);
          },
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            placeholder: (_, _) => const ColoredBox(
              color: Color(0xFFECEFF1),
              child: Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (_, _, _) => _buildIconScene(),
          ),
        ),
        Positioned(
          right: 24,
          bottom: 24,
          child: AnimatedBuilder(
            animation: _loopController,
            builder: (context, _) => Opacity(
              opacity: 0.55 + (0.45 * _loopController.value),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 40, shadows: [
                Shadow(color: Colors.black45, blurRadius: 6),
              ]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIconScene() {
    final style = _visualStyles[widget.visualKey] ?? _visualStyles[SafetyScenarioModel.visualGeneric]!;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [style.color.withValues(alpha: 0.15), style.color.withValues(alpha: 0.05)],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              final scale = 1.0 + (0.15 * _pulseController.value);
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: style.color.withValues(alpha: 0.15 * (1 - _pulseController.value)),
                  ),
                ),
              );
            },
          ),
          Icon(style.sceneIcon, size: 64, color: style.color.withValues(alpha: 0.35)),
          AnimatedBuilder(
            animation: _loopController,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, -6 * _loopController.value),
              child: child,
            ),
            child: Icon(style.hazardIcon, size: 44, color: style.color),
          ),
        ],
      ),
    );
  }
}

class _VisualStyle {
  final IconData hazardIcon;
  final Color color;
  final IconData sceneIcon;
  const _VisualStyle(this.hazardIcon, this.color, this.sceneIcon);
}
