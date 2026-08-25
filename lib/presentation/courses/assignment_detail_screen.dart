// lib/presentation/courses/assignment_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import 'file_viewer_screen.dart';
import '../../shared/widgets/pressable_scale.dart';
import 'dart:convert';

class AssignmentDetailScreen extends StatefulWidget {
  final Map<String, dynamic> post;
  final Map<String, dynamic> course;
  final bool isInstructor;
  final String? targetStudentId;

  const AssignmentDetailScreen({
    super.key,
    required this.post,
    required this.course,
    required this.isInstructor,
    this.targetStudentId,
  });

  @override
  State<AssignmentDetailScreen> createState() => _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState extends State<AssignmentDetailScreen>
    with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;

  // Common
  String? _currentUserName;
  String? _currentUserId;
  String? _currentUserAvatarUrl;

  // Instructor
  List<Map<String, dynamic>> _students = [];
  Map<String, Map<String, dynamic>> _submissions = {};
  bool _isLoadingStudents = true;
  bool _acceptSubmissions = true;
  Map<String, dynamic>? _selectedStudent;
  Map<String, dynamic>? _selectedSubmission;
  List<Map<String, dynamic>> _privateComments = [];
  final _gradeController = TextEditingController();
  final _privateCommentController = TextEditingController();
  bool _isSubmittingComment = false;
  bool _isGrading = false;
  bool _isLoadingPrivate = false;

  // Student
  Map<String, dynamic>? _mySubmission;
  bool _isLoadingSubmission = true;
  List<Map<String, dynamic>> _myPrivateComments = [];
  final _myPrivateCommentController = TextEditingController();
  bool _isSubmittingMyComment = false;
  bool _isUploadingWork = false;
  List<String> _myWorkFileUrls = [];
  List<String> _myWorkFileNames = [];

  bool _isYourWorkExpanded = false;

  List<Map<String, dynamic>> _classComments = [];
  bool _isLoadingComments = true;
  final _classCommentController = TextEditingController();
  RealtimeChannel? _commentChannel;
  RealtimeChannel? _postChannel;

  @override
  void initState() {
    super.initState();
    _loadClassComments();
    _tabController = TabController(
      length: widget.isInstructor ? 2 : 1,
      vsync: this,
    );
    _subscribeToComments();
    _acceptSubmissions = widget.post['accept_submissions'] ?? true;
    _subscribeToPostChanges();
    _loadCurrentUser();
    if (widget.isInstructor) {
      _loadStudentsAndSubmissions();
    } else {
      _loadMySubmission();
    }
  }

