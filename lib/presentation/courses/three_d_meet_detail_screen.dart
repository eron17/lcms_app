import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../shared/widgets/pressable_scale.dart';
import 'code_viewer_screen.dart';
import 'file_viewer_screen.dart';

class ThreeDMeetDetailScreen extends StatefulWidget {
  final Map<String, dynamic> post;
  final Map<String, dynamic> course;
  final bool isInstructor;

  const ThreeDMeetDetailScreen({
    super.key,
    required this.post,
    required this.course,
    required this.isInstructor,
  });

  @override
  State<ThreeDMeetDetailScreen> createState() =>
      _ThreeDMeetDetailScreenState();
}

class _ThreeDMeetDetailScreenState
    extends State<ThreeDMeetDetailScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;

  // "Live" accent — deliberately distinct from AppColors.success, used
  // consistently for the 3D MEET badge / live session card / join button.
  static const Color _liveGreen = Color(0xFF22C55E);

  // ── Shared ────────────────────────────────────────────────────
  bool _isLoading = true;
  Map<String, dynamic>? _currentUser;
  final _commentController = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _isPostingComment = false;

  // ── Instructor: Student Work tab ──────────────────────────────
  List<Map<String, dynamic>> _studentSubmissions = [];
  Map<String, dynamic>? _selectedStudent;
  final _gradeController = TextEditingController();
  bool _isGrading = false;
  bool _isPostingPrivate = false;
  final _privateCommentController = TextEditingController();
  List<Map<String, dynamic>> _privateComments = [];

  // ── Student: My Result tab ────────────────────────────────────
  Map<String, dynamic>? _mySubmission;
  List<Map<String, dynamic>> _myWorkFiles = [];

  // ── Join button timing ────────────────────────────────────────
  String get _scheduleStatus {
    final scheduledStr = widget.post['scheduled_time'] as String?;
    if (scheduledStr == null) return 'none';
    try {
      final scheduled = DateTime.parse(scheduledStr).toLocal();
      final now = DateTime.now();
      final windowEnd = scheduled.add(const Duration(minutes: 15));
      if (now.isBefore(scheduled)) return 'upcoming';
      if (now.isAfter(scheduled) && now.isBefore(windowEnd)) return 'live';
      return 'ended';
    } catch (_) {
      return 'none';
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _commentController.dispose();
    _gradeController.dispose();
    _privateCommentController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final userData = await _supabase
          .from('users')
          .select('id, name, avatar_url, role')
          .eq('id', userId)
          .single();
      _currentUser = userData;

      await _loadComments();

      // Re-verify against the account's actual DB role instead of trusting
      // widget.isInstructor alone — that flag is only whatever the caller
      // passed in, not a server-verified check, so a mismatch (bad route
      // params, a modified client) must not be able to load every
      // student's submissions/source code for this course.
      final isVerifiedInstructor = userData['role'] == 'instructor';
      if (widget.isInstructor && isVerifiedInstructor) {
        await _loadStudentSubmissions();
      } else {
        await _loadMySubmission();
      }
    } catch (e) {
      debugPrint('ThreeDMeet load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Comments ──────────────────────────────────────────────────
  Future<void> _loadComments() async {
    try {
      final data = await _supabase
          .from('comments')
          .select('id, text, created_at, user_id, users(name, avatar_url)')
          .eq('post_id', widget.post['id'])
          .order('created_at');
      if (mounted) {
        setState(() {
          _comments = List<Map<String, dynamic>>.from(
            data.map((c) => {
              ...c,
              'user_name': c['users']?['name'] ?? 'Unknown',
              'avatar_url': c['users']?['avatar_url'],
            }),
          );
        });
      }
    } catch (e) {
      debugPrint('Load comments: $e');
    }
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    // Ensure user data is loaded
    if (_currentUser == null) {
      await _loadAll();
    }
    setState(() => _isPostingComment = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      final now = DateTime.now().toUtc().toIso8601String();
      final userName = _currentUser?['name'] as String? ?? 'User';
      final inserted = await _supabase
          .from('comments')
          .insert({
            'post_id': widget.post['id'],
            'user_id': userId,
            'user_name': userName,
            'text': text,
            'created_at': now,
          })
          .select()
          .single();
      _commentController.clear();
      // Add to local state immediately for instant UI update — use the
      // server-returned row (with its real id) so this comment can be
      // edited/deleted right away, without needing a reload first.
      if (mounted) {
        setState(() {
          _comments.add({
            ...inserted,
            'avatar_url': _currentUser?['avatar_url'],
          });
        });
      }
    } catch (e) {
      debugPrint('Post comment: $e');
    } finally {
      if (mounted) setState(() => _isPostingComment = false);
    }
  }

  // ── Instructor: Student submissions ───────────────────────────
  Future<void> _loadStudentSubmissions() async {
    try {
      final courseId = widget.course['id'] as String;
      final postId = widget.post['id'] as String;

      final enrollments = await _supabase
          .from('enrollments')
          .select('student_id, users(id, name, avatar_url)')
          .eq('course_id', courseId);

      final subs = await _supabase
          .from('submissions')
          .select(
            'id, student_id, score, is_graded, is_pending, '
            'source_code, actual_output, grade_feedback, '
            'file_urls, file_names, status, submitted_at, xp_awarded',
          )
          .eq('assessment_id', postId);

      final subMap = {for (final s in subs) s['student_id']: s};

      final students = <Map<String, dynamic>>[];
      for (final enrollment in enrollments) {
        final user = enrollment['users'] as Map<String, dynamic>?;
        if (user == null) continue;
        final sid = user['id'] as String;
        final sub = subMap[sid];
        students.add({
          'id': sid,
          'name': user['name'] ?? 'Student',
          'avatar_url': user['avatar_url'],
          'submission': sub,
          'score': sub?['score'],
          'is_graded': sub?['is_graded'] ?? false,
          'status': sub?['status'] ?? 'assigned',
        });
      }

      // Sort: graded first, then turned_in, then assigned
      students.sort((a, b) {
        const order = {'turned_in': 0, 'graded': 1, 'assigned': 2};
        return (order[a['status']] ?? 3)
            .compareTo(order[b['status']] ?? 3);
      });

      if (mounted) setState(() => _studentSubmissions = students);
    } catch (e) {
      debugPrint('Load student submissions: $e');
    }
  }

  Future<void> _gradeStudent(String studentId, Map<String, dynamic> sub) async {
    final maxPoints = (widget.post['points'] as int?) ?? 100;
    final score = int.tryParse(_gradeController.text.trim());
    if (score == null || score < 0 || score > maxPoints) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Enter a valid score (0–$maxPoints)',
              style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _isGrading = true);
    try {
      // Prefer the manual_grade_submission RPC (SECURITY DEFINER — verifies
      // the caller is this course's instructor and clamps to the post's
      // max points) so a modified client can't self-grade by writing
      // score/is_graded directly. Falls back to a direct update only until
      // that RPC is deployed — see CLAUDE.md security notes. The fallback
      // path is NOT secure; remove it once the RPC exists.
      try {
        await _supabase.rpc('manual_grade_submission', params: {
          'p_submission_id': sub['id'],
          'p_score': score,
        });
      } on PostgrestException {
        await _supabase.from('submissions').update({
          'score': score,
          'is_graded': true,
          'is_returned': true,
          'returned_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', sub['id']);
      }

      // Notify student of score update
      await _supabase.from('notifications').insert({
        'user_id': studentId,
        'course_id': widget.course['id'],
        'post_id': widget.post['id'],
        'type': 'assignment_graded',
        'title': '${widget.post['title']} has been graded',
        'body': 'Your score: $score/$maxPoints',
        'is_read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Grade saved: $score/$maxPoints',
                style: const TextStyle(fontFamily: 'Poppins')),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _selectedStudent = null);
        _gradeController.clear();
        await _loadStudentSubmissions();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Grade failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save grade. Please try again.',
                style: TextStyle(fontFamily: 'Poppins')),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGrading = false);
    }
  }

  Future<void> _loadPrivateComments(String studentId) async {
    try {
      final data = await _supabase
          .from('private_comments')
          .select('id, text, created_at, sender_id, sender_name')
          .eq('post_id', widget.post['id'])
          .eq('student_id', studentId)
          .order('created_at');
      if (mounted) {
        setState(() {
          _privateComments =
              List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint('Load private comments: $e');
    }
  }

  Future<void> _postPrivateComment(String studentId) async {
    final text = _privateCommentController.text.trim();
    if (text.isEmpty) return;
    setState(() => _isPostingPrivate = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      await _supabase.from('private_comments').insert({
        'post_id': widget.post['id'],
        'student_id': studentId,
        'sender_id': userId,
        'sender_name': _currentUser?['name'] ?? 'Instructor',
        'text': text,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      await _supabase.from('notifications').insert({
        'user_id': studentId,
        'course_id': widget.course['id'],
        'post_id': widget.post['id'],
        'type': 'private_comment',
        'title': 'Comment on ${widget.post['title']}',
        'body': text,
        'is_read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      _privateCommentController.clear();
      await _loadPrivateComments(studentId);
    } catch (e) {
      debugPrint('Post private comment: $e');
    } finally {
      if (mounted) setState(() => _isPostingPrivate = false);
    }
  }

  // ── Student: My submission ────────────────────────────────────
  Future<void> _loadMySubmission() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _supabase
          .from('submissions')
          .select(
            'id, score, is_graded, is_pending, status, '
            'source_code, grade_feedback, file_urls, file_names, '
            'xp_awarded, submitted_at',
          )
          .eq('student_id', userId)
          .eq('assessment_id', widget.post['id'])
          .maybeSingle();

      if (data != null && mounted) {
        final urls = List<String>.from(data['file_urls'] ?? []);
        final names = List<String>.from(data['file_names'] ?? []);
        setState(() {
          _mySubmission = data;
          _myWorkFiles = List.generate(
            urls.length,
            (i) => {
              'url': urls[i],
              'name': i < names.length ? names[i] : 'File ${i + 1}',
            },
          );
        });
      }
    } catch (e) {
      debugPrint('Load my submission: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.bgColor,
        body: const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    // If instructor tapped a student → show student detail view
    if (_selectedStudent != null) {
      return _buildStudentDetailView();
    }

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor:
            isDark ? const Color(0xFF0A1128) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: isDark ? Colors.white : const Color(0xFF0D1B4B),
              size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.post['title'] ?? '3D Meet',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF0D1B4B),
          ),
          overflow: TextOverflow.ellipsis,
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: context.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
          ),
          tabs: [
            const Tab(text: 'Instructions'),
            Tab(
                text: widget.isInstructor
                    ? 'Student Work'
                    : 'My Result'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInstructionsTab(),
          widget.isInstructor
              ? _buildStudentWorkTab()
              : _buildMyResultTab(),
        ],
      ),
    );
  }

  // ── Instructions Tab ──────────────────────────────────────────
  Widget _buildInstructionsTab() {
    final isDark = context.isDark;
    final scheduleStatus = _scheduleStatus;
    final isLive = scheduleStatus == 'live';
    final isUpcoming = scheduleStatus == 'upcoming';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Post type badge + date
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _liveGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '3D MEET',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _liveGreen,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _formatDate(widget.post['created_at']),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Title
          Text(
            widget.post['title'] ?? '',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0D1B4B),
            ),
          ),
          const SizedBox(height: 8),

          // Description
          if (widget.post['description'] != null) ...[
            const Divider(),
            const SizedBox(height: 8),
            Text(
              widget.post['description'],
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: context.textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Attachments
          if (widget.post['material_url'] != null ||
              widget.post['assessment_url'] != null) ...[
            Text(
              'ATTACHMENTS',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            if (widget.post['material_url'] != null)
              _attachmentTile(
                label: widget.post['material_name'] ?? 'Lesson Material',
                url: widget.post['material_url'],
                icon: _getFileTypeIcon(
                  widget.post['material_name'] ?? 'file.pdf',
                ),
                color: _getFileTypeColor(
                  widget.post['material_name'] ?? 'file.pdf',
                ),
              ),
            if (widget.post['assessment_url'] != null)
              _attachmentTile(
                label:
                    widget.post['assessment_name'] ??
                    'Assessment Instruction',
                url: widget.post['assessment_url'],
                icon: _getFileTypeIcon(
                  widget.post['assessment_name'] ?? 'file.pdf',
                ),
                color: _getFileTypeColor(
                  widget.post['assessment_name'] ?? 'file.pdf',
                ),
              ),
            const SizedBox(height: 16),
          ],

          // Join 3D Classroom button
          if (widget.isInstructor && scheduleStatus != 'none') ...[
            _buildInstructorSessionCard(isLive, isUpcoming),
            const SizedBox(height: 16),
          ],
          if (!widget.isInstructor && scheduleStatus != 'none') ...[
            _buildJoinButton(isLive, isUpcoming),
            const SizedBox(height: 16),
          ],

          const Divider(),
          const SizedBox(height: 12),

          // Class comments
          _buildCommentsSection(),
        ],
      ),
    );
  }

  String _getFileTypeLabel(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return 'PDF';
      case 'doc':
      case 'docx':
        return 'DOC';
      case 'ppt':
      case 'pptx':
        return 'PPT';
      case 'xls':
      case 'xlsx':
        return 'XLS';
      default:
        return ext.toUpperCase();
    }
  }

  Color _getFileTypeColor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return const Color(0xFFFF4D4D);
      case 'doc':
      case 'docx':
        return const Color(0xFF2B579A);
      case 'ppt':
      case 'pptx':
        return const Color(0xFFD24726);
      case 'xls':
      case 'xlsx':
        return const Color(0xFF217346);
      default:
        return AppColors.primary;
    }
  }

  IconData _getFileTypeIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Widget _attachmentTile({
    required String label,
    required String url,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        leading: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 1),
                Text(
                  _getFileTypeLabel(label),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
        title: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
        trailing:
            Icon(Icons.chevron_right_rounded, color: color, size: 20),
        onTap: () async {
          if (kIsWeb) {
            // Use Google Docs Viewer so file is displayed in browser
            // not downloaded. Works for PDF, Word, PPT, Excel
            final cleanUrl = url.split('?').first;
            final viewerUrl =
                'https://docs.google.com/viewer'
                '?url=${Uri.encodeComponent(cleanUrl)}'
                '&embedded=false';
            final uri = Uri.parse(viewerUrl);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          } else {
            if (!context.mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FileViewerScreen(
                  url: url,
                  fileName: label,
                  isStudent: !widget.isInstructor,
                ),
              ),
            );
          }
        },
        dense: true,
      ),
    );
  }

  Future<void> _launchUnity(Map<String, dynamic> post) async {
    // Check 15-minute join window
    final scheduledTime = post['scheduled_time'];
    if (scheduledTime != null) {
      final scheduled = DateTime.parse(scheduledTime).toLocal();
      final now = DateTime.now();
      final windowEnd = scheduled.add(const Duration(minutes: 15));

      if (now.isBefore(scheduled)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Session has not started yet.',
                style: TextStyle(fontFamily: 'Poppins'),
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        return;
      }

      if (now.isAfter(windowEnd)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Session has already ended.',
                style: TextStyle(fontFamily: 'Poppins'),
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        return;
      }
    }

    // Get current student data
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final enrollment = await _supabase
          .from('enrollments')
          .select('student_id')
          .eq('student_id', userId)
          .eq('course_id', widget.course['id'])
          .maybeSingle();
      if (enrollment == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'You are not enrolled in this class.',
                style: TextStyle(fontFamily: 'Poppins'),
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final userData = await _supabase
          .from('users')
          .select('streak, pending_bonus_points, avatar_config')
          .eq('id', userId)
          .single();

      // Build comma separated strings
      final keywords =
          (post['required_keywords'] as List?)
              ?.map((k) => k.toString())
              .join(',') ??
          '';
      final forbidden =
          (post['forbidden_patterns'] as List?)
              ?.map((f) => f.toString())
              .join(',') ??
          '';

      // Build deep link URI
      final uri = Uri(
        scheme: 'unitydemo',
        host: 'join',
        queryParameters: {
          'student_id': userId,
          'post_id': post['id'].toString(),
          'lesson_url': post['material_url']?.toString() ?? '',
          'assessment_url': post['assessment_url']?.toString() ?? '',
          'expected_output': post['expected_output']?.toString() ?? '',
          'required_keywords': keywords,
          'forbidden_patterns': forbidden,
          'duration_minutes': (post['duration_minutes'] ?? 60).toString(),
          'points': (post['points'] ?? 100).toString(),
          'streak': (userData['streak'] ?? 0).toString(),
          'pending_bonus_points': (userData['pending_bonus_points'] ?? 0)
              .toString(),
          'avatar_config': jsonEncode(userData['avatar_config'] ?? {}),
        },
      );

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '3D Classroom app is not installed on this device.',
                style: TextStyle(fontFamily: 'Poppins'),
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Launch Unity error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Failed to launch 3D Classroom. Please try again.',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Widget _buildInstructorSessionCard(bool isLive, bool isUpcoming) {
    final scheduledStr = widget.post['scheduled_time'] as String?;
    String timeInfo = '';
    if (scheduledStr != null) {
      try {
        final scheduled = DateTime.parse(scheduledStr).toLocal();
        final windowEnd = scheduled.add(const Duration(minutes: 15));
        final endHour = windowEnd.hour > 12
            ? windowEnd.hour - 12
            : windowEnd.hour;
        final ampm = windowEnd.hour >= 12 ? 'PM' : 'AM';
        final min = windowEnd.minute.toString().padLeft(2, '0');
        timeInfo = 'Session ends at $endHour:$min $ampm';
      } catch (_) {}
    }

    Color cardColor;
    IconData cardIcon;
    String cardTitle;
    String cardSub;

    if (isLive) {
      cardColor = _liveGreen;
      cardIcon = Icons.cast_connected_rounded;
      cardTitle = 'Session is live now';
      cardSub = timeInfo.isNotEmpty
          ? timeInfo
          : 'Students can join right now';
    } else if (isUpcoming) {
      cardColor = AppColors.primary;
      cardIcon = Icons.schedule_rounded;
      cardTitle = '3D Meet scheduled';
      cardSub = 'Students will be able to join at the scheduled time';
    } else {
      cardColor = context.textHint;
      cardIcon = Icons.event_busy_rounded;
      cardTitle = 'Session has ended';
      cardSub = 'The 15-minute join window has passed';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cardColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(cardIcon, color: cardColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cardTitle,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cardColor,
                  ),
                ),
                Text(
                  cardSub,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: cardColor.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinButton(bool isLive, bool isUpcoming) {
    Color btnColor;
    String btnLabel;
    String btnSub;
    IconData btnIcon;

    if (isLive) {
      btnColor = _liveGreen;
      btnLabel = 'Join 3D Classroom';
      btnSub = 'Session is live now';
      btnIcon = Icons.videogame_asset_rounded;
    } else if (isUpcoming) {
      btnColor = Colors.grey;
      btnLabel = '3D Meet Scheduled';
      btnSub =
          'Starts ${_formatScheduleTime(widget.post['scheduled_time'])}';
      btnIcon = Icons.videogame_asset_outlined;
    } else {
      btnColor = Colors.grey;
      btnLabel = 'Session Ended';
      btnSub = _formatScheduleTime(widget.post['scheduled_time']);
      btnIcon = Icons.videogame_asset_off_outlined;
    }

    return PressableScale(
      onPressed: isLive ? () => _launchUnity(widget.post) : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isLive
              ? btnColor
              : btnColor.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          boxShadow: isLive
              ? [
                  BoxShadow(
                    color: btnColor.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(btnIcon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Column(
              children: [
                Text(btnLabel,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    )),
                Text(btnSub,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.85),
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentsSection() {
    final isDark = context.isDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.forum_outlined,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              'Class Comments',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0D1B4B),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_comments.length}',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_comments.isEmpty)
          Text(
            'No comments yet. Be the first to start the discussion!',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: context.textHint,
            ),
          ),
        ..._comments.map((c) => _buildCommentTile(c)),
        const SizedBox(height: 12),
        // Comment input
        Row(
          children: [
            _avatarWidget(
              name: _currentUser?['name'] ?? 'U',
              avatarUrl: _currentUser?['avatar_url'] as String?,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _commentController,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: isDark ? Colors.white : const Color(0xFF0D1B4B),
                ),
                decoration: InputDecoration(
                  hintText: 'Add class comment...',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: context.textHint,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF111E3D)
                      : const Color(0xFFF0F4FF),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  suffixIcon: _isPostingComment
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.send_rounded,
                              color: AppColors.primary, size: 18),
                          onPressed: _postComment,
                        ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildCommentTile(Map<String, dynamic> comment) {
    final isDark = context.isDark;
    final currentUserId = _supabase.auth.currentUser?.id;
    final commentUserId = comment['user_id'] as String?;
    final isOwnComment = currentUserId == commentUserId;
    final canDelete = isOwnComment || widget.isInstructor;
    final canEdit = isOwnComment;
    return GestureDetector(
      onTap: (canDelete || canEdit)
          ? () => _showCommentOptions(comment)
          : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _avatarWidget(
              name: comment['user_name'] ?? 'U',
              avatarUrl: comment['avatar_url'] as String?,
              radius: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        comment['user_name'] ?? '',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0D1B4B),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatDate(comment['created_at']),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: context.textHint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    comment['text'] ?? '',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: context.textSecondary,
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

  void _showCommentOptions(Map<String, dynamic> comment) {
    final isOwn =
        comment['user_id'] == _supabase.auth.currentUser?.id;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Edit Option (Only for owners)
            if (isOwn)
              ListTile(
                leading: const Icon(
                  Icons.edit_outlined,
                  color: AppColors.primary,
                ),
                title: const Text(
                  'Edit comment',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _editComment(comment);
                },
              ),

            // Delete Option (Owners OR Instructor can delete)
            if (isOwn || widget.isInstructor)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: Text(
                  isOwn ? 'Delete comment' : 'Remove student comment',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteComment(comment['id'].toString());
                },
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _editComment(Map<String, dynamic> comment) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => EditCommentDialog(
        comment: comment,
        onSave: (newText) async {
          await _supabase
              .from('comments')
              .update({'text': newText})
              .eq('id', comment['id']);

          if (!mounted) return;
          setState(() {
            final updated = List<Map<String, dynamic>>.from(_comments);
            final index = updated.indexWhere((c) => c['id'] == comment['id']);
            if (index != -1) {
              updated[index] = Map<String, dynamic>.from(updated[index])
                ..['text'] = newText;
              _comments = updated;
            }
          });
        },
      ),
    );
  }

  Future<void> _deleteComment(String commentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark
            ? const Color(0xFF0A1128)
            : Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete comment?',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'This comment will be permanently removed.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: context.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _supabase.from('comments').delete().eq('id', commentId);
      if (!mounted) return;
      setState(() => _comments
          .removeWhere((c) => c['id'].toString() == commentId));
    } catch (e) {
      debugPrint('Delete comment error: $e');
    }
  }

  // ── Student Work Tab (Instructor) ─────────────────────────────
  Widget _buildStudentWorkTab() {
    // Score distribution
    final scores = _studentSubmissions
        .where((s) => s['is_graded'] == true)
        .map((s) => (s['score'] as int?) ?? 0)
        .toList();

    final score0 = scores.where((s) => s == 0).length;
    final score1to74 =
        scores.where((s) => s > 0 && s < 75).length;
    final score75plus = scores.where((s) => s >= 75).length;
    final notSubmitted =
        _studentSubmissions.where((s) => s['status'] == 'assigned').length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Score distribution cards
          const Text(
            'SCORE DISTRIBUTION',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _distCard('Got 0', score0, AppColors.error)),
              const SizedBox(width: 8),
              Expanded(
                  child: _distCard(
                      '1–74', score1to74, const Color(0xFFF97316))),
              const SizedBox(width: 8),
              Expanded(
                  child: _distCard(
                      '75–100', score75plus, AppColors.success)),
              const SizedBox(width: 8),
              Expanded(
                  child: _distCard(
                      'No sub', notSubmitted, context.textHint)),
            ],
          ),
          const SizedBox(height: 20),

          const Text(
            'TAP A STUDENT TO GRADE',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),

          ..._studentSubmissions
              .map((student) => _buildStudentRow(student)),
        ],
      ),
    );
  }

  Widget _distCard(String label, int count, Color color) {
    final isDark = context.isDark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111E3D) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorder
              : const Color(0xFFDDE3F0),
        ),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
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
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStudentRow(Map<String, dynamic> student) {
    final isDark = context.isDark;
    final status = student['status'] as String? ?? 'assigned';
    final score = student['score'] as int?;

    Color statusColor;
    String statusLabel;
    if (status == 'turned_in') {
      statusColor = const Color(0xFFF97316);
      statusLabel = 'Turned in';
    } else if (student['is_graded'] == true) {
      statusColor = AppColors.success;
      statusLabel = score != null ? '$score/100' : 'Graded';
    } else {
      statusColor = context.textHint;
      statusLabel = 'Not submitted';
    }

    return PressableScale(
      scaleFactor: 1.0,
      opacityFactor: 0.5,
      onPressed: () {
        setState(() => _selectedStudent = student);
        if (student['submission'] != null) {
          _loadPrivateComments(student['id']);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color:
              isDark ? const Color(0xFF111E3D) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? AppColors.darkBorder
                : const Color(0xFFDDE3F0),
          ),
        ),
        child: Row(
          children: [
            _avatarWidget(
              name: student['name'] ?? 'S',
              avatarUrl: student['avatar_url'] as String?,
              radius: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                student['name'] ?? '',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? Colors.white
                      : const Color(0xFF0D1B4B),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
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
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                color: context.textHint, size: 16),
          ],
        ),
      ),
    );
  }

  // ── Student Detail View (Instructor tapped a student) ─────────
  Widget _buildStudentDetailView() {
    final isDark = context.isDark;
    final student = _selectedStudent!;
    final sub = student['submission'] as Map<String, dynamic>?;
    final sourceCode = sub?['source_code'] as String?;
    final gradeFeedback =
        List<String>.from(sub?['grade_feedback'] ?? []);
    final fileUrls = List<String>.from(sub?['file_urls'] ?? []);
    final fileNames = List<String>.from(sub?['file_names'] ?? []);

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor:
            isDark ? const Color(0xFF0A1128) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color:
                  isDark ? Colors.white : const Color(0xFF0D1B4B),
              size: 18),
          onPressed: () =>
              setState(() => _selectedStudent = null),
        ),
        title: Text(
          student['name'] ?? '',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color:
                isDark ? Colors.white : const Color(0xFF0D1B4B),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Student header card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF111E3D)
                    : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isDark
                        ? AppColors.darkBorder
                        : const Color(0xFFDDE3F0)),
              ),
              child: Row(
                children: [
                  _avatarWidget(
                    name: student['name'] ?? 'S',
                    avatarUrl: student['avatar_url'] as String?,
                    radius: 24,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        student['name'] ?? '',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0D1B4B),
                        ),
                      ),
                      Text(
                        sub == null
                            ? 'Not submitted'
                            : sub['status'] == 'turned_in'
                                ? 'Turned in'
                                : 'Graded',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: sub == null
                              ? context.textHint
                              : sub['status'] == 'turned_in'
                                  ? AppColors.success
                                  : AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (sub == null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF111E3D)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: isDark
                          ? AppColors.darkBorder
                          : const Color(0xFFDDE3F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.inbox_outlined,
                        color: AppColors.error, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'No submission yet.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[

              // Submitted files
              if (fileUrls.isNotEmpty) ...[
                _sectionTitle('Submitted Work'),
                ...List.generate(fileUrls.length, (i) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary
                          .withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.primary
                              .withValues(alpha: 0.3)),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.insert_drive_file_rounded,
                          color: AppColors.primary, size: 20),
                      title: Text(
                        i < fileNames.length
                            ? fileNames[i]
                            : 'File ${i + 1}',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(
                          Icons.visibility_rounded,
                          color: AppColors.primary,
                          size: 18),
                      dense: true,
                      onTap: () async {
                        final fileLabel = i < fileNames.length
                            ? fileNames[i]
                            : 'File ${i + 1}';
                        final url = fileUrls[i];
                        if (kIsWeb) {
                          final cleanUrl = url.split('?').first;
                          final viewerUrl =
                              'https://docs.google.com/viewer'
                              '?url=${Uri.encodeComponent(cleanUrl)}'
                              '&embedded=false';
                          final uri = Uri.parse(viewerUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        } else {
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FileViewerScreen(
                                url: url,
                                fileName: fileLabel,
                                isStudent: !widget.isInstructor,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  );
                }),
                const SizedBox(height: 16),
              ],

              // Source code preview
              if (sourceCode != null &&
                  sourceCode.isNotEmpty) ...[
                _sectionTitle('Source Code'),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      // Code preview (first 15 lines)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          sourceCode
                              .split('\n')
                              .take(15)
                              .join('\n'),
                          style: const TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 12,
                            color: Color(0xFFD4D4D4),
                            height: 1.6,
                          ),
                        ),
                      ),
                      // View full button
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CodeViewerScreen(
                                studentName: student['name'] ?? '',
                                sourceCode: sourceCode,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              vertical: 10),
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                  color: Colors.white12),
                            ),
                            borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(12)),
                          ),
                          child: const Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Icon(Icons.open_in_full_rounded,
                                  color: AppColors.primary,
                                  size: 14),
                              SizedBox(width: 6),
                              Text(
                                'View full code',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Auto-grader breakdown
              if (gradeFeedback.isNotEmpty) ...[
                _sectionTitle('Scanner Breakdown'),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF111E3D)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isDark
                            ? AppColors.darkBorder
                            : const Color(0xFFDDE3F0)),
                  ),
                  child: Column(
                    children: gradeFeedback
                        .map((f) => _feedbackRow(f))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Grade input
              _sectionTitle('Grade'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:
                      isDark ? const Color(0xFF111E3D) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: isDark
                          ? AppColors.darkBorder
                          : const Color(0xFFDDE3F0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _gradeController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0D1B4B),
                        ),
                        decoration: InputDecoration(
                          hintText: sub['score'] != null
                              ? '${sub['score']}/100 (tap to override)'
                              : 'Set score (0–100)',
                          hintStyle: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: context.textHint,
                          ),
                          prefixIcon: const Icon(
                              Icons.star_outline_rounded,
                              color: AppColors.primary,
                              size: 18),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _isGrading
                          ? null
                          : () => _gradeStudent(
                              student['id'], sub),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        elevation: 0,
                      ),
                      child: _isGrading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : const Text('Grade',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Private comments
              _sectionTitle('Private Comments'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:
                      isDark ? const Color(0xFF111E3D) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFF97316)
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.lock_outline_rounded,
                            color: Color(0xFFF97316), size: 14),
                        SizedBox(width: 6),
                        Text(
                          'Private Comments',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF97316),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    if (_privateComments.isEmpty)
                      Text('No private comments yet.',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: context.textHint)),
                    ..._privateComments.map((c) => Padding(
                          padding:
                              const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                c['sender_name'] ?? '',
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFF97316),
                                ),
                              ),
                              Text(
                                c['text'] ?? '',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _privateCommentController,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0D1B4B),
                            ),
                            decoration: InputDecoration(
                              hintText: 'Add private comment...',
                              hintStyle: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  color: context.textHint),
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF0A1128)
                                  : const Color(0xFFF0F4FF),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10),
                              suffixIcon: _isPostingPrivate
                                  ? const Padding(
                                      padding: EdgeInsets.all(10),
                                      child:
                                          CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(
                                                  0xFFF97316)),
                                    )
                                  : IconButton(
                                      icon: const Icon(
                                          Icons.send_rounded,
                                          color: Color(0xFFF97316),
                                          size: 18),
                                      onPressed: () =>
                                          _postPrivateComment(
                                              student['id']),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _feedbackRow(String feedback) {
    final isPositive = feedback.toLowerCase().contains('found') ||
        feedback.toLowerCase().contains('match') ||
        feedback.toLowerCase().contains('compiled') ||
        feedback.toLowerCase().contains('no forbidden') ||
        feedback.toLowerCase().contains('skipped');
    final isNegative =
        feedback.toLowerCase().contains('missing') ||
        feedback.toLowerCase().contains('error') ||
        feedback.toLowerCase().contains('does not') ||
        feedback.toLowerCase().contains('detected') ||
        feedback.toLowerCase().contains('forbidden');

    final color = isPositive
        ? AppColors.success
        : isNegative
            ? AppColors.error
            : context.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isPositive
                ? Icons.check_circle_outline_rounded
                : isNegative
                    ? Icons.cancel_outlined
                    : Icons.info_outline_rounded,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              feedback,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── My Result Tab (Student) ───────────────────────────────────
  Widget _buildMyResultTab() {
    final isDark = context.isDark;
    final sub = _mySubmission;
    final isGraded = sub?['is_graded'] == true;
    final isTurnedIn = sub?['status'] == 'turned_in';
    final score = sub?['score'] as int?;
    final gradeFeedback =
        List<String>.from(sub?['grade_feedback'] ?? []);
    final xpAwarded = sub?['xp_awarded'] as int?;

    // Submitted but not graded yet
    if (isTurnedIn && !isGraded) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 32),
            Icon(Icons.hourglass_top_rounded,
                size: 72,
                color: context.isDark
                    ? Colors.white12
                    : Colors.black12),
            const SizedBox(height: 16),
            Text(
              'Work submitted',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0D1B4B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your instructor will review and grade your submission.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF97316).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFFF97316)
                        .withValues(alpha: 0.4)),
              ),
              child: const Text(
                'Awaiting grade',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFF97316),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Show submitted files
            if (_myWorkFiles.isNotEmpty) ...[
              _sectionTitle('Submitted files'),
              ..._myWorkFiles.map((f) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF111E3D)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: isDark
                              ? AppColors.darkBorder
                              : const Color(0xFFDDE3F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                            Icons.insert_drive_file_rounded,
                            color: AppColors.primary,
                            size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            f['name'] ?? 'File',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: AppColors.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      );
    }

    // Graded state
    if (isGraded && score != null) {
      final isPassing = score >= 75;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Score display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF111E3D) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isDark
                        ? AppColors.darkBorder
                        : const Color(0xFFDDE3F0)),
              ),
              child: Column(
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '$score',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 52,
                            fontWeight: FontWeight.w800,
                            color: isPassing
                                ? AppColors.success
                                : AppColors.error,
                          ),
                        ),
                        TextSpan(
                          text: ' / 100',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 20,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (xpAwarded != null && xpAwarded > 0)
                    Text(
                      '+$xpAwarded XP earned',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Scanner breakdown
            if (gradeFeedback.isNotEmpty) ...[
              _sectionTitle('Scanner Breakdown'),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF111E3D)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isDark
                          ? AppColors.darkBorder
                          : const Color(0xFFDDE3F0)),
                ),
                child: Column(
                  children: gradeFeedback
                      .map((f) => _feedbackRow(f))
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      );
    }

    // No submission yet — show waiting message
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videogame_asset_outlined,
              size: 72,
              color: context.isDark
                  ? Colors.white12
                  : Colors.black12,
            ),
            const SizedBox(height: 16),
            Text(
              'No submission yet',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.isDark
                    ? Colors.white
                    : const Color(0xFF0D1B4B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Join the 3D Classroom session and complete the activity inside Unity to submit your work.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: context.textSecondary,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────
  Widget _avatarWidget({
    required String name,
    String? avatarUrl,
    double radius = 18,
  }) {
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(avatarUrl),
        backgroundColor:
            AppColors.primary.withValues(alpha: 0.15),
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
      child: Text(
        name[0].toUpperCase(),
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: radius * 0.7,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: context.isDark
              ? Colors.white
              : const Color(0xFF0D1B4B),
        ),
      ),
    );
  }

  String _formatDate(String? dateStr) {
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

  String _formatScheduleTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour;
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '$hour:$min $ampm';
    } catch (_) {
      return '';
    }
  }
}

