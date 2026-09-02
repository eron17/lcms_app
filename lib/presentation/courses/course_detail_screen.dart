// lib/presentation/courses/course_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../data/models/user_model.dart';
import 'post_detail_screen.dart';
import 'three_d_meet_detail_screen.dart';
import 'assignment_detail_screen.dart';
import 'class_settings_screen.dart';
import 'dart:async';
import '../../shared/widgets/pressable_scale.dart';

const Map<String, List<String>> _cppKeywordCategories = {
  'Control Flow': [
    'for',
    'while',
    'do-while',
    'if',
    'else',
    'switch',
    'case',
    'break',
    'continue',
    'return',
  ],
  'Data Types': [
    'int',
    'float',
    'double',
    'char',
    'bool',
    'string',
    'long',
    'short',
    'void',
    'auto',
  ],
  'OOP Concepts': [
    'class',
    'public',
    'private',
    'protected',
    'virtual',
    'override',
    'static',
    'this',
    'new',
    'delete',
    'abstract',
  ],
  'Functions & Templates': [
    'template',
    'inline',
    'operator',
    'friend',
    'explicit',
    'typename',
  ],
  'Memory & Pointers': [
    'pointer (*)',
    'reference (&)',
    'nullptr',
    'malloc',
    'free',
  ],
  'Exception Handling': ['try', 'catch', 'throw'],
  'STL / Libraries': [
    'vector',
    'array',
    'map',
    'set',
    'stack',
    'queue',
    'cout',
    'cin',
    'endl',
  ],
  'Custom': [],
};

Widget _buildAvatar({
  required String name,
  String? avatarUrl,
  double radius = 20,
  double fontSize = 14,
}) {
  if (avatarUrl != null && avatarUrl.isNotEmpty) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
      backgroundImage: NetworkImage(avatarUrl),
      onBackgroundImageError: (_, __) {},
    );
  }
  return CircleAvatar(
    radius: radius,
    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
    child: Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
    ),
  );
}

class CourseDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> course;
  final bool isInstructor;
  final int initialTab;
  final bool isArchived;

  static int initialTabIndex = 0;

  const CourseDetailScreen({
    super.key,
    required this.course,
    required this.isInstructor,
    this.initialTab = 0,
    this.isArchived = false,
  });

  @override
  ConsumerState<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends ConsumerState<CourseDetailScreen>
    with TickerProviderStateMixin {
  // ─── State ───────────────────────────────────────────────
  late int _currentTab;
  final _supabase = Supabase.instance.client;
  UserModel? _currentUser;

  Map<String, dynamic>? _localCourse;
  Map<String, dynamic> get courseData => _localCourse ?? widget.course;
  // Stream data
  List<Map<String, dynamic>> _streamPosts = [];
  bool _isLoadingStream = true;

  // Coursework data
  List<Map<String, dynamic>> _topics = [];
  List<Map<String, dynamic>> _posts = [];
  bool _isLoadingCoursework = true;

  // People data
  List<Map<String, dynamic>> _students = [];
  Map<String, dynamic>? _instructor;
  bool _isLoadingPeople = true;

  // Comments state
  final Map<String, TextEditingController> _commentControllers = {};

  // Coursework topic expansion
  final Map<String, bool> _expandedTopics = {};

  // FAB state (instructor coursework)
  bool _fabExpanded = false;

  // Per-class rank/XP/streak (student side)
  int _classXp = 0;
  int _classStreak = 0;

  // ─── Card Gradients ──────────────────────────────────────
  final List<List<Color>> _cardGradients = [
    [const Color(0xFF7B2FBE), const Color(0xFF4A90D9)],
    [const Color(0xFF1565C0), const Color(0xFF00B4D8)],
    [const Color(0xFF6A0572), const Color(0xFF1E90FF)],
    [const Color(0xFF0D47A1), const Color(0xFF00E5FF)],
    [const Color(0xFF4A148C), const Color(0xFF7B1FA2)],
  ];

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab; // Initialize the tab

    _initializeData(); // Triggers self-loading if needed
  }

  Future<void> _initializeData() async {
    // If we only have the ID (navigated from notification), fetch full course details first
    if (widget.course['title'] == null) {
      try {
        final fullCourse = await _supabase
            .from('courses')
            .select()
            .eq('id', widget.course['id'])
            .single();
        if (mounted) {
          setState(() {
            _localCourse = Map<String, dynamic>.from(fullCourse);
          });
        }
      } catch (e) {
        debugPrint('Error loading full course details: $e');
      }
    }

    // Now safely load the rest of your course dependencies
    _loadCurrentUser();
    _loadStream();
    _loadCoursework();
    _loadPeople();
    if (!widget.isInstructor) _loadEnrollment();
  }

  Future<void> _loadEnrollment() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final data = await _supabase
        .from('enrollments')
        .select('class_xp, class_streak')
        .eq('student_id', userId)
        .eq('course_id', widget.course['id'])
        .maybeSingle();
    if (data != null && mounted) {
      setState(() {
        _classXp = (data['class_xp'] as int?) ?? 0;
        _classStreak = (data['class_streak'] as int?) ?? 0;
      });
    }
  }

  @override
  void dispose() {
    _commentControllers.forEach((_, c) => c.dispose());
    super.dispose();
  }

  // ════════════════════════════════════════════════════════
  // DATA LOADING
  // ════════════════════════════════════════════════════════

  Future<void> _loadCurrentUser() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .single();
      if (mounted) setState(() => _currentUser = UserModel.fromMap(data));
    } catch (e) {
      debugPrint('User error: $e');
    }
  }

  Future<void> _loadStream() async {
    try {
      final data = await _supabase
          .from('posts')
          .select('*, users(name), comments:comments(count)')
          .eq('course_id', courseData['id']) // Changed from widget.course
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _streamPosts = List<Map<String, dynamic>>.from(data);
          _isLoadingStream = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingStream = false);
    }
  }

  Future<void> _loadCoursework() async {
    try {
      final topicsData = await _supabase
          .from('topics')
          .select()
          .eq('course_id', courseData['id']) // Changed from widget.course
          .order('order_index');
      final postsData = await _supabase
          .from('posts')
          .select('*, users(name)')
          .eq('course_id', courseData['id']) // Changed from widget.course
          .neq('type', 'announcement')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _topics = List<Map<String, dynamic>>.from(topicsData);
          _posts = List<Map<String, dynamic>>.from(postsData);
          _isLoadingCoursework = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingCoursework = false);
    }
  }

  Future<void> _loadPeople() async {
    try {
      final instructorId =
          courseData['instructor_id']; // Changed from widget.course
      if (instructorId == null) return;

      // 1. Load Instructor Data
      final instructorData = await _supabase
          .from('users')
          .select()
          .eq('id', instructorId)
          .single();

      // 2. Load Enrollment Data AND the joined User data
      final enrollmentsData = await _supabase
          .from('enrollments')
          .select('users(*)')
          .eq('course_id', courseData['id']); // Changed from widget.course

      if (mounted) {
        setState(() {
          _instructor = instructorData;

          _students = enrollmentsData
              .where((e) => e['users'] != null)
              .map((e) => e['users'] as Map<String, dynamic>)
              .toList();

          _isLoadingPeople = false;
        });
      }
    } catch (e) {
      debugPrint('Load People Error: $e');
      if (mounted) setState(() => _isLoadingPeople = false);
    }
  }

  Future<void> _createOrUpdateAssessmentForPost({
    required Map<String, dynamic> postData,
    required String title,
    required String type,
  }) async {
    if (type != 'assignment') return;

    final postId = postData['id']?.toString();
    final courseId = postData['course_id'] ?? widget.course['id'];

    if (postId == null || postId.isEmpty || courseId == null) {
      throw Exception(
        'Cannot create assessment: missing post ID or course ID.',
      );
    }

    final existingAssessment = await _supabase
        .from('assessments')
        .select('id')
        .eq('id', postId)
        .maybeSingle();

    if (existingAssessment == null) {
      await _supabase.from('assessments').insert({
        'id': postId,
        'course_id': courseId,
        'title': title,
        'type': 'assignment',
      });
    } else {
      await _supabase
          .from('assessments')
          .update({'course_id': courseId, 'title': title, 'type': 'assignment'})
          .eq('id', postId);
    }
  }

  Future<void> _deletePost(String postId) async {
    try {
      await _supabase.from('posts').delete().eq('id', postId);
      await _loadStream();
      await _loadCoursework();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting post: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _removeStudent(String studentId, String studentName) async {
    try {
      await _supabase
          .from('enrollments')
          .delete()
          .eq('student_id', studentId)
          .eq('course_id', widget.course['id']);
      await _loadPeople();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$studentName has been removed from the class.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Remove student error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to remove student: $e',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _deleteTopic(String topicId) async {
    try {
      // Step 1: Update all posts belonging to this topic to have topic_id = null (General)
      await _supabase
          .from('posts')
          .update({'topic_id': null})
          .eq('topic_id', topicId);

      // Step 2: Delete the actual Topic
      await _supabase.from('topics').delete().eq('id', topicId);

      // Step 3: Refresh UI coursework list
      await _loadCoursework();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Topic deleted successfully.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting topic: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ════════════════════════════════════════════════════════
  // INSTRUCTOR DIALOGS
  // ════════════════════════════════════════════════════════

  void _showAnnouncementDialog({Map<String, dynamic>? existing}) {
    final titleController = TextEditingController(
      text: existing?['title'] ?? '',
    );
    final instructionsController = TextEditingController(
      text: existing?['instructions'] ?? '',
    );
    bool isPosting = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.accent, Color(0xFF9B59B6)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.campaign_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      existing != null
                          ? 'Edit Announcement'
                          : 'Create Announcement',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    20,
                    24,
                    MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: Column(
                    children: [
                      _buildSheetField(
                        'Announcement Title',
                        'e.g. Class reminder',
                        titleController,
                        Icons.title_outlined,
                      ),
                      const SizedBox(height: 16),
                      _buildSheetField(
                        'Message',
                        'Write your announcement here...',
                        instructionsController,
                        Icons.message_outlined,
                        maxLines: 5,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          onPressed: isPosting
                              ? null
                              : () async {
                                  if (titleController.text.trim().isEmpty) {
                                    return;
                                  }
                                  setSheet(() => isPosting = true);
                                  try {
                                    final userId =
                                        _supabase.auth.currentUser?.id;
                                    String? targetPostId;

                                    if (existing != null) {
                                      final editData = {
                                        'title': titleController.text.trim(),
                                        'instructions': instructionsController
                                            .text
                                            .trim(),
                                      };
                                      try {
                                        await _supabase
                                            .from('posts')
                                            .update({
                                              ...editData,
                                              'updated_at': DateTime.now()
                                                  .toUtc()
                                                  .toIso8601String(),
                                            })
                                            .eq('id', existing['id']);
                                      } on PostgrestException catch (e) {
                                        // posts.updated_at doesn't exist on
                                        // this Supabase project yet — fall
                                        // back so editing still works.
                                        if (e.code != 'PGRST204') rethrow;
                                        await _supabase
                                            .from('posts')
                                            .update(editData)
                                            .eq('id', existing['id']);
                                      }
                                      targetPostId = existing['id'];
                                    } else {
                                      // Return newly created announcement post to get its ID
                                      final newAnnouncement = await _supabase
                                          .from('posts')
                                          .insert({
                                            'course_id': widget.course['id'],
                                            'instructor_id': userId,
                                            'type': 'announcement',
                                            'title': titleController.text
                                                .trim(),
                                            'instructions':
                                                instructionsController.text
                                                    .trim(),
                                            'created_at': DateTime.now()
                                                .toUtc()
                                                .toIso8601String(),
                                          })
                                          .select()
                                          .single();
                                      targetPostId = newAnnouncement['id'];
                                    }

                                    final studentsData = await _supabase
                                        .from('enrollments')
                                        .select('student_id')
                                        .eq('course_id', widget.course['id']);
                                    final List students = studentsData as List;

                                    if (students.isNotEmpty &&
                                        targetPostId != null) {
                                      final List<Map<String, dynamic>>
                                      notifs = students
                                          .map(
                                            (s) => {
                                              'user_id': s['student_id'],
                                              'course_id': widget.course['id'],
                                              'post_id':
                                                  targetPostId, // ADDED: Links deep routing logic to this post
                                              'type': 'assignment_posted',
                                              'title': 'New Announcement',
                                              'body': titleController.text
                                                  .trim(),
                                              'created_at': DateTime.now()
                                                  .toUtc()
                                                  .toIso8601String(),
                                            },
                                          )
                                          .toList();
                                      await _supabase
                                          .from('notifications')
                                          .insert(notifs);
                                    }

                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                    await _loadStream();
                                  } catch (e) {
                                    setSheet(() => isPosting = false);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(
                                      context,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text('Error: $e'),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                  }
                                },
                          child: isPosting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  existing != null
                                      ? 'Save Changes'
                                      : 'Post Announcement',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
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
      ),
    );
  }

  void _showCreatePostDialog(
    String postType, {
    Map<String, dynamic>? existing,
  }) {
    final titleController = TextEditingController(
      text: existing?['title'] ?? '',
    );
    final instructionsController = TextEditingController(
      text: existing?['instructions'] ?? '',
    );
    final pointsController = TextEditingController(
      text: (existing?['points'] ?? 100).toString(),
    );
    String? selectedTopicId = existing?['topic_id'];

    // ─── Assignment deadline state ───
    DateTime? assignmentDueDate;
    TimeOfDay? assignmentDueTime;
    if (existing?['due_date'] != null) {
      final due = DateTime.parse(existing!['due_date']).toLocal();
      assignmentDueDate = due;
      assignmentDueTime = TimeOfDay(hour: due.hour, minute: due.minute);
    }

    // ─── Scheduling State (3d_meet) ───
    DateTime? scheduledDate;
    TimeOfDay? scheduledTime;
    int durationMinutes = existing?['duration_minutes'] ?? 60;
    bool isPosting = false;

    if (existing?['scheduled_time'] != null) {
      final dt = DateTime.parse(existing!['scheduled_time']).toLocal();
      scheduledDate = dt;
      scheduledTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
    }

    // ─── File upload state ───
    String? materialUrl = existing?['material_url'];
    String? materialName = existing?['material_name'];
    String? assessmentUrl = existing?['assessment_url'];
    String? assessmentName = existing?['assessment_name'];
    bool isUploadingMaterial = false;
    bool isUploadingAssessment = false;
    final stdinController = TextEditingController(
      text: existing?['stdin_input']?.toString() ?? '',
    );
    final expectedOutputController = TextEditingController(
      text: existing?['expected_output']?.toString() ?? '',
    );
    final requiredKeywordControllers = <TextEditingController>[];
    final forbiddenPatternControllers = <TextEditingController>[];

    if (existing != null) {
      if (existing['required_keywords'] != null) {
        final list = List<dynamic>.from(existing['required_keywords']);
        requiredKeywordControllers.addAll(
          list.map((str) => TextEditingController(text: str.toString())),
        );
      }
      if (existing['forbidden_patterns'] != null) {
        final list = List<dynamic>.from(existing['forbidden_patterns']);
        forbiddenPatternControllers.addAll(
          list.map((str) => TextEditingController(text: str.toString())),
        );
      }
    }

    if (requiredKeywordControllers.isEmpty) {
      requiredKeywordControllers.add(TextEditingController());
    }
    if (forbiddenPatternControllers.isEmpty) {
      forbiddenPatternControllers.add(TextEditingController());
    }

    final typeConfig = {
      '3d_meet': {
        'label': '3D Meet Coding',
        'icon': Icons.view_in_ar_outlined,
        'color': const Color(0xFF22C55E),
      },
      'material': {
        'label': 'Lesson Material',
        'icon': Icons.bookmark_outline,
        'color': AppColors.primary,
      },
      'assignment': {
        'label': 'Assignment',
        'icon': Icons.assignment_outlined,
        'color': const Color(0xFFFF6B35),
      },
    };
    final config = typeConfig[postType]!;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Container(
          height: MediaQuery.of(context).size.height * 0.92,
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (config['color'] as Color).withValues(
                          alpha: 0.15,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        config['icon'] as IconData,
                        color: config['color'] as Color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      existing != null
                          ? 'Edit Post'
                          : config['label'] as String,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    20,
                    24,
                    MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSheetField(
                        'Title',
                        'Enter post title',
                        titleController,
                        Icons.title_outlined,
                      ),
                      const SizedBox(height: 16),

                      _buildSheetField(
                        'Instructions / Description',
                        'What do students need to do?',
                        instructionsController,
                        Icons.description_outlined,
                        maxLines: 4,
                      ),
                      const SizedBox(height: 16),

                      // ─── Lesson Material (Hidden for assignments) ──
                      if (postType != 'assignment') ...[
                        _buildUploadButton(
                          label:
                              materialName ??
                              'Attach Lesson Material (PDF, Word, PPT, Excel)',
                          icon: materialName != null
                              ? Icons.check_circle
                              : Icons.picture_as_pdf_outlined,
                          color: AppColors.primary,
                          isUploading: isUploadingMaterial,
                          onTap: () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: [
                                'pdf', 'doc', 'docx',
                                'ppt', 'pptx',
                                'xls', 'xlsx',
                              ],
                            );
                            if (result == null) return;
                            setSheet(() => isUploadingMaterial = true);
                            try {
                              final file = result.files.first;
                              final bytes = kIsWeb
                                  ? file.bytes!
                                  : await File(file.path!).readAsBytes();
                              final fileName =
                                  '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
                              await _supabase.storage
                                  .from('course-materials')
                                  .uploadBinary(fileName, bytes);
                              final url = _supabase.storage
                                  .from('course-materials')
                                  .getPublicUrl(fileName);
                              setSheet(() {
                                materialUrl = url;
                                materialName = file.name;
                                isUploadingMaterial = false;
                              });
                            } catch (e) {
                              setSheet(() => isUploadingMaterial = false);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ─── Assignment Instruction ──
                      if (postType == '3d_meet' ||
                          postType == 'assignment') ...[
                        _buildUploadButton(
                          label:
                              assessmentName ??
                              (postType == 'assignment'
                                  ? 'Attach Assignment File (PDF, Word, PPT, Excel)'
                                  : 'Attach Assessment Instruction (PDF, Word, PPT, Excel)'),
                          icon: assessmentName != null
                              ? Icons.check_circle
                              : Icons.assignment_outlined,
                          color: const Color(0xFFFF6B35),
                          isUploading: isUploadingAssessment,
                          onTap: () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: [
                                'pdf', 'doc', 'docx',
                                'ppt', 'pptx',
                                'xls', 'xlsx',
                              ],
                            );
                            if (result == null) return;
                            setSheet(() => isUploadingAssessment = true);
                            try {
                              final file = result.files.first;
                              final bytes = kIsWeb
                                  ? file.bytes!
                                  : await File(file.path!).readAsBytes();
                              final fileName =
                                  '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
                              await _supabase.storage
                                  .from('course-assessments')
                                  .uploadBinary(fileName, bytes);
                              final url = _supabase.storage
                                  .from('course-assessments')
                                  .getPublicUrl(fileName);
                              setSheet(() {
                                assessmentUrl = url;
                                assessmentName = file.name;
                                isUploadingAssessment = false;
                              });
                            } catch (e) {
                              setSheet(() => isUploadingAssessment = false);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (postType == 'assignment') ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFF6B35,
                            ).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(
                                0xFFFF6B35,
                              ).withValues(alpha: 0.25),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.settings_suggest_outlined,
                                    color: Color(0xFFFF6B35),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Assignment Details',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  // --- Points Input ---
                                  Expanded(
                                    flex: 2,
                                    child: _buildSheetField(
                                      'Points',
                                      '100',
                                      pointsController,
                                      Icons.grade_outlined,
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // --- Due Date Logic ---
                                  Expanded(
                                    flex: 3,
                                    child: GestureDetector(
                                      onTap: () async {
                                        final p = await showDatePicker(
                                          context: context,
                                          initialDate:
                                              assignmentDueDate ??
                                              DateTime.now(),
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime.now().add(
                                            const Duration(days: 365),
                                          ),
                                        );
                                        if (p != null) {
                                          if (!context.mounted) return;
                                          final t = await showTimePicker(
                                            context: context,
                                            initialTime:
                                                assignmentDueTime ??
                                                const TimeOfDay(
                                                  hour: 23,
                                                  minute: 59,
                                                ),
                                          );
                                          if (t != null) {
                                            setSheet(() {
                                              assignmentDueDate = p;
                                              assignmentDueTime = t;
                                            });
                                          }
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 15,
                                        ),
                                        decoration: BoxDecoration(
                                          color: context.cardColor,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: context.borderColor,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.calendar_today_outlined,
                                              size: 16,
                                              color: context.textHint,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                assignmentDueDate == null
                                                    ? 'No Due Date'
                                                    : '${assignmentDueDate!.month}/${assignmentDueDate!.day} ${assignmentDueTime!.format(context)}',
                                                style: TextStyle(
                                                  fontFamily: 'Poppins',
                                                  fontSize: 13,
                                                  color:
                                                      assignmentDueDate == null
                                                      ? context.textHint
                                                      : context.textPrimary,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      _buildTopicPicker(
                        selectedTopicId,
                        (val) => setSheet(() => selectedTopicId = val),
                      ),
                      const SizedBox(height: 24),

                      // ─── 3D Classroom Schedule (Switch Removed, Always Visible) ───
                      if (postType == '3d_meet') ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF22C55E,
                            ).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(
                                0xFF22C55E,
                              ).withValues(alpha: 0.25),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_month_outlined,
                                    color: Color(0xFF22C55E),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Classroom Schedule',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _buildDateTimePicker(
                                context: context,
                                date: scheduledDate,
                                time: scheduledTime,
                                onDateTap: () async {
                                  final p = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime.now(),
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now().add(
                                      const Duration(days: 365),
                                    ),
                                  );
                                  if (p != null) {
                                    setSheet(() => scheduledDate = p);
                                  }
                                },
                                onTimeTap: () async {
                                  final t = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.now(),
                                  );
                                  if (t != null) {
                                    setSheet(() => scheduledTime = t);
                                  }
                                },
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Duration',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: context.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [30, 60, 90, 120].map((mins) {
                                  final isSelected = durationMinutes == mins;
                                  // ─── REVISED DURATION LOGIC ───
                                  String label = mins == 90
                                      ? '1.5 hr'
                                      : (mins >= 60
                                            ? '${mins ~/ 60} hr'
                                            : '$mins min');

                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: GestureDetector(
                                      onTap: () => setSheet(
                                        () => durationMinutes = mins,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? const Color(0xFF22C55E)
                                              : context.cardColor,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? const Color(0xFF22C55E)
                                                : context.borderColor,
                                          ),
                                        ),
                                        child: Text(
                                          label,
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? Colors.white
                                                : context.textSecondary,
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
                        const SizedBox(height: 24),
                      ],

                      if (postType == '3d_meet') ...[
                        const SizedBox(height: 16),
                        const Divider(thickness: 0.5),
                        const SizedBox(height: 16),
                        Text(
                          'Grading Configuration',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 16),

                        Text(
                          'Standard Input (stdin) — Optional',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.isDark
                                ? Colors.white
                                : const Color(0xFF0D1B4B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Leave empty if the program has no cin >>. '
                          'For multiple inputs, put each on a new line.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: context.textHint,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: stdinController,
                          maxLines: 4,
                          minLines: 2,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          style: TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 13,
                            color: context.isDark
                                ? Colors.white
                                : const Color(0xFF0D1B4B),
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'e.g. Juan\n'
                                'or for multiple inputs:\n'
                                '5\n'
                                '3',
                            hintStyle: TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 12,
                              color: context.textHint,
                            ),
                            filled: true,
                            fillColor: context.isDark
                                ? const Color(0xFF080D1F)
                                : const Color(0xFFF0F2F5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppColors.primary.withValues(alpha: 0.4),
                                width: 1,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppColors.primary.withValues(alpha: 0.4),
                                width: 1,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: AppColors.primary,
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                        const SizedBox(height: 16),

                        Text(
                          'Expected Output',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.isDark
                                ? Colors.white
                                : const Color(0xFF0D1B4B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Each line = one expected output line. '
                          'Press Enter to go to the next line.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: context.textHint,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: expectedOutputController,
                          maxLines: 8,
                          minLines: 3,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          style: TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 13,
                            color: context.isDark
                                ? Colors.white
                                : const Color(0xFF0D1B4B),
                          ),
                          decoration: InputDecoration(
                            hintText: 'e.g.\n1\n2\n3\n4\n5',
                            hintStyle: TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 12,
                              color: context.textHint,
                            ),
                            filled: true,
                            fillColor: context.isDark
                                ? const Color(0xFF080D1F)
                                : const Color(0xFFF0F2F5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppColors.primary.withValues(alpha: 0.4),
                                width: 1,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppColors.primary.withValues(alpha: 0.4),
                                width: 1,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: AppColors.primary,
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                        const SizedBox(height: 16),

                        _buildKeywordCategoryPicker(
                          controllers: requiredKeywordControllers,
                          setSheet: setSheet,
                        ),
                        const SizedBox(height: 16),

                        _buildDynamicInputSection(
                          title: 'Forbidden Patterns',
                          subtitle:
                              'Add patterns that students must NOT use. '
                              'Common examples: cout<<1, cout<<2 '
                              '(hardcoded outputs), goto',
                          hint: 'e.g. cout<<1 (hardcoded output)',
                          controllers: forbiddenPatternControllers,
                          setSheet: setSheet,
                        ),
                        const SizedBox(height: 24),
                      ],

                      // ─── Post Button with Strict Validation ───
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: config['color'] as Color,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          onPressed: isPosting
                              ? null
                              : () async {
                                  String? error;
                                  final title = titleController.text.trim();
                                  final desc = instructionsController.text
                                      .trim();

                                  if (title.isEmpty) {
                                    error = "Post title is required";
                                  } else if (desc.isEmpty) {
                                    error =
                                        "Instructions/Description are required";
                                  } else if (postType == 'material' &&
                                      materialUrl == null) {
                                    error =
                                        "Please attach a Lesson Material file";
                                  } else if (postType == 'assignment' &&
                                      assessmentUrl == null) {
                                    error =
                                        "Please attach Assignment Instructions (PDF)";
                                  } else if (postType == 'assignment' &&
                                      (int.tryParse(
                                                pointsController.text.trim(),
                                              ) ==
                                              null ||
                                          int.parse(
                                                pointsController.text.trim(),
                                              ) <=
                                              0)) {
                                    error = "Please enter valid maximum points";
                                  } else if (postType == '3d_meet') {
                                    if (materialUrl == null) {
                                      error =
                                          "Lesson material is required for 3D Meet";
                                    } else if (assessmentUrl == null) {
                                      error =
                                          "Assessment instruction is required for 3D Meet";
                                    } else if (scheduledDate == null ||
                                        scheduledTime == null) {
                                      error =
                                          "Date and Time are required for 3D Meet";
                                    } else if (requiredKeywordControllers
                                        .every(
                                          (c) => c.text.trim().isEmpty,
                                        )) {
                                      error =
                                          "Please add at least one required keyword";
                                    }
                                  }

                                  if (error != null) {
                                    await showDialog(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                        backgroundColor: context.surfaceColor,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        title: Text(
                                          'Missing Information',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w700,
                                            color: context.textPrimary,
                                          ),
                                        ),
                                        content: Text(
                                          error!,
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            color: context.textSecondary,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(dialogContext),
                                            child: const Text('OK'),
                                          ),
                                        ],
                                      ),
                                    );
                                    return;
                                  }

                                  setSheet(() => isPosting = true);
                                  try {
                                    final userId =
                                        _supabase.auth.currentUser?.id;
                                    final expectedOutput =
                                        expectedOutputController.text
                                            .trim()
                                            .isEmpty
                                        ? null
                                        : expectedOutputController.text.trim();
                                    final requiredKeywords =
                                        requiredKeywordControllers
                                            .map((c) => c.text.trim())
                                            .where((text) => text.isNotEmpty)
                                            .toList();
                                    final forbiddenPatterns =
                                        forbiddenPatternControllers
                                            .map((c) => c.text.trim())
                                            .where((text) => text.isNotEmpty)
                                            .toList();
                                    DateTime? finalScheduledTime;
                                    DateTime? finalAssignmentDueDate;
                                    String? targetPostId;
                                    final assignmentPoints =
                                        int.tryParse(
                                          pointsController.text.trim(),
                                        ) ??
                                        100;

                                    if (postType == 'assignment' &&
                                        assignmentDueDate != null &&
                                        assignmentDueTime != null) {
                                      finalAssignmentDueDate = DateTime(
                                        assignmentDueDate!.year,
                                        assignmentDueDate!.month,
                                        assignmentDueDate!.day,
                                        assignmentDueTime!.hour,
                                        assignmentDueTime!.minute,
                                      );
                                    }

                                    if (postType == '3d_meet') {
                                      finalScheduledTime = DateTime(
                                        scheduledDate!.year,
                                        scheduledDate!.month,
                                        scheduledDate!.day,
                                        scheduledTime!.hour,
                                        scheduledTime!.minute,
                                      );
                                    }

                                    // ─── FIX: Check if we are UPDATING or INSERTING ───
                                    if (existing != null) {
                                      // If 'existing' is not null, we UPDATE the current post
                                      final editData = {
                                        'title': title,
                                        'instructions': desc,
                                        'topic_id': selectedTopicId,
                                        'material_url': materialUrl,
                                        'material_name': materialName,
                                        'assessment_url': assessmentUrl,
                                        'assessment_name': assessmentName,
                                        'scheduled_time': finalScheduledTime
                                            ?.toUtc()
                                            .toIso8601String(),
                                        'expected_output': postType == '3d_meet'
                                            ? expectedOutput
                                            : null,
                                        'stdin_input':
                                            stdinController.text.trim().isEmpty
                                            ? null
                                            : stdinController.text.trim(),
                                        'required_keywords':
                                            postType == '3d_meet'
                                            ? requiredKeywords
                                            : null,
                                        'forbidden_patterns':
                                            postType == '3d_meet'
                                            ? forbiddenPatterns
                                            : null,
                                        'duration_minutes':
                                            postType == '3d_meet'
                                            ? durationMinutes
                                            : null,
                                        'points': postType == 'assignment'
                                            ? assignmentPoints
                                            : null,
                                        'due_date': postType == 'assignment'
                                            ? finalAssignmentDueDate
                                                  ?.toUtc()
                                                  .toIso8601String()
                                            : null,
                                      };
                                      try {
                                        await _supabase
                                            .from('posts')
                                            .update({
                                              ...editData,
                                              'updated_at': DateTime.now()
                                                  .toUtc()
                                                  .toIso8601String(),
                                            })
                                            .eq('id', existing['id']);
                                      } on PostgrestException catch (e) {
                                        // posts.updated_at doesn't exist on
                                        // this Supabase project yet — fall
                                        // back so editing still works.
                                        if (e.code != 'PGRST204') rethrow;
                                        await _supabase
                                            .from('posts')
                                            .update(editData)
                                            .eq('id', existing['id']);
                                      }

                                      await _createOrUpdateAssessmentForPost(
                                        postData: existing,
                                        title: title,
                                        type: postType,
                                      );
                                      targetPostId = existing['id'];
                                    } else {
                                      // If 'existing' is null, we create a NEW post (INSERT)
                                      final postData = await _supabase
                                          .from('posts')
                                          .insert({
                                            'course_id': widget.course['id'],
                                            'instructor_id': userId,
                                            'type': postType,
                                            'title': title,
                                            'instructions': desc,
                                            'topic_id': selectedTopicId,
                                            'material_url': materialUrl,
                                            'material_name': materialName,
                                            'assessment_url': assessmentUrl,
                                            'assessment_name': assessmentName,
                                            'scheduled_time': finalScheduledTime
                                                ?.toUtc()
                                                .toIso8601String(),
                                            'expected_output':
                                                postType == '3d_meet'
                                                ? expectedOutput
                                                : null,
                                            'stdin_input':
                                                stdinController.text
                                                    .trim()
                                                    .isEmpty
                                                ? null
                                                : stdinController.text.trim(),
                                            'required_keywords':
                                                postType == '3d_meet'
                                                ? requiredKeywords
                                                : null,
                                            'forbidden_patterns':
                                                postType == '3d_meet'
                                                ? forbiddenPatterns
                                                : null,
                                            'duration_minutes':
                                                postType == '3d_meet'
                                                ? durationMinutes
                                                : null,
                                            'points': postType == 'assignment'
                                                ? assignmentPoints
                                                : null,
                                            'due_date': postType == 'assignment'
                                                ? finalAssignmentDueDate
                                                      ?.toUtc()
                                                      .toIso8601String()
                                                : null,
                                            'created_at': DateTime.now()
                                                .toUtc()
                                                .toIso8601String(),
                                          })
                                          .select()
                                          .single();

                                      await _createOrUpdateAssessmentForPost(
                                        postData: Map<String, dynamic>.from(
                                          postData,
                                        ),
                                        title: title,
                                        type: postType,
                                      );
                                      targetPostId = postData['id'];
                                    }
                                    try {
                                      // 1. Get all students enrolled in this course
                                      final response = await _supabase
                                          .from('enrollments')
                                          .select('student_id')
                                          .eq('course_id', widget.course['id']);

                                      final students = response as List;

                                      if (students.isNotEmpty &&
                                          targetPostId != null) {
                                        // 2. Create the notification list
                                        final List<Map<String, dynamic>>
                                        notifications = students
                                            .map(
                                              (s) => {
                                                'user_id': s['student_id'],
                                                'course_id':
                                                    widget.course['id'],
                                                'post_id':
                                                    targetPostId, // ADDED: Links deep routing logic to this post
                                                'type': 'assignment_posted',
                                                'title':
                                                    'New ${postType.replaceAll('_', ' ')} Posted',
                                                'body':
                                                    'Instructor posted: ${titleController.text.trim()}',
                                                'created_at': DateTime.now()
                                                    .toUtc()
                                                    .toIso8601String(),
                                              },
                                            )
                                            .toList();

                                        // 3. Batch insert all notifications
                                        await _supabase
                                            .from('notifications')
                                            .insert(notifications);
                                      }
                                    } catch (notifError) {
                                      debugPrint(
                                        'Notification fail: $notifError',
                                      );
                                    }

                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                    // Refresh both tabs
                                    await _loadStream();
                                    await _loadCoursework();
                                  } catch (e) {
                                    setSheet(() => isPosting = false);
                                    debugPrint('Error posting: $e');
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Failed to post: $e',
                                            style: const TextStyle(
                                              fontFamily: 'Poppins',
                                            ),
                                          ),
                                          backgroundColor: AppColors.error,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  }
                                },
                          child: isPosting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Post',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
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
      ),
    );
  }

  void _showCreateTopicDialog() {
    final titleController = TextEditingController();
    bool isCreating = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => Dialog(
          backgroundColor: context.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: context.borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create Topic',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Topics help organize your coursework into sections.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: context.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: titleController,
                  autofocus: true,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: context.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. Chapter 1, Week 1...',
                    hintStyle: TextStyle(color: context.textHint),
                    filled: true,
                    fillColor: context.cardColor,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
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
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
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
                                color: context.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          minimumSize: const Size(double.infinity, 48),
                          elevation: 0,
                        ),
                        onPressed: isCreating
                            ? null
                            : () async {
                                if (titleController.text.trim().isEmpty) return;
                                setDialog(() => isCreating = true);
                                try {
                                  await _supabase.from('topics').insert({
                                    'course_id': widget.course['id'],
                                    'title': titleController.text.trim(),
                                    'order_index': _topics.length,
                                    'created_at': DateTime.now()
                                        .toUtc()
                                        .toIso8601String(),
                                  });
                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                  await _loadCoursework();
                                } catch (e) {
                                  setDialog(() => isCreating = false);
                                }
                              },
                        child: isCreating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Create',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w700,
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
      ),
    );
  }

  void _showPostOptions(Map<String, dynamic> post) {
    final type = post['type'] as String;
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
            const SizedBox(height: 16),
            Text(
              post['title'] ?? '',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _buildOptionTile(
              Icons.edit_outlined,
              'Edit Post',
              AppColors.primary,
              () {
                Navigator.pop(context);
                if (type == 'announcement') {
                  _showAnnouncementDialog(existing: post);
                } else {
                  _showCreatePostDialog(type, existing: post);
                }
              },
            ),
            _buildOptionTile(
              Icons.delete_outline,
              'Delete Post',
              AppColors.error,
              () {
                Navigator.pop(context);
                _showDeletePostConfirmation(post);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeletePostConfirmation(Map<String, dynamic> post) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: context.borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.error,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                'Delete Post?',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This will permanently delete "${post['title']}". This cannot be undone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: context.textSecondary,
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
                              color: context.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size(double.infinity, 48),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        await _deletePost(post['id']);
                      },
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
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

  void _showRemoveStudentDialog(Map<String, dynamic> student) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: context.borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.person_remove_outlined,
                color: AppColors.error,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                'Remove Student?',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Remove "${student['name']}" from this class? Their enrollment will be deleted.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: context.textSecondary,
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
                              color: context.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size(double.infinity, 48),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        await _removeStudent(
                          student['id'],
                          student['name'] ?? 'Student',
                        );
                      },
                      child: const Text(
                        'Remove',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
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

  void _showTopicOptions(Map<String, dynamic> topic) {
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
            const SizedBox(height: 16),
            Text(
              'Topic: ${topic['title']}',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _buildOptionTile(
              Icons.edit_outlined,
              'Rename Topic',
              AppColors.primary,
              () {
                Navigator.pop(context);
                _renameTopic(topic);
              },
            ),
            _buildOptionTile(
              Icons.delete_outline,
              'Delete Topic',
              AppColors.error,
              () {
                Navigator.pop(context);
                _showDeleteTopicConfirmation(topic);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameTopic(Map<String, dynamic> topic) async {
    final controller = TextEditingController(
      text: topic['title'] as String? ?? '',
    );
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark
            ? const Color(0xFF0A1128)
            : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Rename topic',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            color: context.isDark ? Colors.white : const Color(0xFF0D1B4B),
          ),
          decoration: InputDecoration(
            hintText: 'Enter new topic name',
            hintStyle: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: context.textHint,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: context.isDark
                    ? AppColors.darkBorder
                    : const Color(0xFFDDE3F0),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: context.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'Save',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;
    if (newName == topic['title']) return;

    try {
      await _supabase
          .from('topics')
          .update({'title': newName})
          .eq('id', topic['id']);
      if (mounted) {
        setState(() {
          topic['title'] = newName;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Topic renamed to "$newName"',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        _loadCoursework();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to rename: $e',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // 2. Alert Dialog warning pop-up
  void _showDeleteTopicConfirmation(Map<String, dynamic> topic) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: context.borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.error,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                'Delete Topic?',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Are you sure you want to delete "${topic['title']}"? All posts inside this topic will be moved to General.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: context.textSecondary,
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
                              color: context.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size(double.infinity, 48),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        await _deleteTopic(topic['id']);
                      },
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
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

  // ════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Control Flow':
        return Icons.alt_route_rounded;
      case 'Data Types':
        return Icons.data_array_rounded;
      case 'OOP Concepts':
        return Icons.account_tree_rounded;
      case 'Functions & Templates':
        return Icons.functions_rounded;
      case 'Memory & Pointers':
        return Icons.memory_rounded;
      case 'Exception Handling':
        return Icons.warning_amber_rounded;
      case 'STL / Libraries':
        return Icons.library_books_rounded;
      case 'Custom':
        return Icons.edit_rounded;
      default:
        return Icons.code_rounded;
    }
  }

  String _getScheduleStatus(String? scheduledTime) {
    if (scheduledTime == null) return 'none';

    try {
      // 1. Parse and convert back to YOUR LOCAL TIME
      final scheduled = DateTime.parse(scheduledTime).toLocal();

      // 2. Get current device time
      final now = DateTime.now();

      final int diff = now.difference(scheduled).inMinutes;

      if (diff < 0) return 'upcoming';
      if (diff >= 0 && diff <= 15) return 'live';
      return 'ended';
    } catch (e) {
      return 'none';
    }
  }

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr).toLocal();
    final now = DateTime.now();
    final isToday =
        date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    if (isToday) {
      final hour = date.hour > 12
          ? date.hour - 12
          : (date.hour == 0 ? 12 : date.hour);
      final ampm = date.hour >= 12 ? 'PM' : 'AM';
      final minute = date.minute.toString().padLeft(2, '0');
      return '$hour:$minute $ampm';
    }
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  IconData _getPostIcon(String type) {
    switch (type) {
      case '3d_meet':
        return Icons.view_in_ar_outlined;
      case 'material':
        return Icons.bookmark_outline;
      case 'assignment':
        return Icons.assignment_outlined;
      case 'announcement':
        return Icons.campaign_outlined;
      default:
        return Icons.article_outlined;
    }
  }

  Color _getPostColor(String type) {
    switch (type) {
      case '3d_meet':
        return const Color(0xFF22C55E);
      case 'material':
        return AppColors.primary;
      case 'assignment':
        return const Color(0xFFFF6B35);
      case 'announcement':
        return AppColors.accent;
      default:
        return AppColors.primary;
    }
  }

  String _getPostTypeLabel(String type) {
    switch (type) {
      case '3d_meet':
        return '3D Meet';
      case 'material':
        return 'Lesson Material';
      case 'assignment':
        return 'Assignment';
      case 'announcement':
        return 'Announcement';
      default:
        return 'Post';
    }
  }

  Widget _buildSheetField(
    String label,
    String hint,
    TextEditingController controller,
    IconData icon, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text, // <--- Add this line
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType, // <--- Add this line
      style: TextStyle(
        fontFamily: 'Poppins',
        color: context.textPrimary,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          color: context.textSecondary,
        ),
        floatingLabelStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(
          fontFamily: 'Poppins',
          color: context.textHint,
          fontSize: 13,
        ),
        prefixIcon: Icon(icon, color: context.textHint, size: 20),
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

  Widget _buildTopicPicker(
    String? selectedTopicId,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose Topic (optional)',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.borderColor),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: selectedTopicId,
              isExpanded: true,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              borderRadius: BorderRadius.circular(12),
              dropdownColor: context.surfaceColor,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: context.textPrimary,
              ),
              hint: Text(
                'General (no topic)',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: context.textHint,
                  fontSize: 13,
                ),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'General (no topic)',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: context.textHint,
                    ),
                  ),
                ),
                ..._topics.map(
                  (t) => DropdownMenuItem<String?>(
                    value: t['id'],
                    child: Text(
                      '${t['title']}',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionTile(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isArchived = widget.course['is_archived'] == true || widget.isArchived;
    final pages = [
      _buildStreamTab(),
      _buildCourseworkTab(),
      _buildPeopleTab(),
    ];

    return Scaffold(
      backgroundColor: context.bgColor,
      body: Stack(
        children: [
          Container(decoration: context.scaffoldGradient),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: pages[_currentTab]),
              ],
            ),
          ),
          // ─── Expanded FAB (Coursework, instructor only) ─
          if (widget.isInstructor && _currentTab == 1 && !isArchived)
            _buildExpandedFAB(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
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

  Widget _buildCourseRankCard() {
    final rank = _getRank(_classXp);
    final nextXp = rank['nextXp'] as int?;
    final rankColor = rank['color'] as Color;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF111D33) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: rankColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(rank['icon'] as IconData, color: rankColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  rank['name'] as String,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: rankColor,
                  ),
                ),
              ),
              Icon(
                Icons.local_fire_department_rounded,
                color: _classStreak > 0
                    ? const Color(0xFFFF9800)
                    : Colors.grey,
                size: 18,
                shadows: _classStreak > 0
                    ? [
                        Shadow(
                          color: const Color(
                            0xFFFF9800,
                          ).withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              const SizedBox(width: 4),
              Text(
                '$_classStreak',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _classStreak > 0
                      ? const Color(0xFFFF9800)
                      : Colors.grey.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: nextXp != null
                        ? (_classXp / nextXp).clamp(0.0, 1.0)
                        : 1.0,
                    minHeight: 6,
                    backgroundColor: context.isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : const Color(0xFF0D1B4B).withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation(rankColor),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                nextXp != null ? '$_classXp / $nextXp XP' : 'MAX RANK',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: context.isDark
                      ? Colors.white.withValues(alpha: 0.45)
                      : const Color(0xFF0D1B4B).withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          // ─── 1. PREMIUM OPACITY-ONLY BACK BUTTON ───
          PressableScale(
            onPressed: () => Navigator.pop(context),
            scaleFactor: 1.0, // ─── FIXED: NO MOVEMENT ───
            opacityFactor: 0.5, // ─── FIXED: DIMMING ONLY ───
            child: Container(
              padding: const EdgeInsets.all(10),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: textColor,
                size: 25, // Balanced size for top bar
              ),
            ),
          ),

          const Spacer(),

          // ─── 2. PREMIUM OPACITY-ONLY SETTINGS BUTTON ───
          if (widget.isInstructor)
            PressableScale(
              onPressed: () async {
                final bool? wasUpdated = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClassSettingsScreen(
                      course: courseData,
                    ), // CHANGED: widget.course -> courseData
                  ),
                );

                // 2. Only refresh the UI if an update actually happened
                if (wasUpdated == true && mounted) {
                  debugPrint('Refresh triggered: Class name updated.');
                  _loadCurrentUser(); // Refresh student count/instructor data
                  _loadStream(); // Refresh class name in stream
                  _loadCoursework(); // Refresh topics

                  // OPTIONAL: If you want to update the Hero Banner Title immediately,
                  // you can add a setState here to update the local 'widget.course' map
                  // or just call your main data fetcher.
                }
              },
              scaleFactor: 1.0,
              opacityFactor: 0.5,
              child: Container(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  Icons.settings_outlined,
                  color: textColor,
                  size: 25,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCourseCard() {
    final gradientIndex =
        (courseData['title'] as String? ?? '').length % _cardGradients.length;
    final gradient = _cardGradients[gradientIndex];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradient[0].withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    courseData['course_code'] ??
                        '', // CHANGED: widget.course -> courseData
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  courseData['title'] ??
                      '', // CHANGED: widget.course -> courseData
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      courseData['instructor_name'] ??
                          'Instructor', // CHANGED: widget.course -> courseData
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.people_outline,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${courseData['enrolled_count'] ?? 0}', // CHANGED: widget.course -> courseData
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    final items = [
      {
        'icon': Icons.forum_outlined,
        'activeIcon': Icons.forum,
        'label': 'Stream',
      },
      {
        'icon': Icons.assignment_outlined,
        'activeIcon': Icons.assignment,
        'label': 'Coursework',
      },
      {
        'icon': Icons.people_outline,
        'activeIcon': Icons.people,
        'label': 'People',
      },
    ];

    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: context.cardColor,
        border: Border(
          top: BorderSide(
            color: context.borderColor.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final isActive = _currentTab == index;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _currentTab = index;
                _fabExpanded = false;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                        ? Colors.white54
                        : const Color(0xFF0D1B4B).withValues(alpha: 0.4),
                    size: 22,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[index]['label'] as String,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                      color: isActive
                          ? Colors.white
                          : context.isDark
                          ? Colors.white54
                          : const Color(0xFF0D1B4B).withValues(alpha: 0.4),
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

  // ─── Expanded FAB ─────────────────────────────────────────
  Widget _buildExpandedFAB() {
    final fabItems = [
      {
        'label': '3D Meet Coding',
        'icon': Icons.view_in_ar_outlined,
        'color': const Color(0xFF22C55E),
        'type': '3d_meet',
      },
      {
        'label': 'Lesson Material',
        'icon': Icons.bookmark_outline,
        'color': AppColors.primary,
        'type': 'material',
      },
      {
        'label': 'Assignment',
        'icon': Icons.assignment_outlined,
        'color': const Color(0xFFFF6B35),
        'type': 'assignment',
      },
      {
        'label': 'Topic',
        'icon': Icons.folder_outlined,
        'color': AppColors.accent,
        'type': 'topic',
      },
    ];

    return Positioned(
      bottom: 80,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mini FAB options
          if (_fabExpanded) ...[
            ...fabItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _fabExpanded = false);
                    if (item['type'] == 'topic') {
                      _showCreateTopicDialog();
                    } else {
                      _showCreatePostDialog(item['type'] as String);
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Label
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: context.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.borderColor),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          item['label'] as String,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Icon button
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: item['color'] as Color,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: (item['color'] as Color).withValues(
                                alpha: 0.35,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          item['icon'] as IconData,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // Main FAB
          GestureDetector(
            onTap: () => setState(() => _fabExpanded = !_fabExpanded),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primary],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                _fabExpanded ? Icons.close : Icons.add,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // STREAM TAB
  // ════════════════════════════════════════════════════════
  Widget _buildStreamTab() {
    if (_isLoadingStream) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    final isArchived = widget.course['is_archived'] == true || widget.isArchived;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadStream,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        children: [
          // ─── Archived banner ───
          if (isArchived)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.archive_rounded,
                    color: AppColors.error,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This class is archived. Content is read-only.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Course card in Stream only
          _buildCourseCard(),

          if (!widget.isInstructor) ...[
            _buildCourseRankCard(),
            const SizedBox(height: 12),
          ],

          // Instructor: Create Announcement button
          if (widget.isInstructor && !isArchived) ...[
            GestureDetector(
              onTap: () => _showAnnouncementDialog(),
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: BorderRadius.circular(
                    16,
                  ), // Increased radius for modern look
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    _buildAvatar(
                      name: _currentUser?.name ?? 'I',
                      avatarUrl: _currentUser?.avatarUrl,
                      radius: 18,
                      fontSize: 12,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Announce something to your class...',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: context.textHint,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.campaign_outlined,
                      color: AppColors.accent,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ],

          // ─── Posts Section ───
          if (_streamPosts.isEmpty)
            _buildEmptyState(
              Icons.campaign_rounded, // Proper Icon instead of Emoji
              'No posts yet',
              widget.isInstructor
                  ? 'Post an announcement to get started!'
                  : 'Your instructor hasn\'t posted anything yet.',
            )
          else
            ..._streamPosts.map((post) => _buildStreamCard(post)),
        ],
      ),
    );
  }

  Widget _buildStreamCard(Map<String, dynamic> post) {
    final type = post['type'] as String;
    final postColor = _getPostColor(type);
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    final int commentCount =
        (post['comments'] != null && (post['comments'] as List).isNotEmpty)
        ? post['comments'][0]['count'] as int
        : 0;

    return GestureDetector(
      onLongPress: widget.isInstructor ? () => _showPostOptions(post) : null,
      child: Padding(
        // ─── 1. FIX WIDTH ───
        // Removed horizontal 16px. Now it only uses the ListView's padding
        // to align perfectly with the top Course Card.
        padding: const EdgeInsets.only(bottom: 12),
        child: PressableScale(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => type == 'assignment'
                  ? AssignmentDetailScreen(
                      post: post,
                      course: widget.course,
                      isInstructor: widget.isInstructor,
                    )
                  : type == '3d_meet'
                  ? ThreeDMeetDetailScreen(
                      post: post,
                      course: widget.course,
                      isInstructor: widget.isInstructor,
                    )
                  : PostDetailScreen(
                      post: post,
                      course: widget.course,
                      isInstructor: widget.isInstructor,
                    ),
            ),
          ).then((_) => _loadStream()),
          scaleFactor: 0.98,
          child: Container(
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(16),
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 4, color: postColor),
                    Expanded(
                      child: Padding(
                        // ─── 2. REDUCE HEIGHT ───
                        // Reduced vertical padding to 10px to make the card slimmer
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Tighter Header
                            Row(
                              children: [
                                _buildTonalBadge(
                                  _getPostTypeLabel(type).toUpperCase(),
                                  postColor,
                                ),
                                const Spacer(),
                                Text(
                                  post['updated_at'] != null
                                      ? 'Posted ${_formatDate(post['created_at'])} '
                                            '(Edited ${_formatDate(post['updated_at'])})'
                                      : _formatDate(post['created_at']),
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 10,
                                    color: textColor.withValues(alpha: 0.4),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6), // Smaller gap
                            // Title (Ellipsis prevents height growth)
                            Text(
                              post['title'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: textColor,
                              ),
                            ),

                            // Compact Subtitle
                            if (post['instructions'] != null)
                              Text(
                                post['instructions'],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  color: textColor.withValues(alpha: 0.5),
                                ),
                              ),

                            const SizedBox(height: 10), // Reduced from 16
                            // Footer Row
                            Row(
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 12,
                                  color: textColor.withValues(alpha: 0.3),
                                ),
                                const SizedBox(width: 4),
                                // ─── THE FIX: Use the commentCount variable here ───
                                Text(
                                  '$commentCount',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    color: textColor.withValues(alpha: 0.3),
                                  ),
                                ),
                                const Spacer(),
                                if (type == 'assignment')
                                  Text(
                                    '${post['points'] ?? 100} pts',
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFF6B35),
                                    ),
                                  ),
                                if (type == '3d_meet')
                                  const Icon(
                                    Icons.videogame_asset_outlined,
                                    size: 14,
                                    color: Color(0xFF22C55E),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Helper for the new Badge style
  Widget _buildTonalBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // COURSEWORK TAB
  // ════════════════════════════════════════════════════════
  Widget _buildCourseworkTab() {
    if (_isLoadingCoursework) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    final generalPosts = _posts.where((p) => p['topic_id'] == null).toList();
    final topicMap = <String, List<Map<String, dynamic>>>{};
    for (final topic in _topics) {
      topicMap[topic['id']] = _posts
          .where((p) => p['topic_id'] == topic['id'])
          .toList();
    }

    // ─── Empty State (Replaced emoji with Icon) ───
    if (_posts.isEmpty && _topics.isEmpty) {
      return _buildEmptyState(
        Icons.library_books_rounded, // Proper Icon
        'No coursework yet',
        widget.isInstructor
            ? 'Tap the + button to create your first post'
            : 'Your instructor hasn\'t posted any coursework yet.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        if (generalPosts.isNotEmpty) ...[
          _buildTopicSection(
            'General',
            'general',
            generalPosts,
            key: const ValueKey('topic_general'), // Added Key
          ),
          const SizedBox(height: 12),
        ],
        ..._topics.map(
          (topic) => Column(
            key: ValueKey('topic_col_${topic['id']}'), // Added Key here
            children: [
              _buildTopicSection(
                topic['title'],
                topic['id'],
                topicMap[topic['id']] ?? [],
                topic: topic,
                key: ValueKey('topic_section_${topic['id']}'), // Added Key here
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopicSection(
    String title,
    String topicKey,
    List<Map<String, dynamic>> posts, {
    Map<String, dynamic>? topic,
    Key? key,
  }) {
    final isExpanded = _expandedTopics[topicKey] ?? true;
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Container(
      key: key, // Use the key here
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20), // Matches your dashboard cards
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
        children: [
          GestureDetector(
            onTap: () =>
                setState(() => _expandedTopics[topicKey] = !isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  // ─── Proper Icon instead of Folder Emoji ───
                  const Icon(
                    Icons.folder_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  // Count indicator
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${posts.length}',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // ─── ADDED: Three-dots options menu for Topic deletion ───
                  if (widget.isInstructor && topic != null) ...[
                    GestureDetector(
                      onTap: () =>
                          _showTopicOptions(topic), // Open options bottom sheet
                      child: Icon(
                        Icons.more_vert,
                        color: textColor.withValues(alpha:0.4),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: textColor.withValues(alpha: 0.4),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            if (posts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No posts in this topic yet',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: textColor.withValues(alpha: 0.4),
                  ),
                ),
              )
            else ...[
              const Divider(height: 1),
              ...posts.asMap().entries.map(
                (entry) => _buildCourseworkItem(
                  entry.value,
                  entry.key == posts.length - 1,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCourseworkItem(Map<String, dynamic> post, bool isLast) {
    final type = post['type'] as String;
    final postColor = _getPostColor(type);
    final postIcon = _getPostIcon(type);
    final hasSchedule = post['scheduled_time'] != null;
    final scheduleStatus = hasSchedule
        ? _getScheduleStatus(post['scheduled_time'])
        : 'none';

    // Using your system dark blue for light mode
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: context.borderColor.withValues(alpha: 0.5),
                ),
              ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: postColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(postIcon, color: postColor, size: 20),
        ),
        title: Text(
          post['title'] ?? '',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(
                post['updated_at'] != null
                    ? 'Posted ${_formatDate(post['created_at'])} '
                          '(Edited ${_formatDate(post['updated_at'])})'
                    : 'Posted ${_formatDate(post['created_at'])}',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: textColor.withValues(alpha: 0.5),
                ),
              ),
              if (hasSchedule) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (scheduleStatus == 'live'
                                ? const Color(0xFF22C55E)
                                : context.textHint)
                            .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        scheduleStatus == 'live'
                            ? Icons.fiber_manual_record
                            : scheduleStatus == 'upcoming'
                            ? Icons.schedule_rounded
                            : Icons.check_circle_rounded,
                        size: 10,
                        color: scheduleStatus == 'live'
                            ? const Color(0xFF22C55E)
                            : context.textHint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        scheduleStatus == 'live'
                            ? 'Live'
                            : scheduleStatus == 'upcoming'
                            ? 'Scheduled'
                            : 'Ended',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: scheduleStatus == 'live'
                              ? const Color(0xFF22C55E)
                              : context.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        // Aligned trailing icon with instructor check
        trailing: widget.isInstructor
            ? GestureDetector(
                onTap: () => _showPostOptions(post),
                child: Icon(
                  Icons.more_vert,
                  color: textColor.withValues(alpha: 0.4),
                  size: 20,
                ),
              )
            : Icon(
                Icons.chevron_right,
                color: textColor.withValues(alpha: 0.3),
                size: 20,
              ),

        // ─── RESTORED NAVIGATION LOGIC ───
        onTap: () =>
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => post['type'] == 'assignment'
                    ? AssignmentDetailScreen(
                        post: post,
                        course: widget.course,
                        isInstructor: widget.isInstructor,
                      )
                    : post['type'] == '3d_meet'
                    ? ThreeDMeetDetailScreen(
                        post: post,
                        course: widget.course,
                        isInstructor: widget.isInstructor,
                      )
                    : PostDetailScreen(
                        post: post,
                        course: widget.course,
                        isInstructor: widget.isInstructor,
                      ),
              ),
            ).then(
              (_) => _loadCoursework(),
            ), // Reloads data when returning from the detail screen
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // PEOPLE TAB
  // ════════════════════════════════════════════════════════
  Widget _buildPeopleTab() {
    if (_isLoadingPeople) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    final currentUserId = _supabase.auth.currentUser?.id;
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        // --- Instructors Section ---
        Text(
          'Instructors',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        Divider(color: context.borderColor.withValues(alpha:0.5)),
        if (_instructor != null)
          _buildPersonTile(_instructor!, isInstructorTile: true),

        const SizedBox(height: 32),

        // --- Students Section ---
        Row(
          children: [
            Text(
              'Students',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_students.length}',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Divider(color: context.borderColor.withValues(alpha:0.5)),

        if (_students.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'No classmates enrolled yet',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: context.textHint,
              ),
              textAlign: TextAlign.center,
            ),
          )
        else
          ..._students.map((student) {
            final isMe = student['id'] == currentUserId;
            return _buildPersonTile(
              student,
              isMe: isMe,
              isInstructorTile: false,
            );
          }),
      ],
    );
  }

  Widget _buildPersonTile(
    Map<String, dynamic> user, {
    bool isMe = false,
    bool isInstructorTile = false,
  }) {
    final name = user['name'] as String? ?? 'User';
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          _buildAvatar(
            name: name,
            avatarUrl: user['avatar_url'] as String?,
            radius: 20,
            fontSize: 14,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Row(
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                    color: textColor,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(You)',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: context.textHint,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Only show the 3-dot menu if the current user IS the instructor
          // and we are NOT looking at the instructor tile itself.
          if (widget.isInstructor && !isInstructorTile)
            GestureDetector(
              onTap: () => _showRemoveStudentDialog(user),
              child: Icon(
                Icons.more_vert,
                color: context.textSecondary,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    // Interstellar Blue in Light Mode, White in Dark Mode
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon with soft circular tint
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 64,
                color: textColor.withValues(alpha: 0.2), // Subtle icon color
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: textColor.withValues(alpha: 0.5),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimePicker({
    required BuildContext context,
    required DateTime? date,
    required TimeOfDay? time,
    required VoidCallback onDateTap,
    required VoidCallback onTimeTap,
  }) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Column(
      children: [
        // Date Picker Box
        GestureDetector(
          onTap: onDateTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 18,
                  color: context.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  date == null
                      ? 'Select Date'
                      : '${date.month}/${date.day}/${date.year}',
                  style: TextStyle(fontFamily: 'Poppins', color: textColor),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Time Picker Box
        GestureDetector(
          onTap: onTimeTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.access_time_outlined,
                  size: 18,
                  color: context.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  time == null ? 'Select Time' : time.format(context),
                  style: TextStyle(fontFamily: 'Poppins', color: textColor),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool isUploading,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isUploading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(Icons.attach_file_outlined, color: color, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicInputSection({
    required String title,
    required String hint,
    required List<TextEditingController> controllers,
    required StateSetter setSheet,
    String? subtitle,
  }) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: context.textHint,
            ),
          ),
        ],
        const SizedBox(height: 8),
        ...controllers.asMap().entries.map((entry) {
          final idx = entry.key;
          final controller = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: controller,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: context.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: '$hint ${idx + 1}',
                      hintStyle: TextStyle(
                        color: context.textHint,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: context.cardColor,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: context.borderColor),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (controllers.length > 1)
                  GestureDetector(
                    onTap: () {
                      setSheet(() {
                        controllers[idx].dispose();
                        controllers.removeAt(idx);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.remove_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () {
            setSheet(() {
              controllers.add(TextEditingController());
            });
          },
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, color: AppColors.primary, size: 18),
              SizedBox(width: 4),
              Text(
                'Add item',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeywordCategoryPicker({
    required List<TextEditingController> controllers,
    required StateSetter setSheet,
  }) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Required Keywords *',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        if (controllers.any((c) => c.text.isNotEmpty)) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: controllers
                .asMap()
                .entries
                .where((e) => e.value.text.isNotEmpty)
                .map((entry) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entry.value.text,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => setSheet(() {
                            controllers[entry.key].dispose();
                            controllers.removeAt(entry.key);
                            if (controllers.isEmpty) {
                              controllers.add(TextEditingController());
                            }
                          }),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  );
                })
                .toList(),
          ),
          const SizedBox(height: 8),
        ],
        GestureDetector(
          onTap: () async {
            final String? selectedCategory = await showModalBottomSheet<String>(
              context: context,
              backgroundColor: context.isDark
                  ? const Color(0xFF0A1128)
                  : Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (ctx) => SafeArea(
                child: DraggableScrollableSheet(
                  initialChildSize: 0.6,
                  minChildSize: 0.4,
                  maxChildSize: 0.85,
                  expand: false,
                  builder: (ctx, scrollController) => Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.isDark
                              ? AppColors.darkBorder
                              : const Color(0xFFDDE3F0),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Select keyword category',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: context.isDark
                                  ? Colors.white
                                  : const Color(0xFF0D1B4B),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          children: [
                            ..._cppKeywordCategories.keys.map((category) {
                              return ListTile(
                                leading: Icon(
                                  _categoryIcon(category),
                                  color: AppColors.primary,
                                  size: 20,
                                ),
                                title: Text(
                                  category,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: context.isDark
                                        ? Colors.white
                                        : const Color(0xFF0D1B4B),
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                  color: AppColors.primary,
                                  size: 20,
                                ),
                                onTap: () => Navigator.pop(ctx, category),
                              );
                            }),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            if (selectedCategory == null) return;
            if (!mounted) return;

            if (selectedCategory == 'Custom') {
              final customController = TextEditingController();
              final custom = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: context.isDark
                      ? const Color(0xFF0A1128)
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: Text(
                    'Custom keyword',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.isDark
                          ? Colors.white
                          : const Color(0xFF0D1B4B),
                    ),
                  ),
                  content: TextField(
                    controller: customController,
                    autofocus: true,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: context.isDark
                          ? Colors.white
                          : const Color(0xFF0D1B4B),
                    ),
                    decoration: InputDecoration(
                      hintText: 'e.g. myFunction, NODE',
                      hintStyle: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: context.textHint,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.darkBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: context.textHint,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(ctx, customController.text.trim()),
                      child: const Text(
                        'Add',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
              if (custom != null && custom.isNotEmpty) {
                setSheet(() {
                  final existing = controllers.map((c) => c.text).toList();
                  if (!existing.contains(custom)) {
                    controllers.add(TextEditingController(text: custom));
                  }
                });
              }
              return;
            }

            final keywords = _cppKeywordCategories[selectedCategory]!;
            final alreadyAdded = controllers.map((c) => c.text).toList();
            final String? selectedKeyword = await showModalBottomSheet<String>(
              context: context,
              backgroundColor: context.isDark
                  ? const Color(0xFF0A1128)
                  : Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (ctx) => SafeArea(
                child: DraggableScrollableSheet(
                  initialChildSize: 0.6,
                  minChildSize: 0.4,
                  maxChildSize: 0.88,
                  expand: false,
                  builder: (_, scrollController) => Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.isDark
                              ? AppColors.darkBorder
                              : const Color(0xFFDDE3F0),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () => Navigator.pop(ctx),
                              child: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                size: 18,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              selectedCategory,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: context.isDark
                                    ? Colors.white
                                    : const Color(0xFF0D1B4B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          children: [
                            ...keywords.map((kw) {
                              final isAdded = alreadyAdded.contains(kw);
                              return ListTile(
                                title: Text(
                                  kw,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: isAdded
                                        ? context.textHint
                                        : context.isDark
                                        ? Colors.white
                                        : const Color(0xFF0D1B4B),
                                  ),
                                ),
                                trailing: isAdded
                                    ? const Icon(
                                        Icons.check_rounded,
                                        color: AppColors.success,
                                        size: 18,
                                      )
                                    : const Icon(
                                        Icons.add_rounded,
                                        color: AppColors.primary,
                                        size: 18,
                                      ),
                                onTap: isAdded
                                    ? null
                                    : () => Navigator.pop(ctx, kw),
                              );
                            }),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            if (selectedKeyword != null) {
              setSheet(() {
                controllers.add(TextEditingController(text: selectedKeyword));
              });
            }
          },
          child: const Row(
            children: [
              Icon(
                Icons.add_circle_outline,
                color: AppColors.primary,
                size: 18,
              ),
              SizedBox(width: 6),
              Text(
                'Add keyword',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
