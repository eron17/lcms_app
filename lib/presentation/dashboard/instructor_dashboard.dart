// lib/presentation/dashboard/instructor_dashboard.dart
import 'package:flutter/material.dart';
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
import '../notifications/notifications_screen.dart';
import 'package:flutter/services.dart';

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
  final _searchController = TextEditingController();
  String _courseFilter = 'Active';

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
  }

  @override
  void dispose() {
    _glowController.dispose();
    _fabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ─── Data Loading ────────────────────────────────────────

  Future<void> _loadData() async {
    await Future.wait([_loadUser(), _loadCourses(), _loadPendingSubmissions()]);
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

  // ─── Actions ─────────────────────────────────────────────

  String _generateClassCode() => List.generate(
    6,
    (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[Random().nextInt(36)],
  ).join();

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
                            height: 54,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              onPressed: isCreating
                                  ? null
                                  : () async {
                                      if (!formKey.currentState!.validate()) {
                                        return;
                                      }
                                      setSheetState(() => isCreating = true);

                                      await _createCourse(
                                        title: titleController.text.trim(),
                                        courseCode: courseCodeController.text
                                            .trim()
                                            .toUpperCase(),
                                        program: programController.text.trim(),
                                        section: sectionController.text.trim(),
                                        description: descriptionController.text
                                            .trim(),
                                      );

                                      if (mounted) Navigator.pop(context);
                                    },
                              child: isCreating
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Create Class',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
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

  Future<void> _createCourse({
    required String title,
    required String courseCode,
    required String program,
    required String section,
    required String description,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
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
        'created_at': DateTime.now().toIso8601String(),
      });
      await _loadCourses();
      if (mounted) _showClassCodeDialog(classCode, fullTitle);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
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
                            content: const Text('Class code copied! 📋'),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: const Color(0xFF0D1B4B),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_rounded, color: Colors.white, size: 14),
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
            _buildOptionItem(
              Icons.publish_outlined,
              (course['is_published'] ?? false) ? 'Unpublish' : 'Publish',
              AppColors.success,
              () {
                Navigator.pop(context);
                _togglePublish(course);
              },
            ),
            _buildOptionItem(
              Icons.archive_outlined,
              'Archive Class',
              Colors.orange,
              () {
                Navigator.pop(context);
                _archiveCourse(course['id']);
              },
            ),
            _buildOptionItem(
              Icons.delete_outline,
              'Delete Class',
              AppColors.error,
              () {
                Navigator.pop(context);
                _deleteCourse(course['id']);
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
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _togglePublish(Map<String, dynamic> course) async {
    try {
      await _supabase
          .from('courses')
          .update({'is_published': !(course['is_published'] ?? false)})
          .eq('id', course['id']);
      await _loadCourses();
    } catch (e) {
      debugPrint('Toggle error: $e');
    }
  }

  Future<void> _archiveCourse(String courseId) async {
    try {
      await _supabase
          .from('courses')
          .update({'is_published': false, 'is_archived': true})
          .eq('id', courseId);
      await _loadCourses();
    } catch (e) {
      debugPrint('Archive error: $e');
    }
  }

  void _showDeleteConfirmation(String courseId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Class'),
        content: const Text(
          'Are you sure you want to delete this class? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteCourse(courseId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCourse(String courseId) async {
    try {
      await _supabase.from('courses').delete().eq('id', courseId);
      await _loadCourses();
    } catch (e) {
      debugPrint('Delete error: $e');
    }
  }

  Future<void> _logout() async {
    try {
      await _supabase.auth.signOut();
      if (mounted) context.go(AppRoutes.opening);
    } catch (e) {
      debugPrint('Logout error: $e');
    }
  }

  // ─── BUILD ───────────────────────────────────────────────

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
                      _buildClassesPage(),
                      _buildReportsPage(),
                      _buildProfilePage(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_currentIndex == 1)
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
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationsScreen(isInstructor: true),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              child: Icon(
                Icons.notifications_outlined,
                color: context.isDark ? Colors.white : const Color(0xFF0D1B4B),
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFAB() {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) => GestureDetector(
        onTap: _showCreateCourseDialog,
        child: Container(
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
        'icon': Icons.class_outlined,
        'activeIcon': Icons.class_,
        'label': 'Classes',
      },
      {
        'icon': Icons.bar_chart_outlined,
        'activeIcon': Icons.bar_chart,
        'label': 'Reports',
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
            onTap: () => setState(() => _currentIndex = index),
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
    final activeCoursesCount = _courses.where((c) => c['is_published'] == true).length;
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Welcome Banner (Colors kept white for contrast) ───
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7B2FBE), Color(0xFF1565C0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7B2FBE).withValues(alpha: 0.3),
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
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white70),
                      ),
                      Text(
                        name,
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Manage your classes and track student progress.',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70),
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
                  child: const Icon(Icons.school_outlined, color: Colors.white, size: 32),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ─── Quick Stats (REPLACED EMOJIS WITH ICONS) ───
          Row(
            children: [
              _buildStatCard(
                Icons.auto_stories_rounded, // Proper Icon
                '${_courses.length}',
                'Total Classes',
                AppColors.primary,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                Icons.people_alt_rounded, // Proper Icon
                '$_totalStudents',
                'Total Students',
                AppColors.accent,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
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

          const SizedBox(height: 24),

          // ─── Shortcut Buttons ───
          Row(
            children: [
              Expanded(
                child: _buildShortcutButton(
                  '+ Create Class',
                  AppColors.primaryDark,
                  AppColors.primary,
                  Icons.add_circle_outline,
                  () {
                    setState(() => _currentIndex = 1);
                    Future.delayed(const Duration(milliseconds: 300), _showCreateCourseDialog);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildShortcutButton(
                  'Submissions', // Removed emoji from text
                  AppColors.warning,
                  const Color(0xFFFF8C61),
                  Icons.assignment_outlined,
                  () => setState(() => _currentIndex = 2),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ─── Sections Overview ───
          if (_courses.isNotEmpty) ...[
            _buildSectionHeader('Sections Overview', icon: Icons.analytics_outlined),
            const SizedBox(height: 12),
            _buildSectionsOverview(), 
            const SizedBox(height: 24),
          ],

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildSectionsOverview() {
    return Container(
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        children: _courses.asMap().entries.map((entry) {
          final course = entry.value;
          final index = entry.key;
          final count = course['enrolled_count'] as int? ?? 0;

          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: index < _courses.length - 1
                  ? Border(bottom: BorderSide(color: context.borderColor))
                  : null,
            ),
            child: Row(
              children: [
                // The "CP" Box (Structure Restored)
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _cardGradients[index % _cardGradients.length],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Text(
                      'CP', // Original text from your structure
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course['title'] ?? '',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.isDark
                              ? Colors.white
                              : const Color(0xFF0D1B4B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${course['course_code']} • ${course['section'] ?? ''}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Student Count (Aligned Right)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$count',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      'students',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPendingSubmissionCard(Map<String, dynamic> submission) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.assignment_outlined,
            color: AppColors.warning,
            size: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  submission['users']?['name'] ?? 'Student',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                Text(
                  submission['assessments']?['title'] ?? 'Assessment',
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.warning),
        ],
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String value, String label, Color color) {
    // Interstellar Blue for Light Mode text, White for Dark Mode
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(16),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon with a soft background tint (Matches Student Side)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: textColor.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutButton(
    String label,
    Color c1,
    Color c2,
    IconData icon,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [c1, c2]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {IconData? icon}) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
        ],
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
      ],
    );
  }

  // ─── Classes Page ────────────────────────────────────────
  Widget _buildClassesPage() {
    final titleColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    final filtered = _courses.where((c) {
      final matchesSearch =
          _searchController.text.isEmpty ||
          c['title'].toString().toLowerCase().contains(
            _searchController.text.toLowerCase(),
          ) ||
          c['course_code'].toString().toLowerCase().contains(
            _searchController.text.toLowerCase(),
          );

      final isArchived = c['is_archived'] == true;
      final matchesFilter = _courseFilter == 'Active'
          ? !isArchived
          : isArchived;

      return matchesSearch && matchesFilter;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'My Classes',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 12),
              // ─── Search Bar ────────────────────────────────
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: titleColor,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Search classes...',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    color: context.textHint,
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(Icons.search, color: context.textHint),
                  filled: true,
                  fillColor: context.cardColor,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF1E90FF),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // ─── Filter Tabs ───────────────────────────────
              Row(
                children: ['Active', 'Archived'].map((filter) {
                  final isActive = _courseFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _courseFilter = filter),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: isActive
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFF1565C0),
                                    Color(0xFF1E90FF),
                                  ],
                                )
                              : null,
                          color: isActive ? null : context.cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isActive
                                ? Colors.transparent
                                : context.borderColor,
                          ),
                        ),
                        child: Text(
                          filter,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: isActive
                                ? Colors.white
                                : titleColor.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyClasses()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  physics: const BouncingScrollPhysics(),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) =>
                      _buildCourseCard(filtered[index], index),
                ),
        ),
      ],
    );
  }

  Widget _buildCourseCard(Map<String, dynamic> course, int index) {
    final gradient = _cardGradients[index % _cardGradients.length];
    final isPublished = course['is_published'] == true;
    final enrolledCount = course['enrolled_count'] as int? ?? 0;
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor.withValues(alpha: 0.5)),
        boxShadow: context.isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        children: [
          // ─── Header Gradient Section ───────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Course Code Badge
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
                              course['course_code'] ?? 'N/A',
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Status Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isPublished
                                  ? Colors.green.withValues(alpha: 0.3)
                                  : Colors.orange.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isPublished ? 'Published' : 'Draft',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isPublished
                                    ? Colors.greenAccent
                                    : Colors.orange,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        course['title'] ?? '',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _showCourseOptions(course),
                  child: const Icon(
                    Icons.more_vert,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),

          // ─── Body Section ──────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 16,
                      color: textColor.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$enrolledCount students enrolled',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: textColor.withValues(alpha: 0.7),
                      ),
                    ),
                    const Spacer(),
                    // Class Code Chip (Blue tint)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E90FF).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF1E90FF).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.key_outlined,
                            size: 12,
                            color: Color(0xFF1E90FF),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            course['class_code'] ?? '------',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E90FF),
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Manage Class Button
                GestureDetector(
                  onTap: () {
                    context.push(
                      AppRoutes.courseDetail,
                      extra: {'course': course, 'isInstructor': true},
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: gradient,
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'Manage Class',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
              color: textColor.withValues(alpha: 0.15), // Subtle tint for a modern feel
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
    final titleColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Main Title (Replaced Emoji) ──────────────────
          Row(
            children: [
              const Icon(Icons.analytics_rounded, color: AppColors.primary, size: 24),
              const SizedBox(width: 10),
              Text(
                'Reports',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ─── Students Per Section ───────────────────────
          _buildSectionHeader('Students Per Section', icon: Icons.groups_rounded),
          const SizedBox(height: 12),

          _courses.isEmpty
              ? _buildEmptyReportState('No classes created yet.')
              : Column(
                  children: _courses.asMap().entries.map((entry) {
                    final course = entry.value;
                    final index = entry.key;
                    final count = course['enrolled_count'] as int? ?? 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.cardColor,
                        borderRadius: BorderRadius.circular(20), // Matches system theme
                        border: Border.all(color: context.borderColor),
                        boxShadow: context.isDark ? [] : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
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
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: titleColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '$count students',
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: count > 0 ? (count / 50).clamp(0.0, 1.0) : 0,
                              backgroundColor: context.isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.grey.withValues(alpha: 0.1),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _cardGradients[index % _cardGradients.length][1],
                              ),
                              minHeight: 8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Compare with your physical masterlist to find missing students',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: titleColor.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),

          const SizedBox(height: 32),

          // ─── Pending Submissions ────────────────────────
          _buildSectionHeader('Pending Submissions', icon: Icons.pending_actions_rounded),
          const SizedBox(height: 12),

          _pendingSubmissions.isEmpty
              ? _buildEmptySubmissionsState()
              : Column(
                  children: _pendingSubmissions
                      .map((s) => _buildPendingSubmissionCard(s))
                      .toList(),
                ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  // ─── Empty State Helpers ─────────────────────────────────

  Widget _buildEmptyReportState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Center(
        child: Text(
          message,
          style: TextStyle(fontFamily: 'Poppins', color: context.textSecondary),
        ),
      ),
    );
  }

  Widget _buildEmptySubmissionsState() {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.borderColor),
        boxShadow: context.isDark ? [] : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          // ─── Proper Icon instead of Emoji ───
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.task_alt_rounded, 
              size: 40, 
              color: AppColors.success
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'All caught up!',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No pending student submissions to grade.',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: textColor.withValues(alpha: 0.5),
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ─── Profile Page ────────────────────────────────────────
  Widget _buildProfilePage() {
    final user = _currentUser;
    final titleColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          // ─── Header Profile Card ──────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7B2FBE), Color(0xFF1565C0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24), // Matches student dashboard
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7B2FBE).withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () async {
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
                        radius: 45,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: Text(
                          (user?.name ?? 'I').substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  user?.name ?? 'Instructor',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  user?.email ?? '',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 16),
                
                // ─── UPDATED INSTRUCTOR BADGE (No Emojis) ───
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.school_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Instructor',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ─── Stats Row ───────────────────────────────────
          Row(
            children: [
              _buildStatCard(
                Icons.auto_stories_rounded,
                '${_courses.length}',
                'Classes',
                AppColors.primary,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                Icons.people_rounded,
                '$_totalStudents',
                'Students',
                AppColors.accent,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ─── Settings List ────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.borderColor),
              boxShadow: context.isDark ? [] : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Column(
              children: [
                _buildSettingsItem(
                  Icons.dark_mode_outlined,
                  'Dark Mode',
                  trailing: Switch(
                    value: ref.watch(themeProvider) == ThemeMode.dark,
                    onChanged: (_) => ref.read(themeProvider.notifier).toggleTheme(),
                    activeThumbColor: AppColors.primary,
                  ),
                ),
                Divider(color: context.borderColor, height: 1),
                _buildSettingsItem(
                  Icons.logout_rounded,
                  'Logout',
                  color: AppColors.error,
                  onTap: _logout,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSettingsItem(
    IconData icon,
    String label, {
    Color? color,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final defaultColor = context.isDark
        ? Colors.white
        : const Color(0xFF0D1B4B);
    final effectiveColor = color ?? defaultColor;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: effectiveColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: effectiveColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right,
                  color: defaultColor.withValues(alpha: 0.3),
                  size: 18,
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlowEffect(Size size) => Positioned(
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
        labelStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          color: textColor.withValues(alpha: 0.5),
        ),
        floatingLabelStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(
          fontFamily: 'Poppins',
          color: textColor.withValues(alpha: 0.2),
          fontSize: 13,
        ),
        prefixIcon: Icon(
          icon,
          color: textColor.withValues(alpha: 0.3),
          size: 20,
        ),
        filled: true,
        fillColor: context.cardColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }

  int get _totalStudents => _courses.fold(
    0,
    (sum, item) => sum + (item['enrolled_count'] as int? ?? 0),
  );
}
