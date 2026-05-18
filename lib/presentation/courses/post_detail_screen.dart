// lib/presentation/courses/post_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import 'file_viewer_screen.dart';

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
  bool _isSavingOffline = false;
  bool _materialSaved = false;
  bool _assessmentSaved = false;
  String? _currentUserName;

  @override
  void initState() {
    super.initState();
    _loadComments();
    _loadCurrentUser();
    _checkAlreadySaved();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _supabase.from('users').select('name').eq('id', userId).single();
      if (mounted) setState(() => _currentUserName = data['name']);
    } catch (e) { debugPrint('User load: $e'); }
  }

  Future<void> _loadComments() async {
    try {
      final data = await _supabase
          .from('comments')
          .select()
          .eq('post_id', widget.post['id'])
          .order('created_at', ascending: true);
      if (mounted) setState(() => _comments = List<Map<String, dynamic>>.from(data));
    } catch (e) { debugPrint('Comments: $e'); }
  }

  Future<void> _submitComment() async {
    if (_commentController.text.trim().isEmpty) return;
    final text = _commentController.text.trim();
    setState(() => _isSubmittingComment = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      await _supabase.from('comments').insert({
        'post_id': widget.post['id'],
        'user_id': userId,
        'user_name': _currentUserName ?? 'User',
        'text': text,
        'created_at': DateTime.now().toIso8601String(),
      });
      _commentController.clear();
      await _loadComments();
    } catch (e) { debugPrint('Comment submit: $e'); }
    finally { if (mounted) setState(() => _isSubmittingComment = false); }
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await _supabase.from('comments').delete().eq('id', commentId);
      await _loadComments();
    } catch (e) { debugPrint('Delete comment: $e'); }
  }

  Future<void> _checkAlreadySaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final filesJson = prefs.getStringList('offline_files') ?? [];
      final files = filesJson.map((f) => Map<String, dynamic>.from(jsonDecode(f))).toList();
      final materialUrl = widget.post['material_url'];
      final assessmentUrl = widget.post['assessment_url'];
      if (mounted) {
        setState(() {
          _materialSaved = materialUrl != null &&
              files.any((f) => f['source_url'] == materialUrl);
          _assessmentSaved = assessmentUrl != null &&
              files.any((f) => f['source_url'] == assessmentUrl);
        });
      }
    } catch (e) { debugPrint('Check saved: $e'); }
  }

  Future<void> _saveFilesOffline() async {
    final materialUrl = widget.post['material_url'] as String?;
    final materialName = widget.post['material_name'] as String?;
    final assessmentUrl = widget.post['assessment_url'] as String?;
    final assessmentName = widget.post['assessment_name'] as String?;

    if (materialUrl == null && assessmentUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No files attached to this post.'),
            behavior: SnackBarBehavior.floating));
      return;
    }

    setState(() => _isSavingOffline = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final filesJson = prefs.getStringList('offline_files') ?? [];
      final tempDir = await getTemporaryDirectory();
      int savedCount = 0;

      // Save material
      if (materialUrl != null && !_materialSaved && materialName != null) {
        final response = await http.get(Uri.parse(materialUrl));
        if (response.statusCode == 200) {
          final fileName = '${DateTime.now().millisecondsSinceEpoch}_$materialName';
          final filePath = '${tempDir.path}/$fileName';
          await File(filePath).writeAsBytes(response.bodyBytes);
          filesJson.add(jsonEncode({
            'name': materialName,
            'path': filePath,
            'source_url': materialUrl,
            'course_title': widget.course['title'],
            'post_title': widget.post['title'],
            'saved_at': DateTime.now().toIso8601String(),
            'type': 'material',
          }));
          savedCount++;
        }
      }

      // Save assessment
      if (assessmentUrl != null && !_assessmentSaved && assessmentName != null) {
        final response = await http.get(Uri.parse(assessmentUrl));
        if (response.statusCode == 200) {
          final fileName = '${DateTime.now().millisecondsSinceEpoch}_$assessmentName';
          final filePath = '${tempDir.path}/$fileName';
          await File(filePath).writeAsBytes(response.bodyBytes);
          filesJson.add(jsonEncode({
            'name': assessmentName,
            'path': filePath,
            'source_url': assessmentUrl,
            'course_title': widget.course['title'],
            'post_title': widget.post['title'],
            'saved_at': DateTime.now().toIso8601String(),
            'type': 'assessment',
          }));
          savedCount++;
        }
      }

      await prefs.setStringList('offline_files', filesJson);
      if (mounted) {
        setState(() {
          _materialSaved = materialUrl != null;
          _assessmentSaved = assessmentUrl != null;
          _isSavingOffline = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(savedCount > 0
                ? '$savedCount file${savedCount > 1 ? 's' : ''} saved for offline access! 📥'
                : 'Files already saved offline.'),
            backgroundColor: savedCount > 0 ? Colors.green.shade700 : Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingOffline = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving files: $e'),
              backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating));
      }
    }
  }

  // ─── Helpers ─────────────────────────────────────────────
  String _getScheduleStatus(String? scheduledTime) {
    if (scheduledTime == null) return 'none';
    final scheduled = DateTime.parse(scheduledTime);
    final now = DateTime.now();
    if (now.isBefore(scheduled)) return 'upcoming';
    if (now.isAfter(scheduled.add(const Duration(hours: 2)))) return 'ended';
    return 'live';
  }

  String _formatScheduleTime(String? scheduledTime) {
    if (scheduledTime == null) return '';
    final dt = DateTime.parse(scheduledTime);
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour == 0 ? 12 : dt.hour;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, $hour:$min $ampm';
  }

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[date.month - 1]} ${date.day}';
  }

  Color _getPostColor(String type) {
    switch (type) {
      case '3d_meet': return const Color(0xFF22C55E);
      case 'material': return AppColors.primary;
      case 'assignment': return const Color(0xFFFF6B35);
      case 'announcement': return AppColors.accent;
      default: return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final type = post['type'] as String? ?? 'material';
    final postColor = _getPostColor(type);
    final currentUserId = _supabase.auth.currentUser?.id;
    final hasFiles = post['material_url'] != null || post['assessment_url'] != null;
    final allSaved = _materialSaved && _assessmentSaved;

    return Scaffold(
      backgroundColor: context.bgColor,
      body: Stack(
        children: [
          Container(decoration: context.scaffoldGradient),
          SafeArea(
            child: Column(
              children: [
                // ─── Top Bar ────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: context.cardColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Icon(Icons.arrow_back, color: context.textPrimary, size: 20),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(post['title'] ?? '',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 16,
                              fontWeight: FontWeight.w700, color: context.textPrimary),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),

                // ─── Scrollable Content ──────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // ─── Post Header Card ──────────────
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: context.cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: postColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(_getPostIcon(type), color: postColor, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(post['title'] ?? '',
                                          style: TextStyle(fontFamily: 'Poppins', fontSize: 16,
                                              fontWeight: FontWeight.w700, color: context.textPrimary)),
                                        Row(
                                          children: [
                                            Text(_formatDate(post['created_at']),
                                              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: context.textSecondary)),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: postColor.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Text(_getPostTypeLabel(type),
                                                style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                                                    fontWeight: FontWeight.w600, color: postColor)),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              if (post['instructions'] != null) ...[
                                const SizedBox(height: 14),
                                Divider(color: context.borderColor, height: 1),
                                const SizedBox(height: 14),
                                Text(post['instructions'],
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                                      color: context.textPrimary, height: 1.6)),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // ─── Files ─────────────────────────
                        if (post['material_url'] != null)
                          _buildFileCard(
                            name: post['material_name'] ?? 'Lesson Material',
                            icon: Icons.picture_as_pdf_outlined,
                            color: AppColors.primary,
                            url: post['material_url'],
                            isSaved: _materialSaved,
                          ),

                        if (post['assessment_url'] != null)
                          _buildFileCard(
                            name: post['assessment_name'] ?? 'Assessment Instructions',
                            icon: Icons.assignment_outlined,
                            color: const Color(0xFFFF6B35),
                            url: post['assessment_url'],
                            isSaved: _assessmentSaved,
                          ),

                        // ─── 3D Classroom Button ────────────
                        if (post['scheduled_time'] != null) ...[
                          const SizedBox(height: 4),
                          _build3DButton(post['scheduled_time']),
                          const SizedBox(height: 12),
                        ],

                        // ─── Save Offline Button ────────────
                        if (hasFiles && !widget.isInstructor) ...[
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: (_isSavingOffline || allSaved) ? null : _saveFilesOffline,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: allSaved
                                    ? Colors.green.shade700
                                    : context.cardColor,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: allSaved
                                      ? Colors.green.shade700
                                      : AppColors.primary.withValues(alpha: 0.5),
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_isSavingOffline)
                                    const SizedBox(width: 20, height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                                  else
                                    Icon(
                                      allSaved ? Icons.check_circle_outline : Icons.download_outlined,
                                      color: allSaved ? Colors.white : AppColors.primary,
                                      size: 20,
                                    ),
                                  const SizedBox(width: 10),
                                  Text(
                                    allSaved ? 'Files Saved Offline ✓' : 'Save Files Offline',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: allSaved ? Colors.white : AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // ─── Comments Section ───────────────
                        Container(
                          decoration: BoxDecoration(
                            color: context.cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                                child: Text('Class Comments',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                                      fontWeight: FontWeight.w700, color: context.textPrimary)),
                              ),
                              Divider(color: context.borderColor, height: 1),

                              if (_comments.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Center(
                                    child: Text('No comments yet. Be the first to comment!',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: context.textHint)),
                                  ),
                                ),

                              ..._comments.map((comment) {
                                final isOwn = comment['user_id'] == currentUserId;
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                                        child: Text(
                                          (comment['user_name'] as String).substring(0, 1).toUpperCase(),
                                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                                              fontWeight: FontWeight.w600, color: AppColors.primary)),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: context.bgColor,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: context.borderColor),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(comment['user_name'] ?? '',
                                                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                                                        fontWeight: FontWeight.w600, color: context.textPrimary)),
                                                  const Spacer(),
                                                  Text(_formatDate(comment['created_at']),
                                                    style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: context.textHint)),
                                                  if (isOwn || widget.isInstructor) ...[
                                                    const SizedBox(width: 6),
                                                    GestureDetector(
                                                      onTap: () => _deleteComment(comment['id']),
                                                      child: Icon(Icons.close, size: 14, color: context.textHint),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(comment['text'] ?? '',
                                                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: context.textPrimary)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),

                              // Comment input
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                                      child: Text(
                                        (_currentUserName ?? 'U').substring(0, 1).toUpperCase(),
                                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                                            fontWeight: FontWeight.w600, color: AppColors.primary)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: _commentController,
                                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: context.textPrimary),
                                        decoration: InputDecoration(
                                          hintText: 'Add class comment...',
                                          hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: context.textHint),
                                          filled: true,
                                          fillColor: context.bgColor,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: context.borderColor)),
                                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: context.borderColor)),
                                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                                          suffixIcon: GestureDetector(
                                            onTap: _submitComment,
                                            child: _isSubmittingComment
                                                ? const Padding(padding: EdgeInsets.all(8),
                                                    child: SizedBox(width: 16, height: 16,
                                                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
                                                : const Icon(Icons.send_rounded, color: AppColors.primary, size: 20),
                                          ),
                                        ),
                                        onSubmitted: (_) => _submitComment(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Widget _buildFileCard({
    required String name,
    required IconData icon,
    required Color color,
    required String url,
    required bool isSaved,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(name,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
              fontWeight: FontWeight.w600, color: color),
          maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(isSaved ? '✓ Saved offline' : 'Tap to view',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
              color: isSaved ? Colors.green : context.textHint)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_outlined, color: color, size: 18),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: color.withValues(alpha: 0.5), size: 16),
          ],
        ),
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => FileViewerScreen(url: url, fileName: name),
        )),
      ),
    );
  }

  Widget _build3DButton(String scheduledTime) {
    final status = _getScheduleStatus(scheduledTime);
    final isLive = status == 'live';
    final isUpcoming = status == 'upcoming';
    final Color btnColor = isLive ? const Color(0xFF22C55E) : Colors.grey;
    final String btnText = isLive ? '🎮 Join 3D Classroom' : isUpcoming ? '🎮 Join 3D Classroom' : '🎮 Session Ended';
    final String subText = isLive ? 'Session is live now! 🔴' : _formatScheduleTime(scheduledTime);

    return GestureDetector(
      onTap: isLive ? () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Launching 3D Classroom... 🎮'), behavior: SnackBarBehavior.floating));
      } : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isLive ? btnColor : btnColor.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          boxShadow: isLive ? [BoxShadow(color: btnColor.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))] : [],
        ),
        child: Column(
          children: [
            Text(btnText, style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 2),
            Text(subText, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }

  IconData _getPostIcon(String type) {
    switch (type) {
      case '3d_meet': return Icons.view_in_ar_outlined;
      case 'material': return Icons.bookmark_outline;
      case 'assignment': return Icons.assignment_outlined;
      case 'announcement': return Icons.campaign_outlined;
      default: return Icons.article_outlined;
    }
  }

  String _getPostTypeLabel(String type) {
    switch (type) {
      case '3d_meet': return '3D Meet';
      case 'material': return 'Material';
      case 'assignment': return 'Assignment';
      case 'announcement': return 'Announcement';
      default: return 'Post';
    }
  }
}
