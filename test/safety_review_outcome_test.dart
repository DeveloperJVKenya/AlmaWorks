import 'package:almaworks/models/safety_training/safety_training_review_model.dart';
import 'package:flutter_test/flutter_test.dart';

final _reviewedAt = DateTime(2026, 10, 1, 9);

SafetyTrainingReviewModel _review(
  String status, {
  DateTime? expiresAt,
  List<String> assigned = const [],
  DateTime? dueAt,
}) {
  return SafetyTrainingReviewModel(
    id: 'r1',
    workerUid: 'w1',
    workerName: 'Worker',
    workerRole: 'Technician',
    status: status,
    notes: '',
    totalAttempts: 0,
    scenariosAttempted: 0,
    firstTryCorrect: 0,
    totalPoints: 0,
    expiresAt: expiresAt,
    assignedScenarioIds: assigned,
    dueAt: dueAt,
    reviewedByUid: 'a1',
    reviewedByName: 'Admin',
    reviewedByRole: 'MainAdmin',
    reviewedAt: _reviewedAt,
  );
}

void main() {
  group('clearance expiry', () {
    test('uses the stored expiry', () {
      final review = _review(SafetyTrainingReviewModel.statusCleared, expiresAt: DateTime(2026, 11, 1));
      expect(review.isClearanceExpired(DateTime(2026, 10, 31)), isFalse);
      expect(review.isClearanceExpired(DateTime(2026, 11, 1)), isTrue);
    });

    test('older clearances without one lapse after the validity period', () {
      final review = _review(SafetyTrainingReviewModel.statusCleared);
      expect(review.clearanceExpiresAt, _reviewedAt.add(SafetyTrainingReviewModel.clearanceValidity));
    });

    test('only clearances expire', () {
      final review = _review(SafetyTrainingReviewModel.statusEscalated, expiresAt: DateTime(2026, 10, 2));
      expect(review.isClearanceExpired(DateTime(2027)), isFalse);
    });
  });

  group('retraining progress', () {
    final review = _review(
      SafetyTrainingReviewModel.statusNeedsRetraining,
      assigned: ['a', 'b', 'retired'],
      dueAt: DateTime(2026, 10, 15),
    );

    test('only attempts after the review count, and deactivated scenarios are left out', () {
      final progress = RetrainingProgress.of(
        review,
        {
          'a': _reviewedAt.add(const Duration(days: 1)), // redone since review
          'b': _reviewedAt.subtract(const Duration(days: 1)), // only before review
        },
        activeScenarioIds: {'a', 'b'},
      );
      expect(progress.assigned, ['a', 'b']);
      expect(progress.remaining, ['b']);
      expect(progress.done, 1);
      expect(progress.isOverdue(DateTime(2026, 10, 14)), isFalse);
      expect(progress.isOverdue(DateTime(2026, 10, 16)), isTrue);
    });

    test('complete retraining is never overdue', () {
      final later = _reviewedAt.add(const Duration(days: 1));
      final progress = RetrainingProgress.of(review, {'a': later, 'b': later, 'retired': later});
      expect(progress.isComplete, isTrue);
      expect(progress.isOverdue(DateTime(2027)), isFalse);
    });
  });
}