class EditCommentDialog extends StatefulWidget {
  final Map<String, dynamic> comment;
  final Future<void> Function(String) onSave;

  const EditCommentDialog({
    super.key,
    required this.comment,
    required this.onSave,
  });

  @override
  State<EditCommentDialog> createState() => _EditCommentDialogState();
}

class _EditCommentDialogState extends State<EditCommentDialog> {
  late TextEditingController _controller;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.comment['text'] ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final textColor = isDark ? Colors.white : const Color(0xFF0D1B4B);

    return AlertDialog(
      backgroundColor: context.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: const Text(
        'Edit Comment',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: TextStyle(
          color: textColor,
          fontFamily: 'Poppins',
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: 'Edit your message...',
          hintStyle: TextStyle(
            fontFamily: 'Poppins',
            color: context.textHint,
            fontSize: 14,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: _isSaving
              ? null
              : () async {
                  final newText = _controller.text.trim();
                  if (newText.isEmpty || newText == widget.comment['text']) {
                    Navigator.pop(context);
                    return;
                  }

                  setState(() => _isSaving = true);

                  try {
                    await widget.onSave(newText);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  } catch (e) {
                    if (kDebugMode) debugPrint('Update comment failed: $e');
                    if (!context.mounted) return;
                    setState(() => _isSaving = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Failed to update comment. Please try again.'),
                      ),
                    );
                  }
                },
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  'Save',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ],
    );
  }
}
