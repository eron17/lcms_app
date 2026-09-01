// lib/presentation/auth/opening_screen.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/pressable_scale.dart';

class OpeningScreen extends ConsumerStatefulWidget {
  const OpeningScreen({super.key});

  @override
  ConsumerState<OpeningScreen> createState() => _OpeningScreenState();
}

class _OpeningScreenState extends ConsumerState<OpeningScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _buttonController;
  late AnimationController _glowController;

  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<double> _textFade;
  late Animation<Offset> _textSlide;
  late Animation<double> _buttonFade;
  late Animation<Offset> _buttonSlide;
  late Animation<double> _glowAnimation;

  final _scrollController = ScrollController();
  final _heroKey = GlobalKey();
  final _featuresKey = GlobalKey();
  final _aboutKey = GlobalKey();
  int _expandedFeature = 0;

  final List<Map<String, dynamic>> _features = [
    {
      'icon': Icons.view_in_ar_rounded,
      'color': const Color(0xFF3B9EFF),
      'title': '3D Classroom',
      'summary': 'Unity-powered immersive coding environment',
      'detail':
          'Students enter a live 3D classroom built in Unity 6. '
          'They write real C++ code inside the environment and '
          'submit directly from Unity to the grading system.',
    },
    {
      'icon': Icons.qr_code_scanner_rounded,
      'color': const Color(0xFF4CAF50),
      'title': 'Code Scanner',
      'summary': 'Auto-verifies student output vs expected results',
      'detail':
          'The CodeScanner checks required keywords, forbidden '
          'patterns, and compares actual output to the instructor\'s '
          'expected output. AutoGrader calculates the final score '
          'instantly.',
    },
    {
      'icon': Icons.shield_rounded,
      'color': const Color(0xFF7B2FBE),
      'title': 'Rank Badges',
      'summary': '8 ranks from Script Kiddie to Compiler Whisperer',
      'detail':
          'Students earn ranks based on class XP: Script Kiddie → '
          'Code Newbie → Junior Dev → Refactorer → Stack Overflow '
          'Guru → Tech Lead → 10x Developer → Compiler Whisperer.',
    },
    {
      'icon': Icons.leaderboard_rounded,
      'color': const Color(0xFFFFD700),
      'title': 'Live Leaderboard',
      'summary': 'Per-class XP and streak rankings in real time',
      'detail':
          'Each class has its own leaderboard updated via Supabase '
          'Realtime. XP and streak update the moment a grade is '
          'given — no refresh needed.',
    },
    {
      'icon': Icons.assignment_rounded,
      'color': const Color(0xFFFF9800),
      'title': 'Assignment Management',
      'summary': 'Due dates, grading, and student work tracking',
      'detail':
          'Instructors post assignments with due dates, points, and '
          'file attachments. Students submit work and instructors '
          'grade with feedback. XP awarded automatically.',
    },
    {
      'icon': Icons.bar_chart_rounded,
      'color': const Color(0xFF00BCD4),
      'title': 'Reports & Analytics',
      'summary': 'Pass rate and submission tracking per class',
      'detail':
          'Instructors see total, graded, ungraded, and '
          'no-submission counts per class. Drill down into '
          'individual student performance.',
    },
  ];

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _startAnimations();
  }

  void _initAnimations() {
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoController, curve: Curves.easeOut));
    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _textController, curve: Curves.easeOut));
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _textController, curve: Curves.easeOut));

    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _buttonFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _buttonController, curve: Curves.easeOut));
    _buttonSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _buttonController, curve: Curves.easeOut));

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.4, end: 0.8).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  void _startAnimations() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 500));
    _textController.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    _buttonController.forward();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _buttonController.dispose();
    _glowController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    if (kIsWeb) {
      return Scaffold(
        backgroundColor: const Color(0xFF060d1f),
        body: Column(
          children: [
            _buildNavbar(),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Column(
                  children: [
                    _buildHeroSection(),
                    _buildFeaturesSection(),
                    _buildAboutSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.bgColor,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.35),
            radius: 1.2,
            colors: [context.surfaceColor, context.bgColor],
          ),
        ),
        child: Stack(
          children: [
            _buildGridOverlay(size),
            if (context.isDark) _buildGlowEffect(size),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const Spacer(flex: 35),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FadeTransition(
                          opacity: _logoFade,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: Image.asset(
                              'assets/images/logo.png',
                              width: size.width * 0.5,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FadeTransition(
                          opacity: _textFade,
                          child: SlideTransition(
                            position: _textSlide,
                            child: Image.asset(
                              'assets/images/app_name.png',
                              width: size.width * 0.7,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(flex: 65),
                    FadeTransition(
                      opacity: _buttonFade,
                      child: SlideTransition(
                        position: _buttonSlide,
                        child: Column(
                          children: [
                            _buildGetStartedButton(context),
                            const SizedBox(height: 24),
                            _buildLoginLink(context),
                            if (kIsWeb) ...[
                              const SizedBox(height: 8),
                              _buildDownloadButton(context),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridOverlay(Size size) {
    return Opacity(
      opacity: 0.04,
      child: CustomPaint(
        size: size,
        painter: _GridPainter(context.textPrimary),
      ),
    );
  }

  Widget _buildGlowEffect(Size size) {
    return Positioned(
      top: size.height * 0.35 - 140,
      left: size.width * 0.5 - 140,
      child: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) {
          return Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha:_glowAnimation.value),
                  blurRadius: 100,
                  spreadRadius: 20,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildGetStartedButton(BuildContext context) {
    return PressableScale(
      onPressed: () => context.go(AppRoutes.register),
      child: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) {
          return Container(
            width: double.infinity,
            height: 60,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryDark, AppColors.primary],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha:0.4 * _glowAnimation.value),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'Get Started',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoginLink(BuildContext context) {
    return PressableScale(
      onPressed: () => context.go(AppRoutes.login),
      scaleFactor: 1.0,   
      opacityFactor: 0.6, 
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        color: Colors.transparent, 
        child: const Text(
          'I already have an account',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E90FF), 
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadButton(BuildContext context) {
    return PressableScale(
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'APK download coming soon!',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: const Color(0xFF22C55E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        color: Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.android_rounded,
              size: 18,
              color: const Color(0xFF22C55E).withValues(alpha: 0.8),
            ),
            const SizedBox(width: 8),
            Text(
              'Download Android app',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF22C55E).withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Web landing page (kIsWeb) ─────────────────────────────

  Widget _buildNavbar() {
    return Container(
      height: 56,
      color: const Color(0xFF080e20),
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final isNarrow = constraints.maxWidth < 600;
          return Row(
            children: [
              Image.asset('assets/images/logo.png', height: 32),
              const SizedBox(width: 10),
              Image.asset('assets/images/app_name.png', height: 22),
              const Spacer(),
              if (!isNarrow) ...[
                _navLink('Home', () => _scrollTo(_heroKey)),
                const SizedBox(width: 28),
                _navLink('Features', () => _scrollTo(_featuresKey)),
                const SizedBox(width: 28),
                _navLink('About', () => _scrollTo(_aboutKey)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _navLink(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          color: Color(0x8CFFFFFF),
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    return Container(
      key: _heroKey,
      color: const Color(0xFF060d1f),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final isNarrow = constraints.maxWidth < 700;
          if (isNarrow) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [_buildHeroLeft(context)],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(60, 80, 60, 60),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [Expanded(child: _buildHeroLeft(context))],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeroLeft(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF3B9EFF).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF3B9EFF).withValues(alpha: 0.3),
            ),
          ),
          child: const Text(
            '3D immersive coding platform',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: Color(0xFF3B9EFF),
            ),
          ),
        ),
        const SizedBox(height: 20),
        RichText(
          text: const TextSpan(
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 38,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.15,
            ),
            children: [
              TextSpan(text: 'Learn to code in\na '),
              TextSpan(
                text: '3D classroom',
                style: TextStyle(color: Color(0xFF3B9EFF)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'An immersive learning management system where '
          'students write real C++ code, get auto-graded in '
          'real time, and compete on live leaderboards.',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            color: Color(0x80FFFFFF),
            height: 1.6,
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.login),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B9EFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Get started',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () => context.go(AppRoutes.login),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Sign in',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        const Text(
          'ALSO AVAILABLE ON',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            color: Color(0x55FFFFFF),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'APK download coming soon!',
                  style: TextStyle(fontFamily: 'Poppins'),
                ),
                backgroundColor: Color(0xFF111d33),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.android_rounded,
                  color: Color(0xFF4CAF50),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Download for Android',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'APK • Coming soon',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturesSection() {
    return Container(
      key: _featuresKey,
      color: const Color(0xFF080e20),
      padding: const EdgeInsets.fromLTRB(60, 60, 60, 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Features',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Everything you need for immersive coding education',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              color: Color(0x80FFFFFF),
            ),
          ),
          const SizedBox(height: 32),
          LayoutBuilder(
            builder: (ctx, constraints) {
              final w = constraints.maxWidth;
              final cols = w > 900
                  ? 3
                  : w > 600
                  ? 2
                  : 1;
              final ratio = w > 900
                  ? 1.6
                  : w > 600
                  ? 1.8
                  : 3.5;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: ratio,
                ),
                itemCount: _features.length,
                itemBuilder: (ctx, i) {
                  final f = _features[i];
                  final isExpanded = _expandedFeature == i;
                  final color = f['color'] as Color;

                  return GestureDetector(
                    onTap: () => setState(
                      () => _expandedFeature = isExpanded ? -1 : i,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: isExpanded
                            ? color.withValues(alpha: 0.1)
                            : const Color(0xFF111d33),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isExpanded
                              ? color.withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(f['icon'] as IconData, color: color, size: 22),
                          const SizedBox(height: 10),
                          Text(
                            f['title'] as String,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isExpanded ? color : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isExpanded
                                ? f['detail'] as String
                                : f['summary'] as String,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.5),
                              height: 1.5,
                            ),
                            maxLines: isExpanded ? 6 : 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
    return Container(
      key: _aboutKey,
      color: const Color(0xFF060d1f),
      padding: const EdgeInsets.fromLTRB(60, 60, 60, 80),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'About Code Lab 3D',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Code Lab 3D is an immersive learning management '
                  'system built for Pampanga State University. Students '
                  'write real C++ code inside a Unity 3D classroom, get '
                  'auto-graded in real time, and compete on live '
                  'per-class leaderboards.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: Color(0x80FFFFFF),
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'BUILT WITH',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Color(0x55FFFFFF),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      [
                        'Flutter',
                        'Unity 6',
                        'Supabase',
                        'JDoodle API',
                        'Vercel',
                        'Photon Fusion 2',
                      ].map((tech) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF3B9EFF,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(
                                0xFF3B9EFF,
                              ).withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            tech,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: Color(0xFF3B9EFF),
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
          SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DEVELOPMENT TEAM',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Color(0x55FFFFFF),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 14),
                ...[
                  {
                    'name': 'Beltran, Joshua Alexandre P.',
                    'initials': 'JB',
                    'color': const Color(0xFF7B2FBE),
                  },
                  {
                    'name': 'Bernal, Lynix Ivy D.',
                    'initials': 'LB',
                    'color': const Color(0xFF3B9EFF),
                  },
                  {
                    'name': 'Guintu, John Dexter M.',
                    'initials': 'JG',
                    'color': const Color(0xFF4CAF50),
                  },
                  {
                    'name': 'Hermano, Aaron L.',
                    'initials': 'AH',
                    'color': const Color(0xFFFF9800),
                  },
                  {
                    'name': 'Rodriguez, Chrys-Enjie R.',
                    'initials': 'CR',
                    'color': const Color(0xFFFF5252),
                  },
                ].map((member) {
                  final color = member['color'] as Color;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: color.withValues(alpha: 0.2),
                          child: Text(
                            member['initials'] as String,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          member['name'] as String,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color color;
  _GridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    const spacing = 30.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}