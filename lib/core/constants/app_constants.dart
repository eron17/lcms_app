// lib/core/constants/app_constants.dart

class AppConstants {
  AppConstants._();

  // ─── App Info ──────────────────────────────────────────────
  static const String appName = 'C++ LCMS';
  static const String appVersion = '1.0.0';

  // ─── Firestore Collections ─────────────────────────────────
  static const String usersCollection = 'users';
  static const String coursesCollection = 'courses';
  static const String modulesCollection = 'modules';
  static const String contentCollection = 'content_items';
  static const String assessmentsCollection = 'assessments';
  static const String submissionsCollection = 'submissions';
  static const String progressCollection = 'progress';
  static const String leaderboardCollection = 'leaderboard';
  static const String badgesCollection = 'badges';
  static const String enrollmentsCollection = 'enrollments';

  // ─── User Roles ────────────────────────────────────────────
  static const String roleStudent = 'student';
  static const String roleInstructor = 'instructor';

  // ─── Content Types ─────────────────────────────────────────
  static const String contentTypePdf = 'pdf';
  static const String contentTypeVideo = 'video';
  static const String contentTypeCode = 'code';
  static const String contentTypeImage = 'image';
  static const String contentTypeLink = 'link';

  // ─── Assessment Types ──────────────────────────────────────
  static const String assessmentTypeQuiz = 'quiz';
  static const String assessmentTypeCoding = 'coding';
  static const String assessmentTypeFile = 'file';

  // ─── Gamification ──────────────────────────────────────────
  static const int xpPerLessonComplete = 10;
  static const int xpPerQuizPass = 25;
  static const int xpPerAssignmentSubmit = 15;
  static const int xpPerPerfectScore = 50;

  static const Map<String, int> levelThresholds = {
    'Script Kiddie': 0,
    'Code Newbie': 300,
    'Junior Dev': 1000,
    'Refactorer': 2500,
    'Stack Overflow Guru': 5000,
    'Tech Lead': 8000,
    '10x Developer': 12000,
    'Compiler Whisperer': 18000,
  };

  // ─── JDoodle API ───────────────────────────────────────────
  static const String jdoodleBaseUrl = 'https://api.jdoodle.com/v1';
  static const String jdoodleLanguage = 'cpp17';

  // ─── Storage Paths ─────────────────────────────────────────
  static const String storageCourseThumbnails = 'course_thumbnails';
  static const String storageContentFiles = 'content_files';
  static const String storageSubmissions = 'submissions';
  static const String storageAvatars = 'avatars';

  // ─── Unity API ─────────────────────────────────────────────
  static const String unityApiVersion = 'v1';

  // ─── Pagination ────────────────────────────────────────────
  static const int defaultPageSize = 10;

  // ─── Cache ─────────────────────────────────────────────────
  static const int cacheExpiryHours = 24;
}
