// lib/presentation/dashboard/instructor_dashboard.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/router/app_router.dart';
import '../../data/models/user_model.dart';
import '../../providers/theme_provider.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/constants/app_colors.dart';
import 'dart:math';
import '../profile/edit_profile_screen.dart';
import '../courses/archived_classes_screen.dart';
import '../notifications/notifications_screen.dart';
import '../courses/assignment_detail_screen.dart';
import 'package:flutter/services.dart';
import '../../shared/widgets/pressable_scale.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';


class InstructorDashboard extends ConsumerStatefulWidget {
  const InstructorDashboard({super.key});

  @override
  ConsumerState<InstructorDashboard> createState() =>
      _InstructorDashboardState();
}

class _InstructorDashboardState extends ConsumerState<InstructorDashboard>
    with TickerProviderStateMixin {
  // ─── State ───────────────────────────────────────────────
  int _currentIndex = 0;
  final _supabase = Supabase.instance.client;
  UserModel? _currentUser;
  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _pendingSubmissions = [];
  bool _isLoadingCourses = true;
  final _homeSearchController = TextEditingController();
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final _localAuth = LocalAuthentication();
  bool _biometricsEnabled = false;
  String _homeSearchQuery = '';
  bool _hasUnreadNotifications = false;

  // Instructor leaderboard state
  String? _lbSelectedCourseId;
  bool _lbIsLoading = false;
  List<Map<String, dynamic>> _lbData = [];
  List<Map<String, dynamic>> _instructorCourses = [];
  RealtimeChannel? _rankingChannel;

  // Reports drill-down state
  Map<String, dynamic>? _selectedCourse;
  Map<String, dynamic>? _selectedPost;
  List<Map<String, dynamic>> _reportCourses = [];
  List<Map<String, dynamic>> _reportPosts = [];
  List<Map<String, dynamic>> _reportStudents = [];
  bool _isLoadingReport = false;
  String _studentFilter = 'all'; // 'all','graded','ungraded','no_sub'
  int _reportTotalSubmissions = 0;
  int _reportGraded = 0;
  int _reportUngraded = 0;
  int _reportNotSubmitted = 0;

  // ─── Animations ──────────────────────────────────────────
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;
  late AnimationController _fabController;
  late Animation<double> _fabAnimation;

  final List<List<Color>> _cardGradients = [
    [const Color(0xFF7B2FBE), const Color(0xFF4A90D9)],
    [const Color(0xFF1565C0), const Color(0xFF00B4D8)],
    [const Color(0xFF6A0572), const Color(0xFF1E90FF)],
    [const Color(0xFF0D47A1), const Color(0xFF00E5FF)],
    [const Color(0xFF4A148C), const Color(0xFF7B1FA2)],
    [const Color(0xFF1A237E), const Color(0xFF283593)],
  ];

  @override
  void initState() {
    super.initState();
    _initNotificationListener();
    _checkUnreadNotifications();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fabAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fabController, curve: Curves.easeOut));
    _fabController.forward();
    _loadData();
    _loadInstructorCourses();
    _checkBiometricStatus();
  }

  Future<void> _checkBiometricStatus() async {
    try {
      final savedEmail = await _storage.read(key: 'user_email');
      if (mounted) {
        setState(() => _biometricsEnabled = savedEmail != null);
      }
    } catch (e) {
      debugPrint('Biometric check error: $e');
    }
  }

  Future<void> _toggleBiometrics(bool enabled) async {
    if (enabled) {
      _showEnableBiometricsDialog();
    } else {
      await _storage.delete(key: 'user_email');
      await _storage.delete(key: 'user_password');
      if (mounted) setState(() => _biometricsEnabled = false);
    }
  }

  void _showEnableBiometricsDialog() {
    final passController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark
            ? const Color(0xFF0A1128)
            : Colors.white,
        title: const Text(
          'Enable Biometrics',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your current password to enable fingerprint login.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Current Password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (passController.text.isEmpty) return;
              final authenticated = await _localAuth.authenticate(
                localizedReason: 'Confirm fingerprint to enable fast login',
                options: const AuthenticationOptions(biometricOnly: true),
              );
              if (authenticated) {
                await _storage.write(
                  key: 'user_email',
                  value: _currentUser?.email,
                );
                await _storage.write(
                  key: 'user_password',
                  value: passController.text.trim(),
                );
                if (!context.mounted) return;
                setState(() => _biometricsEnabled = true);
                Navigator.pop(ctx);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Biometric login enabled!')),
                );
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _rankingChannel?.unsubscribe();
    _glowController.dispose();
    _fabController.dispose();
    _homeSearchController.dispose();
    super.dispose();
  }

  // ─── Data Loading ────────────────────────────────────────

  Future<void> _loadData() async {
    await Future.wait([
      _loadUser(),
      _loadCourses(),
      _loadPendingSubmissions(),
      _loadReports(),
    ]);
  }

  Future<void> _loadUser() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .single();
      if (mounted) {
        setState(() {
          _currentUser = UserModel.fromMap(data);
        });
      }
    } catch (e) {
      debugPrint('User load error: $e');
    }
  }

  Future<void> _loadCourses() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _supabase
          .from('courses')
          .select('*')
          .eq('instructor_id', userId)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _courses = List<Map<String, dynamic>>.from(data as List);
          _isLoadingCourses = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingCourses = false);
    }
  }

  Future<void> _loadPendingSubmissions() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _supabase
          .from('submissions')
          .select('*, assessments(title), users(name)')
          .eq('is_graded', false)
          .order('submitted_at', ascending: false)
          .limit(10);
      if (mounted) {
        setState(() {
          _pendingSubmissions = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint('Submissions error: $e');
    }
  }

  Future<void> _loadReports() async {
    setState(() => _isLoadingReport = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final courses = await _supabase
          .from('courses')
          .select('id, title, course_code, section')
          .eq('instructor_id', userId)
          .eq('is_archived', false)
          .order('created_at');

      int totalSub = 0, totalGraded = 0, totalUngraded = 0, totalNoSub = 0;

      final enriched = <Map<String, dynamic>>[];
      for (final course in courses) {
        final enrollments = await _supabase
            .from('enrollments')
            .select('student_id')
            .eq('course_id', course['id']);
        final studentCount = enrollments.length;

        final posts = await _supabase
            .from('posts')
            .select('id')
            .eq('course_id', course['id'])
            .inFilter('type', ['assignment', '3d_meet']);

        int passCount = 0;
        int gradedPosts = 0;

        for (final post in posts) {
          // submitted_at determines whether a row is an actual turn-in
          // (vs. a draft with files attached but never submitted).
          final subs = await _supabase
              .from('submissions')
              .select('is_graded, score, student_id, submitted_at')
              .eq('assessment_id', post['id']);

          final turnedIn =
              subs.where((s) => s['submitted_at'] != null).toList();
          final gradedSubs =
              turnedIn.where((s) => s['is_graded'] == true).length;
          final ungradedSubs =
              turnedIn.where((s) => s['is_graded'] != true).length;
          final passingSubs = turnedIn
              .where((s) =>
                  s['is_graded'] == true && (s['score'] as num? ?? 0) >= 75)
              .length;
          final noSubCount = studentCount - turnedIn.length;

          totalSub += turnedIn.length;
          totalGraded += gradedSubs;
          totalUngraded += ungradedSubs;
          totalNoSub += noSubCount < 0 ? 0 : noSubCount;

          if (gradedSubs > 0) {
            passCount += passingSubs;
            gradedPosts++;
          }
        }

        final passRate = studentCount > 0 && gradedPosts > 0
            ? (passCount / (gradedPosts * studentCount) * 100).clamp(0, 100)
            : 0.0;

        enriched.add({
          ...course,
          'student_count': studentCount,
          'pass_rate': passRate,
        });
      }

      if (mounted) {
        setState(() {
          _reportCourses = enriched;
          _reportTotalSubmissions = totalSub;
          _reportGraded = totalGraded;
          _reportUngraded = totalUngraded;
          _reportNotSubmitted = totalNoSub;
        });
      }
    } catch (e) {
      debugPrint('Reports load error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingReport = false);
    }
  }

  Future<void> _loadLevel2(String courseId) async {
    setState(() => _isLoadingReport = true);
    try {
      final enrollments = await _supabase
          .from('enrollments')
          .select('student_id')
          .eq('course_id', courseId);
      final studentCount = enrollments.length;

      final posts = await _supabase
          .from('posts')
          .select('id, title, type, created_at')
          .eq('course_id', courseId)
          .inFilter('type', ['assignment', '3d_meet'])
          .order('created_at', ascending: false);

      final enriched = <Map<String, dynamic>>[];
      for (final post in posts) {
        final subs = await _supabase
            .from('submissions')
            .select('is_graded, student_id, submitted_at')
            .eq('assessment_id', post['id']);

        final turnedIn =
            subs.where((s) => s['submitted_at'] != null).toList();
        final gradedCount =
            turnedIn.where((s) => s['is_graded'] == true).length;
        final ungradedCount =
            turnedIn.where((s) => s['is_graded'] != true).length;
        final noSubCount =
            (studentCount - turnedIn.length).clamp(0, studentCount);

        enriched.add({
          ...post,
          'graded_count': gradedCount,
          'ungraded_count': ungradedCount,
          'no_sub_count': noSubCount,
        });
      }

      if (mounted) setState(() => _reportPosts = enriched);
    } catch (e) {
      debugPrint('Level 2 report load error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingReport = false);
    }
  }

  Future<void> _loadLevel3(String postId) async {
    setState(() => _isLoadingReport = true);
    try {
      final courseId = _selectedCourse!['id'] as String;

      final enrollments = await _supabase
          .from('enrollments')
          .select('student_id, users(id, name, avatar_url)')
          .eq('course_id', courseId);

      // No 'status' column on submissions — status is derived below from
      // submitted_at (turned in?) and is_graded, matching the same logic
      // AssignmentDetailScreen uses (_submissionIsTurnedIn/_submissionHasFile).
      final subs = await _supabase
          .from('submissions')
          .select('student_id, is_graded, score, submitted_at')
          .eq('assessment_id', postId);

      final subMap = {for (final s in subs) s['student_id']: s};

      final students = <Map<String, dynamic>>[];
      int graded = 0, ungraded = 0, noSub = 0;

      for (final enrollment in enrollments) {
        final userData = enrollment['users'] as Map<String, dynamic>?;
        if (userData == null) continue;
        final sid = userData['id'] as String;
        final sub = subMap[sid];
        final isTurnedIn = sub != null && sub['submitted_at'] != null;

        String status;
        if (!isTurnedIn) {
          status = 'assigned';
          noSub++;
        } else if (sub['is_graded'] == true) {
          status = 'graded';
          graded++;
        } else {
          status = 'turned_in';
          ungraded++;
        }

        students.add({
          'id': sid,
          'name': userData['name'] ?? '',
          'avatar_url': userData['avatar_url'],
          'status': status,
          'score': sub?['score'],
        });
      }

      if (mounted) {
        setState(() {
          _reportStudents = students;
          _reportGraded = graded;
          _reportUngraded = ungraded;
          _reportNotSubmitted = noSub;
          _studentFilter = 'all';
        });
      }
    } catch (e) {
      debugPrint('Level 3 report load error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingReport = false);
    }
  }

  void _initNotificationListener() {
  final userId = _supabase.auth.currentUser?.id;
  if (userId == null) return;

  // Real-time listener for the notifications table
  _supabase
    .channel('public:notifications')
    .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      callback: (payload) {
        // If the new notification is for ME, show the red dot
        if (payload.newRecord['user_id'] == userId) {
          if (mounted) setState(() => _hasUnreadNotifications = true);
        }
      },
    )
    .subscribe();
}

  Future<void> _checkUnreadNotifications() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final data = await _supabase
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false)
          .limit(1);
      if (mounted) {
        setState(() => _hasUnreadNotifications = (data as List).isNotEmpty);
      }
    } catch (e) {
      debugPrint('Check unread notifications: $e');
    }
  }

  // ─── Actions ─────────────────────────────────────────────

  String _generateClassCode() {
    final random = Random.secure();
    return List.generate(
      6,
      (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[random.nextInt(36)],
    ).join();
  }

  void _showCreateCourseDialog() {
    final titleController = TextEditingController();
    final courseCodeController = TextEditingController();
    final programController = TextEditingController();
    final sectionController = TextEditingController();
    final descriptionController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isCreating = false;

    // Use system dark blue for text in light mode
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: context.surfaceColor, // Turns white in Light Mode
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                // ─── Handle ───
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.borderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // ─── Header ───
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primaryDark, AppColors.primary],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Create New Class',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),

                // ─── Form ───
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSheetField(
                            'Course Title',
                            'e.g. Introduction to C++',
                            titleController,
                            Icons.book_outlined,
                            validator: (v) => v?.isEmpty ?? true
                                ? 'Enter course title'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          _buildSheetField(
                            'Course Code',
                            'e.g. CPC113',
                            courseCodeController,
                            Icons.tag,
                            validator: (v) =>
                                v?.isEmpty ?? true ? 'Enter course code' : null,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildSheetField(
                                  'Program',
                                  'e.g. BSIT',
                                  programController,
                                  Icons.school_outlined,
                                  validator: (v) =>
                                      v?.isEmpty ?? true ? 'Required' : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildSheetField(
                                  'Year & Section',
                                  'e.g. 1-A',
                                  sectionController,
                                  Icons.group_outlined,
                                  validator: (v) =>
                                      v?.isEmpty ?? true ? 'Required' : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildSheetField(
                            'Description (optional)',
                            'What is this course about?',
                            descriptionController,
                            Icons.description_outlined,
                            maxLines: 3,
                          ),
                          const SizedBox(height: 32),

                          // ─── Create Button ───
                          SizedBox(
                            width: double.infinity,
                            height: 54, // Keep original height
                            child: PressableScale(
                              // 1. Disable interaction if already creating
                              onPressed: isCreating
                                  ? null
                                  : () async {
                                      if (!formKey.currentState!.validate()) {
                                        return;
                                      }
                                      setSheetState(() => isCreating = true);

                                      final String?
                                      generatedCode = await _createCourse(
                                        title: titleController.text.trim(),
                                        courseCode: courseCodeController.text
                                            .trim()
                                            .toUpperCase(),
                                        program: programController.text.trim(),
                                        section: sectionController.text.trim(),
                                        description: descriptionController.text
                                            .trim(),
                                      );

                                      if (!context.mounted) return;
                                      Navigator.pop(
                                        context,
                                      ); // Close bottom sheet
                                      if (generatedCode != null) {
                                        final fullTitle =
                                            '${titleController.text.trim()} - ${programController.text.trim()} ${sectionController.text.trim()}';
                                        _showClassCodeDialog(
                                          generatedCode,
                                          fullTitle,
                                        );
                                      } else {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Failed to create class. Please try again.',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                              scaleFactor: 0.96, // Tactile shrink
                              opacityFactor: 0.7, // Professional dimming
                              child: Container(
                                decoration: BoxDecoration(
                                  // 2. Applied consistent premium gradient
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppColors.primaryDark,
                                      AppColors.primary,
                                    ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: isCreating
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.5,
                                          ),
                                        )
                                      : const Text(
                                          'Create Class',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: Colors.white,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<String?> _createCourse({
    required String title,
    required String courseCode,
    required String program,
    required String section,
    required String description,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final classCode = _generateClassCode();
      final fullTitle = '$title - $program $section';

      await _supabase.from('courses').insert({
        'title': fullTitle,
        'description': description,
        'instructor_id': userId,
        'instructor_name': _currentUser?.name ?? 'Instructor',
        'course_code': courseCode,
        'class_code': classCode,
        'program': program,
        'section': section,
        'is_published': true,
        'enrolled_count': 0,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      await _loadCourses();
      return classCode; // Return the code so the UI can show it
    } catch (e) {
      debugPrint('Create Course Error: $e');
      return null;
    }
  }

  void _showClassCodeDialog(String classCode, String courseTitle) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: context.borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.celebration_rounded,
                  size: 48,
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Class Created!',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                courseTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: textColor.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 28),

              // ─── Class Code Box ───
              Container(
                padding: const EdgeInsets.all(24),
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryDark, AppColors.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    const Text(
                      'CLASS CODE',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      classCode,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // ─── Copy Button ───
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: classCode));
                        HapticFeedback.mediumImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Class code copied!'),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.copy_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Copy Code',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _loadCourses();
                  },
                  child: const Text('Got it!'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCourseOptions(Map<String, dynamic> course) {
    final isArchived = course['is_archived'] == true;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              course['title'] ?? '',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _buildOptionItem(
              Icons.key_outlined,
              'Show Class Code',
              AppColors.primary,
              () {
                Navigator.pop(context);
                _showClassCodeDialog(
                  course['class_code'] ?? '',
                  course['title'] ?? '',
                );
              },
            ),
            // Changed: Removed Publish/Unpublish. Added Restore if archived.
            if (isArchived)
              _buildOptionItem(
                Icons.restore_page_outlined,
                'Restore Class',
                Colors.green,
                () async {
                  Navigator.pop(context);
                  final userId = _supabase.auth.currentUser?.id;
                  if (userId == null) return;
                  await _supabase
                      .from('courses')
                      .update({'is_archived': false, 'is_published': true})
                      .eq('id', course['id'])
                      .eq('instructor_id', userId);
                  await _loadCourses();
                },
              )
            else
              _buildOptionItem(
                Icons.archive_outlined,
                'Archive Class',
                Colors.orange,
                () async {
                  Navigator.pop(context);
                  await _archiveCourse(course['id']);
                },
              ),
            _buildOptionItem(
              Icons.delete_outline,
              'Delete Class',
              AppColors.error,
              () {
                Navigator.pop(context);
                _showDeleteConfirmation(course['id']); // Pass ID
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionItem(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _archiveCourse(String courseId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      await _supabase
          .from('courses')
          .update({'is_published': false, 'is_archived': true})
          .eq('id', courseId)
          .eq('instructor_id', userId);
      await _loadCourses();
    } catch (e) {
      debugPrint('Archive error: $e');
    }
  }

  void _showDeleteConfirmation(String courseId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: Text(
          'Delete Class?',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: context.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete this class? All data will be lost permanently.',
          style: TextStyle(fontFamily: 'Poppins', color: context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'CANCEL',
              style: TextStyle(fontFamily: 'Poppins', color: context.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(context);
              _deleteCourse(courseId);
            },
            child: const Text(
              'YES, DELETE',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCourse(String courseId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      await _supabase
          .from('courses')
          .delete()
          .eq('id', courseId)
          .eq('instructor_id', userId);
      await _loadCourses();
    } catch (e) {
      debugPrint('Delete error: $e');
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark
            ? const Color(0xFF0A1128)
            : Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Log out?',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'You will need to sign in again to '
          'access your account.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    color: context.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    color: AppColors.error,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      // Logging out only ends the session — saved biometric credentials
      // are intentionally left in place so fingerprint sign-in keeps
      // working next time. They're only cleared by the 2-min background
      // timeout / killed-while-backgrounded security paths in
      // app_security_manager.dart.
      await _supabase.auth.signOut();
      if (mounted) context.go(AppRoutes.opening);
    } catch (e) {
      debugPrint('Logout error: $e');
    }
  }

  // ─── BUILD ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 900;
        if (isDesktop) {
          return _buildDesktopLayout();
        }
        return _buildMobileLayout();
      },
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: Stack(
        children: [
          _buildBackground(),
          if (context.isDark) _buildGlowEffect(MediaQuery.of(context).size),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: [
                      _buildHomePage(),
                      _buildReportsPage(),
                      _buildInstructorLeaderboardPage(),
                      _buildProfilePage(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_currentIndex == 0)
            Positioned(
              bottom: 80,
              right: 20,
              child: ScaleTransition(scale: _fabAnimation, child: _buildFAB()),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildDesktopLayout() {
    final pages = [
      _buildHomePage(),
      _buildReportsPage(),
      _buildInstructorLeaderboardPage(),
      _buildProfilePage(),
    ];
    final navItems = [
      (Icons.home_rounded, 'Home'),
      (Icons.bar_chart_rounded, 'Reports'),
      (Icons.emoji_events_rounded, 'Ranking'),
      (Icons.person_rounded, 'Profile'),
    ];

    return Scaffold(
      backgroundColor: context.bgColor,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sidebar
          Container(
            width: 220,
            decoration: BoxDecoration(
              color: context.isDark ? const Color(0xFF0A1128) : Colors.white,
              border: Border(
                right: BorderSide(color: context.borderColor, width: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                  child: Image.asset(
                    'assets/images/app_name.png',
                    height: 28,
                    fit: BoxFit.contain,
                  ),
                ),
                // Nav items
                ...List.generate(navItems.length, (i) {
                  final isActive = _currentIndex == i;
                  return GestureDetector(
                    onTap: () => setState(() => _currentIndex = i),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            navItems[i].$1,
                            color: isActive
                                ? AppColors.primary
                                : context.textSecondary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            navItems[i].$2,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: isActive
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: isActive
                                  ? AppColors.primary
                                  : context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const Spacer(),
                // Notification bell
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const NotificationsScreen(isInstructor: true),
                        ),
                      );
                      await _checkUnreadNotifications();
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          Icons.notifications_outlined,
                          color: context.textSecondary,
                          size: 22,
                        ),
                        if (_hasUnreadNotifications)
                          Positioned(
                            top: -1,
                            right: -1,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: context.isDark
                                      ? const Color(0xFF0A1128)
                                      : Colors.white,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Content area
          Expanded(
            child: Stack(
              children: [
                pages[_currentIndex],
                if (_currentIndex == 0)
                  Positioned(
                    bottom: 24,
                    right: 24,
                    child: ScaleTransition(
                      scale: _fabAnimation,
                      child: _buildFAB(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() => Container(decoration: context.scaffoldGradient);

  Widget _buildTopBar() {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Image.asset('assets/images/app_name.png', height: 28, fit: BoxFit.contain),
          const Spacer(),
          
          // ─── CORRECTED PRESSABLE NOTIFICATION BUTTON ───
          PressableScale(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  // Pass 'true' directly since this is the Instructor Dashboard
                  builder: (_) => const NotificationsScreen(isInstructor: true),
                ),
              );
              // Re-check real unread state rather than blindly clearing —
              // the user may not have read everything in that screen.
              await _checkUnreadNotifications();
            },
            scaleFactor: 0.94, 
            opacityFactor: 0.6, 
            child: Container(
              padding: const EdgeInsets.all(10),              
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.notifications_outlined,
                    color: textColor,
                    size: 25, 
                  ),
                  
                  // ─── THE RED NOTIFICATION DOT ───
                  if (_hasUnreadNotifications)
                    Positioned(
                      top: -1,
                      right: -1,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: context.cardColor, 
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFAB() {
    return PressableScale(
      onPressed: _showCreateCourseDialog,
      scaleFactor: 0.94, // Deeper interaction for the small FAB
      opacityFactor: 0.8,
      child: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) => Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryDark, AppColors.primary],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              if (context.isDark)
                BoxShadow(
                  color: AppColors.primary.withValues(
                    alpha: _glowAnimation.value * 0.6,
                  ),
                  blurRadius: 16,
                  spreadRadius: 2,
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    final items = [
      {'icon': Icons.home_outlined, 'activeIcon': Icons.home, 'label': 'Home'},
      {
        'icon': Icons.bar_chart_outlined,
        'activeIcon': Icons.bar_chart,
        'label': 'Reports',
      },
      {
        'icon': Icons.emoji_events_outlined,
        'activeIcon': Icons.emoji_events_rounded,
        'label': 'Ranking',
      },
      {
        'icon': Icons.person_outline,
        'activeIcon': Icons.person,
        'label': 'Profile',
      },
    ];
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: context.cardColor,
        border: Border(
          top: BorderSide(color: context.borderColor.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final isActive = _currentIndex == index;
          return GestureDetector(
            onTap: () {
              setState(() => _currentIndex = index);
              if (index == 2) _loadReports();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: isActive
                    ? const LinearGradient(
                        colors: [AppColors.primaryDark, AppColors.primary],
                      )
                    : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isActive
                        ? items[index]['activeIcon'] as IconData
                        : items[index]['icon'] as IconData,
                    color: isActive
                        ? Colors.white
                        : textColor.withValues(alpha: 0.5),
                    size: 22,
                  ),
                  Text(
                    items[index]['label'] as String,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      color: isActive
                          ? Colors.white
                          : textColor.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── Home Page ───────────────────────────────────────────
  Widget _buildHomePage() {
    final name = _currentUser?.name ?? 'Instructor';
    final activeCoursesCount = _courses
        .where((c) => c['is_published'] == true)
        .length;
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, isDesktop ? 32 : 0, 20, 20),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) ...[
            // ─── Web Welcome Bar ───
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accent, AppColors.studentColor],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Good day,',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  Text(
                    name,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Manage your classes and track student progress',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildWebStatCard(
                  icon: Icons.book_rounded,
                  color: const Color(0xFF3B9EFF),
                  value: '${_courses.length}',
                  label: 'Total classes',
                ),
                const SizedBox(width: 10),
                _buildWebStatCard(
                  icon: Icons.people_rounded,
                  color: const Color(0xFF4CAF50),
                  value: '$_totalStudents',
                  label: 'Total students',
                ),
                const SizedBox(width: 10),
                _buildWebStatCard(
                  icon: Icons.pending_actions_rounded,
                  color: const Color(0xFFFF9800),
                  value: '${_pendingSubmissions.length}',
                  label: 'Pending grades',
                ),
                const SizedBox(width: 10),
                _buildWebStatCard(
                  icon: Icons.check_circle_rounded,
                  color: const Color(0xFF7B2FBE),
                  value: '$activeCoursesCount',
                  label: 'Published',
                ),
              ],
            ),
            const SizedBox(height: 16),
          ] else ...[
            // ─── Welcome Banner (Colors kept white for contrast) ───
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accent, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Good day,',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                        Text(
                          name,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Manage your classes and track student progress.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.school_outlined,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ─── Quick Stats (REPLACED EMOJIS WITH ICONS) ───
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [
                _buildStatCard(
                  Icons.auto_stories_rounded, // Proper Icon
                  '${_courses.length}',
                  'Total Classes',
                  AppColors.primary,
                ),
                _buildStatCard(
                  Icons.people_alt_rounded, // Proper Icon
                  '$_totalStudents',
                  'Total Students',
                  AppColors.accent,
                ),
                _buildStatCard(
                  Icons.pending_actions_rounded, // Proper Icon
                  '${_pendingSubmissions.length}',
                  'Pending Grades',
                  AppColors.warning,
                ),
                _buildStatCard(
                  Icons.check_circle_outline_rounded, // Proper Icon
                  '$activeCoursesCount',
                  'Published',
                  AppColors.success,
                ),
              ],
            ),

            const SizedBox(height: 16),
          ],

          // ─── Search bar ───
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: TextField(
              controller: _homeSearchController,
              onChanged: (v) => setState(() => _homeSearchQuery = v),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: context.isDark ? Colors.white : const Color(0xFF0D1B4B),
              ),
              decoration: InputDecoration(
                hintText: 'Search classes...',
                hintStyle: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: context.textHint,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: context.textHint,
                  size: 20,
                ),
                filled: true,
                fillColor: context.isDark
                    ? const Color(0xFF111E3D)
                    : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),

          // ─── My Classes label ───
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              'My Classes',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: context.isDark ? Colors.white : const Color(0xFF0D1B4B),
              ),
            ),
          ),

          // ─── Classes list (filtered by search) ───
          ..._buildHomeClassesList(),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  List<Widget> _buildHomeClassesList() {
    if (_isLoadingCourses) {
      return const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    final activeCourses = _courses
        .where((c) => c['is_archived'] != true)
        .toList();

    if (activeCourses.isEmpty) {
      return [_buildEmptyClasses()];
    }

    final filtered = activeCourses.where((c) {
      if (_homeSearchQuery.isEmpty) return true;
      final title = (c['title'] as String? ?? '').toLowerCase();
      final code = (c['course_code'] as String? ?? '').toLowerCase();
      final query = _homeSearchQuery.toLowerCase();
      return title.contains(query) || code.contains(query);
    }).toList();

    if (filtered.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              'No classes match "$_homeSearchQuery"',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: context.textHint,
              ),
            ),
          ),
        ),
      ];
    }

    if (MediaQuery.of(context).size.width > 900) {
      return [
        LayoutBuilder(
          builder: (ctx, constraints) {
            final w = constraints.maxWidth;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: w > 1200 ? 3 : 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: w > 1200 ? 2.2 : 2.0,
              ),
              itemCount: filtered.length,
              itemBuilder: (ctx, i) => _buildWebClassCard(filtered[i], i),
            );
          },
        ),
      ];
    }

    return filtered
        .asMap()
        .entries
        .map((entry) => _buildCourseCard(entry.value, entry.key))
        .toList();
  }

  Widget _buildWebStatCard({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
  }) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.isDark ? const Color(0xFF111d33) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: context.isDark
                ? Colors.white.withValues(alpha: 0.07)
                : const Color(0xFFDDE3F0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                color: textColor.withValues(alpha: 0.4),
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebClassCard(Map<String, dynamic> course, int index) {
    final colors = [
      [const Color(0xFF7B2FBE), const Color(0xFF4a90e2)],
      [const Color(0xFF1a6eb5), const Color(0xFF0d9488)],
      [const Color(0xFF2196F3), const Color(0xFF00BCD4)],
      [const Color(0xFF7B2FBE), const Color(0xFF2196F3)],
    ];
    final c = colors[index % colors.length];
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return PressableScale(
      onPressed: () => context.push(
        AppRoutes.courseDetail,
        extra: {'course': course, 'isInstructor': true},
      ),
      scaleFactor: 0.98,
      opacityFactor: 0.9,
      child: Container(
        decoration: BoxDecoration(
          color: context.isDark ? const Color(0xFF111d33) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: context.isDark
                ? Colors.white.withValues(alpha: 0.07)
                : const Color(0xFFDDE3F0),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: c,
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      course['course_code'] ?? '',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _showCourseOptions(course),
                    child: const Icon(
                      Icons.more_vert,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course['title'] ?? '',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${course['enrolled_count'] ?? 0} students',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: textColor.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: textColor.withValues(alpha: 0.4),
              letterSpacing: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCourseCard(Map<String, dynamic> course, int index) {
    final gradient = _cardGradients[index % _cardGradients.length];
    final isPublished = course['is_published'] == true;
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return PressableScale(
      onPressed: () => context.push(
        AppRoutes.courseDetail,
        extra: {'course': course, 'isInstructor': true},
      ),
      scaleFactor: 0.98,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: context.isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          children: [
            Hero(
              tag: 'course_header_${course['id']}',
              child: Container(
                height: 80,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            course['course_code'] ?? 'CODE',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isPublished ? 'PUBLISHED' : 'DRAFT',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: isPublished
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    PressableScale(
                      onPressed: () => _showCourseOptions(course),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: const Icon(
                          Icons.more_vert_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course['title'] ?? '',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${course['enrolled_count'] ?? 0} students enrolled',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: textColor.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      course['class_code'] ?? '---',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyClasses() {
    // Flexible color: Interstellar Blue in Light Mode, White in Dark Mode
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ─── Proper Icon instead of Emoji ───
            Icon(
              Icons.school_rounded,
              size: 80,
              color: textColor.withValues(
                alpha: 0.15,
              ), // Subtle tint for a modern feel
            ),
            const SizedBox(height: 20),
            Text(
              'No classes yet',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to create your first class!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: textColor.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Reports Page ────────────────────────────────────────
  Widget _buildReportsPage() {
    if (_selectedPost != null) return _buildLevel3();
    if (_selectedCourse != null) return _buildLevel2();
    return _buildLevel1();
  }

  // ── LEVEL 1: All classes overview ─────────────────────────────
  Widget _buildLevel1() {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, isDesktop ? 32 : 16, 16, 8),
          child: Text(
            'Reports',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: context.isDark ? Colors.white : const Color(0xFF0D1B4B),
            ),
          ),
        ),
        // Stat cards
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.8,
            children: [
              _reportStatCard('Total', _reportTotalSubmissions, AppColors.primary),
              _reportStatCard('Graded', _reportGraded, AppColors.success),
              _reportStatCard('Ungraded', _reportUngraded, const Color(0xFFF97316)),
              _reportStatCard('No submission', _reportNotSubmitted, AppColors.error),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'TAP A CLASS TO VIEW',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _isLoadingReport
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _reportCourses.isEmpty
                  ? Center(
                      child: Text(
                        'No classes yet',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: context.textHint,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: _reportCourses.length,
                      itemBuilder: (_, i) =>
                          _buildCourseReportCard(_reportCourses[i]),
                    ),
        ),
      ],
    );
  }

  Widget _reportStatCard(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF111E3D) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.isDark
              ? AppColors.darkBorder
              : const Color(0xFFDDE3F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value.toString(),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseReportCard(Map<String, dynamic> course) {
    final passRate = (course['pass_rate'] as num?)?.toInt() ?? 0;
    final studentCount = (course['student_count'] as int?) ?? 0;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedCourse = course);
        _loadLevel2(course['id']);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.isDark ? const Color(0xFF111E3D) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: context.isDark
                ? AppColors.darkBorder
                : const Color(0xFFDDE3F0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    course['title'] ?? '',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.isDark
                          ? Colors.white
                          : const Color(0xFF0D1B4B),
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$passRate% pass',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: passRate / 100,
                backgroundColor: context.isDark
                    ? const Color(0xFF1E2D5A)
                    : const Color(0xFFEEF2FF),
                valueColor: const AlwaysStoppedAnimation(AppColors.success),
                minHeight: 5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$studentCount students',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── LEVEL 2: Assignments of selected class ─────────────────────
  Widget _buildLevel2() {
    final course = _selectedCourse!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back header
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _selectedCourse = null),
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 18, color: AppColors.primary),
              ),
              Expanded(
                child: Text(
                  course['title'] ?? '',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.isDark
                        ? Colors.white
                        : const Color(0xFF0D1B4B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        // Breadcrumb
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: const Border(
                left: BorderSide(color: AppColors.primary, width: 3),
              ),
            ),
            child: Text(
              '${course['course_code'] ?? ''} · ${course['section'] ?? ''}',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: context.textSecondary,
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'TAP AN ASSIGNMENT',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: AppColors.primary,
            ),
          ),
        ),
        Expanded(
          child: _isLoadingReport
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _reportPosts.isEmpty
                  ? Center(
                      child: Text(
                        'No assignments yet',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: context.textHint,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: _reportPosts.length,
                      itemBuilder: (_, i) =>
                          _buildPostReportCard(_reportPosts[i]),
                    ),
        ),
      ],
    );
  }

  Widget _buildPostReportCard(Map<String, dynamic> post) {
    final graded = (post['graded_count'] as int?) ?? 0;
    final ungraded = (post['ungraded_count'] as int?) ?? 0;
    final noSub = (post['no_sub_count'] as int?) ?? 0;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedPost = post);
        _loadLevel3(post['id']);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.isDark ? const Color(0xFF111E3D) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: context.isDark
                ? AppColors.darkBorder
                : const Color(0xFFDDE3F0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    post['title'] ?? '',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.isDark
                          ? Colors.white
                          : const Color(0xFF0D1B4B),
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.primary, size: 20),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${post['type'] ?? 'assignment'} · ${_formatPostDate(post['created_at'])}',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                _miniChip('$graded graded', AppColors.success),
                _miniChip('$ungraded ungraded', const Color(0xFFF97316)),
                _miniChip('$noSub no sub', context.textHint),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ── LEVEL 3: Students for selected assignment ──────────────────
  Widget _buildLevel3() {
    final post = _selectedPost!;
    final filtered = _reportStudents.where((s) {
      if (_studentFilter == 'all') return true;
      if (_studentFilter == 'graded') return s['status'] == 'graded';
      if (_studentFilter == 'ungraded') return s['status'] == 'turned_in';
      if (_studentFilter == 'no_sub') {
        return s['status'] == 'assigned' || s['status'] == null;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _selectedPost = null),
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 18, color: AppColors.primary),
              ),
              Expanded(
                child: Text(
                  post['title'] ?? '',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.isDark
                        ? Colors.white
                        : const Color(0xFF0D1B4B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        // Assignment breadcrumb
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF97316).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: const Border(
                left: BorderSide(color: Color(0xFFF97316), width: 3),
              ),
            ),
            child: Text(
              '${_selectedCourse?['title'] ?? ''} · ${post['type'] ?? 'assignment'}',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: context.textSecondary,
              ),
            ),
          ),
        ),
        // Mini stat row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: _reportStatCard(
                    'Graded', _reportGraded, AppColors.success),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _reportStatCard(
                    'Ungraded', _reportUngraded, const Color(0xFFF97316)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _reportStatCard(
                    'No sub', _reportNotSubmitted, AppColors.error),
              ),
            ],
          ),
        ),
        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              _filterChip('All', 'all'),
              const SizedBox(width: 8),
              _filterChip('Graded', 'graded'),
              const SizedBox(width: 8),
              _filterChip('Ungraded', 'ungraded'),
              const SizedBox(width: 8),
              _filterChip('No submission', 'no_sub'),
            ],
          ),
        ),
        // Student list
        Expanded(
          child: _isLoadingReport
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No students found',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: context.textHint,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) =>
                          _buildStudentReportRow(filtered[i]),
                    ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    final isActive = _studentFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _studentFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary
              : context.isDark
                  ? const Color(0xFF111E3D)
                  : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? AppColors.primary
                : context.isDark
                    ? AppColors.darkBorder
                    : const Color(0xFFDDE3F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            color: isActive ? Colors.white : context.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildStudentReportRow(Map<String, dynamic> student) {
    final status = student['status'] as String? ?? 'assigned';
    final isGraded = status == 'graded';
    final isTurnedIn = status == 'turned_in';

    Color statusColor;
    String statusLabel;
    if (isGraded) {
      statusColor = AppColors.success;
      statusLabel = 'Graded';
    } else if (isTurnedIn) {
      statusColor = const Color(0xFFF97316);
      statusLabel = 'Ungraded';
    } else {
      statusColor = context.textHint;
      statusLabel = 'No submission';
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AssignmentDetailScreen(
              post: _selectedPost!,
              course: _selectedCourse!,
              isInstructor: true,
              targetStudentId: student['id'],
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.isDark ? const Color(0xFF111E3D) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: context.isDark
                ? AppColors.darkBorder
                : const Color(0xFFDDE3F0),
          ),
        ),
        child: Row(
          children: [
            Builder(builder: (_) {
              final url = student['avatar_url'] as String?;
              final name = student['name'] ?? 'S';
              if (url != null && url.isNotEmpty) {
                return CircleAvatar(
                  radius: 18,
                  backgroundImage: NetworkImage(url),
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  onBackgroundImageError: (_, __) {},
                );
              }
              return CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Text(
                  name[0].toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              );
            }),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                student['name'] ?? '',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.isDark
                      ? Colors.white
                      : const Color(0xFF0D1B4B),
                ),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPostDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}';
    } catch (_) {
      return '';
    }
  }

  // ─── Instructor Leaderboard ────────────────────────────────
  Future<void> _loadInstructorCourses() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _supabase
          .from('courses')
          .select('id, title')
          .eq('instructor_id', userId)
          .eq('is_archived', false)
          .order('title');
      if (mounted) {
        setState(
          () => _instructorCourses = List<Map<String, dynamic>>.from(data),
        );
        // Auto-select the first class so the ranking page loads
        // immediately without requiring a manual pick.
        if (_lbSelectedCourseId == null && _instructorCourses.isNotEmpty) {
          final firstCourseId = _instructorCourses.first['id'] as String;
          setState(() => _lbSelectedCourseId = firstCourseId);
          _loadInstructorLeaderboard(firstCourseId);
          _subscribeToRankingInstructor(firstCourseId);
        }
      }
    } catch (e) {
      debugPrint('Load instructor courses: $e');
    }
  }

  void _subscribeToRankingInstructor(String courseId) {
    _rankingChannel?.unsubscribe();
    _rankingChannel = _supabase
        .channel('instructor-ranking-${courseId}_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'enrollments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'course_id',
            value: courseId,
          ),
          callback: (_) {
            if (mounted) _loadInstructorLeaderboard(courseId);
          },
        )
        .subscribe();
  }

  Future<void> _loadInstructorLeaderboard(String courseId) async {
    setState(() => _lbIsLoading = true);
    try {
      // Per-class XP/streak, not the student's global users.xp — this
      // leaderboard is scoped to one class, matching what students see
      // on their own per-class ranking view.
      final enrollmentsData = await _supabase
          .from('enrollments')
          .select('student_id, class_xp, class_streak, users(id, name, avatar_url)')
          .eq('course_id', courseId);

      List<Map<String, dynamic>> students;

      students = enrollmentsData
          .map((e) {
            final u = e['users'] as Map<String, dynamic>?;
            return {
              'id': u?['id'] ?? e['student_id'],
              'name': u?['name'] ?? 'Student',
              'avatar_url': u?['avatar_url'],
              'xp': (e['class_xp'] as int?) ?? 0,
              'class_streak': (e['class_streak'] as int?) ?? 0,
            };
          })
          .toList();

      students.sort((a, b) => (b['xp'] as int).compareTo(a['xp'] as int));

      if (mounted) {
        setState(() => _lbData = students);
      }
    } catch (e) {
      debugPrint('Load instructor leaderboard: $e');
    } finally {
      if (mounted) setState(() => _lbIsLoading = false);
    }
  }

  Widget _buildInstructorLeaderboardPage() {
    final currentUserId = _supabase.auth.currentUser?.id;
    final themeColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, isDesktop ? 32 : 8, 20, 16),
          child: Column(
            children: [
              // ─── Header with Proper Icon ───
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.emoji_events_rounded, // Proper Trophy Icon
                    color: AppColors.gold,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Ranking',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: themeColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ─── Class Selector Dropdown ────────────────
              if (_instructorCourses.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: context.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _lbSelectedCourseId != null
                          ? AppColors.primary
                          : context.borderColor,
                      width: _lbSelectedCourseId != null ? 1.5 : 1,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _lbSelectedCourseId,
                      isExpanded: true,
                      dropdownColor: context.surfaceColor,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: themeColor,
                      ),
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: _lbSelectedCourseId != null
                            ? AppColors.primary
                            : themeColor.withValues(alpha: 0.5),
                      ),
                      hint: Row(
                        children: [
                          const Icon(
                            Icons.class_rounded,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Select a class',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              color: themeColor.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                      items: _instructorCourses.map((course) {
                        return DropdownMenuItem<String?>(
                          value: course['id'] as String,
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  course['title'] ?? 'Untitled',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    color: themeColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _lbSelectedCourseId = val;
                        });
                        if (val != null) {
                          _loadInstructorLeaderboard(val);
                          _subscribeToRankingInstructor(val);
                        }
                      },
                    ),
                  ),
                ),

            ],
          ),
        ),

        if (_lbSelectedCourseId == null)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.emoji_events_outlined,
                    size: 72,
                    color: context.isDark ? Colors.white12 : Colors.black12,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select a class to view rankings',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the dropdown above to choose a class.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: context.isDark ? Colors.white24 : Colors.black26,
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (_lbIsLoading)
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )
        else ...[
          // Top 3 podium
          if (_lbData.length >= 3) _buildPodium(_lbData.take(3).toList()),

          const SizedBox(height: 16),

          // ─── Ranking List ───
          Expanded(
            child: _lbData.isEmpty
                ? _buildEmptyLeaderboard(themeColor)
                : ListView.builder(
                    // 100 padding at bottom ensures the list isn't hidden by the bottom nav
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    physics: const BouncingScrollPhysics(),
                    // We subtract 3 because the top 3 are already in the Podium
                    itemCount: _lbData.length > 3 ? _lbData.length - 3 : 0,
                    itemBuilder: (context, index) {
                      // index + 3 gets the students starting from Rank #4
                      final user = _lbData[index + 3];
                      return _buildRankRow(
                        user,
                        index + 4,
                        currentUserId,
                        themeColor,
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }

  // Helper for empty state
  Widget _buildEmptyLeaderboard(Color themeColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.military_tech_outlined,
            size: 64,
            color: themeColor.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No rankings yet',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: themeColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Students will appear here once they earn XP.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPodium(List<Map<String, dynamic>> top3) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 2nd Place
          if (top3.length > 1)
            Expanded(child: _buildPodiumItem(top3[1], 2, 120)),
          const SizedBox(width: 12),
          // 1st Place
          if (top3.isNotEmpty)
            Expanded(child: _buildPodiumItem(top3[0], 1, 160)),
          const SizedBox(width: 12),
          // 3rd Place
          if (top3.length > 2)
            Expanded(child: _buildPodiumItem(top3[2], 3, 100)),
        ],
      ),
    );
  }

  Widget _buildPodiumItem(Map<String, dynamic> user, int rank, double height) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    final medalColors = {
      1: const Color(0xFFFFD700), // Gold
      2: const Color(0xFFC0C0C0), // Silver
      3: const Color(0xFFCD7F32), // Bronze
    };

    return PressableScale(
      onPressed: () {},
      child: Container(
        constraints: BoxConstraints(minHeight: height),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: medalColors[rank]!.withValues(alpha: 0.2),
            width: 2,
          ),
          boxShadow: [
            // Only 1st Place gets the "Aura" glow
            if (rank == 1)
              BoxShadow(
                color: medalColors[rank]!.withValues(alpha: 0.2),
                blurRadius: 25,
                spreadRadius: 2,
                offset: const Offset(0, -5),
              ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Profile picture with rank badge (replaces medal icon)
            Stack(
              clipBehavior: Clip.none,
              children: [
                Builder(
                  builder: (_) {
                    final url = user['avatar_url'] as String?;
                    final name = user['name'] as String? ?? 'S';
                    final double radius = rank == 1 ? 32 : 26;
                    final Color ringColor = medalColors[rank]!;
                    if (url != null && url.isNotEmpty) {
                      return CircleAvatar(
                        radius: radius,
                        backgroundImage: NetworkImage(url),
                        backgroundColor: ringColor.withValues(alpha: 0.15),
                        onBackgroundImageError: (_, __) {},
                      );
                    }
                    return CircleAvatar(
                      radius: radius,
                      backgroundColor: ringColor.withValues(alpha: 0.15),
                      child: Text(
                        name[0].toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: rank == 1 ? 22 : 18,
                          fontWeight: FontWeight.w700,
                          color: ringColor,
                        ),
                      ),
                    );
                  },
                ),
                Positioned(
                  bottom: -2,
                  right: -4,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: medalColors[rank],
                      shape: BoxShape.circle,
                      border: Border.all(color: context.cardColor, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        '$rank',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ─── SPECIAL NAME EFFECTS ───
            Text(
              (user['name'] as String? ?? 'User').split(' ').first,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w900, // Extra Bold
                fontSize: rank == 1 ? 14 : 12,
                color: textColor,
                // Text Glow Effect
                shadows: [
                  Shadow(
                    color: medalColors[rank]!.withValues(alpha: 0.5),
                    blurRadius: 8.0,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            Builder(
              builder: (context) {
                final xp = (user['xp'] as int?) ?? 0;
                final rankInfo = _getRank(xp);
                final rankColor = rankInfo['color'] as Color;
                final badgeAsset = _getBadgeAsset(
                  rankInfo['name'] as String,
                );
                final isFirst = rank == 1;
                final imageSize = isFirst ? 72.0 : 64.0;
                final glowSize = isFirst ? 60.0 : 52.0;

                return Column(
                  children: [
                    SizedBox(
                      width: imageSize,
                      height: imageSize,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: glowSize,
                            height: glowSize,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                isFirst ? 14 : 12,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: rankColor.withValues(alpha: 0.35),
                                  blurRadius: 18,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                          ),
                          Image.asset(
                            badgeAsset,
                            width: imageSize,
                            height: imageSize,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rankInfo['name'] as String,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: rankColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 4),

            Text(
              '${user['xp'] ?? 0} XP',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                color: medalColors[rank],
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0, // Wider for premium feel
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankRow(
    Map<String, dynamic> user,
    int rank,
    String? currentUserId,
    Color themeColor,
  ) {
    final isMe = user['id'] == currentUserId;
    final rowColor = isMe ? AppColors.primary : themeColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressableScale(
        onPressed: () {},
        scaleFactor: 0.98,
        opacityFactor: 0.8,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isMe
                ? AppColors.primary.withValues(alpha: 0.08)
                : context.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isMe
                  ? AppColors.primary.withValues(alpha: 0.2)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  '#$rank',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w800,
                    color: rowColor.withValues(alpha: 0.4),
                    fontSize: 13,
                  ),
                ),
              ),
              Builder(
                builder: (_) {
                  final url = user['avatar_url'] as String?;
                  final name = (user['name'] as String?) ?? 'S';
                  if (url != null && url.trim().isNotEmpty) {
                    return CircleAvatar(
                      radius: 18,
                      backgroundImage: NetworkImage(url),
                      backgroundColor: rowColor.withValues(alpha: 0.1),
                      onBackgroundImageError: (_, __) {},
                    );
                  }
                  return CircleAvatar(
                    radius: 18,
                    backgroundColor: rowColor.withValues(alpha: 0.1),
                    child: Text(
                      name[0].toUpperCase(),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: rowColor,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user['name'] ?? '',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        color: themeColor,
                        fontSize: 14,
                      ),
                    ),
                    Builder(
                      builder: (_) {
                        final xp = (user['xp'] as int?) ?? 0;
                        final rankInfo = _getRank(xp);
                        return Text(
                          rankInfo['name'] as String,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            color: rankInfo['color'] as Color,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${user['xp']} XP',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w900,
                      color: AppColors.gold,
                      fontSize: 14,
                    ),
                  ),
                  if (user['class_streak'] != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Builder(
                          builder: (_) {
                            final s = (user['class_streak'] as int?) ?? 0;
                            return Icon(
                              Icons.local_fire_department_rounded,
                              color: s > 0
                                  ? const Color(0xFFFF9800)
                                  : Colors.grey,
                              size: 12,
                              shadows: s > 0
                                  ? [
                                      Shadow(
                                        color: const Color(
                                          0xFFFF9800,
                                        ).withValues(alpha: 0.5),
                                        blurRadius: 6,
                                      ),
                                    ]
                                  : null,
                            );
                          },
                        ),
                        Builder(
                          builder: (_) {
                            final s = (user['class_streak'] as int?) ?? 0;
                            return Text(
                              '$s',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: s > 0
                                    ? const Color(0xFFFF9800)
                                    : Colors.grey.withValues(alpha: 0.4),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _getRank(int xp) {
    if (xp >= 18000) {
      return {
        'name': 'Compiler Whisperer',
        'icon': Icons.auto_awesome_rounded,
        'color': const Color(0xFFFFD700),
        'nextXp': null,
      };
    } else if (xp >= 12000) {
      return {
        'name': '10x Developer',
        'icon': Icons.bolt_rounded,
        'color': const Color(0xFFE040FB),
        'nextXp': 18000,
      };
    } else if (xp >= 8000) {
      return {
        'name': 'Tech Lead',
        'icon': Icons.account_tree_rounded,
        'color': const Color(0xFF2196F3),
        'nextXp': 12000,
      };
    } else if (xp >= 5000) {
      return {
        'name': 'Stack Overflow Guru',
        'icon': Icons.search_rounded,
        'color': const Color(0xFFFF9800),
        'nextXp': 8000,
      };
    } else if (xp >= 2500) {
      return {
        'name': 'Refactorer',
        'icon': Icons.refresh_rounded,
        'color': const Color(0xFF00BCD4),
        'nextXp': 5000,
      };
    } else if (xp >= 1000) {
      return {
        'name': 'Junior Dev',
        'icon': Icons.laptop_rounded,
        'color': const Color(0xFF4CAF50),
        'nextXp': 2500,
      };
    } else if (xp >= 300) {
      return {
        'name': 'Code Newbie',
        'icon': Icons.eco_rounded,
        'color': const Color(0xFF9E9E9E),
        'nextXp': 1000,
      };
    } else {
      return {
        'name': 'Script Kiddie',
        'icon': Icons.content_copy_rounded,
        'color': const Color(0xFFFF5252),
        'nextXp': 300,
      };
    }
  }

  String _getBadgeAsset(String rankName) {
    switch (rankName) {
      case 'Script Kiddie':
        return 'assets/images/ranks/badge_01_script_kiddie.png';
      case 'Code Newbie':
        return 'assets/images/ranks/badge_02_code_newbie.png';
      case 'Junior Dev':
        return 'assets/images/ranks/badge_03_junior_dev.png';
      case 'Refactorer':
        return 'assets/images/ranks/badge_04_refactorer.png';
      case 'Stack Overflow Guru':
        return 'assets/images/ranks/badge_05_stackoverflow_guru.png';
      case 'Tech Lead':
        return 'assets/images/ranks/badge_06_tech_lead.png';
      case '10x Developer':
        return 'assets/images/ranks/badge_07_10x_developer.png';
      case 'Compiler Whisperer':
        return 'assets/images/ranks/badge_08_compiler_whisperer.png';
      default:
        return 'assets/images/ranks/badge_01_script_kiddie.png';
    }
  }

  Widget _buildProfilePage() {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    final isDesktop = MediaQuery.of(context).size.width > 900;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, isDesktop ? 32 : 20, 20, 20),
      child: Column(
        children: [
          // Instructor Identity Card
          Container(
            padding: const EdgeInsets.all(24),
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                PressableScale(
                  onPressed: _currentUser == null
                      ? null
                      : () async {
                    final updated = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditProfileScreen(user: _currentUser!),
                      ),
                    );
                    if (updated == true) _loadUser();
                  },
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        backgroundImage: _currentUser?.avatarUrl != null
                            ? NetworkImage(_currentUser!.avatarUrl!)
                            : null,
                        onBackgroundImageError: _currentUser?.avatarUrl != null
                            ? (_, __) {}
                            : null,
                        child: _currentUser?.avatarUrl == null
                            ? Text(
                                (_currentUser?.name ?? 'I')[0].toUpperCase(),
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              )
                            : null,
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _currentUser?.name ?? 'Instructor',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _currentUser?.email ?? '',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'FACULTY INSTRUCTOR',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Section header
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Row(
              children: [
                Icon(
                  Icons.security_rounded,
                  size: 16,
                  color: textColor.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 8),
                Text(
                  'ACCOUNT SECURITY & PREFERENCES',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: textColor.withValues(alpha: 0.4),
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          // Unified Settings Area
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                if (!kIsWeb) ...[
                  _buildPremiumSettingsItem(
                    Icons.fingerprint,
                    'Biometric Login',
                    trailing: _buildAnimatedToggle(
                      value: _biometricsEnabled,
                      onTap: () => _toggleBiometrics(!_biometricsEnabled),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: context.borderColor.withValues(alpha: 0.5),
                    ),
                  ),
                ],
                _buildPremiumSettingsItem(
                  Icons.dark_mode_outlined,
                  'Dark Mode',
                  trailing: _buildAnimatedToggle(
                    value: ref.watch(themeProvider) == ThemeMode.dark,
                    onTap: () => ref.read(themeProvider.notifier).toggleTheme(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(
                    height: 1,
                    thickness: 0.5,
                    color: context.borderColor.withValues(alpha: 0.5),
                  ),
                ),
                _buildPremiumSettingsItem(
                  Icons.archive_rounded,
                  'Archived Classes',
                  onTap: () async {
                    final didRestore = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ArchivedClassesScreen(
                          isInstructor: true,
                        ),
                      ),
                    );
                    if (didRestore == true) {
                      _loadCourses();
                    }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(
                    height: 1,
                    thickness: 0.5,
                    color: context.borderColor.withValues(alpha: 0.5),
                  ),
                ),
                _buildPremiumSettingsItem(
                  Icons.logout_rounded,
                  'Logout',
                  color: Colors.redAccent,
                  onTap: _logout,
                  showChevron: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumSettingsItem(
    IconData icon,
    String label, {
    Color? color,
    Widget? trailing,
    VoidCallback? onTap,
    bool showChevron = true,
  }) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    return PressableScale(
      onPressed: onTap,
      scaleFactor: 0.98,
      opacityFactor: 0.6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        color: Colors.transparent,
        child: Row(
          children: [
            Icon(
              icon,
              color: color ?? textColor.withValues(alpha: 0.8),
              size: 22,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color ?? textColor,
                ),
              ),
            ),
            if (trailing != null) trailing,
            if (trailing == null && showChevron)
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: textColor.withValues(alpha: 0.2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlowEffect(Size size) {
    return Positioned(
      top: -60,
      left: size.width * 0.5 - 120,
      child: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) => Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(
                  alpha: _glowAnimation.value * 0.5,
                ),
                blurRadius: 100,
                spreadRadius: 30,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSheetField(
    String label,
    String hint,
    TextEditingController controller,
    IconData icon, {
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: TextStyle(fontFamily: 'Poppins', color: textColor, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: context.cardColor,
        prefixIcon: Icon(
          icon,
          color: textColor.withValues(alpha: 0.3),
          size: 20,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.borderColor),
        ),
      ),
    );
  }

  int get _totalStudents => _courses.fold(
    0,
    (sum, item) => sum + (item['enrolled_count'] as int? ?? 0),
  );

  Widget _buildAnimatedToggle({
    required bool value,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onPressed: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 48,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: value ? AppColors.primary : Colors.black12,
          boxShadow: value
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha:0.4),
                    blurRadius: 10,
                  ),
                ]
              : [],
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 250),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
