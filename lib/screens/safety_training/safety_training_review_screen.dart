import 'package:almaworks/models/safety_training/safety_training_review_model.dart';
import 'package:almaworks/models/safety_training/safety_training_session_model.dart';
import 'package:almaworks/services/safety_training_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

/// Per-worker aggregate derived from their session history, used to build
/// the reviewable roster on this screen.
class _WorkerStanding {
  final String workerUid;
  final String workerName;
  final String workerRole;
  final int totalAttempts;
  final int correctAttempts;
  final int totalPoints;
  final DateTime lastAttemptAt;

  const _WorkerStanding({
    required this.workerUid,
    required this.workerName,
    required this.workerRole,
    required this.totalAttempts,
    required this.correctAttempts,
    required this.totalPoints,
    required this.lastAttemptAt,
  });
}

/// MainAdmin/SystemAdmin-only screen: every worker who has completed at
/// least one safety-training scenario, with their accumulated score and
/// current review standing, and an action to record a next-step
/// determination (cleared / needs retraining / escalated) for that worker.
class SafetyTrainingReviewScreen extends StatelessWidget {
  final Logger logger;
  final String reviewerUid;
  final String reviewerName;
  final String reviewerRole;

  const SafetyTrainingReviewScreen({
    super.key,
    required this.logger,
    required this.reviewerUid,
    required this.reviewerName,
    required this.reviewerRole,
  });

