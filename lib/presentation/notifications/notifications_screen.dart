// lib/presentation/notifications/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../shared/widgets/pressable_scale.dart'; // Using our shared widget
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import 'package:lcms_app/presentation/courses/assignment_detail_screen.dart';
import 'package:lcms_app/presentation/courses/post_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final bool isInstructor;
  const NotificationsScreen({super.key, required this.isInstructor});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  RealtimeChannel? _channel;
  bool _hasUnreadNotifications = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _subscribeRealtime();
    _checkUnreadStatus();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  // --- Keep your existing Logic Methods (Supabase calls) ---
  Future<void> _loadNotifications() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkUnreadStatus() async {
  try {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    
    final count = await _supabase
        .from('notifications')
        .select('id')
        .eq('user_id', userId)
        .eq('is_read', false); // Only select unread ones

    if (mounted) {
      setState(() => _hasUnreadNotifications = (count as List).isNotEmpty);
    }
  } catch (e) { debugPrint('Badge check error: $e'); }
}

  void _subscribeRealtime() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    _channel = _supabase
        .channel('notifications_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          callback: (payload) {
            if (payload.newRecord['user_id'] == userId && mounted) {
              _loadNotifications();
              _checkUnreadStatus();
            }
          },
        )
        .subscribe();
  }

  Future<void> _handleNotificationTap(Map<String, dynamic> notif) async {
  final postId = notif['post_id'];
  final courseId = notif['course_id'];

  if (postId == null || courseId == null) {
    // If it's a general notification without a post link, just go to the course details
    context.push(
      AppRoutes.courseDetail, 
      extra: {
        'course': {'id': courseId}, 
        'isInstructor': widget.isInstructor
      }
    );
    return;
  }

  // 1. Mark as read
  _markAsRead(notif['id']);

  // 2. SHOW LOADING SPINNER
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(
      child: CircularProgressIndicator(color: Colors.white),
    ),
  );

  try {
    // 3. FETCH DATA FROM SUPABASE
    final results = await Future.wait([
      _supabase.from('posts').select('*, users(name)').eq('id', postId).single(),
      _supabase.from('courses').select().eq('id', courseId).single(),
    ]);

    final postData = results[0];
    final courseData = results[1];

    if (mounted) {
      Navigator.pop(context); // Remove loading spinner
    }

    // 4. ROUTE TO THE CORRECT DETAIL SCREEN
    if (postData['type'] == 'assignment') {
      // Go to Assignment Details Screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AssignmentDetailScreen(
            post: postData,
            course: courseData,
            isInstructor: widget.isInstructor,
          ),
        ),
      );
    } else {
      // Go to Post Details Screen (Material, 3D Meet, Announcement)
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostDetailScreen(
            post: postData,
            course: courseData,
            isInstructor: widget.isInstructor,
          ),
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      Navigator.pop(context); // Safety close spinner
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load post details: $e')),
      );
    }
    debugPrint('Notification Navigation Error: $e');
  }
}
  
  Future<void> _markAsRead(String id) async {
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', id);
      if (mounted) {
        setState(() {
          final i = _notifications.indexWhere((n) => n['id'] == id);
          if (i != -1) _notifications[i]['is_read'] = true;
        });
      }
    } catch (e) {
      debugPrint('Mark read: $e');
    }
  }

  Future<void> _markAllRead() async {
    HapticFeedback.mediumImpact();
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
      if (mounted) {
        setState(() {
          for (var n in _notifications) {
            n['is_read'] = true;
          }
        });
      }
    } catch (e) {
      debugPrint('Mark all: $e');
    }
  }

  Future<void> _deleteNotification(String id) async {
    try {
      await _supabase.from('notifications').delete().eq('id', id);
      if (mounted) {
        setState(() => _notifications.removeWhere((n) => n['id'] == id));
      }
    } catch (e) {
      debugPrint('Delete notif: $e');
    }
  }

  int get _unreadCount =>
      _notifications.where((n) => n['is_read'] == false).length;

  // --- REFINED BUILD METHOD ---

  @override
  Widget build(BuildContext context) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Scaffold(
      backgroundColor: context.bgColor,
      body: Stack(
        children: [
          Container(decoration: context.scaffoldGradient),
          SafeArea(
            child: Column(
              children: [
                // ─── PREMIUM TOP BAR ───
                _buildTopBar(textColor),

                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _notifications.isEmpty
                      ? _buildEmptyState(textColor)
                      : RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: _loadNotifications,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            itemCount: _notifications.length,
                            itemBuilder: (context, index) {
                              final notif = _notifications[index];
                              return _buildSwipeableNotification(
                                notif,
                                textColor,
                              );
                            },
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

  Widget _buildTopBar(Color textColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          PressableScale(
            onPressed: () => Navigator.pop(context),
            scaleFactor: 1.0, // Changed from 0.94 to 1.0 (Opacity only)
            opacityFactor: 0.5,
            child: Container(
              padding: const EdgeInsets.all(10),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: textColor,
                size: 25,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'Notifications',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
          const Spacer(),
          if (_unreadCount > 0)
            PressableScale(
              onPressed: _markAllRead,
              scaleFactor: 1.0, // Dim only
              opacityFactor: 0.5,
              child: const Text(
                'Mark all read',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSwipeableNotification(
    Map<String, dynamic> notif,
    Color textColor,
  ) {
    final String id = notif['id'].toString();
    final bool isRead = notif['is_read'] == true;
    final String type = notif['type'] as String? ?? 'post';
    final Color typeColor = _getColor(type);

    return Dismissible(
      key: Key(id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        _deleteNotification(id);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.redAccent,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: PressableScale(
          onPressed: () => _handleNotificationTap(notif), 
          scaleFactor: 0.98,
          opacityFactor: 0.8,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isRead
                  ? context.cardColor.withValues(alpha: 0.6)
                  : context.cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: isRead
                  ? []
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon Badge
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_getIcon(type), color: typeColor, size: 22),
                ),
                const SizedBox(width: 16),
                // Text Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notif['title'] ?? '',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: isRead
                              ? FontWeight.w600
                              : FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                      if (notif['body'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            notif['body'],
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: textColor.withValues(alpha: 0.5),
                              height: 1.4,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        _formatDate(notif['created_at']),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: textColor.withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                  ),
                ),
                // Unread Indicator Pulse
                if (!isRead)
                  Container(
                    margin: const EdgeInsets.only(top: 4, left: 8),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: typeColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: typeColor.withValues(alpha: 0.4),
                          blurRadius: 6,
                          spreadRadius: 2,
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

  // --- Helper Methods (Icons & Colors) ---
  IconData _getIcon(String type) {
    switch (type) {
      case 'assignment_posted':
        return Icons.assignment_outlined;
      case 'assignment_graded':
        return Icons.stars_rounded;
      case '3d_meet_live':
        return Icons.videogame_asset_rounded;
      case 'milestone': // ─── ADD THIS ───
        return Icons.emoji_events_rounded; 
      case 'student_joined':
        return Icons.person_add_alt_1_rounded;
      case 'submission_received':
        return Icons.assignment_turned_in_rounded;
      case 'class_comment':
        return Icons.forum_rounded;
      case 'private_comment':
        return Icons.lock_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  // 2. Ensure these colors match the brand
  Color _getColor(String type) {
    switch (type) {
      case '3d_meet_live':
        return const Color(0xFF22C55E); // Green
      case 'assignment_posted':
      case 'submission_received':
        return const Color(0xFFFF6B35); // Orange
      case 'assignment_graded':
        return AppColors.primary; // Blue
      case 'milestone': // ─── ADD THIS ───
        return AppColors.gold; 
      default:
        return AppColors.primary;
    }
  }

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${date.day}/${date.month}';
  }

  Widget _buildEmptyState(Color textColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 80,
            color: textColor.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 20),
          Text(
            "You're all caught up!",
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          Text(
            'No new notifications at the moment.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              color: textColor.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
