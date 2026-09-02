// lib/presentation/courses/post_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import 'file_viewer_screen.dart';
import 'dart:async';
import '../../shared/widgets/pressable_scale.dart';

class PostDetailScreen extends StatefulWidget {
  final Map<String, dynamic> post;
  final Map<String, dynamic> course;
  final bool isInstructor;

  const PostDetailScreen({
    super.key,
    required this.post,
    required this.course,
    required this.isInstructor,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _comments = [];
  final _commentController = TextEditingController();
  bool _isSubmittingComment = false;
  bool _materialSaved = false;
  bool _assessmentSaved = false;
  String? _currentUserName;
  String? _currentUserAvatarUrl;
  Timer? _refreshTimer;
  RealtimeChannel? _commentChannel;

  @override
  void initState() {
    super.initState();
    _loadComments();
    _loadCurrentUser();
    _checkAlreadySaved();
    _subscribeToComments();

    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _commentController.dispose();
    _commentChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _supabase
          .from('users')
          .select('name, avatar_url')
          .eq('id', userId)
          .single();
      if (mounted) {
        setState(() {
          _currentUserName = data['name'];
          _currentUserAvatarUrl = data['avatar_url'];
        });
      }
    } catch (e) {
      debugPrint('User load: $e');
    }
  }

  Future<void> _loadComments() async {
    try {
      final data = await _supabase
          .from('comments')
          .select('*, users(avatar_url)')
          .eq('post_id', widget.post['id'])
          .order('created_at', ascending: true);
      if (mounted) {
        setState(() {
          _comments = List<Map<String, dynamic>>.from(data).map((c) {
            return {
              ...c,
              'avatar_url': c['users']?['avatar_url'],
            };
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Comments: $e');
    }
  }

  Future<void> _submitComment() async {
    if (_commentController.text.trim().isEmpty) return;
    final text = _commentController.text.trim();
    setState(() => _isSubmittingComment = true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // 1. Save the actual comment to the DB
      await _supabase.from('comments').insert({
        'post_id': widget.post['id'],
        'user_id': userId,
        'user_name': _currentUserName ?? 'User',
        'text': text,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // 2. ─── CONSOLIDATED NOTIFICATION LOGIC ───
      try {
        if (widget.isInstructor) {
          // --- CASE A: Instructor comments (Notify ALL students) ---
          final studentsData = await _supabase
              .from('enrollments')
              .select('student_id')
              .eq('course_id', widget.course['id']);

          final List students = studentsData as List;
          if (students.isNotEmpty) {
            final List<Map<String, dynamic>> notifs = students.map((s) => {
              'user_id': s['student_id'],
              'course_id': widget.course['id'],
              'post_id': widget.post['id'],
              'type': 'class_comment',
              'title': 'Instructor commented',
              'body': '${widget.post['title']}: $text',
              'created_at': DateTime.now().toUtc().toIso8601String(),
            }).toList();
            await _supabase.from('notifications').insert(notifs);
          }
        } else {
          // --- CASE B: Student comments (Notify Instructor IF NOT MUTED) ---
          // 1. Fetch Instructor ID and their notification preference
          final courseSettings = await _supabase
              .from('courses')
              .select('notify_on_comments, instructor_id')
              .eq('id', widget.course['id'])
              .single();

          // 2. Only fire if they have it turned ON (true)
          if (courseSettings['notify_on_comments'] == true) {
            await _supabase.from('notifications').insert({
              'user_id': courseSettings['instructor_id'],
              'course_id': widget.course['id'],
              'post_id': widget.post['id'],
              'type': 'class_comment',
              'title': 'New comment from $_currentUserName',
              'body': '${widget.post['title']}: $text',
              'created_at': DateTime.now().toUtc().toIso8601String(),
            });
          }
        }
      } catch (notifErr) {
        debugPrint('Comment Notification Error: $notifErr');
      }

      _commentController.clear();
      await _loadComments();
    } catch (e) {
      debugPrint('Comment submit error: $e');
    } finally {
      if (mounted) setState(() => _isSubmittingComment = false);
    }
  }

  void _subscribeToComments() {
  _commentChannel = _supabase
      .channel('public:comments:post_${widget.post['id']}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'comments',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'post_id',
          value: widget.post['id'],
        ),
        callback: (payload) => _loadComments(), // Refresh UI when DB changes
      )
      .subscribe();
}

  void _showCommentOptions(Map<String, dynamic> comment) {
    final isOwn = comment['user_id'] == _supabase.auth.currentUser?.id;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle Bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Only show Edit if it's the user's own comment
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
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showEditCommentDialog(comment);
                },
              ),

            // Instructors can delete anyone's comment; Users can delete their own
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
              ),
              title: const Text(
                'Delete comment',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  color: Colors.redAccent,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _deleteComment(comment['id']);
              },
            ),
            const SizedBox(height: 20), // Bottom breathing room
          ],
        ),
      ),
    );
  }

  // ─── NEW: EDIT COMMENT DIALOG ───
  void _showEditCommentDialog(Map<String, dynamic> comment) {
    final controller = TextEditingController(text: comment['text']);
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent closing while saving
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: context.surfaceColor,
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
            controller: controller,
            autofocus: true,
            style: TextStyle(color: context.textPrimary, fontFamily: 'Poppins'),
            decoration: InputDecoration(
              hintText: 'Edit your message...',
              hintStyle: TextStyle(color: context.textHint),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      final newText = controller.text.trim();
                      if (newText.isEmpty || newText == comment['text']) {
                        Navigator.pop(context);
                        return;
                      }

                      setDialogState(() => isSaving = true);

                      try {
                        // 1. Await the database update
                        await _supabase
                            .from('comments')
                            .update({'text': newText})
                            .eq('id', comment['id']);

                        if (!context.mounted) return;
                        Navigator.pop(context); // Close dialog
                        _loadComments(); // Refresh UI list
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Comment updated')),
                        );
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        debugPrint('Edit Error: $e');
                        // This will show you exactly why it failed (usually RLS)
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Update failed: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              child: isSaving
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
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await _supabase.from('comments').delete().eq('id', commentId);
      await _loadComments();
    } catch (e) {
      debugPrint('Delete comment: $e');
    }
  }

  Future<void> _checkAlreadySaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final filesJson = prefs.getStringList('offline_files') ?? [];
      final files = filesJson
          .map((f) => Map<String, dynamic>.from(jsonDecode(f)))
          .toList();
      final materialUrl = widget.post['material_url'];
      final assessmentUrl = widget.post['assessment_url'];
      if (mounted) {
        setState(() {
          _materialSaved =
              materialUrl != null &&
              files.any((f) => f['source_url'] == materialUrl);
          _assessmentSaved =
              assessmentUrl != null &&
              files.any((f) => f['source_url'] == assessmentUrl);
        });
      }
    } catch (e) {
      debugPrint('Check saved: $e');
    }
  }

  // ─── Helpers ───
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

  String _formatScheduleTime(String? scheduledTime) {
    if (scheduledTime == null) return '';
    final dt = DateTime.parse(scheduledTime).toLocal();
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
    final hour = dt.hour > 12
        ? dt.hour - 12
        : dt.hour == 0
        ? 12
        : dt.hour;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, $hour:$min $ampm';
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

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final type = post['type'] as String? ?? 'material';
    final postColor = _getPostColor(type);
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    final hasFiles =
        post['material_url'] != null || post['assessment_url'] != null;
    final allSaved = _materialSaved && _assessmentSaved;

    return Scaffold(
      backgroundColor: context.bgColor,
      // 1. Updated AppBar without redundant title
      appBar: _buildPremiumAppBar(context, textColor),
      body: Stack(
        children: [
          Container(decoration: context.scaffoldGradient),
          SafeArea(
            child: Column(
              // ─── Using a Column to split Scrollable vs Fixed ───
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPremiumHeader(post, type, postColor, textColor),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Divider(thickness: 0.5),
                        ),

                        if (post['instructions'] != null)
                          _buildInstructionBody(
                            post['instructions'],
                            textColor,
                          ),

                        if (hasFiles)
                          _buildPremiumAttachmentSection(post, textColor),

                        _buildUniversalActionZone(
                          post,
                          type,
                          hasFiles,
                          allSaved,
                        ),

                        const SizedBox(height: 8),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Divider(height: 1, thickness: 0.5),
                        ),
                        const SizedBox(height: 8),

                        // ─── Comment List Only ───
                        _buildCommentsHeader(textColor),
                        _buildCommentListOnly(textColor),
                      ],
                    ),
                  ),
                ),

                // ─── 2. DOCKED INPUT BAR (The fixed bottom section) ───
                _buildDockedCommentInput(textColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildPremiumAppBar(
    BuildContext context,
    Color textColor,
  ) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      // ─── INCREASE WIDTH TO SUPPORT THE BOXED ICON ───
      leadingWidth: 70,
      leading: Center(
        child: PressableScale(
          onPressed: () => Navigator.pop(context),
          scaleFactor: 1.0, // ─── FIXED: NO MOVEMENT ───
          opacityFactor: 0.5, // ─── FIXED: DIMMING ONLY ───
          child: Container(
            margin: const EdgeInsets.only(
              left: 8,
            ), // Slight offset from screen edge
            padding: const EdgeInsets.all(10),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: textColor,
              size: 25, // Pro-ratio for AppBar icons
            ),
          ),
        ),
      ),
      title: null,
      centerTitle: true,
    );
  }

  Widget _buildPremiumCommentBubble(
    Map<String, dynamic> comment,
    Color textColor,
  ) {
    final isOwn = comment['user_id'] == _supabase.auth.currentUser?.id;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: GestureDetector(
        // Tapping the bubble opens the edit/delete menu
        onTap: (isOwn || widget.isInstructor)
            ? () => _showCommentOptions(comment)
            : null,
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (_) {
                final url = (comment['avatar_url'] as String?)?.trim();
                final name = comment['user_name'] as String? ?? 'U';
                if (url != null && url.isNotEmpty) {
                  return CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFFD6EBFF),
                    backgroundImage: NetworkImage(url),
                    onBackgroundImageError: (_, __) {},
                  );
                }
                return CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFFD6EBFF),
                  child: Text(
                    name[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF007BFF),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        comment['user_name'] ?? 'User',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(comment['created_at']),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: textColor.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    comment['text'] ?? '',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: textColor.withValues(alpha: 0.9),
                      height: 1.4,
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

  Widget _buildUniversalActionZone(
    Map post,
    String type,
    bool hasFiles,
    bool allSaved,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: [
          // Join 3D Meet Button
          if (type == '3d_meet' && post['scheduled_time'] != null)
            _build3DButton(post['scheduled_time']),
        ],
      ),
    );
  }

  // 1. Separate the list from the input field
  Widget _buildCommentListOnly(Color textColor) {
    if (_comments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Text(
          'No comments yet. Be the first to comment!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: textColor.withValues(alpha: 0.4),
          ),
        ),
      );
    }
    return Column(
      children: _comments
          .map((comment) => _buildPremiumCommentBubble(comment, textColor))
          .toList(),
    );
  }

  // 2. The Floating/Docked Input bar
  Widget _buildDockedCommentInput(Color textColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        border: Border(
          top: BorderSide(color: textColor.withValues(alpha: 0.1), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // ─── UPDATED: Consistent White/Light Blue Circle Avatar ───
          Builder(
            builder: (_) {
              final url = _currentUserAvatarUrl?.trim();
              final name = _currentUserName ?? 'U';
              if (url != null && url.isNotEmpty) {
                return CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFFD6EBFF),
                  backgroundImage: NetworkImage(url),
                  onBackgroundImageError: (_, __) {},
                );
              }
              return CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFD6EBFF), // Matches Assignment design
                child: Text(
                  name[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF007BFF), // Matches Assignment design
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _commentController,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: textColor,
              ),
              decoration: InputDecoration(
                hintText: 'Add class comment...',
                hintStyle: TextStyle(fontSize: 14, color: context.textHint),
                filled: true,
                fillColor: context.isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFFF1F4F8),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  onPressed: _submitComment,
                  icon: _isSubmittingComment
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumHeader(
    Map post,
    String type,
    Color color,
    Color textColor,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Styled Type Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _getPostTypeLabel(type).toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _formatDate(post['created_at']),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: textColor.withValues(alpha:0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            post['title'] ?? '',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: textColor,
              height: 1.2,
            ),
          ),

          if (type == 'assignment') ...[
            const SizedBox(height: 8),
            Text(
              '${post['points'] ?? 100} points',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                color: Color(0xFFFF6B35),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInstructionBody(String text, Color textColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 15,
          color: textColor.withValues(alpha:0.8),
          height: 1.6,
        ),
      ),
    );
  }

  Widget _buildPremiumAttachmentSection(Map post, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              'ATTACHMENTS',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 1.1,
                color: textColor.withValues(alpha:0.4),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha:0.03),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                if (post['material_url'] != null)
                  _buildSimpleFileRow(
                    name: post['material_name'] ?? 'Lesson Material',
                    icon: _getFileTypeIcon(post['material_name'] ?? 'file.pdf'),
                    color: _getFileTypeColor(
                      post['material_name'] ?? 'file.pdf',
                    ),
                    url: post['material_url'],
                    isSaved: _materialSaved,
                  ),
                if (post['assessment_url'] != null)
                  _buildSimpleFileRow(
                    name: post['assessment_name'] ?? 'Assignment Instructions',
                    icon: _getFileTypeIcon(
                      post['assessment_name'] ?? 'file.pdf',
                    ),
                    color: _getFileTypeColor(
                      post['assessment_name'] ?? 'file.pdf',
                    ),
                    url: post['assessment_url'],
                    isSaved: _assessmentSaved,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsHeader(Color textColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Row(
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 18,
            color: textColor.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          Text(
            'Class Comments',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${_comments.length}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _build3DButton(String scheduledTime) {
    final status = _getScheduleStatus(scheduledTime);
    final isLive = status == 'live';
    final isUpcoming = status == 'upcoming';

    Color btnColor;
    IconData btnIcon;
    String btnLabel;
    String btnSub;

    if (isLive) {
      btnColor = const Color(0xFF22C55E);
      btnIcon = Icons.videogame_asset_rounded;
      btnLabel = 'Join 3D Classroom';
      btnSub = 'Session is live now';
    } else if (isUpcoming) {
      btnColor = Colors.grey;
      btnIcon = Icons.videogame_asset_outlined;
      btnLabel = '3D Meet Scheduled';
      btnSub = 'Starts ${_formatScheduleTime(scheduledTime)}';
    } else {
      btnColor = Colors.grey;
      btnIcon = Icons.videogame_asset_off_outlined;
      btnLabel = 'Session Ended';
      btnSub = _formatScheduleTime(scheduledTime);
    }

    return GestureDetector(
      onTap: isLive
          ? () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Launching 3D Classroom...'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isLive ? btnColor : btnColor.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
          boxShadow: isLive
              ? [
                  BoxShadow(
                    color: btnColor.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
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
                Text(
                  btnLabel,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  btnSub,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Simplified File Row
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

  Widget _buildSimpleFileRow({
    required String name,
    required IconData icon,
    required Color color,
    required String url,
    required bool isSaved,
  }) {
    return ListTile(
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
                fileName: name,
                isStudent: !widget.isInstructor,
              ),
            ),
          );
        }
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
                _getFileTypeLabel(name),
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
        name,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          color: context.textPrimary,
        ),
      ),
      subtitle: isSaved
          ? const Text(
              '✓ Saved offline',
              style: TextStyle(fontSize: 11, color: Colors.green),
            )
          : null,
      trailing: Icon(Icons.chevron_right, color: context.textHint, size: 20),
    );
  }

  String _getPostTypeLabel(String type) {
    switch (type) {
      case '3d_meet':
        return '3D Meet';
      case 'material':
        return 'Lesson Material';
      case 'assignment':
        return 'Assignment';
      default:
        return 'Announcement';
    }
  }
}
