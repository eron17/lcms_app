// lib/main.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'providers/theme_provider.dart';
import 'core/utils/grading_service.dart';
import 'core/utils/app_security_manager.dart';
import 'presentation/shared/theme_ripple_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _initializeApp();
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('App initialization failed: $e\n$stackTrace');
    }
    rethrow;
  }
  runApp(const ProviderScope(child: LCMSApp()));
}

Future<void> _initializeApp() async {
  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    // ─── PKCE flow needed for deep link password reset ────
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      autoRefreshToken: true,
    ),
  );
  GradingService.initialize();
}

class LCMSApp extends ConsumerStatefulWidget {
  const LCMSApp({super.key});

  @override
  ConsumerState<LCMSApp> createState() => _LCMSAppState();
}

class _LCMSAppState extends ConsumerState<LCMSApp>
    with TickerProviderStateMixin {
  OverlayEntry? _rippleEntry;
  AnimationController? _rippleController;

  @override
  void initState() {
    super.initState();
    _handleAuthDeepLink();
    _handleUnityReturnDeepLink();
    AppSecurityManager().initialize(
      onLogout: _forceLogout,
    );
  }

  @override
  void dispose() {
    AppSecurityManager().dispose();
    super.dispose();
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

  // TODO(Joshua): Wire up the return deep link from Unity here.
  //
  // Unity finishes a 3D Meet session and hands control back to this app
  // via a deep link to com.psulubao.it.lcms_app://return, carrying
  // 'score' and 'post_id' as query parameters (source_code/actual_output
  // are written straight to Supabase by Unity — GradingService.initialize()
  // in main() already picks those up via its own realtime listener, so
  // this handler's only job is catching the app *opening* and routing
  // the student to the right screen).
  //
  // This app currently has no package that listens for incoming links
  // while already running (url_launcher, used by _launchUnity() in
  // three_d_meet_detail_screen.dart, only sends links out). Adding one
  // (app_links or uni_links) means touching pubspec.yaml and the Android
  // manifest's intent-filter for that scheme/host, which is bigger than
  // a Find→Replace change, so it wasn't added here.
  //
  // Once that package is in: subscribe to its incoming-link stream,
  // check uri.host == 'return', read score/post_id from
  // uri.queryParameters, then something like:
  //   ref.read(appRouterProvider).go(AppRoutes.courseDetail, extra: {...});
  // to land the student back on the right post showing their grade.
  void _handleUnityReturnDeepLink() {}

  void triggerThemeRipple({
    required Offset origin,
    required bool toIsDark,
    required BuildContext context,
  }) async {
    _rippleController?.dispose();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    final newTheme = toIsDark ? ThemeMode.dark : ThemeMode.light;

    final animation = CurvedAnimation(
      parent: _rippleController!,
      curve: Curves.easeInOut,
    );

    // Build the new-theme widget as overlay
    _rippleEntry = OverlayEntry(
      builder: (_) => ThemeRippleOverlay(
        animation: animation,
        center: origin,
        isDarkTarget: toIsDark,
        child: MaterialApp.router(
          title: 'Code Lab 3D',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: newTheme,
          routerConfig: ref.read(appRouterProvider),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.noScaling),
            child: child!,
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_rippleEntry!);
    await _rippleController!.forward();

    // Apply the theme change and remove overlay
    ref.read(themeProvider.notifier).setTheme(newTheme);
    _rippleEntry?.remove();
    _rippleEntry = null;
    _rippleController?.dispose();
    _rippleController = null;
  }

  Future<void> _forceLogout() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    if (!mounted) return;
    ref.read(appRouterProvider).go(AppRoutes.login);
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
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: child!,
        );
      },
    );
  }
}
