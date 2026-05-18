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

final appRouterProvider = Provider<GoRouter>((ref) {
  final supabase = Supabase.instance.client;

  String getInitialRoute() {
    final session = supabase.auth.currentSession;
    if (session != null) return AppRoutes.studentDashboard;
    return AppRoutes.opening;
  }

  return GoRouter(
    initialLocation: getInitialRoute(),
    debugLogDiagnostics: true,
    routes: [
      GoRoute(
        path: AppRoutes.opening,
        name: 'opening',
        builder: (context, state) => const OpeningScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (context, state) => const LoginScreen(showRegister: false),
      ),
      GoRoute(
        path: AppRoutes.register,
        name: 'register',
        builder: (context, state) => const LoginScreen(showRegister: true),
      ),
      GoRoute(
        path: AppRoutes.studentDashboard,
        name: 'studentDashboard',
        builder: (context, state) => const StudentDashboard(),
      ),
      GoRoute(
        path: AppRoutes.instructorDashboard,
        name: 'instructorDashboard',
        builder: (context, state) => const InstructorDashboard(),
      ),
      GoRoute(
        path: AppRoutes.courseDetail,
        name: 'courseDetail',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return CourseDetailScreen(
            course: extra['course'] as Map<String, dynamic>,
            isInstructor: extra['isInstructor'] as bool,
          );
        },
      ),
      // ─── Reset Password (deep link target) ─────────────
      GoRoute(
        path: AppRoutes.resetPassword,
        name: 'resetPassword',
        builder: (context, state) => const ResetPasswordScreen(),
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
