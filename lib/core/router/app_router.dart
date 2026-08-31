// lib/core/router/app_router.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../presentation/auth/opening_screen.dart';
import '../../presentation/auth/login_screen.dart';
import '../../presentation/auth/reset_password_screen.dart';
import '../../presentation/dashboard/student_dashboard.dart';
import '../../presentation/dashboard/instructor_dashboard.dart';
import '../../presentation/courses/course_detail_screen.dart';
import '../utils/app_security_manager.dart';

class AppRoutes {
  AppRoutes._();
  static const String opening = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String studentDashboard = '/student/dashboard';
  static const String instructorDashboard = '/instructor/dashboard';
  static const String courseDetail = '/course/detail';
  static const String resetPassword = '/reset-password';
}

CustomTransitionPage<void> _fadeScalePage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Fade + slight scale (Option C)
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final supabase = Supabase.instance.client;

  const authRoutes = {
    AppRoutes.opening,
    AppRoutes.login,
    AppRoutes.register,
    AppRoutes.resetPassword,
  };

  return GoRouter(
    initialLocation: AppRoutes.opening,
    debugLogDiagnostics: true,
    redirect: (context, state) async {
      final session = supabase.auth.currentSession;
      final isAuthRoute = authRoutes.contains(state.matchedLocation);

      // ── Not logged in ──────────────────────────────
      if (session == null) {
        return isAuthRoute ? null : AppRoutes.opening;
      }

      // ── Check background lock expiry ───────────────
      final expired = await AppSecurityManager().isBackgroundLockExpired();
      if (expired) {
        try {
          await supabase.auth.signOut();
        } catch (_) {}
        return AppRoutes.login;
      }

      // ── Refresh session to fix idle token expiry ───
      // Ensures all dashboard queries have a valid
      // token after long idle — fixes "classes not
      // loading" bug
      try {
        await supabase.auth.refreshSession();
      } catch (_) {
        await supabase.auth.signOut();
        return AppRoutes.login;
      }

      // ── Helper: fetch role and return correct route ─
      Future<String> routeForRole() async {
        try {
          final userId = session.user.id;
          final userData = await supabase
              .from('users')
              .select('role')
              .eq('id', userId)
              .single();
          final role = userData['role'] as String? ?? 'student';
          return role == 'instructor'
              ? AppRoutes.instructorDashboard
              : AppRoutes.studentDashboard;
        } catch (_) {
          await supabase.auth.signOut();
          return AppRoutes.login;
        }
      }

      // ── On opening screen → route to correct dash ──
      if (state.matchedLocation == AppRoutes.opening) {
        return routeForRole();
      }

      // ── Already on auth screen while logged in ──────
      if (isAuthRoute) {
        // EXCEPTION: always allow resetPassword screen even when a
        // session exists — this is the password recovery flow, where
        // Supabase creates a session before the user has actually
        // reset anything.
        if (state.matchedLocation == AppRoutes.resetPassword) {
          return null;
        }
        return routeForRole();
      }

      // ── Logged in, on correct screen → do nothing ──
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.opening,
        name: 'opening',
        pageBuilder: (context, state) =>
            _fadeScalePage(const OpeningScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        pageBuilder: (context, state) =>
            _fadeScalePage(const LoginScreen(showRegister: false), state),
      ),
      GoRoute(
        path: AppRoutes.register,
        name: 'register',
        pageBuilder: (context, state) =>
            _fadeScalePage(const LoginScreen(showRegister: true), state),
      ),
      GoRoute(
        path: AppRoutes.studentDashboard,
        name: 'studentDashboard',
        pageBuilder: (context, state) =>
            _fadeScalePage(const StudentDashboard(), state),
      ),
      GoRoute(
        path: AppRoutes.instructorDashboard,
        name: 'instructorDashboard',
        pageBuilder: (context, state) =>
            _fadeScalePage(const InstructorDashboard(), state),
      ),
      GoRoute(
        path: AppRoutes.courseDetail,
        name: 'courseDetail',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return _fadeScalePage(
            CourseDetailScreen(
              course: extra['course'] as Map<String, dynamic>,
              isInstructor: extra['isInstructor'] as bool,
              initialTab: extra['initialTab'] ?? 0,
            ),
            state,
          );
        },
      ),
      // ─── Reset Password (deep link target) ─────────────
      GoRoute(
        path: AppRoutes.resetPassword,
        name: 'resetPassword',
        pageBuilder: (context, state) =>
            _fadeScalePage(const ResetPasswordScreen(), state),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Page not found: ${state.uri}'),
            TextButton(
              onPressed: () => context.go(AppRoutes.opening),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    ),
  );
});
