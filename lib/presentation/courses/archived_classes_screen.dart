import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import 'course_detail_screen.dart';
import '../../shared/widgets/page_transitions.dart';

class ArchivedClassesScreen extends StatefulWidget {
  final bool isInstructor;
  const ArchivedClassesScreen({
    super.key,
    required this.isInstructor,
  });

  @override
  State<ArchivedClassesScreen> createState() =>
      _ArchivedClassesScreenState();
}

class _ArchivedClassesScreenState
    extends State<ArchivedClassesScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _archivedCourses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadArchivedCourses();
  }

  Future<void> _loadArchivedCourses() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      List<Map<String, dynamic>> data;
      if (widget.isInstructor) {
        data = List<Map<String, dynamic>>.from(
          await _supabase
              .from('courses')
              .select()
              .eq('instructor_id', userId)
              .eq('is_archived', true)
              .order('created_at', ascending: false),
        );
      } else {
        final enrollments = await _supabase
            .from('enrollments')
            .select('course_id, courses(*)')
            .eq('student_id', userId);
        data = enrollments
            .where((e) =>
                e['courses']?['is_archived'] == true)
            .map((e) =>
                Map<String, dynamic>.from(
                    e['courses'] as Map))
            .toList();
      }

      if (mounted) {
        setState(() => _archivedCourses = data);
      }
    } catch (e) {
      debugPrint('Load archived: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showCourseOptions(
      Map<String, dynamic> course) async {
    if (!widget.isInstructor) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: context.isDark
          ? const Color(0xFF0A1128)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(
                Icons.key_rounded,
                color: AppColors.primary,
              ),
              title: const Text(
                'Show class code',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _showClassCode(course);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.unarchive_rounded,
                color: AppColors.success,
              ),
              title: const Text(
                'Restore class',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _restoreClass(course);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
              title: const Text(
                'Delete class',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: AppColors.error,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _deleteClass(course);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showClassCode(Map<String, dynamic> course) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark
            ? const Color(0xFF0A1128)
            : Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Class Code',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          course['class_code'] ?? 'N/A',
          style: const TextStyle(
            fontFamily: 'Courier',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
            letterSpacing: 4,
          ),
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreClass(
      Map<String, dynamic> course) async {
    try {
      await _supabase
          .from('courses')
          .update({'is_archived': false, 'is_published': true})
          .eq('id', course['id']);
      if (mounted) {
        setState(() => _archivedCourses
            .removeWhere((c) => c['id'] == course['id']));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${course['title']} restored.',
              style: const TextStyle(
                  fontFamily: 'Poppins'),
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        if (context.mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e',
                style: const TextStyle(
                    fontFamily: 'Poppins')),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _deleteClass(
      Map<String, dynamic> course) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark
            ? const Color(0xFF0A1128)
            : Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete class?',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'This will permanently delete the class '
          'and all its content. This cannot be undone.',
          style: TextStyle(
              fontFamily: 'Poppins', fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    color: context.textSecondary)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, true),
            child: const Text('Delete',
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
      await _supabase
          .from('courses')
          .delete()
          .eq('id', course['id']);
      if (mounted) {
        setState(() => _archivedCourses
            .removeWhere(
                (c) => c['id'] == course['id']));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Class deleted.',
                style:
                    TextStyle(fontFamily: 'Poppins')),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Delete class: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.isDark
            ? const Color(0xFF0A1128)
            : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: context.isDark
                ? Colors.white
                : const Color(0xFF0D1B4B),
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Archived Classes',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.isDark
                ? Colors.white
                : const Color(0xFF0D1B4B),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppColors.primary))
          : _archivedCourses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.archive_outlined,
                        size: 72,
                        color: context.isDark
                            ? Colors.white12
                            : Colors.black12,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No archived classes',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: context.textHint,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _archivedCourses.length,
                  itemBuilder: (_, i) {
                    final course =
                        _archivedCourses[i];
                    return Container(
                      margin: const EdgeInsets.only(
                          bottom: 12),
                      decoration: BoxDecoration(
                        color: context.isDark
                            ? const Color(0xFF111E3D)
                            : Colors.white,
                        borderRadius:
                            BorderRadius.circular(14),
                        border: Border.all(
                          color: context.isDark
                              ? AppColors.darkBorder
                              : const Color(
                                  0xFFDDE3F0),
                        ),
                      ),
                      child: ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary
                                .withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(
                                    10),
                          ),
                          child: Center(
                            child: Text(
                              (course['course_code']
                                          as String? ??
                                      'C')
                                  .substring(0, 2)
                                  .toUpperCase(),
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                fontWeight:
                                    FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          course['title'] ?? '',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.isDark
                                ? Colors.white
                                : const Color(
                                    0xFF0D1B4B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${course['course_code'] ?? ''} • Archived',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: context.textHint,
                          ),
                        ),
                        trailing: widget.isInstructor
                            ? IconButton(
                                icon: Icon(
                                  Icons.more_vert_rounded,
                                  color: context.textHint,
                                ),
                                onPressed: () =>
                                    _showCourseOptions(
                                        course),
                              )
                            : null,
                        onTap: () {
                                // Open course in read-only mode
                                // for both instructor and student
                                Navigator.push(
                                  context,
                                  FadeScaleRoute(
                                    builder: (_) => CourseDetailScreen(
                                      course: course,
                                      isInstructor: widget.isInstructor,
                                      initialTab: 0,
                                      isArchived: true,
                                    ),
                                  ),
                                );
                              },
                      ),
                    );
                  },
                ),
    );
  }
}