  @override
  void dispose() {
    _commentChannel?.unsubscribe();
    _postChannel?.unsubscribe();
    _classCommentController.dispose();
    _tabController.dispose();
    _gradeController.dispose();
    _privateCommentController.dispose();
    _myPrivateCommentController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════
  // DATA LOADING
  // ════════════════════════════════════════════════════════

  Future<void> _loadCurrentUser() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      _currentUserId = userId;
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
      debugPrint('User: $e');
    }
  }

  Future<void> _loadClassComments() async {
    try {
      // Use widget.post['id'] to make sure we are looking at the right assignment
      final data = await _supabase
          .from('comments')
          .select('*, users(avatar_url)')
          .eq('post_id', widget.post['id'])
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _classComments = List<Map<String, dynamic>>.from(data).map((c) {
            return {...c, 'avatar_url': c['users']?['avatar_url']};
          }).toList();
          _isLoadingComments = false;
        });
        debugPrint('DEBUG: Loaded ${_classComments.length} comments');
      }
    } catch (e) {
      debugPrint('DEBUG: Load Comments Error: $e');
    }
  }

  Future<void> _submitClassComment() async {
    final text = _classCommentController.text.trim();
    if (text.isEmpty) return;

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // 1. Save the comment
      await _supabase.from('comments').insert({
        'post_id': widget.post['id'],
        'user_id': userId,
        'user_name': _currentUserName ?? 'User',
        'text': text,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // 2. SEND NOTIFICATIONS
      if (widget.isInstructor) {
        // Instructor commented: Fetch all students to notify the whole class
        final students = await _supabase.from('enrollments').select('student_id').eq('course_id', widget.course['id']);
        if (students.isNotEmpty) {
          final List<Map<String, dynamic>> batchNotifs = students.map((s) => {
            'user_id': s['student_id'],
            'course_id': widget.course['id'],
            'post_id': widget.post['id'],
            'type': 'class_comment',
            'title': 'Instructor commented',
            'body': '${widget.post['title']}: $text',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          }).toList();
          await _supabase.from('notifications').insert(batchNotifs);
        }
      } else {
        // Student commented: Notify only the Instructor
        await _supabase.from('notifications').insert({
          'user_id': widget.course['instructor_id'],
          'course_id': widget.course['id'],
          'post_id': widget.post['id'],
          'type': 'class_comment',
          'title': 'New comment from $_currentUserName',
          'body': '${widget.post['title']}: $text',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      _classCommentController.clear();
      _loadClassComments(); 
    } catch (e) { debugPrint('Notif Error: $e'); }
  }

  Future<void> _loadMySubmission() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      if (mounted) setState(() => _isLoadingSubmission = true);

      final assessmentId = await _getOrCreateAssessmentId();

      final submission = await _supabase
          .from('submissions')
          .select()
          .eq('assessment_id', assessmentId)
          .eq('student_id', userId)
          .maybeSingle();

      final commentData = await _supabase
          .from('private_comments')
          .select()
          .eq('post_id', widget.post['id'])
          .eq('student_id', userId)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _mySubmission = submission;

          if (submission != null) {
            final rawUrl = submission['file_url'];
            final rawName = submission['file_name'];
            
            // Decodes JSON lists of files, or handles legacy single file strings
            if (rawUrl != null && rawUrl.startsWith('[')) {
              _myWorkFileUrls = List<String>.from(jsonDecode(rawUrl));
              _myWorkFileNames = List<String>.from(jsonDecode(rawName));
            } else if (rawUrl != null) {
              _myWorkFileUrls = [rawUrl];
              _myWorkFileNames = [rawName ?? 'File'];
            } else {
              _myWorkFileUrls = [];
              _myWorkFileNames = [];
            }
          } else {
            _myWorkFileUrls = [];
            _myWorkFileNames = [];
          }

          _myPrivateComments = List<Map<String, dynamic>>.from(commentData);
          _isLoadingStudents = false;
          _isLoadingSubmission = false;
        });
      }
    } catch (e) {
      debugPrint('Load my submission error: $e');
      if (mounted) {
        setState(() {
          _isLoadingStudents = false;
          _isLoadingSubmission = false;
        });
      }
    }
  }

  Future<void> _loadStudentsAndSubmissions() async {
    try {
      // 1. Get the Assessment ID
      final assessmentId = await _getOrCreateAssessmentId();

      // 2. Fetch all students enrolled in this course in ONE query
      // This joins the enrollments and users tables automatically
      final enrollmentsData = await _supabase
          .from('enrollments')
          .select('student_id, users(id, name, avatar_url)')
          .eq('course_id', widget.course['id']);

      final List<Map<String, dynamic>> studentsList = (enrollmentsData as List)
          .map((e) {
            return Map<String, dynamic>.from(e['users'] as Map);
          })
          .toList();

      // 3. Fetch all submissions for this assessment
      // Because we added the Unique Constraint, we don't need to filter duplicates anymore!
      final submissionsData = await _supabase
          .from('submissions')
          .select()
          .eq('assessment_id', assessmentId);

      final submissionsMap = <String, Map<String, dynamic>>{};
      for (final item in submissionsData) {
        final row = Map<String, dynamic>.from(item as Map);
        submissionsMap[row['student_id'].toString()] = row;
      }

      if (mounted) {
        setState(() {
          _students = studentsList;
          _submissions = submissionsMap;

          // Refresh the selected student's specific submission if one is open
          if (_selectedStudent != null) {
            _selectedSubmission =
                _submissions[_selectedStudent!['id'].toString()];
          } else if (widget.targetStudentId != null) {
            // Jump straight to the requested student's grading view
            // (e.g. navigated here from the Reports drill-down).
            for (final s in studentsList) {
              if (s['id'].toString() == widget.targetStudentId) {
                _selectedStudent = s;
                _selectedSubmission = submissionsMap[s['id'].toString()];
                break;
              }
            }
          }

          _isLoadingStudents = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading class data: $e');
      if (mounted) setState(() => _isLoadingStudents = false);
    }
  }

  bool _submissionHasFile(Map<String, dynamic>? submission) {
    final fileUrl = submission?['file_url'];
    return fileUrl != null && fileUrl.toString().trim().isNotEmpty;
  }

  bool _submissionIsTurnedIn(Map<String, dynamic>? submission) {
    final submittedAt = submission?['submitted_at'];
    return submittedAt != null && submittedAt.toString().trim().isNotEmpty;
  }

  Future<Map<String, dynamic>?> _loadSingleSubmission(String studentId) async {
    try {
      final assessmentId = await _getOrCreateAssessmentId();

      final submissionsData = await _supabase
          .from('submissions')
          .select()
          .eq('assessment_id', assessmentId)
          .eq('student_id', studentId)
          .order('submitted_at', ascending: false, nullsFirst: false)
          .order('created_at', ascending: false, nullsFirst: false);

      Map<String, dynamic>? bestSubmission;
      for (final item in submissionsData) {
        final row = Map<String, dynamic>.from(item as Map);
        final rowTurnedIn = _submissionIsTurnedIn(row);
        final rowHasFile = _submissionHasFile(row);

        if (rowTurnedIn && rowHasFile) {
          bestSubmission = row;
          break;
        }
        if (bestSubmission == null) {
          bestSubmission = row;
          continue;
        }
        if ((rowTurnedIn && !_submissionIsTurnedIn(bestSubmission)) ||
            (rowTurnedIn == _submissionIsTurnedIn(bestSubmission) &&
                rowHasFile &&
                !_submissionHasFile(bestSubmission))) {
          bestSubmission = row;
        }
      }

      if (bestSubmission == null) {
        if (mounted) {
          setState(() {
            _submissions.remove(studentId);
            _selectedSubmission = null;
          });
        }
        return null;
      }

      if (mounted) {
        setState(() {
          _submissions[studentId] = bestSubmission!;
          _selectedSubmission = bestSubmission;
        });
      }
      return bestSubmission;
    } catch (e) {
      debugPrint('Load single submission error: $e');
      return _submissions[studentId];
    }
  }

  void _subscribeToPostChanges() {
    final postId = widget.post['id'] as String?;
    if (postId == null) return;
    _postChannel = _supabase
        .channel('post_$postId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'posts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: postId,
          ),
          callback: (payload) {
            if (mounted) {
              setState(() {
                final updated = payload.newRecord;
                widget.post['accept_submissions'] =
                    updated['accept_submissions'];
                widget.post['due_date'] = updated['due_date'];
                _acceptSubmissions =
                    updated['accept_submissions'] ?? _acceptSubmissions;
              });
            }
          },
        )
        .subscribe();
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
          callback: (payload) => _loadClassComments(), // Refresh list on change
        )
        .subscribe();
  }

  void _showEditCommentDialog(Map<String, dynamic> comment, String postId) {
    final controller = TextEditingController(text: comment['text']);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: const Text(
          'Edit Comment',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: context.textPrimary, fontFamily: 'Poppins'),
          decoration: InputDecoration(
            hintText: 'Edit message...',
            hintStyle: TextStyle(color: context.textHint),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newText = controller.text.trim();
              if (newText.isEmpty) return;

              await _supabase
                  .from('comments')
                  .update({'text': newText})
                  .eq('id', comment['id']);

              if (mounted) {
                Navigator.pop(context);
                _loadClassComments(); // Refresh the comment list
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ─── 2. MISSING DELETE METHOD ───
  Future<void> _deleteComment(String commentId, String postId) async {
    try {
      await _supabase.from('comments').delete().eq('id', commentId);
      // Refresh the list immediately
      _loadClassComments();
    } catch (e) {
      debugPrint('Delete error: $e');
    }
  }

  void _showCommentOptions(Map<String, dynamic> comment) {
    final isOwn = comment['user_id'] == _supabase.auth.currentUser?.id;
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

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
                  _showEditCommentDialog(comment, widget.post['id']);
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
                  _deleteComment(comment['id'], widget.post['id']);
                },
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _loadPrivateComments(String studentId) async {
    setState(() => _isLoadingPrivate = true);
    try {
      final data = await _supabase
          .from('private_comments')
          .select()
          .eq('post_id', widget.post['id'])
          .eq('student_id', studentId)
          .order('created_at', ascending: true);
      if (mounted) {
        setState(() {
          _privateComments = List<Map<String, dynamic>>.from(data);
          _isLoadingPrivate = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingPrivate = false);
    }
  }

  Future<String> _getOrCreateAssessmentId() async {
    final postId = widget.post['id']?.toString();

    if (postId == null || postId.isEmpty) {
      throw Exception('Post ID is missing. Cannot create assessment.');
    }

    final existing = await _supabase
        .from('assessments')
        .select('id')
        .eq('id', postId)
        .maybeSingle();

    if (existing != null && existing['id'] != null) {
      return existing['id'].toString();
    }

    final assessmentData = <String, dynamic>{
      'id': postId,
      'course_id': widget.course['id'],
      'title': widget.post['title'] ?? 'Assignment',
      'type': widget.post['type'] ?? 'assignment',
    };

    final moduleId =
        widget.post['module_id'] ??
        widget.post['moduleId'] ??
        widget.course['module_id'];
    if (moduleId != null) {
      assessmentData['module_id'] = moduleId;
    }

    try {
      await _supabase.from('assessments').insert(assessmentData);
    } on PostgrestException catch (e) {
      // 23505 means another request already created the same assessment.
      if (e.code != '23505') {
        rethrow;
      }
    }

    return postId;
  }

  // ════════════════════════════════════════════════════════
  // STUDENT ACTIONS
  // ════════════════════════════════════════════════════════

  Future<void> _pickAndUploadWork() async {
    if (_myWorkFileUrls.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can upload a maximum of 5 files.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg', 'mp4'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    if (_myWorkFileUrls.length + result.files.length > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exceeds 5-file limit (Current: ${_myWorkFileUrls.length}).'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isUploadingWork = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('You must be logged in before uploading work.');
      }

      if (_currentUserName == null) await _loadCurrentUser();
      final assessmentId = await _getOrCreateAssessmentId();

      List<String> newUrls = List.from(_myWorkFileUrls);
      List<String> newNames = List.from(_myWorkFileNames);

      for (final file in result.files) {
        final bytes = file.bytes ?? await File(file.path!).readAsBytes();
        final safeFileName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final storagePath = '$assessmentId/$userId/${DateTime.now().millisecondsSinceEpoch}_$safeFileName';

        await _supabase.storage
            .from('submissions')
            .uploadBinary(storagePath, bytes);
        final url = _supabase.storage
            .from('submissions')
            .getPublicUrl(storagePath);

        newUrls.add(url);
        newNames.add(file.name);
      }

      final serializedUrls = jsonEncode(newUrls);
      final serializedNames = jsonEncode(newNames);

      if (_mySubmission == null) {
        final data = await _supabase
            .from('submissions')
            .upsert(
              {
                'assessment_id': assessmentId,
                'course_id': widget.course['id'],
                'student_id': userId,
                'student_name': _currentUserName ?? 'Student',
                'type': widget.post['type'] ?? 'assignment',
                'file_url': serializedUrls,
                'file_name': serializedNames,
                'max_score': _maxPoints,
                'is_graded': false,
                'is_returned': false,
              },
              onConflict: 'student_id, assessment_id',
            )
            .select()
            .single();

        if (mounted) {
          setState(() {
            _mySubmission = Map<String, dynamic>.from(data);
            _myWorkFileUrls = newUrls;
            _myWorkFileNames = newNames;
          });
        }
      } else {
        await _supabase
            .from('submissions')
            .update({
              'file_url': serializedUrls,
              'file_name': serializedNames,
              'student_name': _currentUserName ?? 'Student',
            })
            .eq('id', _mySubmission!['id']);

        if (mounted) {
          setState(() {
            _mySubmission!['file_url'] = serializedUrls;
            _mySubmission!['file_name'] = serializedNames;
            _myWorkFileUrls = newUrls;
            _myWorkFileNames = newNames;
          });
        }
      }

      // ─── REMOVED: Auto turn-in line has been deleted ───
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result.files.length} file(s) attached successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingWork = false);
    }
  }

  Future<void> _removeWorkAtIndex(int index) async {
    if (_hasTurnedIn || _isGraded) return;

    List<String> newUrls = List.from(_myWorkFileUrls);
    List<String> newNames = List.from(_myWorkFileNames);

    newUrls.removeAt(index);
    newNames.removeAt(index);

    try {
      await _supabase
          .from('submissions')
          .update({
            'file_url': newUrls.isEmpty ? null : jsonEncode(newUrls),
            'file_name': newNames.isEmpty ? null : jsonEncode(newNames),
          })
          .eq('id', _mySubmission!['id']);

      setState(() {
        _myWorkFileUrls = newUrls;
        _myWorkFileNames = newNames;
        _mySubmission!['file_url'] = newUrls.isEmpty ? null : jsonEncode(newUrls);
        _mySubmission!['file_name'] = newNames.isEmpty ? null : jsonEncode(newNames);
      });
    } catch (e) {
      debugPrint('Remove work: $e');
    }
  }

  Future<void> _unsubmitWork() async {
    if (_mySubmission == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark
            ? const Color(0xFF0A1128)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Unsubmit work?',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Your submission will be withdrawn. You can re-upload and turn in again.',
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
              'Unsubmit',
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

    setState(() => _isUploadingWork = true); // Show loading spinner
    try {
      // 1. Update Supabase
      await _supabase
          .from('submissions')
          .update({'submitted_at': null}) // Clear the turned-in timestamp
          .eq('id', _mySubmission!['id']);

      // 2. Reload from the database so the file lists/status are decoded correctly
      await _loadMySubmission();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unsubmitted. You can now edit your work.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Unsubmit error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingWork = false);
    }
  }

  Future<void> _markAsDone() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('You must be logged in before submitting work.');
      }

      if (_isGraded) return;

      if (_isPastDue) {
        throw Exception('The deadline has passed.');
      }

      // ─── SAFE ERROR HANDLING: Check if files list is empty ───
      if (_myWorkFileUrls.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please attach at least one file before turning in.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return; // Exit early without saving or sending notifications
      }

      if (_currentUserName == null) await _loadCurrentUser();
      final assessmentId = await _getOrCreateAssessmentId();
      final now = DateTime.now().toIso8601String();

      if (_mySubmission == null) {
        final data = await _supabase
            .from('submissions')
            .upsert(
              {
                'assessment_id': assessmentId,
                'course_id': widget.course['id'],
                'student_id': userId,
                'student_name': _currentUserName ?? 'Student',
                'type': widget.post['type'] ?? 'assignment',
                'file_url': jsonEncode(_myWorkFileUrls),
                'file_name': jsonEncode(_myWorkFileNames),
                'submitted_at': now,
                'max_score': _maxPoints,
                'is_graded': false,
                'is_returned': false,
              },
              onConflict: 'student_id, assessment_id',
            )
            .select()
            .single();

        if (mounted) {
          setState(() => _mySubmission = Map<String, dynamic>.from(data));
        }
      } else {
        await _supabase
            .from('submissions')
            .update({
              'submitted_at': now,
              'student_name': _currentUserName ?? 'Student',
              'file_url': jsonEncode(_myWorkFileUrls),
              'file_name': jsonEncode(_myWorkFileNames),
              'max_score': _maxPoints,
              'is_graded': false,
              'is_returned': false,
            })
            .eq('id', _mySubmission!['id']);

        if (mounted) {
          setState(() {
            _mySubmission!['submitted_at'] = now;
            _mySubmission!['file_url'] = jsonEncode(_myWorkFileUrls);
            _mySubmission!['file_name'] = jsonEncode(_myWorkFileNames);
            _mySubmission!['max_score'] = _maxPoints;
            _mySubmission!['is_graded'] = false;
            _mySubmission!['is_returned'] = false;
          });
        }
      }

      await _loadMySubmission();

      try {
        await _supabase.from('notifications').insert({
          'user_id': widget.course['instructor_id'],
          'course_id': widget.course['id'],
          'post_id': widget.post['id'],
          'sender_id': userId,
          'type': 'submission_received',
          'title': 'New Submission: $_currentUserName',
          'body': 'Work turned in for: ${widget.post['title']}',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (notifErr) {
        debugPrint('Notif Fail: $notifErr');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Assignment turned in!'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Turn in error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _submitMyPrivateComment() async {
    if (_myPrivateCommentController.text.trim().isEmpty) return;
    final text = _myPrivateCommentController.text.trim();
    setState(() => _isSubmittingMyComment = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      await _supabase.from('private_comments').insert({
        'post_id': widget.post['id'],
        'student_id': userId,
        'sender_id': userId,
        'sender_name': _currentUserName ?? 'Student',
        'text': text,
        'created_at': DateTime.now().toIso8601String(),
      });
      _myPrivateCommentController.clear();
      await _loadMySubmission();
    } catch (e) {
      debugPrint('Private comment: $e');
    } finally {
      if (mounted) setState(() => _isSubmittingMyComment = false);
    }
  }

  // ════════════════════════════════════════════════════════
  // INSTRUCTOR ACTIONS
  // ════════════════════════════════════════════════════════

  Future<void> _submitPrivateComment(String studentId) async {
    if (_privateCommentController.text.trim().isEmpty) return;
    final text = _privateCommentController.text.trim();
    setState(() => _isSubmittingComment = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      await _supabase.from('private_comments').insert({
        'post_id': widget.post['id'],
        'student_id': studentId,
        'sender_id': userId,
        'sender_name': _currentUserName ?? 'Instructor',
        'text': text,
        'created_at': DateTime.now().toIso8601String(),
      });
      _privateCommentController.clear();
      await _loadPrivateComments(studentId);
      await _supabase.from('notifications').insert({
        'user_id': studentId,
        'course_id': widget.course['id'],
        'post_id': widget.post['id'],
        'type': 'private_comment',
        'title': 'New private comment on ${widget.post['title']}',
        'body': text,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Instructor comment: $e');
    } finally {
      if (mounted) setState(() => _isSubmittingComment = false);
    }
  }

  Future<void> _gradeSubmission(String studentId) async {
    final score = int.tryParse(_gradeController.text.trim());
    if (score == null || score < 0 || score > _maxPoints) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Enter a valid score (0-$_maxPoints)'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _isGrading = true);
    try {
      final submission =
          await _loadSingleSubmission(studentId) ??
          _submissions[studentId] ??
          _selectedSubmission;
      if (!_submissionIsTurnedIn(submission)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This student has not turned in the assignment yet.',
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      if (!_submissionHasFile(submission)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This student turned in the assignment, but no file is attached.',
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      await _supabase
          .from('submissions')
          .update({
            'score': score,
            'is_graded': true,
            'is_returned': true,
            'returned_at': DateTime.now().toIso8601String(),
          })
          .eq('id', submission!['id']);

      // ─── Assignment XP: score × 0.20, +streak bonus on a perfect score ───
      // Assignment grading does NOT change the streak — only 3D Meet does.
      // Note: this formula assumes a 0-100 scale; an assignment whose
      // _maxPoints isn't 100 will get disproportionate XP and can never
      // trigger the streak bonus (which requires score == 100 exactly).
      final oldXpAwarded = (submission['xp_awarded'] as int?) ?? 0;

      final baseXp = (score * 0.20).round();
      int xpAwarded = baseXp;

      final studentData = await _supabase
          .from('users')
          .select('streak')
          .eq('id', studentId)
          .single();
      final currentStreak = (studentData['streak'] as int?) ?? 0;

      if (score == 100 && currentStreak > 0) {
        xpAwarded = baseXp + (currentStreak * 10);
      }

      await _supabase
          .from('submissions')
          .update({'xp_awarded': xpAwarded})
          .eq('id', submission['id']);

      // RLS blocks instructors from updating a student's xp column
      // directly, so this goes through a SECURITY DEFINER RPC instead.
      // Award only the delta so re-grading a submission doesn't
      // double-count XP already granted for it.
      final xpDifference = xpAwarded - oldXpAwarded;
      if (xpDifference != 0) {
        await _supabase.rpc(
          'increment_student_xp',
          params: {'p_student_id': studentId, 'p_xp': xpDifference},
        );
      }

      await _supabase.from('notifications').insert({
        'user_id': studentId, // Student receives this
        'course_id': widget.course['id'],
        'post_id': widget.post['id'],
        'type': 'assignment_graded',
        'title': 'Assignment Graded!',
        'body':
            'You got $score/$_maxPoints on ${widget.post['title']}. '
            '+$xpAwarded XP earned!',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _loadStudentsAndSubmissions();
      if (mounted) {
        setState(() {
          _selectedSubmission = _submissions[studentId] ?? _selectedSubmission;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Grade submitted!'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGrading = false);
    }
  }

  Future<void> _toggleAcceptSubmissions() async {
    try {
      final newValue = !_acceptSubmissions;
      await _supabase
          .from('posts')
          .update({'accept_submissions': newValue})
          .eq('id', widget.post['id']);
      if (mounted) setState(() => _acceptSubmissions = newValue);
    } catch (e) {
      debugPrint('Toggle: $e');
    }
  }

  // ════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    final date = DateTime.parse(dateStr);
    final now = DateTime.now();
    final diff = date.difference(now);
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
    final hour = date.hour > 12
        ? date.hour - 12
        : date.hour == 0
        ? 12
        : date.hour;
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    final min = date.minute.toString().padLeft(2, '0');
    if (diff.inDays == 0) return 'Due today, $hour:$min $ampm';
    if (diff.inDays == 1) return 'Due tomorrow, $hour:$min $ampm';
    if (diff.inDays < 0) {
      return 'Past due ${months[date.month - 1]} ${date.day}';
    }
    return 'Due ${months[date.month - 1]} ${date.day}, $hour:$min $ampm';
  }

  DateTime? get _dueDate {
    final value = widget.post['due_date'];
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  bool get _isPastDue {
    final due = _dueDate;
    return due != null && DateTime.now().isAfter(due);
  }

  bool get _hasTurnedIn => _submissionIsTurnedIn(_mySubmission);
  bool get _hasAttachedFile => _myWorkFileUrls.isNotEmpty;
  bool get _isGraded => _mySubmission?['is_graded'] == true;
  int get _maxPoints =>
      int.tryParse((widget.post['points'] ?? 100).toString()) ?? 100;
  int get _turnedInCount =>
      _submissions.values.where((s) => s['submitted_at'] != null).length;
  int get _gradedCount =>
      _submissions.values.where((s) => s['is_graded'] == true).length;
  int get _assignedCount => _students.length - _turnedInCount;

  // ════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: Stack(
        children: [
          Container(decoration: context.scaffoldGradient),
          SafeArea(
            child: Column(
              children: [
                // ─── Top Bar ──────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      // ─── PREMIUM OPACITY-ONLY BACK BUTTON ───
                      PressableScale(
                        onPressed: _selectedStudent != null
                            ? () => setState(() {
                                _selectedStudent = null;
                                _selectedSubmission = null;
                                _privateComments = [];
                              })
                            : () => Navigator.pop(context),
                        scaleFactor: 1.0, // ─── FIXED: No shrink animation ───
                        opacityFactor:
                            0.5, // ─── FIXED: Dimming feedback only ───
                        child: Container(
                          padding: const EdgeInsets.all(
                            10,
                          ), // Standardized padding
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: context.textPrimary,
                            size: 25, // Premium size for top bar icons
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          _selectedStudent != null
                              ? _selectedStudent!['name'] ?? 'Student'
                              : widget.post['title'] ?? '',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                // ─── Instructor Tabs ───────────────────────
                if (widget.isInstructor && _selectedStudent == null) ...[
                  Container(
                    color: context.cardColor,
                    child: TabBar(
                      controller: _tabController,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: context.textSecondary,
                      indicatorColor: AppColors.primary,
                      indicatorWeight: 2.5,
                      labelStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                      ),
                      tabs: const [
                        Tab(text: 'Instructions'),
                        Tab(text: 'Student Work'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildInstructionsTab(),
                        _buildStudentWorkTab(),
                      ],
                    ),
                  ),
                ] else if (_selectedStudent != null) ...[
                  Expanded(child: _buildInstructorStudentView()),
                ] else ...[
                  // Student view
                  Expanded(child: _buildStudentView()),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // STUDENT VIEW (Google Classroom style)
  // ════════════════════════════════════════════════════════

  Widget _buildStudentView() {
    final post = widget.post;
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    final dueDate = post['due_date'];
    final isPastDue =
        dueDate != null &&
        DateTime.parse(dueDate).toLocal().isBefore(DateTime.now());

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── 1. MINIMALIST HEADER ───
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (dueDate != null)
                        Text(
                          _formatDate(dueDate),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isPastDue
                                ? AppColors.error
                                : textColor.withValues(alpha: 0.5),
                          ),
                        ),
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 8),
                      Text(
                        '$_maxPoints points',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF6B35),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(thickness: 0.5),
                ),

                // ─── 2. CONTENT ───
                if (post['instructions'] != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Text(
                      post['instructions'],
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        color: textColor.withValues(alpha: 0.8),
                        height: 1.6,
                      ),
                    ),
                  ),

                // ─── 3. ATTACHMENTS ───
                if (post['assessment_url'] != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Text(
                      'ATTACHMENTS',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 1.1,
                        color: textColor.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: textColor.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: _buildAttachmentTile(
                      post['assessment_name'] ?? 'File',
                      post['assessment_url'],
                      _getFileTypeIcon(post['assessment_name'] ?? 'file.pdf'),
                      _getFileTypeColor(post['assessment_name'] ?? 'file.pdf'),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(thickness: 0.5),
                ),

                // ─── 4. NEW CLASS COMMENTS GATEWAY ───
                _buildClassCommentsEntry(textColor),

                const SizedBox(height: 120), // Room for the Work Panel
              ],
            ),
          ),
        ),
        // Sticky Panel
        _buildYourWorkPanel(isPastDue),
      ],
    );
  }

  Widget _buildClassCommentsEntry(Color textColor) {
    return PressableScale(
      onPressed: () => _showClassCommentsSheet(),
      scaleFactor: 1.0, // No shrink
      opacityFactor: 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Row(
          children: [
            const Icon(
              Icons.forum_outlined,
              size: 20,
              color: AppColors.primary,
            ),
            const SizedBox(width: 12),
            Text(
              'Class comments',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: textColor,
              ),
            ),
            const Spacer(),
            _buildCommentCountBadge(textColor),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: textColor.withValues(alpha: 0.2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYourWorkPanel(bool isPastDue) {
    if (_isLoadingSubmission) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: const Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
      );
    }
    final canSubmit = _acceptSubmissions && !isPastDue;
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.fastOutSlowIn,
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ─── DRAG HANDLE / TOGGLE ───
          GestureDetector(
            onTap: () =>
                setState(() => _isYourWorkExpanded = !_isYourWorkExpanded),
            behavior: HitTestBehavior.opaque,
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: context.borderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(
                    children: [
                      Text(
                        'Your work',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                      const Spacer(),
                      // Status Badge
                      _buildStatusBadge(),
                      const SizedBox(width: 12),
                      Icon(
                        _isYourWorkExpanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_up_rounded,
                        color: textColor.withValues(alpha: 0.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ─── EXPANDABLE CONTENT ───
          if (_isYourWorkExpanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Graded result (score + XP earned)
                  if (_isGraded) ...[
                    _buildGradedResultCard(),
                    const SizedBox(height: 16),
                  ],

                  // Attachments List
                  if (_myWorkFileNames.isNotEmpty) // Changed this line
                    _buildUserFileTile(textColor, canSubmit)
                  else
                    _buildEmptyWorkState(),

                  const SizedBox(height: 16),

                  // Private Comments Gateway
                  GestureDetector(
                    onTap: () => _showPrivateCommentsSheet(),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B35).withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lock_rounded,
                            color: Color(0xFFFF6B35),
                            size: 16,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _myPrivateComments.isEmpty
                                ? 'Private comments'
                                : '${_myPrivateComments.length} private comments',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              color: Color(0xFFFF6B35),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFFFF6B35),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ─── ACTION BUTTONS (Always at bottom) ───
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            child: Column(
              children: [
                if (!canSubmit && !_hasTurnedIn)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lock_clock_rounded,
                            color: AppColors.error,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isPastDue
                                      ? 'Deadline has passed'
                                      : 'Submissions are closed',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.error,
                                  ),
                                ),
                                Text(
                                  isPastDue
                                      ? 'The due date for this assignment has passed. '
                                            'Contact your instructor to request an '
                                            'extension.'
                                      : 'Your instructor has closed submissions. You '
                                            'can still upload files but cannot turn in '
                                            'until submissions reopen.',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    color: AppColors.error.withValues(alpha: 0.8),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_isYourWorkExpanded &&
                    canSubmit &&
                    !_hasTurnedIn &&
                    !_isGraded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildActionButton(
                      label: 'Add work',
                      onTap: _pickAndUploadWork,
                      color: AppColors.primary.withValues(alpha: 0.1),
                      textColor: AppColors.primary,
                    ),
                  ),

                // Turn In / Unsubmit Button
                _buildFinalSubmitButton(canSubmit),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showClassCommentsSheet() {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Allows it to take up more space
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        // Enables real-time updates inside the sheet
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.8,
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  // --- Header & Drag Handle ---
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
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Text(
                          'Class Comments',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _buildCommentCountBadge(textColor),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: textColor.withValues(alpha: 0.4),
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // --- Scrollable Comment List ---
                  Expanded(
                    child: _classComments.isEmpty
                        ? _buildNoCommentsPlaceholder()
                        : ListView.builder(
                            padding: const EdgeInsets.all(20),
                            itemCount: _classComments.length,
                            itemBuilder: (ctx, index) {
                              final comment = _classComments[index];
                              return _buildPremiumCommentBubble(
                                comment,
                                textColor,
                              );
                            },
                          ),
                  ),

                  // --- Google Classroom Style Input Bar ---
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      border: Border(
                        top: BorderSide(color: context.borderColor, width: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
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
                          child: TextField(
                            controller: _classCommentController,
                            style: TextStyle(color: textColor, fontSize: 14),
                            autofocus: false,
                            decoration: InputDecoration(
                              hintText: 'Add class comment...',
                              hintStyle: TextStyle(
                                color: context.textHint,
                                fontSize: 14,
                              ),
                              filled: true,
                              fillColor: context.isDark
                                  ? context.bgColor
                                  : const Color(0xFFEBEBEB),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              suffixIcon: IconButton(
                                icon: const Icon(
                                  Icons.send_rounded,
                                  color: AppColors.primary,
                                  size: 20,
                                ),
                                onPressed: () async {
                                  // Submit logic
                                  await _submitClassComment();
                                  // Refresh the sheet UI
                                  setSheetState(() {});
                                },
                              ),
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
        },
      ),
    );
  }

  void _showPrivateCommentsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            height: MediaQuery.of(ctx).size.height * 0.75,
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
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
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        color: Color(0xFFFF6B35),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Private Comments',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(color: context.borderColor, height: 1),
                Expanded(
                  child: _myPrivateComments.isEmpty
                      ? Center(
                          child: Text(
                            'No private comments yet.',
                            style: TextStyle(
                              color: context.textHint,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _myPrivateComments.length,
                          itemBuilder: (ctx, i) {
                            final c = _myPrivateComments[i];
                            final isOwn = c['sender_id'] == _currentUserId;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: isOwn
                                    ? MainAxisAlignment.end
                                    : MainAxisAlignment.start,
                                children: [
                                  if (!isOwn) ...[
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: const Color(
                                        0xFFFF6B35,
                                      ).withValues(alpha: 0.15),
                                      child: Text(
                                        (c['sender_name'] as String)
                                            .substring(0, 1)
                                            .toUpperCase(),
                                        style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFFF6B35),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isOwn
                                            ? AppColors.primary.withValues(
                                                alpha: 0.1,
                                              )
                                            : context.cardColor,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isOwn
                                              ? AppColors.primary.withValues(
                                                  alpha: 0.2,
                                                )
                                              : context.borderColor,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: isOwn
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            c['sender_name'] ?? '',
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isOwn
                                                  ? AppColors.primary
                                                  : context.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            c['text'] ?? '',
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontSize: 13,
                                              color: context.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (isOwn) const SizedBox(width: 8),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _myPrivateCommentController,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: context.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'Add comment to ${widget.course['instructor_name'] ?? 'Instructor'}',
                            hintStyle: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              color: context.textHint,
                            ),
                            filled: true,
                            fillColor: context.bgColor,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide(
                                color: context.borderColor,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide(
                                color: context.borderColor,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: const BorderSide(
                                color: Color(0xFFFF6B35),
                                width: 1.5,
                              ),
                            ),
                            suffixIcon: GestureDetector(
                              onTap: () async {
                                await _submitMyPrivateComment();
                                setSheet(() {});
                              },
                              child: _isSubmittingMyComment
                                  ? const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFFFF6B35),
                                        ),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.send_rounded,
                                      color: Color(0xFFFF6B35),
                                      size: 20,
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
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // INSTRUCTOR VIEWS
  // ════════════════════════════════════════════════════════

  Widget _buildInstructionsTab() {
    final post = widget.post;
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    final dueDate = post['due_date'];
    final isPastDue =
        dueDate != null &&
        DateTime.parse(dueDate).toLocal().isBefore(DateTime.now());

    return Column(
      children: [
        // ─── 1. SCROLLABLE CONTENT ───
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── 1. PREMIUM HEADER ───
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Tonal Type Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'ASSIGNMENT',
                              style: TextStyle(
                                color: Color(0xFFFF6B35),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (dueDate != null)
                            Text(
                              _formatDate(dueDate),
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isPastDue
                                    ? AppColors.error
                                    : textColor.withValues(alpha: 0.5),
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
                      const SizedBox(height: 8),
                      Text(
                        '$_maxPoints points',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF6B35),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(thickness: 0.5),
                ),

                // ─── 2. INSTRUCTIONS BODY ───
                if (post['instructions'] != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Text(
                      post['instructions'],
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        color: textColor.withValues(alpha: 0.8),
                        height: 1.6,
                      ),
                    ),
                  ),

                // ─── 3. ATTACHMENTS (Ghost Container Style) ───
                if (post['assessment_url'] != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Text(
                      'ATTACHMENTS',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 1.1,
                        color: textColor.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: textColor.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: _buildAttachmentTile(
                      post['assessment_name'] ?? 'Assignment Instructions',
                      post['assessment_url'],
                      _getFileTypeIcon(
                        post['assessment_name'] ?? 'file.pdf',
                      ),
                      _getFileTypeColor(
                        post['assessment_name'] ?? 'file.pdf',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(height: 48, thickness: 0.5),
                ),

                // ─── UNIFIED CLASS COMMENTS SECTION ───
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.forum_outlined,
                            color: textColor.withValues(alpha: 0.7),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Class comments',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildCommentCountBadge(textColor),
                        ],
                      ),
                      const SizedBox(height: 24),

                      if (_isLoadingComments)
                        _buildCommentSkeleton()
                      else if (_classComments.isEmpty)
                        _buildNoCommentsPlaceholder()
                      else
                        ..._classComments.map(
                          (c) => _buildPremiumCommentBubble(c, textColor),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 32), // Soft breathing room inside scroll
              ],
            ),
          ),
        ),

        // ─── 2. FIXED COMMENT INPUT AT THE BOTTOM ───
        _buildCommentInput(textColor),
      ],
    );
  }

  Widget _buildStudentWorkTab() {
    if (_isLoadingStudents) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    // Split students into categories
    final turnedInStudents = _students
        .where((s) => _submissions[s['id']]?['submitted_at'] != null)
        .toList();

    final assignedStudents = _students
        .where((s) => _submissions[s['id']]?['submitted_at'] == null)
        .toList();

    return Column(
      children: [
        // ─── Stats Bar ───
        Container(
          color: context.cardColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('$_turnedInCount', 'Turned in'),
              _buildStatItem('$_assignedCount', 'Assigned'),
              _buildStatItem('$_gradedCount', 'Graded'),
            ],
          ),
        ),
        const Divider(height: 1),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              // Show Turn in Status Toggle (Accepting Submissions)
              _buildSubmissionToggle(),

              if (turnedInStudents.isNotEmpty) ...[
                _buildSectionHeader('TURNED IN'),
                ..._buildStudentRows(turnedInStudents),
              ],

              if (assignedStudents.isNotEmpty) ...[
                _buildSectionHeader('ASSIGNED'),
                ..._buildStudentRows(assignedStudents),
              ],

              if (_students.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: Text('No students enrolled yet.')),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String count, String label) {
    return Column(
      children: [
        Text(
          count,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: context.textPrimary,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.textSecondary),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: context.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSubmissionToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Accepting submissions',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
                Text(
                  _acceptSubmissions
                      ? 'Students can turn in their work'
                      : 'Submissions are currently locked',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // --- Custom Animated Switch ---
          GestureDetector(
            onTap:
                _toggleAcceptSubmissions, // Calls your existing Supabase logic
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 48,
              height: 26,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: _acceptSubmissions
                    ? AppColors.primary
                    : (context.isDark ? Colors.white10 : Colors.black12),
                boxShadow: _acceptSubmissions
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [],
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: _acceptSubmissions
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumCommentBubble(Map<String, dynamic> c, Color textColor) {
    final isOwn = c['user_id'] == _supabase.auth.currentUser?.id;
    final canManage = isOwn || widget.isInstructor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: GestureDetector(
        onTap: canManage ? () => _showCommentOptions(c) : null,
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (_) {
                final url = (c['avatar_url'] as String?)?.trim();
                final name = c['user_name'] as String? ?? 'U';
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
                        c['user_name'] ?? 'User',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Today',
                        style: TextStyle(fontSize: 11, color: context.textHint),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    c['text'] ?? '',
                    style: TextStyle(
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

  List<Widget> _buildStudentRows(List<Map<String, dynamic>> students) {
    return students.map((student) {
      final submission = _submissions[student['id']];
      final hasTurnedIn = _submissionIsTurnedIn(submission);
      final hasFile = _submissionHasFile(submission);
      final isGradedS = submission?['is_graded'] == true;

      return PressableScale(
        scaleFactor: 1.0,      // Disable scale animation
        opacityFactor: 0.5,    // Enable opacity dimming indicator
        onPressed: () async {
          setState(() {
            _selectedStudent = student;
            _selectedSubmission = submission;
            _gradeController.clear();
            if (submission?['score'] != null) {
              _gradeController.text = submission!['score'].toString();
            }
          });
          final freshSubmission = await _loadSingleSubmission(student['id']);
          if (freshSubmission?['score'] != null && mounted) {
            setState(
              () => _gradeController.text = freshSubmission!['score'].toString(),
            );
          }
          _loadPrivateComments(student['id']);
        },
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leading: Builder(
            builder: (_) {
              final url = student['avatar_url'] as String?;
              final name = student['name'] as String? ?? 'S';
              if (url != null && url.isNotEmpty) {
                return CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary.withOpacity(0.15),
                  backgroundImage: NetworkImage(url),
                  onBackgroundImageError: (_, __) {},
                );
              }
              return CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primary.withOpacity(0.15),
                child: Text(
                  name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              );
            },
          ),
          title: Text(
            student['name'] ?? '',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: context.textPrimary,
            ),
          ),
          trailing: Text(
            isGradedS
                ? '${submission!['score']}/$_maxPoints'
                : hasTurnedIn
                ? 'Turned in'
                : hasFile
                ? 'Draft attached'
                : 'Assigned',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: isGradedS
                  ? AppColors.primary
                  : hasTurnedIn
                  ? Colors.green
                  : hasFile
                  ? const Color(0xFFFF6B35)
                  : context.textSecondary,
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildInstructorStudentView() {
    final student = _selectedStudent!;
    final submission = _submissions[student['id']] ?? _selectedSubmission;
    final hasTurnedIn = _submissionIsTurnedIn(submission);
    final hasFile = _submissionHasFile(submission);
    final isGradedS = submission?['is_graded'] == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Student info + submission
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
                    Builder(
                      builder: (_) {
                        final url = student['avatar_url'] as String?;
                        final name = student['name'] as String? ?? 'S';
                        if (url != null && url.isNotEmpty) {
                          return CircleAvatar(
                            radius: 24,
                            backgroundColor: AppColors.primary.withValues(
                              alpha: 0.15,
                            ),
                            backgroundImage: NetworkImage(url),
                            onBackgroundImageError: (_, __) {},
                          );
                        }
                        return CircleAvatar(
                          radius: 24,
                          backgroundColor: AppColors.primary.withValues(
                            alpha: 0.15,
                          ),
                          child: Text(
                            name.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
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
                          Text(
                            student['name'] ?? '',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                          Text(
                            hasTurnedIn
                                ? 'Turned in'
                                : hasFile
                                ? 'File attached, not turned in'
                                : 'Not submitted',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: hasTurnedIn
                                  ? Colors.green
                                  : hasFile
                                  ? const Color(0xFFFF6B35)
                                  : context.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (submission != null && hasFile) ...[
                  const SizedBox(height: 14),
                  Divider(color: context.borderColor, height: 1),
                  const SizedBox(height: 12),
                  Text(
                    hasTurnedIn
                        ? 'Submitted Work'
                        : 'Attached File (Not Turned In Yet)',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildInstructorFilesList(submission), // Updated
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Grade input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Grade',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                if (!hasTurnedIn) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.bgColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Text(
                      hasFile
                          ? 'The student has an attached file, but it is not turned in yet. You can view the file, but grading is enabled only after the student taps Turn in.'
                          : 'No file has been attached or turned in yet.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: context.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (isGradedS) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Current Score',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: context.textPrimary,
                          ),
                        ),
                        Text(
                          '${submission!['score']}/$_maxPoints',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _gradeController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: context.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              '${isGradedS ? 'Update' : 'Set'} Score (0-$_maxPoints)',
                          labelStyle: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                          prefixIcon: Icon(
                            Icons.grade_outlined,
                            color: context.textHint,
                            size: 20,
                          ),
                          suffixText: '/ $_maxPoints',
                          suffixStyle: TextStyle(
                            fontFamily: 'Poppins',
                            color: context.textSecondary,
                          ),
                          filled: true,
                          fillColor: context.bgColor,
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
                              color: AppColors.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size(80, 52),
                        elevation: 0,
                      ),
                      onPressed: _isGrading || !hasTurnedIn
                          ? null
                          : () => _gradeSubmission(student['id']),
                      child: _isGrading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              !hasTurnedIn
                                  ? 'Waiting'
                                  : isGradedS
                                  ? 'Update'
                                  : 'Grade',
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Private comments
          Container(
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFFF6B35).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        color: Color(0xFFFF6B35),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Private Comments',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(color: context.borderColor, height: 1),
                if (_isLoadingPrivate)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                else if (_privateComments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No private comments yet.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: context.textHint,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ..._privateComments.map((c) {
                    final isOwn = c['sender_id'] == _currentUserId;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: isOwn
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        children: [
                          if (!isOwn) ...[
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: const Color(
                                0xFFFF6B35,
                              ).withValues(alpha: 0.15),
                              child: Text(
                                (c['sender_name'] as String)
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFF6B35),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isOwn
                                    ? AppColors.primary.withValues(alpha: 0.1)
                                    : context.bgColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isOwn
                                      ? AppColors.primary.withValues(alpha: 0.2)
                                      : context.borderColor,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: isOwn
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c['sender_name'] ?? '',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isOwn
                                          ? AppColors.primary
                                          : context.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    c['text'] ?? '',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 13,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (isOwn) const SizedBox(width: 8),
                        ],
                      ),
                    );
                  }),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: const Color(
                          0xFFFF6B35,
                        ).withValues(alpha: 0.15),
                        child: Text(
                          (_currentUserName ?? 'I')
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFF6B35),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _privateCommentController,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: context.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Add private comment...',
                            hintStyle: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              color: context.textHint,
                            ),
                            filled: true,
                            fillColor: context.bgColor,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(
                                color: context.borderColor,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(
                                color: context.borderColor,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: const BorderSide(
                                color: Color(0xFFFF6B35),
                                width: 1.5,
                              ),
                            ),
                            suffixIcon: GestureDetector(
                              onTap: () => _submitPrivateComment(student['id']),
                              child: _isSubmittingComment
                                  ? const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFFFF6B35),
                                        ),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.send_rounded,
                                      color: Color(0xFFFF6B35),
                                      size: 20,
                                    ),
                            ),
                          ),
                          onSubmitted: (_) =>
                              _submitPrivateComment(student['id']),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildInstructorFilesList(Map<String, dynamic> submission) {
    final rawUrl = submission['file_url'];
    final rawName = submission['file_name'];
    List<String> urls = [];
    List<String> names = [];

    if (rawUrl != null && rawUrl.startsWith('[')) {
      urls = List<String>.from(jsonDecode(rawUrl));
      names = List<String>.from(jsonDecode(rawName));
    } else if (rawUrl != null) {
      urls = [rawUrl];
      names = [rawName ?? 'File'];
    }

    return Column(
      children: List.generate(urls.length, (i) {
        return _buildAttachmentTile(
          names[i],
          urls[i],
          _getFileTypeIcon(names[i]),
          _getFileTypeColor(names[i]),
        );
      }),
    );
  }

  Widget _buildCommentCountBadge(Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: textColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${_classComments.length}',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildNoCommentsPlaceholder() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'No class comments yet. Be the first to start the discussion!',
        style: TextStyle(
          color: context.textHint,
          fontSize: 13,
          fontFamily: 'Poppins',
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildCommentInput(Color textColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        border: Border(
          top: BorderSide(
            color: textColor.withOpacity(0.1),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
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
            child: TextField(
              controller: _classCommentController,
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Add class comment...',
                hintStyle: TextStyle(color: context.textHint, fontSize: 14),
                filled: true,
                fillColor: context.isDark
                    ? context.bgColor
                    : const Color(0xFFEBEBEB),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(
                    Icons.send_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  onPressed: _submitClassComment,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Shared Widgets ───────────────────────────────────────

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

  Widget _buildAttachmentTile(
    String name,
    String url,
    IconData icon,
    Color color,
  ) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FileViewerScreen(
            url: url,
            fileName: name,
            isStudent: !widget.isInstructor,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
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
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
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
            Icon(Icons.visibility_outlined, color: color, size: 16),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              color: color.withValues(alpha: 0.5),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  // ─── 1. STATUS BADGE (Assigned / Turned In / Graded) ───
  // ─── Graded result card (score + XP earned) shown to the student ───
  Widget _buildGradedResultCard() {
    final score = (_mySubmission?['score'] as int?) ?? 0;
    final xpAwarded = (_mySubmission?['xp_awarded'] as int?) ?? 0;
    final isPassing = _maxPoints > 0 && (score / _maxPoints) >= 0.6;
    final baseXpForFullScore = (_maxPoints * 0.20).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: context.bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        children: [
          Text(
            '$score / $_maxPoints',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: isPassing ? AppColors.success : AppColors.error,
            ),
          ),
          if (xpAwarded > 0) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                '+$xpAwarded XP earned',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF59E0B),
                ),
              ),
            ),
            if (score == _maxPoints && xpAwarded > baseXpForFullScore) ...[
              const SizedBox(height: 4),
              Text(
                'Streak bonus included!',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.8),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    final isMissing =
        !_hasTurnedIn &&
        !_isGraded &&
        (!_acceptSubmissions || _isPastDue);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _hasTurnedIn
            ? Colors.green.withValues(alpha: 0.1)
            : context.bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _hasTurnedIn
              ? Colors.green.withValues(alpha: 0.4)
              : context.borderColor,
        ),
      ),
      child: Text(
        _isGraded
            ? 'Graded'
            : _hasTurnedIn
            ? 'Turned in'
            : isMissing
            ? 'Missing'
            : _hasAttachedFile
            ? 'Attached'
            : 'Assigned',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _isGraded
              ? AppColors.primary
              : _hasTurnedIn
              ? Colors.green
              : isMissing
              ? AppColors.error
              : _hasAttachedFile
              ? AppColors.primary
              : context.textSecondary,
        ),
      ),
    );
  }

  // ─── 2. USER FILE TILE (The uploaded assignment) ───
  Widget _buildUserFileTile(Color textColor, bool canSubmit) {
    return Column(
      children: List.generate(_myWorkFileUrls.length, (index) {
        final fileName = _myWorkFileNames[index];
        final fileUrl = _myWorkFileUrls[index];

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: textColor.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.insert_drive_file_outlined,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  fileName,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!_hasTurnedIn && canSubmit && !_isGraded)
                GestureDetector(
                  onTap: () => _removeWorkAtIndex(index),
                  child: Icon(
                    Icons.close_rounded,
                    color: context.textHint,
                    size: 20,
                  ),
                )
              else
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FileViewerScreen(
                        url: fileUrl,
                        fileName: fileName,
                        isStudent: !widget.isInstructor,
                      ),
                    ),
                  ),
                  child: Icon(
                    Icons.visibility_outlined,
                    color: textColor.withOpacity(0.3),
                    size: 18,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  // ─── 3. EMPTY WORK STATE ───
  Widget _buildEmptyWorkState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'You have no attachments uploaded.',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: context.textHint,
          ),
        ),
      ),
    );
  }

  // ─── 4. REUSABLE ACTION BUTTON ───
  Widget _buildActionButton({
    required String label,
    required VoidCallback? onTap,
    Color? color,
    Color? textColor,
  }) {
    return PressableScale(
      onPressed: onTap,
      child: Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          color: color ?? AppColors.primary,
          borderRadius: BorderRadius.circular(24),
          border: color != null
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.2))
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: textColor ?? Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // ─── 5. FINAL SUBMIT/UNSUBMIT BUTTON ───
  Widget _buildFinalSubmitButton(bool canSubmit) {
    final isLocked = !_hasTurnedIn && !_isGraded && !canSubmit;
    return _buildActionButton(
      label: _isGraded ? 'Graded' : (_hasTurnedIn ? 'Unsubmit' : 'Turn in'),
      onTap: (_isGraded || isLocked)
          ? null
          : (_hasTurnedIn ? _unsubmitWork : _markAsDone),
      color: _hasTurnedIn
          ? context.cardColor
          : (_isGraded
              ? context.cardColor
              : isLocked
              ? Colors.grey.withValues(alpha: 0.4)
              : AppColors.primary),
      textColor: (_hasTurnedIn || _isGraded)
          ? AppColors.primary
          : isLocked
          ? Colors.white.withValues(alpha: 0.6)
          : Colors.white,
    );
  }

  Widget _buildCommentSkeleton() {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    return Column(
      children: List.generate(
        3,
        (index) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: textColor.withValues(alpha: 0.05),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 100,
                      height: 10,
                      decoration: BoxDecoration(
                        color: textColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      height: 10,
                      decoration: BoxDecoration(
                        color: textColor.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
