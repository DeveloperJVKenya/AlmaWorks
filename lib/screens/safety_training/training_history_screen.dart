import 'package:almaworks/models/safety_training/safety_training_session_model.dart';
import 'package:almaworks/services/safety_training_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

/// Session history: a worker sees their own past attempts (including their
/// free-text reasoning answers); an admin sees every worker's attempts, so a
/// trainer can review how workers explained the "why" behind each hazard.
class TrainingHistoryScreen extends StatelessWidget {
  final Logger logger;
  final String currentUid;
  final bool isAdmin;

  const TrainingHistoryScreen({
    super.key,
    required this.logger,
    required this.currentUid,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final service = SafetyTrainingService();
    final dateFormat = DateFormat('MMM d, yyyy · HH:mm');
    return Scaffold(
      appBar: AppBar(
        title: Text(isAdmin ? 'Worker Safety History' : 'My Safety History',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF0A2E5A),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<SafetyTrainingSessionModel>>(
        stream: isAdmin ? service.streamAllSessions() : service.streamWorkerSessions(currentUid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            logger.e('❌ TrainingHistoryScreen: stream error: ${snapshot.error}');
            return Center(child: Text('Unable to load history', style: GoogleFonts.poppins()));
          }
          final sessions = snapshot.data ?? [];
          if (sessions.isEmpty) {
            return Center(
              child: Text('No completed sessions yet', style: GoogleFonts.poppins(color: Colors.grey[600])),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sessions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final s = sessions[index];
              return Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(s.isCorrect ? Icons.check_circle : Icons.cancel,
                              color: s.isCorrect ? Colors.green : Colors.redAccent, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(s.scenarioTitle,
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                          ),
                          Text('+${s.pointsEarned} pts', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (isAdmin)
                        Text('${s.workerName} · ${s.workerRole}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700])),
                      Text(dateFormat.format(s.completedAt), style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[500])),
                      if (s.reasoningAnswer.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                          child: Text('"${s.reasoningAnswer}"',
                              style: GoogleFonts.poppins(fontSize: 12, fontStyle: FontStyle.italic)),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
