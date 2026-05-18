// lib/presentation/notifications/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Added for HapticFeedback
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_extensions.dart';

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

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

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
            final newRecord = payload.newRecord;
            if (newRecord['user_id'] == userId) {
              if (mounted) _loadNotifications();
            }
          },
        )
        .subscribe();
  }

  Future<void> _markAsRead(String id) async {
    try {
      await _supabase.from('notifications').update({'is_read': true}).eq('id', id);
      if (mounted) {
        setState(() {
          final i = _notifications.indexWhere((n) => n['id'] == id);
          if (i != -1) _notifications[i]['is_read'] = true;
        });
      }
    } catch (e) { debugPrint('Mark read: $e'); }
  }

  Future<void> _markAllRead() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      await _supabase.from('notifications').update({'is_read': true}).eq('user_id', userId).eq('is_read', false);
      if (mounted) {
        setState(() {
          for (var n in _notifications) {
            n['is_read'] = true;
          }
        });
      }
    } catch (e) { debugPrint('Mark all: $e'); }
  }

  Future<void> _deleteNotification(String id) async {
    try {
      await _supabase.from('notifications').delete().eq('id', id);
      if (mounted) setState(() => _notifications.removeWhere((n) => n['id'] == id));
    } catch (e) { debugPrint('Delete notif: $e'); }
  }

  int get _unreadCount => _notifications.where((n) => n['is_read'] == false).length;

  IconData _getIcon(String type) {
    switch (type) {
      case 'post': return Icons.campaign_rounded;
      case 'class_comment': return Icons.forum_rounded;
      case 'private_comment': return Icons.lock_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  Color _getColor(String type) {
    switch (type) {
      case 'post': return AppColors.accent;
      case 'class_comment': return AppColors.primary;
      case 'private_comment': return const Color(0xFFFF6B35);
      default: return AppColors.primary;
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

  @override
  Widget build(BuildContext context) {
    // Interstellar Blue for Light Mode, White for Dark Mode
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Scaffold(
      backgroundColor: context.bgColor,
      body: Stack(
        children: [
          Container(decoration: context.scaffoldGradient),
          SafeArea(
            child: Column(
              children: [
                // ─── Custom Top Bar ───
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: context.cardColor, 
                            borderRadius: BorderRadius.circular(12), 
                            border: Border.all(color: context.borderColor)
                          ),
                          child: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 18),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Notifications', 
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.bold, color: textColor)
                      ),
                      const Spacer(),
                      if (_unreadCount > 0)
                        GestureDetector(
                          onTap: _markAllRead,
                          child: const Text(
                            'Mark all read', 
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600)
                          ),
                        ),
                    ],
                  ),
                ),
                
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                      : _notifications.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // ─── Proper Icon instead of Emoji ───
                                  Icon(
                                    Icons.notifications_none_rounded, 
                                    size: 80, 
                                    color: textColor.withValues(alpha: 0.15)
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    "You're all caught up!", 
                                    style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.bold, color: textColor)
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No new notifications at the moment.', 
                                    style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: textColor.withValues(alpha: 0.5))
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              color: AppColors.primary,
                              onRefresh: _loadNotifications,
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                itemCount: _notifications.length,
                                itemBuilder: (context, index) {
                                  final notif = _notifications[index];
                                  final isRead = notif['is_read'] == true;
                                  final type = notif['type'] as String? ?? 'post';
                                  final color = _getColor(type);

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: context.cardColor,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: isRead ? context.borderColor : color.withValues(alpha: 0.4)),
                                      boxShadow: context.isDark ? [] : [
                                        BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))
                                      ],
                                    ),
                                    child: ListTile(
                                      onTap: () => _markAsRead(notif['id']),
                                      contentPadding: const EdgeInsets.all(12),
                                      leading: Container(
                                        width: 48, height: 48,
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.1), 
                                          borderRadius: BorderRadius.circular(14)
                                        ),
                                        child: Icon(_getIcon(type), color: color, size: 24),
                                      ),
                                      title: Text(
                                        notif['title'] ?? '',
                                        style: TextStyle(
                                          fontFamily: 'Poppins', 
                                          fontSize: 14, 
                                          fontWeight: isRead ? FontWeight.w500 : FontWeight.bold, 
                                          color: textColor
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (notif['body'] != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 2),
                                              child: Text(
                                                notif['body'], 
                                                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: textColor.withValues(alpha: 0.6)),
                                                maxLines: 2, overflow: TextOverflow.ellipsis
                                              ),
                                            ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _formatDate(notif['created_at']), 
                                            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: textColor.withValues(alpha: 0.4))
                                          ),
                                        ],
                                      ),
                                      trailing: !isRead ? Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)) : null,
                                    ),
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
}