  @override
  Widget build(BuildContext context) {
    final service = SafetyTrainingService();
    return Scaffold(
      appBar: AppBar(
        title: Text('Review Worker Safety Standing',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF0A2E5A),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<SafetyTrainingSessionModel>>(
        stream: service.streamAllSessions(),
        builder: (context, sessionsSnap) {
          if (sessionsSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (sessionsSnap.hasError) {
            logger.e('❌ SafetyTrainingReviewScreen: sessions stream error: ${sessionsSnap.error}');
            return Center(child: Text('Unable to load worker sessions', style: GoogleFonts.poppins()));
          }
          final standings = _groupByWorker(sessionsSnap.data ?? []);
          if (standings.isEmpty) {
            return Center(
              child: Text('No workers have completed a scenario yet', style: GoogleFonts.poppins(color: Colors.grey[600])),
            );
          }
          return StreamBuilder<List<SafetyTrainingReviewModel>>(
            stream: service.streamAllReviews(),
            builder: (context, reviewsSnap) {
              final latestReviewByWorker = _latestReviewByWorker(reviewsSnap.data ?? []);
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: standings.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final standing = standings[index];
                  final review = latestReviewByWorker[standing.workerUid];
                  return _WorkerStandingCard(
                    standing: standing,
                    review: review,
                    onReview: () => _openReviewSheet(context, service, standing),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  List<_WorkerStanding> _groupByWorker(List<SafetyTrainingSessionModel> sessions) {
    final byWorker = <String, List<SafetyTrainingSessionModel>>{};
    for (final session in sessions) {
      byWorker.putIfAbsent(session.workerUid, () => []).add(session);
    }
    final standings = byWorker.entries.map((entry) {
      final workerSessions = entry.value;
      final correct = workerSessions.where((s) => s.isCorrect).length;
      final points = workerSessions.fold<int>(0, (sum, s) => sum + s.pointsEarned);
      // Sessions arrive newest-first (streamAllSessions orders by
      // completedAt desc), so the first entry is the worker's latest attempt.
      final latest = workerSessions.first;
      return _WorkerStanding(
        workerUid: entry.key,
        workerName: latest.workerName,
        workerRole: latest.workerRole,
        totalAttempts: workerSessions.length,
        correctAttempts: correct,
        totalPoints: points,
        lastAttemptAt: latest.completedAt,
      );
    }).toList();
    standings.sort((a, b) => b.lastAttemptAt.compareTo(a.lastAttemptAt));
    return standings;
  }

  Map<String, SafetyTrainingReviewModel> _latestReviewByWorker(List<SafetyTrainingReviewModel> reviews) {
    // reviews arrives newest-first (streamAllReviews orders by reviewedAt
    // desc), so the first occurrence per workerUid is their current standing.
    final latest = <String, SafetyTrainingReviewModel>{};
    for (final review in reviews) {
      latest.putIfAbsent(review.workerUid, () => review);
    }
    return latest;
  }

  Future<void> _openReviewSheet(
    BuildContext context,
    SafetyTrainingService service,
    _WorkerStanding standing,
  ) async {
    var selectedStatus = SafetyTrainingReviewModel.statusCleared;
    final notesController = TextEditingController();

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Review ${standing.workerName}',
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    '${standing.correctAttempts}/${standing.totalAttempts} correct · ${standing.totalPoints} pts',
                    style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  Text('Next step', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      SafetyTrainingReviewModel.statusCleared,
                      SafetyTrainingReviewModel.statusNeedsRetraining,
                      SafetyTrainingReviewModel.statusEscalated,
                    ].map((status) {
                      final isSelected = selectedStatus == status;
                      return ChoiceChip(
                        label: Text(SafetyTrainingReviewModel.statusLabel(status)),
                        selected: isSelected,
                        onSelected: (_) => setSheetState(() => selectedStatus = status),
                        selectedColor: const Color(0xFF0A2E5A),
                        labelStyle: GoogleFonts.poppins(
                          fontSize: 12,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    style: GoogleFonts.poppins(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Notes (optional)',
                      labelStyle: GoogleFonts.poppins(fontSize: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A2E5A),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(sheetContext, true),
                      child: Text('Save Determination', style: GoogleFonts.poppins(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (submitted != true) return;

    try {
      await service.recordReview(SafetyTrainingReviewModel(
        id: '',
        workerUid: standing.workerUid,
        workerName: standing.workerName,
        workerRole: standing.workerRole,
        status: selectedStatus,
        notes: notesController.text.trim(),
        totalAttempts: standing.totalAttempts,
        correctAttempts: standing.correctAttempts,
        totalPoints: standing.totalPoints,
        reviewedByUid: reviewerUid,
        reviewedByName: reviewerName,
        reviewedByRole: reviewerRole,
        reviewedAt: DateTime.now(),
      ));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Determination recorded for ${standing.workerName}', style: GoogleFonts.poppins())),
        );
      }
    } catch (e) {
      logger.e('❌ SafetyTrainingReviewScreen: Error recording review: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to record determination', style: GoogleFonts.poppins())),
        );
      }
    }
  }
}

class _WorkerStandingCard extends StatelessWidget {
  final _WorkerStanding standing;
  final SafetyTrainingReviewModel? review;
  final VoidCallback onReview;

  const _WorkerStandingCard({required this.standing, required this.review, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final accuracyPct =
        standing.totalAttempts == 0 ? 0 : ((standing.correctAttempts / standing.totalAttempts) * 100).round();

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onReview,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(standing.workerName,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                  _StatusBadge(status: review?.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(standing.workerRole, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 8),
              Text(
                '${standing.correctAttempts}/${standing.totalAttempts} correct · $accuracyPct% accuracy · ${standing.totalPoints} pts',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700]),
              ),
              Text('Last attempt: ${dateFormat.format(standing.lastAttemptAt)}',
                  style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[500])),
              if (review != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Reviewed by ${review!.reviewedByName} on ${dateFormat.format(review!.reviewedAt)}',
                  style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic),
                ),
                if (review!.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('"${review!.notes}"',
                        style: GoogleFonts.poppins(fontSize: 12, fontStyle: FontStyle.italic)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String? status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    switch (status) {
      case SafetyTrainingReviewModel.statusCleared:
        color = Colors.green;
        label = SafetyTrainingReviewModel.statusLabel(status!);
        break;
      case SafetyTrainingReviewModel.statusNeedsRetraining:
        color = Colors.orange;
        label = SafetyTrainingReviewModel.statusLabel(status!);
        break;
      case SafetyTrainingReviewModel.statusEscalated:
        color = Colors.redAccent;
        label = SafetyTrainingReviewModel.statusLabel(status!);
        break;
      default:
        color = Colors.grey;
        label = 'Not Reviewed';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: GoogleFonts.poppins(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
