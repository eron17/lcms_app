import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSecurityManager with WidgetsBindingObserver {
  static final AppSecurityManager _instance =
      AppSecurityManager._internal();
  factory AppSecurityManager() => _instance;
  AppSecurityManager._internal();

  static const int _backgroundLockSeconds = 120;
  static const String _backgroundedAtKey = 'app_backgrounded_at';
  static const String _sessionActiveKey = 'session_active';

  final _supabase = Supabase.instance.client;
  Timer? _inactivityTimer;
  bool _isLocked = false;
  VoidCallback? onLockRequired;
  VoidCallback? onLogoutRequired;

  void initialize({
    required VoidCallback onLock,
    required VoidCallback onLogout,
  }) {
    onLockRequired = onLock;
    onLogoutRequired = onLogout;
    WidgetsBinding.instance.addObserver(this);
    _markSessionActive();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
  }

  Future<void> _markSessionActive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sessionActiveKey, true);
    await prefs.remove(_backgroundedAtKey);
  }

  Future<void> _markBackgrounded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _backgroundedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _checkIfShouldLockOrLogout() async {
    final prefs = await SharedPreferences.getInstance();
    final backgroundedAt = prefs.getInt(_backgroundedAtKey);

    if (backgroundedAt == null) return;

    final elapsed = DateTime.now().millisecondsSinceEpoch - backgroundedAt;
    final elapsedSeconds = elapsed ~/ 1000;

    if (elapsedSeconds >= _backgroundLockSeconds) {
      // Been in background too long — lock the app
      _isLocked = true;
      onLockRequired?.call();
    }
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.paused:
        await _markBackgrounded();
        // Mark as potentially killed so if the
        // process dies while paused (removed from
        // recents), next start sees the flag
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('app_was_killed', true);
        } catch (_) {}
        _inactivityTimer?.cancel();
        break;

      case AppLifecycleState.resumed:
        // 1. Check lock FIRST before anything else
        //    Must be awaited so backgroundedAt is
        //    read before _markSessionActive clears it
        await _checkIfShouldLockOrLogout();

        // 2. Only mark active if NOT locked
        //    If locked, let the lock screen handle it
        if (!_isLocked) {
          // Refresh session only if not locked
          try {
            await Supabase.instance.client.auth.refreshSession();
          } catch (_) {}
          await _markSessionActive();
          // Clear the killed flag since app
          // resumed normally
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('app_was_killed');
          } catch (_) {}
        }
        _inactivityTimer?.cancel();
        break;

      case AppLifecycleState.detached:
        // Mark that app was killed/removed
        // so next cold start knows to logout
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('app_was_killed', true);
          await prefs.remove(_backgroundedAtKey);
        } catch (_) {}
        break;

      case AppLifecycleState.hidden:
        _markBackgrounded();
        break;

      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _performLogout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sessionActiveKey, false);
      await prefs.remove(_backgroundedAtKey);
      await _supabase.auth.signOut();
    } catch (_) {}
  }

  Future<bool> shouldRequireLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionActive = prefs.getBool(_sessionActiveKey) ?? false;
    final user = _supabase.auth.currentUser;

    // If no active session or user is null
    // → require full login
    if (!sessionActive || user == null) return true;

    // If app was backgrounded and came back
    // check elapsed time
    final backgroundedAt = prefs.getInt(_backgroundedAtKey);
    if (backgroundedAt != null) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - backgroundedAt;
      if (elapsed ~/ 1000 >= _backgroundLockSeconds) {
        return true;
      }
    }
    return false;
  }

  // Race-free variant of the background-timeout half of
  // shouldRequireLogin(): checked at router startup/redirect time,
  // before _markSessionActive() may have had a chance to persist
  // 'session_active' for this process — so it must not depend on
  // that flag, or a valid session would get logged out on a plain
  // cold start.
  Future<bool> isBackgroundLockExpired() async {
    final prefs = await SharedPreferences.getInstance();

    // Check if app was killed/removed from recents
    // This flag is set in paused/detached and cleared
    // only on successful resume
    final wasKilled = prefs.getBool('app_was_killed') ?? false;
    if (wasKilled) {
      // Clear the flag and force logout
      await prefs.remove('app_was_killed');
      await prefs.remove(_backgroundedAtKey);
      return true; // → router will force logout
    }

    // Check background timeout (2 min lock)
    final backgroundedAt = prefs.getInt(_backgroundedAtKey);
    if (backgroundedAt == null) return false;
    final elapsed = DateTime.now().millisecondsSinceEpoch - backgroundedAt;
    return elapsed ~/ 1000 >= _backgroundLockSeconds;
  }

  bool get isLocked => _isLocked;

  void unlock() {
    _isLocked = false;
    _markSessionActive();
  }
}
