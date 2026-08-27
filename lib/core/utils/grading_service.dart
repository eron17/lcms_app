import 'package:supabase_flutter/supabase_flutter.dart';
import 'auto_grader.dart';

class GradingService {
  static final _supabase = Supabase.instance.client;
  static RealtimeChannel? _channel;
  static bool _isRunning = false;

  // ── Initialize (call once in main.dart) ─────────────────────────────────
  static void initialize() {
    if (_isRunning) return; // Guard against double-init
    _isRunning = true;
    _startListening();
  }

  static void dispose() {
    _channel?.unsubscribe();
    _channel = null;
    _isRunning = false;
  }

  // ── Realtime Listener ────────────────────────────────────────────────────
  static void _startListening() {
    _channel = _supabase
        .channel('grading-service')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'submissions',
          callback: (payload) async {
            final record = payload.newRecord;

            // Only process submissions that are pending grading
            if (record['is_pending'] != true) return;

            await _processSubmission(record);
          },
        )
        .subscribe();
  }

  // ── Core Grading Flow ────────────────────────────────────────────────────
  static Future<void> _processSubmission(
      Map<String, dynamic> submission) async {
    final submissionId = submission['id'] as String?;
    final postId = submission['assessment_id'] as String?;
    final studentId = submission['student_id'] as String?;
    final sourceCode = submission['source_code'] as String? ?? '';
    final actualOutput = submission['actual_output'] as String? ?? '';

    // Guard: skip if any required field is missing
    if (submissionId == null || postId == null || studentId == null) return;

    try {
      // ── Step 1: Fetch post grading config ───────────────────────────────
      final postData = await _supabase
          .from('posts')
          .select(
            'course_id, expected_output, required_keywords, forbidden_patterns, points',
          )
          .eq('id', postId)
          .single();

      final courseId = postData['course_id'] as String?;
      if (courseId == null) return;

      final expectedOutput =
          (postData['expected_output'] as String?) ?? '';
      final requiredKeywords =
          List<String>.from(postData['required_keywords'] ?? []);
      final forbiddenPatterns =
          List<String>.from(postData['forbidden_patterns'] ?? []);
      final totalPoints = (postData['points'] as int?) ?? 100;

      // ── Step 3: Get correct submission rank ──────────────────────────────
      // Count submissions for this post that are already graded with score >= 75
      final rankResponse = await _supabase
          .from('submissions')
          .select('id')
          .eq('assessment_id', postId)
          .eq('is_graded', true)
          .gte('score', 75)
          .count();

      final correctSubmissionRank = rankResponse.count + 1;

      // ── Step 4: Run AutoGrader ───────────────────────────────────────────
      // Streak/bonus inputs are no longer sourced from the student — XP and
      // streak are now per-class (enrollments.class_xp/class_streak), and
      // the streak itself is now a simple day-based counter (updated below
      // via update_class_streak) rather than the old genuine-100 gate, so
      // AutoGrader's streak-bonus params are left at their defaults (0).
      final result = AutoGrader.grade(
        sourceCode: sourceCode,
        actualOutput: actualOutput,
        expectedOutput: expectedOutput,
        requiredKeywords: requiredKeywords,
        forbiddenPatterns: forbiddenPatterns,
        totalPoints: totalPoints,
        isThreeDMeet: true,
        correctSubmissionRank: correctSubmissionRank,
      );

      final score = result['score'] as int;
      final xpAwarded = result['xpAwarded'] as int;
      final gradeFeedback =
          List<String>.from(result['gradeFeedback'] ?? []);
      final rank = result['rank'] as int;

      // ── Step 5: Save result to submissions table ─────────────────────────
      await _supabase.from('submissions').update({
        'score': score,
        'xp_awarded': xpAwarded,
        'is_graded': true,
        'is_pending': false,
        'grade_feedback': gradeFeedback,
        'rank': rank,
        'graded_at': DateTime.now().toIso8601String(),
      }).eq('id', submissionId);

      // ── Step 6: Award per-class XP and update the per-class streak ───────
      if (xpAwarded != 0) {
        await _supabase.rpc(
          'increment_student_xp',
          params: {
            'p_student_id': studentId,
            'p_course_id': courseId,
            'p_xp': xpAwarded,
          },
        );
      }
      await _supabase.rpc(
        'update_class_streak',
        params: {'p_student_id': studentId, 'p_course_id': courseId},
      );

      // ── Step 7: Update leaderboard (if you have one) ────────────────────
      final updatedUser = await _supabase
          .from('users')
          .select('xp')
          .eq('id', studentId)
          .single();
      await _updateLeaderboard(
        studentId: studentId,
        courseId: courseId,
        newTotalXp: (updatedUser['xp'] as int?) ?? 0,
      );
    } catch (e) {
      // Mark as failed so Unity doesn't spin forever
      // is_pending = false so Unity proceeds, is_graded = false signals error
      try {
        await _supabase.from('submissions').update({
          'is_pending': false,
          'is_graded': false,
          'grade_feedback': [
            'Grading failed. Please contact your instructor.',
            'Error: ${e.toString()}',
          ],
        }).eq('id', submissionId);
      } catch (_) {
        // If even the error update fails, nothing more we can do
      }
    }
  }

  // ── Leaderboard Update ───────────────────────────────────────────────────
  static Future<void> _updateLeaderboard({
    required String studentId,
    required String? courseId,
    required int newTotalXp,
  }) async {
    if (courseId == null) return;
    try {
      // Upsert into leaderboard table (create if not exists)
      await _supabase.from('leaderboard').upsert({
        'student_id': studentId,
        'course_id': courseId,
        'total_xp': newTotalXp,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'student_id, course_id');
    } catch (_) {
      // Leaderboard update is non-critical — don't let it fail grading
    }
  }

}