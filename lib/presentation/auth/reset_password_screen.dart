// lib/presentation/auth/reset_password_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/router/app_router.dart';
import '../../shared/widgets/pressable_scale.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen>
    with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _newPassVisible = false;
  bool _confirmPassVisible = false;
  bool _isLoading = false;
  bool _isSuccess = false;

  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await _supabase.auth.updateUser(
        UserAttributes(password: _newPasswordController.text.trim()),
      );
      if (mounted) {
        await _supabase.auth.signOut();
        setState(() { _isLoading = false; _isSuccess = true; });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(child: Text('Password reset successfully! Please sign in.',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600))),
            ]),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 3),
          ),
        );

        await Future.delayed(const Duration(seconds: 2));
        if (mounted) context.go(AppRoutes.login);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e', style: const TextStyle(fontFamily: 'Poppins')),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Widget _buildResetButton() {
    return PressableScale(
      onPressed: _isLoading ? null : _resetPassword,
      scaleFactor: 0.96, // Action button moves
      opacityFactor: 0.7,
      child: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) => Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1565C0), Color(0xFF1E90FF)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1E90FF).withValues(alpha: _glowAnimation.value * 0.5),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : const Text(
                    'Reset Password',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ─── REPLACED: THE BACK LINK ───────────────────────────────────────────────

  Widget _buildBackToSignIn() {
    return PressableScale(
      onPressed: () => context.go(AppRoutes.login),
      scaleFactor: 1.0, // Text link does not move
      opacityFactor: 0.5, // Only dims
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.arrow_back, color: Color(0xFF1E90FF), size: 14),
            SizedBox(width: 8),
            Text(
              'Back to Sign In',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E90FF), // Branding blue
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF080D1F) : const Color(0xFFF5F7FF),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? const RadialGradient(center: Alignment(0, -0.3), radius: 1.2, colors: [Color(0xFF0D1B4B), Color(0xFF080D1F)])
              : const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF0F4FF), Color(0xFFE8EEFF)]),
        ),
        child: Stack(
          children: [
            Opacity(opacity: 0.04, child: CustomPaint(size: size, painter: _GridPainter())),
            if (isDark) _buildTopGlow(size),

            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Icon Section
                        _buildStatusIcon(),
                        const SizedBox(height: 32),

                        // Text Section (Title & Subtitle)
                        _buildHeaderStrings(isDark),
                        const SizedBox(height: 36),

                        // Conditional content: Form or Final Success Indicator
                        AnimatedSize(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOutCubic,
                          child: _isSuccess 
                            ? const Padding(
                                padding: EdgeInsets.only(top: 20),
                                child: CircularProgressIndicator(color: Color(0xFF1E90FF), strokeWidth: 2),
                              )
                            : Column(
                                children: [
                                  _buildField(
                                    label: 'New Password',
                                    controller: _newPasswordController,
                                    icon: Icons.lock_outline_rounded,
                                    isPassword: true,
                                    isVisible: _newPassVisible,
                                    onToggle: () => setState(() => _newPassVisible = !_newPassVisible),
                                    validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
                                  ),
                                  _buildField(
                                    label: 'Confirm New Password',
                                    controller: _confirmPasswordController,
                                    icon: Icons.lock_reset_rounded,
                                    isPassword: true,
                                    isVisible: _confirmPassVisible,
                                    onToggle: () => setState(() => _confirmPassVisible = !_confirmPassVisible),
                                    validator: (v) => (v != _newPasswordController.text) ? 'Passwords do not match' : null,
                                  ),
                                  const SizedBox(height: 12),
                                  _buildResetButton(),
                                  const SizedBox(height: 16),
                                  _buildBackToSignIn(),
                                ],
                              ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopGlow(Size size) {
    return Positioned(
      top: -60, left: size.width * 0.5 - 120,
      child: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) => Container(
          width: 240, height: 240,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: const Color(0xFF1E90FF).withValues(alpha: _glowAnimation.value * 0.5), blurRadius: 100, spreadRadius: 30)],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
      child: _isSuccess
          ? Container(
              key: const ValueKey('icon_success'),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), shape: BoxShape.circle, border: Border.all(color: Colors.green.withValues(alpha: 0.4), width: 2.5)),
              child: const Icon(Icons.check_rounded, color: Colors.green, size: 64),
            )
          : Container(
              key: const ValueKey('icon_lock'),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(color: const Color(0xFF1E90FF).withValues(alpha: 0.15), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF1E90FF).withValues(alpha: 0.3), width: 2.5)),
              child: const Icon(Icons.vpn_key_outlined, color: Color(0xFF1E90FF), size: 64),
            ),
    );
  }

  Widget _buildHeaderStrings(bool isDark) {
    final title = _isSuccess ? 'Password Reset!' : 'Reset Password';
    final subtitle = _isSuccess 
        ? 'Your password has been updated\nsuccessfully. Redirecting...' 
        : 'Enter your new password below.';
    
    return Column(
      children: [
        Text(title, style: TextStyle(fontFamily: 'Poppins', fontSize: 28, fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF0D1B4B))),
        const SizedBox(height: 12),
        Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF0D1B4B).withValues(alpha: 0.6), height: 1.5)),
      ],
    );
  }

  

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required bool isPassword,
    required bool isVisible,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0D1B4B);
    final fillColor = isDark ? const Color(0xFF0A1128) : Colors.white;
    final borderColor = isDark ? const Color(0xFF1E3A6E) : const Color(0xFFDDE3F0);
    final iconColor = isDark ? Colors.white.withValues(alpha: 0.3) : const Color(0xFF0D1B4B).withValues(alpha: 0.4);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword && !isVisible,
        validator: validator,
        style: TextStyle(fontFamily: 'Poppins', color: textColor, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: iconColor),
          floatingLabelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Color(0xFF1E90FF), fontWeight: FontWeight.w600),
          prefixIcon: Icon(icon, color: iconColor, size: 20),
          suffixIcon: IconButton(
            icon: Icon(isVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: iconColor, size: 20),
            onPressed: onToggle,
          ),
          filled: true, fillColor: fillColor,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor, width: 1)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor, width: 1)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E90FF), width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent, width: 1)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent, width: 1.5)),
          errorStyle: const TextStyle(fontFamily: 'Poppins', color: Colors.redAccent, fontSize: 11),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white..strokeWidth = 0.5;
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
