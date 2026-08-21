import 'code_scanner.dart';

/// Computes score, XP, and streak/bonus updates for a graded submission.
///
/// Used for both 3D Meet auto-grading (code + output based, with a
/// streak/bonus mechanic) and regular assignment grading (percentage-tier
/// XP, no streak).
class AutoGrader {
  static const double _compileWeight = 0.05;
  static const double _outputWeight = 0.85;
  static const double _keywordWeight = 0.10;
  // No forbidden weight — cheating wipes the entire score to 0 instead.

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
    final feedback = <String>[];
    int score = 0;

    // ── Output match — 85% ────────────────────────────────────────────────
    final passedOutput = _normalize(actualOutput) == _normalize(expectedOutput);
    if (passedOutput) {
      score += (totalPoints * _outputWeight).round();
      feedback.add('Output matches the expected result.');
    } else {
      feedback.add('Output did not match the expected result.');
    }

    // ── Compiles — 5% ─────────────────────────────────────────────────────
    // No explicit compile-status field is passed through from Unity/JDoodle
    // yet, so this is inferred: non-empty output with no obvious compiler
    // error marker counts as "compiled".
    final hasCompileError = RegExp(
      r'error[:\s]',
      caseSensitive: false,
    ).hasMatch(actualOutput);
    final compiles = actualOutput.trim().isNotEmpty && !hasCompileError;
    if (compiles) {
      score += (totalPoints * _compileWeight).round();
      feedback.add('Code compiled and produced output.');
    } else {
      feedback.add('Code did not compile or produced no output.');
    }

    // ── Required keywords — 10%, 5% floor ───────────────────────────────
    // Keywords are guidance — never a grade killer. The output match and
    // forbidden/hardcoded checks are the real judges of understanding vs
    // cheating.
    final foundCount = requiredKeywords.where(scanner.hasKeyword).length;
    final passedKeywords =
        requiredKeywords.isEmpty || foundCount == requiredKeywords.length;
    int keywordScore;
    if (requiredKeywords.isEmpty) {
      keywordScore = (totalPoints * _keywordWeight).round();
      feedback.add('No required keywords set — keyword check skipped');
    } else if (foundCount == requiredKeywords.length) {
      // All keywords found → full 10%
      keywordScore = (totalPoints * _keywordWeight).round();
      feedback.add('All required keywords used');
    } else if (foundCount > 0) {
      // Some keywords found → 7%
      keywordScore = (totalPoints * 0.07).round();
      feedback.add(
        '$foundCount of ${requiredKeywords.length} '
        'required keywords found',
      );
    } else {
      // None found → 5% floor (effort credit)
      keywordScore = (totalPoints * 0.05).round();
      feedback.add(
        'Required keywords not detected — '
        'review the assessment instructions',
      );
    }
    score += keywordScore;

    // ── Zero tolerance: forbidden patterns / hardcoded output ────────────
    final forbiddenFound = scanner.anyForbiddenFound(forbiddenPatterns);
    final hardcoded = scanner.isLikelyHardcoded;
    if (forbiddenFound) {
      feedback.add('Forbidden pattern(s) detected — submission score is 0.');
    }
    if (hardcoded) {
      feedback.add('Hardcoded output detected — submission score is 0.');
    }
    final passedForbidden = !forbiddenFound && !hardcoded;
    if (!passedForbidden) {
      score = 0;
      feedback.add('Final score: 0 — cheating detected');
    }

    // ── Clamp to avoid floating-point overflow ────────────────────────────
    score = score.clamp(0, totalPoints);

    // A submission only counts as "genuinely correct" for streak/rank
    // purposes when the output matches and no cheating signal fired.
    final isCorrect = passedOutput && passedForbidden;
    var isGenuineHundred = false;

    int newStreak = currentStreak;
    int newPendingBonusPoints = pendingBonusPoints;
    int xpAwarded;

    if (isThreeDMeet) {
      if (score == 0) {
        xpAwarded = 0;
        newStreak = 0;
        newPendingBonusPoints = 0;
      } else if (!isCorrect) {
        // Compiled and/or used the right keywords, but output was wrong.
        xpAwarded = 15;
        newStreak = 0;
        newPendingBonusPoints = 0;
      } else if (correctSubmissionRank == 1) {
        final streakBonus = (currentStreak * 10).clamp(0, 100);
        xpAwarded = 50 + streakBonus;
        newStreak = (currentStreak + 1).clamp(0, 10);
        newPendingBonusPoints = newStreak * 10;
        isGenuineHundred = true;
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
      final percent = totalPoints == 0
          ? 0
          : (score * 100 / totalPoints).round();
      if (percent >= 100) {
        xpAwarded = 50;
      } else if (percent >= 90) {
        xpAwarded = 45;
      } else if (percent >= 80) {
        xpAwarded = 35;
      } else if (percent >= 70) {
        xpAwarded = 25;
      } else if (percent >= 50) {
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
