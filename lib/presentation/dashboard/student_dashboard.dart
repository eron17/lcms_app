// lib/presentation/dashboard/student_dashboard.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/router/app_router.dart';
import '../../data/models/user_model.dart';
import '../../providers/theme_provider.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/constants/app_colors.dart';
import '../courses/offline_files_screen.dart';
import '../courses/archived_classes_screen.dart';
import '../profile/edit_profile_screen.dart';
import '../notifications/notifications_screen.dart';
import '../../shared/widgets/pressable_scale.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class StudentDashboard extends ConsumerStatefulWidget {
  const StudentDashboard({super.key});

  @override
  ConsumerState<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends ConsumerState<StudentDashboard>
    with TickerProviderStateMixin {
  // ─── State ───────────────────────────────────────────────
  int _currentIndex = 0;
  final _supabase = Supabase.instance.client;
  UserModel? _currentUser;
  List<Map<String, dynamic>> _enrolledCourses = [];
  List<Map<String, dynamic>> _allCourses = [];
  List<Map<String, dynamic>> _leaderboard = [];
  bool _isLoadingCourses = true;
  String? _selectedLeaderboardCourseId; // null = All Classes
  RealtimeChannel? _xpChannel;
  RealtimeChannel? _enrollmentChannel;
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final _localAuth = LocalAuthentication();
  bool _biometricsEnabled = false;
  bool _hasUnreadNotifications = false;

  // ─── Animation ───────────────────────────────────────────
  late AnimationController _fabController;
  late Animation<double> _fabAnimation;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

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
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fabAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fabController, curve: Curves.easeOut));
    _fabController.forward();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _loadData();
    _subscribeToXpChanges();
    _subscribeToEnrollmentChanges();
    _checkBiometricStatus();
  }

  void _subscribeToEnrollmentChanges() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    _enrollmentChannel?.unsubscribe();

    _enrollmentChannel = _supabase
        .channel(
          'enrollments_${userId}_${DateTime.now().millisecondsSinceEpoch}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'enrollments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'student_id',
            value: userId,
          ),
          callback: (payload) {
            // Re-fetch rather than hand-patch _enrolledCourses, same
            // reasoning as _subscribeToXpChanges: keeps every merged
            // field (class_xp, class_streak, course data) in sync
            // through the one already-working load path.
            if (mounted) _loadEnrolledCourses();
          },
        )
        .subscribe();
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
      setState(() => _biometricsEnabled = false);
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

  void _subscribeToXpChanges() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Unsubscribe existing channel first so a re-subscribe (e.g. after
    // resume) doesn't collide with a still-open channel of the same name
    _xpChannel?.unsubscribe();

    _xpChannel = _supabase
        .channel('user_xp_${userId}_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (payload) {
            // Re-fetch rather than hand-patch _currentUser (a UserModel,
            // not a raw map) — keeps every field in sync, not just
            // xp/streak, with one already-working code path.
            if (mounted) _loadUser();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _xpChannel?.unsubscribe();
    _enrollmentChannel?.unsubscribe();
    _fabController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadUser(),
      _loadEnrolledCourses(),
      _loadLeaderboard(),
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

  Future<void> _loadEnrolledCourses() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _supabase
          .from('enrollments')
          .select('course_id, class_xp, class_streak, courses(*)')
          .eq('student_id', userId);
      if (mounted) {
        setState(() {
          _allCourses = List<Map<String, dynamic>>.from(
            data.map((e) => {
              ...e['courses'] as Map<String, dynamic>,
              'class_xp': e['class_xp'],
              'class_streak': e['class_streak'],
            }),
          );
          // My Classes / leaderboard filter should not surface archived
          // classes; the Active/Archived toggle in _buildCoursesPage still
          // reads the unfiltered _allCourses list.
          _enrolledCourses = _allCourses
              .where((c) => c['is_archived'] != true)
              .toList();
          _isLoadingCourses = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingCourses = false);
    }
  }

  Future<void> _loadLeaderboard({String? courseId}) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      if (courseId != null) {
        // ─── Specific class: per-class XP/streak from enrollments ───
        final data = await _supabase
            .from('enrollments')
            .select('class_xp, class_streak, users(id, name, avatar_url)')
            .eq('course_id', courseId)
            .order('class_xp', ascending: false)
            .limit(20);
        if (mounted) {
          setState(() {
            _leaderboard = List<Map<String, dynamic>>.from(data).map((e) {
              final u = e['users'] as Map<String, dynamic>? ?? {};
              return {
                'id': u['id'],
                'name': u['name'],
                'avatar_url': u['avatar_url'],
                'xp': e['class_xp'],
                'class_streak': e['class_streak'],
              };
            }).toList();
          });
        }
        return;
      }

      List<String> courseIds;

      {
        // ─── All Classes: get all enrolled course IDs ───
        final enrollments = await _supabase
            .from('enrollments')
            .select('course_id')
            .eq('student_id', userId);

        if ((enrollments as List).isEmpty) {
          final selfData = await _supabase
              .from('users')
              .select('id, name, xp, level, avatar_url')
              .eq('id', userId)
              .single();
          if (mounted) {
            setState(
              () => _leaderboard = [Map<String, dynamic>.from(selfData)],
            );
          }
          return;
        }

        courseIds = enrollments.map((e) => e['course_id'] as String).toList();
      }

      // Get all student IDs enrolled in those courses
      final classmateEnrollments = await _supabase
          .from('enrollments')
          .select('student_id')
          .inFilter('course_id', courseIds);

      final classmates = (classmateEnrollments as List)
          .map((e) => e['student_id'] as String)
          .toSet()
          .toList();

      List<Map<String, dynamic>> sortedData;

      final data = await _supabase
          .from('users')
          .select('id, name, xp, level, avatar_url')
          .inFilter('id', classmates)
          .eq('role', 'student')
          .order('xp', ascending: false)
          .limit(20);

      sortedData = List<Map<String, dynamic>>.from(data);

      if (mounted) {
        // Apply the exact same sorting logic here
        sortedData.sort((a, b) {
          int xpCompare = (b['xp'] as int? ?? 0).compareTo(
            a['xp'] as int? ?? 0,
          );
          if (xpCompare != 0) return xpCompare;
          return (a['name'] as String? ?? '').toLowerCase().compareTo(
            (b['name'] as String? ?? '').toLowerCase(),
          );
        });

        setState(() => _leaderboard = sortedData);
      }
    } catch (e) {
      debugPrint('Leaderboard error: $e');
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

  void _showJoinClassDialog() {
    final codeController = TextEditingController();
    bool isJoining = false;
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    showDialog(
      context: context,
      barrierColor: context.isDark
          ? Colors.black.withValues(alpha: 0.8)
          : Colors.black.withValues(alpha: 0.4),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: context.surfaceColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: context.borderColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Header ---
                  Row(
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
                          Icons.add_circle_outline,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Join a Class',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ask your instructor for the class code then enter it here.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: textColor.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- Input Field ---
                  TextField(
                    controller: codeController,
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                    ),
                    decoration: InputDecoration(
                      hintText: 'e.g. kfs1fy',
                      hintStyle: TextStyle(
                        color: context.textHint,
                        letterSpacing: 1,
                      ),
                      filled: true,
                      fillColor: context.cardColor,
                      contentPadding: const EdgeInsets.all(16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.borderColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // --- Buttons ---
                  Row(
                    children: [
                      Expanded(
                        child: PressableScale(
                          onPressed: () => Navigator.pop(context),
                          scaleFactor: 0.98,
                          opacityFactor: 0.6,
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: context.cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: context.borderColor),
                            ),
                            child: Center(
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: textColor.withValues(alpha: 0.7),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PressableScale(
                          onPressed: isJoining
                              ? null
                              : () async {
                                  final code = codeController.text
                                      .trim()
                                      .toLowerCase();
                                  if (code.isEmpty) return;
                                  setDialogState(() => isJoining = true);
                                  await _joinClass(code);
                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                },
                          scaleFactor: 0.96,
                          opacityFactor: 0.7,
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.primaryDark,
                                  AppColors.primary,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
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
                              child: isJoining
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Join',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _joinClass(String courseCode) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Find course by code (case insensitive)
      final courseData = await _supabase
          .from('courses')
          .select()
          .ilike('class_code', courseCode)
          .eq('is_published', true)
          .single();

      // Check if already enrolled
      final existing = await _supabase
          .from('enrollments')
          .select()
          .eq('student_id', userId)
          .eq('course_id', courseData['id'])
          .maybeSingle();

      if (existing != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You are already enrolled in this class!'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Enroll student
      await _supabase.from('enrollments').insert({
        'student_id': userId,
        'course_id': courseData['id'],
        'enrolled_at': DateTime.now().toIso8601String(),
      });

      // Refresh data
      await _loadEnrolledCourses();

      try {
        await _supabase.from('notifications').insert({
          'user_id': courseData['instructor_id'], // Teacher receives this
          'course_id': courseData['id'],
          'type': 'student_joined',
          'title': 'Class Enrollment',
          'body':
              '${_currentUser?.name ?? 'A student'} has joined ${courseData['title']}',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (notifErr) {
        // Log error but don't stop the student from seeing success
        debugPrint('Instructor Notification Error: $notifErr');
      }
      // ──────────────────────────────────────────

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully joined ${courseData['title']}!'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('JOIN ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Class not found. Check the code and try again.',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  // ─── Leave Class Dialog ─────────────────────────────────
  void _showLeaveClassDialog(Map<String, dynamic> course) {
    showDialog(
      context: context,
      barrierColor: context.isDark
          ? Colors.black.withValues(alpha: 0.8)
          : Colors.black.withValues(alpha: 0.4),
      builder: (context) => Dialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: context.borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.logout, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                'Leave Class?',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.isDark
                      ? Colors.white
                      : const Color(0xFF0D1B4B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Are you sure you want to leave "${course['title']}"? Your progress will be lost.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color:
                      (context.isDark ? Colors.white : const Color(0xFF0D1B4B))
                          .withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: context.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: context.isDark
                                  ? Colors.white
                                  : const Color(0xFF0D1B4B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        await _leaveClass(course['id']);
                      },
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.red.shade800,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'Leave',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _leaveClass(String courseId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase
          .from('enrollments')
          .delete()
          .eq('student_id', userId)
          .eq('course_id', courseId);

      // Refresh UI
      setState(() {
        _enrolledCourses.removeWhere((course) => course['id'] == courseId);
      });
      await _loadEnrolledCourses();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Left class successfully')),
        );
      }
    } catch (e) {
      debugPrint('Leave class error: $e');
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
    await _supabase.auth.signOut();
    if (mounted) context.go(AppRoutes.opening);
  }

  // ─── UTILS ───────────────────────────────────────────────


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

  @override
  Widget build(BuildContext context) {
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
                      _buildLeaderboardPage(),
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

  Widget _buildBackground() => Container(decoration: context.scaffoldGradient);

  Widget _buildTopBar() {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Image.asset(
            'assets/images/app_name.png',
            height: 28,
            fit: BoxFit.contain,
          ),
          const Spacer(),

          // ─── CORRECTED PRESSABLE NOTIFICATION BUTTON ───
          PressableScale(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  // Pass 'true' directly since this is the Instructor Dashboard
                  builder: (_) =>
                      const NotificationsScreen(isInstructor: false),
                ),
              );
              // Clear badge when returning
              if (mounted) setState(() => _hasUnreadNotifications = false);
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
      onPressed: _showJoinClassDialog,
      scaleFactor: 0.94, // Slightly more "squish" for the FAB feels premium
      opacityFactor: 0.8, // Subtle dimming so the gradient remains vibrant
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
              // Safety net: refresh per-class XP/streak when Profile
              // tab opens, in case the realtime update was missed.
              if (index == 2) _loadEnrolledCourses();
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
                        : context.isDark
                        ? Colors.white70
                        : const Color(0xFF0D1B4B),
                    size: 22,
                  ),
                  Text(
                    items[index]['label'] as String,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      color: isActive
                          ? Colors.white
                          : context.isDark
                          ? Colors.white70
                          : const Color(0xFF0D1B4B),
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

  // ════════════════════════════════════════════════════════
  // HOME PAGE
  // ════════════════════════════════════════════════════════

  Widget _buildHomePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWelcomeBanner(),
          const SizedBox(height: 24),
          _buildSectionHeader(
            'My Classes',
            icon: Icons.auto_stories, // Added proper icon
            onSeeAll: null,
          ),
          const SizedBox(height: 14),
          if (_isLoadingCourses)
            const Center(child: CircularProgressIndicator())
          else if (_enrolledCourses.isEmpty)
            _buildEmptyClasses()
          else
            Column(
              children: _enrolledCourses
                  .take(3)
                  .map(
                    (e) => _buildCourseCard(
                      e,
                      _enrolledCourses.indexOf(e),
                      tagSuffix: '_home',
                    ),
                  ) // Add this
                  .toList(),
            ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildWelcomeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B2FBE), Color(0xFF1E90FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Welcome back,',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontFamily: 'Poppins',
            ),
          ),
          Text(
            _currentUser?.name.split(' ').first ?? 'Student',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    String title, {
    IconData? icon,
    VoidCallback? onSeeAll,
  }) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: AppColors.primary, size: 22), // Proper Icon
              const SizedBox(width: 10),
            ],
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ],
        ),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: const Text(
              'See all',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }


  Widget _buildCourseCard(
    Map<String, dynamic> course,
    int index, {
    String tagSuffix = '',
  }) {
    final gradient = _cardGradients[index % _cardGradients.length];
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return PressableScale(
      onPressed: () => context.push(
        AppRoutes.courseDetail,
        extra: {'course': course, 'isInstructor': false},
      ),
      scaleFactor: 0.98,
      opacityFactor: 0.9,
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
              tag: 'course_header_${course['id']}$tagSuffix',
              child: Container(
                height: 70,
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
                    // --- Course Code Badge ---
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        course['course_code'] ?? 'CODE',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const Spacer(),

                    GestureDetector(
                      onTap: () {
                        _showLeaveClassDialog(course);
                      },
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course['title'] ?? '',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: gradient[0].withValues(alpha: 0.1),
                        child: Icon(
                          Icons.person_outline_rounded,
                          size: 14,
                          color: gradient[0],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        course['instructor_name'] ?? 'Instructor',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.6),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.borderColor),
        boxShadow: context.isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Proper Library Icon instead of emoji
          Icon(
            Icons.library_books_rounded,
            size: 64,
            color: context.isDark
                ? Colors.white24
                : Colors.grey.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 20),
          Text(
            'No classes joined yet',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the + button below to enter your class code and get started!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: textColor.withValues(alpha: 0.6),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardPage() {
    final currentUserId = _supabase.auth.currentUser?.id;
    // Flexible color: Interstellar Blue in Light Mode, White in Dark Mode
    final themeColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
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
                      color: themeColor, // Flexible color
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ─── Class Filter Dropdown ────────────────
              if (_enrolledCourses.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: context.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedLeaderboardCourseId != null
                          ? AppColors.primary
                          : context.borderColor,
                      width: _selectedLeaderboardCourseId != null ? 1.5 : 1,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedLeaderboardCourseId,
                      isExpanded: true,
                      dropdownColor: context.surfaceColor,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: themeColor,
                      ),
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: _selectedLeaderboardCourseId != null
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
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Row(
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
                                  color: themeColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ..._enrolledCourses.map(
                          (course) => DropdownMenuItem<String?>(
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
                                    course['title'] ?? '',
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
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedLeaderboardCourseId = val);
                        _loadLeaderboard(courseId: val);
                      },
                    ),
                  ),
                ),

            ],
          ),
        ),

        if (_selectedLeaderboardCourseId == null)
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
        else ...[
          // Top 3 podium
          if (_leaderboard.length >= 3)
            _buildPodium(_leaderboard.take(3).toList()),

          const SizedBox(height: 16),

          // ─── Ranking List ───
          Expanded(
            child: _leaderboard.isEmpty
                ? _buildEmptyLeaderboard(themeColor)
                : ListView.builder(
                    // 100 padding at bottom ensures the list isn't hidden by the bottom nav
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    physics: const BouncingScrollPhysics(),
                    // We subtract 3 because the top 3 are already in the Podium
                    itemCount: _leaderboard.length > 3
                        ? _leaderboard.length - 3
                        : 0,
                    itemBuilder: (context, index) {
                      // index + 3 gets the students starting from Rank #4
                      final user = _leaderboard[index + 3];
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
            'No classmates yet',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: themeColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Join a class to compete with classmates!',
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

  // ─── PROFILE PAGE ─────────────────────────────────────────

  Widget _buildProfilePage() {
    final user = _currentUser;
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── 1. IDENTITY HERO CARD ───
          _buildIdentityCard(user),

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildProfileStat(
                  'Total XP',
                  '${user?.xp ?? 0}',
                  Icons.bolt_rounded,
                  const Color(0xFFFFD700),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildProfileStat(
                  'Classes',
                  '${_enrolledCourses.length}',
                  Icons.menu_book_rounded,
                  AppColors.primary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ─── 2. PREMIUM 3D AVATAR BUTTON ───
          _build3DAvatarButton(textColor),

          const SizedBox(height: 32),

          // ─── 3. RANKING PER CLASS ───
          _buildRankingPerClass(),

          const SizedBox(height: 32),

          // ─── 4. SETTINGS SECTION (Unified List) ───
          _buildPremiumSectionHeader(
            'ACCOUNT SECURITY & PREFERENCES',
            Icons.settings_suggest_rounded,
            textColor,
          ),
          const SizedBox(height: 8),
          _buildSettingsList(),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  // ─── COMPONENT BUILDERS ────────────────────────────────────────────────────

  Widget _buildIdentityCard(user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B2FBE), Color(0xFF1E90FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar with Scale Interaction
          PressableScale(
            onPressed: () async {
              final updated = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditProfileScreen(user: user!),
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
                  backgroundImage:
                      user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty
                      ? NetworkImage(user.avatarUrl!)
                      : null,
                  child: user?.avatarUrl == null || user!.avatarUrl!.isEmpty
                      ? Text(
                          (user?.name ?? 'S')[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 2,
                    ),
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
            user?.name ?? 'Student',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            user?.email ?? '',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileStat(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              color: context.textHint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankingPerClass() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Icon(Icons.shield_rounded, size: 14, color: context.textHint),
              const SizedBox(width: 6),
              Text(
                'RANKING PER CLASS',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.textHint,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            children: _enrolledCourses.asMap().entries.map((entry) {
              final course = entry.value;
              final xp = (course['class_xp'] as int?) ?? 0;
              final streak = (course['class_streak'] as int?) ?? 0;
              final rank = _getRank(xp);
              final rankColor = rank['color'] as Color;
              final courseTitle = course['title'] ?? '';
              final courseCode = course['course_code'] ?? '';
              final isLast = entry.key == _enrolledCourses.length - 1;
              final badgeAsset = _getBadgeAsset(rank['name'] as String);

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: rankColor.withValues(
                                        alpha: 0.35,
                                      ),
                                      blurRadius: 14,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                              Image.asset(
                                badgeAsset,
                                width: 56,
                                height: 56,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rank['name'] as String,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: rankColor,
                                ),
                              ),
                              Text(
                                '$courseCode – $courseTitle',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10,
                                  color: context.textHint,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: context.borderColor.withValues(
                                  alpha: 0.3,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '$xp XP',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10,
                                  color: context.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.local_fire_department_rounded,
                                  color: streak > 0
                                      ? const Color(0xFFFF9800)
                                      : Colors.grey,
                                  size: 12,
                                  shadows: streak > 0
                                      ? [
                                          Shadow(
                                            color: const Color(
                                              0xFFFF9800,
                                            ).withValues(alpha: 0.5),
                                            blurRadius: 6,
                                          ),
                                        ]
                                      : null,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '$streak',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    color: streak > 0
                                        ? const Color(0xFFFF9800)
                                        : Colors.grey.withValues(alpha: 0.4),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: context.borderColor,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
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

  Widget _build3DAvatarButton(Color textColor) {
    return PressableScale(
      onPressed: () {
        // Navigate to 3D Avatar Customization
      },
      scaleFactor: 0.96, // Physical movement for primary action
      opacityFactor: 0.7, // Active state dimming
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.isDark
              ? textColor.withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: textColor.withValues(alpha: 0.08)),
          boxShadow: context.isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.accessibility_new_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '3D Avatar',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  Text(
                    'Customize your 3D avatar',
                    style: TextStyle(
                      fontSize: 12,
                      color: textColor.withValues(alpha: 0.5),
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
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

  Widget _buildPremiumSectionHeader(
    String title,
    IconData icon,
    Color textColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: textColor.withValues(alpha: 0.4)),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: textColor.withValues(alpha: 0.4),
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsList() {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    return Container(
      clipBehavior:
          Clip.antiAlias, // Ensures the ripples/dimming don't leak past corners
      decoration: BoxDecoration(
        color: context.isDark
            ? textColor.withValues(alpha: 0.03)
            : Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          // Biometric Login
          _buildPremiumSettingsItem(
            Icons.fingerprint,
            'Biometric Login',
            trailing: _buildAnimatedToggle(
              value: _biometricsEnabled,
              onTap: () => _toggleBiometrics(!_biometricsEnabled),
            ),
            showChevron: false,
          ),
          _buildPremiumDivider(),
          // Dark Mode Toggle (Toggle itself handles its own animation)
          _buildPremiumSettingsItem(
            Icons.dark_mode_outlined,
            'Dark Mode',
            trailing: _buildAnimatedToggle(
              value: ref.watch(themeProvider) == ThemeMode.dark,
              onTap: () => ref.read(themeProvider.notifier).toggleTheme(),
            ),
            showChevron: false,
          ),
          _buildPremiumDivider(),
          // Archived Classes
          _buildPremiumSettingsItem(
            Icons.archive_rounded,
            'Archived Classes',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ArchivedClassesScreen(
                  isInstructor: false,
                ),
              ),
            ),
          ),
          _buildPremiumDivider(),
          // Offline Content (Now with Dimming)
          _buildPremiumSettingsItem(
            Icons.cloud_download_outlined,
            'Offline Content',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OfflineFilesScreen()),
            ),
          ),
          _buildPremiumDivider(),
          // Logout (Now with Dimming)
          _buildPremiumSettingsItem(
            Icons.logout_rounded,
            'Logout',
            color: Colors.redAccent,
            onTap: _logout,
            showChevron: false,
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
    final effectiveColor = color ?? textColor;

    return PressableScale(
      onPressed: onTap,
      scaleFactor: 0.98, // Subtle scale for list items
      opacityFactor: 0.6, // Noticeable dimming for row selection
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        color: Colors.transparent, // Ensures the entire row is tappable
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
                  color: effectiveColor,
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

  Widget _buildPremiumDivider() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Divider(
      height: 1,
      thickness: 0.5,
      color: context.borderColor.withValues(alpha: 0.5),
    ),
  );

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

  // Helper for when search has no results
  Widget _buildAnimatedToggle({
    required bool value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
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
