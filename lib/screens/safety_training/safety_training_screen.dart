import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/models/safety_training/safety_scenario_model.dart';
import 'package:almaworks/models/safety_training/safety_training_review_model.dart';
import 'package:almaworks/screens/safety_training/add_scenario_screen.dart';
import 'package:almaworks/screens/safety_training/safety_training_review_screen.dart';
import 'package:almaworks/screens/safety_training/scenario_play_screen.dart';
import 'package:almaworks/screens/safety_training/training_history_screen.dart';
import 'package:almaworks/services/safety_training_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/safety_training/hazard_scene_visual.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';

/// Hub screen for the gamified safety-training module: a scoreboard summary
/// for the current worker, followed by the catalog of active scenarios they
/// can play. Admin roles additionally get an "Author scenario" action and a
/// shortcut into the all-workers history/leaderboard view.
class SafetyTrainingScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;

  const SafetyTrainingScreen({
    super.key,
    required this.project,
    required this.logger,
  });

  @override
  State<SafetyTrainingScreen> createState() => _SafetyTrainingScreenState();
}

class _SafetyTrainingScreenState extends State<SafetyTrainingScreen> {
  final SafetyTrainingService _service = SafetyTrainingService();
  String _userRole = 'Client';
  String _userName = '';
  String? _uid;
  bool _isLoadingUser = true;
  SafetyScoreSummary _summary = SafetyScoreSummary.empty;
  SafetyTrainingReviewModel? _latestReview;

  bool get _isAdmin => ['MainAdmin', 'Admin', 'SystemAdmin'].contains(_userRole);

