import 'code_scanner.dart';

/// Computes score, XP, and streak/bonus updates for a graded submission.
///
/// Used for both 3D Meet auto-grading (code + output based, with a
/// streak/bonus mechanic) and regular assignment grading (percentage-tier
/// XP, no streak).
class AutoGrader {
  static Map<String, dynamic> grade({
    required String sourceCode,
    required String actualOutput,
    required String expectedOutput,
    required List<String> requiredKeywords,
    required List<String> forbiddenPatterns,
    int totalPoints = 100,
    int currentStreak = 0,
    int pendingBonusPoints = 0,
    bool isThreeDMeet = false,
    int correctSubmissionRank = 1,
  }) {
    final scanner = CodeScanner(sourceCode);
    final passedKeywords = scanner.allKeywordsPresent(requiredKeywords);
    final passedForbidden = !scanner.anyForbiddenFound(forbiddenPatterns);
    final passedOutput =
        _normalize(actualOutput) == _normalize(expectedOutput);

    final feedback = <String>[];
    int rawPercent;
    int newStreak = currentStreak;
    int newPendingBonusPoints = pendingBonusPoints;
    var isGenuineHundred = false;

    if (!passedForbidden) {
      rawPercent = 0;
      newStreak = 0;
      newPendingBonusPoints = 0;
      feedback.add('Forbidden pattern(s) detected in the submitted code.');
    } else if (!passedKeywords) {
      rawPercent = 0;
      newStreak = 0;
      newPendingBonusPoints = 0;
      feedback.add(
        'One or more required concepts/keywords are missing from the code.',
      );
    } else if (passedOutput) {
      final rankedScore = (100 - (correctSubmissionRank - 1)).clamp(75, 100);
      rawPercent = rankedScore;
      isGenuineHundred =
          correctSubmissionRank == 1 || pendingBonusPoints == 0;
      if (correctSubmissionRank == 1) {
        feedback.add('First correct submission! Full marks awarded.');
      } else {
        feedback.add(
          'Correct submission — rank #$correctSubmissionRank. Score: $rankedScore/100.',
        );
      }
    } else {
      rawPercent = 50;
      newStreak = 0;
      newPendingBonusPoints = 0;
      feedback.add(
        'Output did not match the expected result. Partial credit awarded for correct concepts.',
      );
    }

    final score = (totalPoints * rawPercent / 100).round();

    int xpAwarded;
    if (isThreeDMeet) {
      if (rawPercent == 0) {
        xpAwarded = 0;
        newStreak = 0;
        newPendingBonusPoints = 0;
      } else if (rawPercent == 50) {
        xpAwarded = 15;
      } else if (correctSubmissionRank == 1) {
        final streakBonus = (currentStreak * 10).clamp(0, 100);
        xpAwarded = 50 + streakBonus;
        newStreak = (currentStreak + 1).clamp(0, 10);
        newPendingBonusPoints = newStreak * 10;
      } else {
        // Rank 2 or higher among correct submissions.
        if (score >= 90) {
          xpAwarded = 45;
        } else if (score >= 80) {
          xpAwarded = 35;
        } else {
          xpAwarded = 25;
        }
        newStreak = 0;
        newPendingBonusPoints = 0;
      }
    } else {
      if (rawPercent >= 100) {
        xpAwarded = 50;
      } else if (rawPercent >= 90) {
        xpAwarded = 45;
      } else if (rawPercent >= 80) {
        xpAwarded = 35;
      } else if (rawPercent >= 70) {
        xpAwarded = 25;
      } else if (rawPercent >= 50) {
        xpAwarded = 15;
      } else {
        xpAwarded = 0;
      }
      // Streak not affected for regular assignments.
      newStreak = currentStreak;
      newPendingBonusPoints = pendingBonusPoints;
    }

    return {
      'score': score,
      'xpAwarded': xpAwarded,
      'newStreak': newStreak,
      'newPendingBonusPoints': newPendingBonusPoints,
      'gradeFeedback': feedback,
      'passedOutput': passedOutput,
      'passedKeywords': passedKeywords,
      'passedForbidden': passedForbidden,
      'isGenuineHundred': isGenuineHundred,
      'rank': correctSubmissionRank,
    };
  }

  /// Trims whitespace and collapses repeated whitespace so formatting
  /// differences (extra spaces, blank lines) don't fail the comparison.
  static String _normalize(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Counts how many submissions for [postId] already graded as correct
  /// (score >= 75) precede this one, used to rank simultaneous correct
  /// submissions before calling [grade].
  static Future<int> getCorrectSubmissionRank(
    dynamic supabaseClient,
    String postId,
  ) async {
    final response = await supabaseClient
        .from('submissions')
        .select('id')
        .eq('assessment_id', postId)
        .eq('is_graded', true)
        .gte('score', 75)
        .count();
    final count = response.count ?? 0;
    return count + 1;
  }
}
