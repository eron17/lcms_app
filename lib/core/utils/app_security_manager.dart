import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSecurityManager with WidgetsBindingObserver {
  static final AppSecurityManager _instance =
      AppSecurityManager._internal();
  factory AppSecurityManager() => _instance;
  AppSecurityManager._internal();

  static const int _backgroundLogoutSeconds = 120;
  static const String _backgroundedAtKey = 'app_backgrounded_at';

  VoidCallback? onLogoutRequired;
  bool _isResuming = false;
  static int? _backgroundedAtMs;

  void initialize({required VoidCallback onLogout}) {
    onLogoutRequired = onLogout;
    WidgetsBinding.instance.addObserver(this);
    _clearBackgroundedAt();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  Future<void> _clearBackgroundedAt() async {
    _backgroundedAtMs = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_backgroundedAtKey);
      await prefs.remove('app_was_killed');
    } catch (_) {}
  }

  void _saveBackgroundedAt() {
    // Guards against the RETURN journey re-firing hidden/inactive
    // before resumed runs (hidden → inactive → resumed, no paused
    // in between) — checking the timestamp itself, not _isResuming,
    // because _isResuming only becomes true inside the resumed case,
    // which executes AFTER these events on the way back. An
    // _isResuming-only guard cannot protect against them.
    if (_backgroundedAtMs != null) return;
    _backgroundedAtMs = DateTime.now().millisecondsSinceEpoch;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(_backgroundedAtKey, _backgroundedAtMs!);
      prefs.setBool('app_was_killed', true);
    });
    debugPrint('AppSecurity: backgrounded at $_backgroundedAtMs');
  }

  Future<void> _checkAndLogoutIfNeeded() async {
    int? backgroundedAt = _backgroundedAtMs;
    if (backgroundedAt == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        backgroundedAt = prefs.getInt(_backgroundedAtKey);
      } catch (_) {}
    }

    if (backgroundedAt == null) return;

    final elapsed = DateTime.now().millisecondsSinceEpoch - backgroundedAt;
    final elapsedSeconds = elapsed ~/ 1000;

    debugPrint(
      'AppSecurity: backgrounded ${elapsedSeconds}s ago '
      '(logout threshold: ${_backgroundLogoutSeconds}s)',
    );

    if (elapsedSeconds >= _backgroundLogoutSeconds) {
      debugPrint('AppSecurity: timeout → logging out');
      await _performLogout();
    } else {
      // Under threshold — just refresh session
      try {
        await Supabase.instance.client.auth.refreshSession();
        debugPrint('AppSecurity: session refreshed');
      } catch (e) {
        debugPrint('AppSecurity: session refresh failed → $e');
        // If refresh fails, also logout
        await _performLogout();
      }
    }
  }

  Future<void> _performLogout() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    await _clearBackgroundedAt();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onLogoutRequired?.call();
    });
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    debugPrint('AppSecurity: lifecycle → $state');
    switch (state) {
      case AppLifecycleState.inactive:
        if (!_isResuming) _saveBackgroundedAt();
        break;

      case AppLifecycleState.hidden:
        if (!_isResuming) _saveBackgroundedAt();
        break;

      case AppLifecycleState.paused:
        if (!_isResuming) _saveBackgroundedAt();
        break;

      case AppLifecycleState.resumed:
        _isResuming = true;
        await _checkAndLogoutIfNeeded();
        await _clearBackgroundedAt();
        _isResuming = false;
        break;

      case AppLifecycleState.detached:
        _saveBackgroundedAt();
        break;
    }
  }

  Future<bool> isBackgroundLockExpired() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wasKilled = prefs.getBool('app_was_killed') ?? false;
      if (wasKilled) {
        final backgroundedAt = prefs.getInt(_backgroundedAtKey);
        if (backgroundedAt != null) {
          final elapsed =
              DateTime.now().millisecondsSinceEpoch - backgroundedAt;
          if (elapsed ~/ 1000 >= _backgroundLogoutSeconds) {
            await prefs.remove('app_was_killed');
            await prefs.remove(_backgroundedAtKey);
            return true;
          }
        }
        await prefs.remove('app_was_killed');
      }
    } catch (_) {}
    return false;
  }
}