  // Reviewing a worker's overall standing and deciding next steps is
  // deliberately scoped to just MainAdmin/SystemAdmin, not the wider
  // admin-tier `_isAdmin` set — this is a managerial determination, not
  // routine content authoring.
  bool get _isReviewer => ['MainAdmin', 'SystemAdmin'].contains(_userRole);

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoadingUser = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('Users')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      final summary = await _service.fetchWorkerScoreSummary(user.uid);
      // Fetched separately from the block above: a worker with no reviews
      // yet — or any transient/permission hiccup on this specific query —
      // shouldn't stop the role/summary load that the rest of the screen
      // (including the reviewer button) depends on.
      SafetyTrainingReviewModel? latestReview;
      try {
        latestReview = await _service.fetchLatestReviewForWorker(user.uid);
      } catch (e) {
        widget.logger.e('❌ SafetyTrainingScreen: Error loading latest review: $e');
      }
      if (!mounted) return;
      setState(() {
        _uid = user.uid;
        if (snap.docs.isNotEmpty) {
          _userRole = snap.docs.first.data()['role'] as String? ?? 'Client';
          _userName = snap.docs.first.id;
        }
        _summary = summary;
        _latestReview = latestReview;
        _isLoadingUser = false;
      });
    } catch (e) {
      widget.logger.e('❌ SafetyTrainingScreen: Error loading user: $e');
      if (mounted) setState(() => _isLoadingUser = false);
    }
  }

  Future<void> _refreshSummary() async {
    final uid = _uid;
    if (uid == null) return;
    final summary = await _service.fetchWorkerScoreSummary(uid);
    SafetyTrainingReviewModel? latestReview;
    try {
      latestReview = await _service.fetchLatestReviewForWorker(uid);
    } catch (e) {
      widget.logger.e('❌ SafetyTrainingScreen: Error refreshing latest review: $e');
      latestReview = _latestReview;
    }
    if (mounted) {
      setState(() {
        _summary = summary;
        _latestReview = latestReview;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseLayout(
      title: '${widget.project.name} - Safety Training',
      project: widget.project,
      logger: widget.logger,
      selectedMenuItem: 'Safety Training',
      onMenuItemSelected: (_) {},
      actions: [
        if (_isReviewer)
          IconButton(
            icon: const Icon(Icons.fact_check_outlined),
            tooltip: 'Review worker safety standing',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SafetyTrainingReviewScreen(
                  logger: widget.logger,
                  reviewerUid: _uid ?? '',
                  reviewerName: _userName,
                  reviewerRole: _userRole,
                ),
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.leaderboard),
          tooltip: _isAdmin ? 'All-worker history' : 'My history',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TrainingHistoryScreen(
                logger: widget.logger,
                currentUid: _uid ?? '',
                isAdmin: _isAdmin,
              ),
            ),
          ),
        ),
      ],
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddScenarioScreen(
                    logger: widget.logger,
                    createdByUid: _uid ?? '',
                    createdByName: _userName,
                    createdByRole: _userRole,
                  ),
                ),
              ),
              backgroundColor: const Color(0xFF0A2E5A),
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text('Author Scenario', style: GoogleFonts.poppins(color: Colors.white)),
            )
          : null,
      child: _isLoadingUser
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshSummary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildScoreCard(),
                  if (_latestReview != null) ...[
                    const SizedBox(height: 12),
                    _buildStandingBanner(_latestReview!),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'Safety Scenarios',
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0A2E5A)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Work through each scenario, spot the hazard, and explain how to stay safe.',
                    style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<List<SafetyScenarioModel>>(
                    stream: _service.streamActiveScenarios(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        widget.logger.e('❌ SafetyTrainingScreen: stream error: ${snapshot.error}');
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: Text('Unable to load scenarios', style: GoogleFonts.poppins())),
                        );
                      }
                      final scenarios = snapshot.data ?? [];
                      if (scenarios.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              _isAdmin
                                  ? 'No scenarios yet — tap "Author Scenario" to add one.'
                                  : 'No safety scenarios available yet.',
                              style: GoogleFonts.poppins(color: Colors.grey[600]),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      return Column(children: scenarios.map(_buildScenarioCard).toList());
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildScoreCard() {
    final accuracyPct = (_summary.accuracy * 100).round();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF0A2E5A), Color(0xFF14508F)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your Safety Score', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                Text('${_summary.totalPoints} pts',
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  '${_summary.correctAttempts}/${_summary.totalAttempts} correct · $accuracyPct% accuracy',
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.shield_moon, color: Colors.white, size: 48),
        ],
      ),
    );
  }

  Widget _buildStandingBanner(SafetyTrainingReviewModel review) {
    final Color color;
    final IconData icon;
    switch (review.status) {
      case SafetyTrainingReviewModel.statusCleared:
        color = Colors.green;
        icon = Icons.verified_outlined;
        break;
      case SafetyTrainingReviewModel.statusNeedsRetraining:
        color = Colors.orange;
        icon = Icons.replay_circle_filled_outlined;
        break;
      case SafetyTrainingReviewModel.statusEscalated:
        color = Colors.redAccent;
        icon = Icons.report_gmailerrorred_outlined;
        break;
      default:
        color = Colors.grey;
        icon = Icons.info_outline;
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(SafetyTrainingReviewModel.statusLabel(review.status),
                    style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
                if (review.notes.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(review.notes, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700])),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScenarioCard(SafetyScenarioModel scenario) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ScenarioPlayScreen(
                scenario: scenario,
                project: widget.project,
                logger: widget.logger,
                workerUid: _uid ?? '',
                workerName: _userName,
                workerRole: _userRole,
              ),
            ),
          );
          _refreshSummary();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HazardSceneVisual(
              visualKey: scenario.visualKey,
              imageUrl: scenario.imageUrl,
              lottieUrl: scenario.lottieUrl,
              riveUrl: scenario.riveUrl,
              height: 140,
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(scenario.title,
                            style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                      Chip(
                        label: Text(scenario.difficulty, style: GoogleFonts.poppins(fontSize: 11, color: Colors.white)),
                        backgroundColor: const Color(0xFF0A2E5A),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(scenario.category, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 6),
                  Text(
                    scenario.sceneDescription,
                    style: GoogleFonts.poppins(fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
