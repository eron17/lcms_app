// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://vzbkcakuvckfkcbkvwul.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ6YmtjYWt1dmNrZmtjYmt2d3VsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgxNzY1NDUsImV4cCI6MjA5Mzc1MjU0NX0.pDub4i72u5_H7RNDEcZm8Yiqdo--2abMs1LSmG61UBU',
    // ─── PKCE flow needed for deep link password reset ────
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  runApp(const ProviderScope(child: LCMSApp()));
}

final supabase = Supabase.instance.client;

class LCMSApp extends ConsumerStatefulWidget {
  const LCMSApp({super.key});

  @override
  ConsumerState<LCMSApp> createState() => _LCMSAppState();
}

class _LCMSAppState extends ConsumerState<LCMSApp> {
  @override
  void initState() {
    super.initState();
    _handleAuthDeepLink();
  }

  void _handleAuthDeepLink() {
    // Listens for when user clicks the password reset link in email
    // Supabase automatically exchanges the token and fires this event
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        // Navigate to reset password screen
        ref.read(appRouterProvider).go(AppRoutes.resetPassword);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'Code Lab 3D',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
