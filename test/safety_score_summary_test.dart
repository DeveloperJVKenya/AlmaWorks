import 'package:almaworks/models/safety_training/safety_training_session_model.dart';
import 'package:almaworks/services/safety_training_service.dart';
import 'package:flutter_test/flutter_test.dart';

SafetyTrainingSessionModel _session(
  String id,
  String scenarioId, {
  required bool correct,
  required int points,
  required int minute,
}) {
  return SafetyTrainingSessionModel(
    id: id,
    scenarioId: scenarioId,
    scenarioTitle: scenarioId,
    category: 'General',
    workerUid: 'w1',
    workerName: 'Worker',
    workerRole: 'Technician',
    selectedOptionIndex: 0,
    isCorrect: correct,
    reasoningAnswer: 'r',
    pointsEarned: points,
    timeTakenSeconds: 1,
    completedAt: DateTime(2026, 10, 1, 9, minute),
  );
}

void main() {
  test('empty history scores nothing', () {
    final summary = SafetyScoreSummary.fromSessions(const []);
    expect(summary.totalAttempts, 0);
    expect(summary.accuracy, 0);
    expect(summary.totalPoints, 0);
  });

  test('only the first attempt per scenario counts, regardless of input order', () {
    final summary = SafetyScoreSummary.fromSessions([
      // Newest first, as streamed — including legacy retries that were
      // (wrongly) awarded points before first-attempt scoring.
      _session('a3', 'A', correct: true, points: 10, minute: 30),
      _session('b1', 'B', correct: true, points: 20, minute: 20),
      _session('a2', 'A', correct: true, points: 10, minute: 10),
      _session('a1', 'A', correct: false, points: 0, minute: 0),
    ]);
    expect(summary.totalAttempts, 4);
    expect(summary.scenariosAttempted, 2);
    expect(summary.firstTryCorrect, 1);
    expect(summary.totalPoints, 20);
    expect(summary.accuracy, 0.5);
    expect(summary.firstAttemptByScenario['A']!.id, 'a1');
    expect(summary.firstAttemptByScenario['B']!.id, 'b1');
  });

  test('coverage counts only currently active scenarios', () {
    final summary = SafetyScoreSummary.fromSessions([
      _session('a1', 'A', correct: true, points: 10, minute: 0),
      _session('x1', 'retired', correct: true, points: 10, minute: 1),
    ]);
    expect(summary.completedOf(['A', 'B', 'C']), 1);
  });
}
