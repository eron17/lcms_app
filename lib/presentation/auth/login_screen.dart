// lib/presentation/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/foundation.dart';
import '../../core/router/app_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../shared/widgets/pressable_scale.dart';
import '../../core/utils/string_utils.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
class LoginScreen extends StatefulWidget {
  final bool showRegister;
  const LoginScreen({super.key, this.showRegister = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  // ─── Tab State ───────────────────────────────────────────
  late bool _isSignIn;
  bool _isStudent = true;
  bool _isLoading = false;
  String _selectedSex = 'male';

  // ─── Password Visibility ─────────────────────────────────
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  bool _secretVisible = false;

  // ─── Controllers ─────────────────────────────────────────
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _secretController = TextEditingController();
  final _forgotEmailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ─── Supabase ────────────────────────────────────────────
  final _supabase = Supabase.instance.client;

  // ─── Biometrics ──────────────────────────────────────────
  final _localAuth = LocalAuthentication();
  bool _biometricsAvailable = false;

  // ─── Animations ──────────────────────────────────────────
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _isSignIn = !widget.showRegister;
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _checkBiometrics();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _tryAutoBiometricSignIn(),
    );
  }

  // Auto-triggers the existing biometric sign-in instead of requiring a
  // button tap, but only when this device actually has saved credentials
  // to unlock with — otherwise _authenticateWithBiometrics() would show
  // its "sign in with email first" error the instant the screen opens,
  // before a first-time user has done anything.
  Future<void> _tryAutoBiometricSignIn() async {
    if (!_isSignIn) return;
    final savedEmail = await _storage.read(key: 'user_email');
    final savedPassword = await _storage.read(key: 'user_password');
    if (savedEmail == null ||
        savedPassword == null ||
        savedEmail.isEmpty ||
        savedPassword.isEmpty) {
      return;
    }
    if (!mounted) return;
    await _checkBiometrics();
    if (!mounted || !_biometricsAvailable) return;
    await _authenticateWithBiometrics();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _secretController.dispose();
    _forgotEmailController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  // ─── Biometrics ──────────────────────────────────────────
  Future<void> _checkBiometrics() async {
    if (kIsWeb) return;
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (mounted) {
        setState(
          () => _biometricsAvailable = !kIsWeb && canCheck && isSupported,
        );
      }
    } catch (e) {
      debugPrint('Biometrics check error: $e');
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    try {
      // 1. Check if we have saved credentials first
      final savedEmail = await _storage.read(key: 'user_email');
      final savedPassword = await _storage.read(key: 'user_password');

      if (!mounted) return;
      if (savedEmail == null ||
          savedPassword == null ||
          savedEmail.isEmpty ||
          savedPassword.isEmpty) {
        _showError(
          'Please sign in with email and password first to enable biometrics.',
        );
        return;
      }

      // 2. Trigger the Fingerprint/FaceID scanner
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Scan your fingerprint to sign in',
        options: const AuthenticationOptions(
          biometricOnly: true, // Force fingerprint/FaceID
          stickyAuth: true,
        ),
      );

      if (authenticated && mounted) {
        setState(() => _isLoading = true);

        // 3. Log in to Supabase using the SECURELY stored credentials
        final response = await _supabase.auth.signInWithPassword(
          email: savedEmail,
          password: savedPassword,
        );

        final biometricUser = response.user;
        if (biometricUser != null && mounted) {
          await _navigateToDashboard(biometricUser.id);
        }
      }
    } catch (e) {
      debugPrint('Biometric Error: $e');
      if (mounted) _showError('Biometric authentication failed.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Auth Logic ──────────────────────────────────────────
  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      if (_isSignIn) {
        // ─── Sign In ───────────────────────────────────────
        final response = await _supabase.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        final signedInUser = response.user;
        if (signedInUser != null && mounted) {
          // ─── NEW: Save credentials for future biometric login ───
          await _storage.write(
            key: 'user_email',
            value: _emailController.text.trim(),
          );
          await _storage.write(
            key: 'user_password',
            value: _passwordController.text.trim(),
          );

          await _navigateToDashboard(signedInUser.id);
        }
      } else {
        // ─── Sign Up ───────────────────────────────────────
        if (!_isStudent) {
          final settings = await _supabase
              .from('app_settings')
              .select('value')
              .eq('key', 'faculty_secret_code')
              .single();
          if (_secretController.text.trim() != settings['value']) {
            throw 'Invalid faculty secret code.';
          }
        }

        final response = await _supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        final newUser = response.user;
        if (newUser != null) {
          await _supabase.from('users').insert({
            'id': newUser.id,
            'name': toTitleCase(_nameController.text.trim()),
            'email': _emailController.text.trim(),
            'role': _isStudent ? 'student' : 'instructor',
            'sex': _isStudent ? _selectedSex : null,
            'xp': 0,
            'level': 1,
            'badges': [],
            'streak': 0,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });

          if (mounted) {
            // Show success snackbar
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: Colors.white,
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Account Created! Please sign in.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.green.shade700,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                duration: const Duration(seconds: 2),
              ),
            );
            // Sign out to clear session, then redirect to Sign In tab
            await _supabase.auth.signOut();
            await Future.delayed(const Duration(milliseconds: 500));
            if (mounted) setState(() => _isSignIn = true);
          }
        }
      }
    } on AuthException catch (e) {
      if (kDebugMode) debugPrint('Auth error: ${e.statusCode} ${e.message}');
      if (!mounted) return;
      String message;
      if (_isSignIn) {
        // Never say specifically whether the email or password was wrong —
        // that would let an attacker enumerate registered emails.
        switch (e.statusCode) {
          case '400':
            message = 'Invalid email or password.';
            break;
          case '422':
            message = 'Email format is not valid.';
            break;
          case '429':
            message = 'Too many attempts. Please wait and try again.';
            break;
          case '500':
            message = 'Server error. Please try again later.';
            break;
          default:
            message = 'Sign in failed. Please try again.';
        }
      } else {
        switch (e.statusCode) {
          case '400':
            message =
                'This email is already registered. Please sign in instead.';
            break;
          case '422':
            message = 'Email format is not valid.';
            break;
          case '429':
            message = 'Too many attempts. Please wait and try again.';
            break;
          case '500':
            message = 'Server error. Please try again later.';
            break;
          default:
            message = 'Sign up failed. Please try again.';
        }
      }
      _showError(message);
    } catch (e) {
      if (kDebugMode) debugPrint('Auth error: $e');
      if (!mounted) return;
      // Never show a raw backend/exception message here — it can leak
      // account-enumeration signals or internal details the user
      // shouldn't see. The one exception is our own app-thrown secret
      // code error, which is safe to show verbatim.
      if (e.toString().contains('Invalid faculty secret code')) {
        _showError('Invalid faculty secret code.');
      } else {
        _showError(
          _isSignIn
              ? 'Unable to sign in. Please try again.'
              : 'Unable to create your account. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _navigateToDashboard(String userId) async {
    final userData = await _supabase
        .from('users')
        .select('role')
        .eq('id', userId)
        .single();
    if (!mounted) return;
    final role = userData['role'];
    if (role == 'instructor') {
      context.go(AppRoutes.instructorDashboard);
    } else if (role == 'student') {
      context.go(AppRoutes.studentDashboard);
    } else {
      await _supabase.auth.signOut();
      if (!mounted) return;
      _showError('Your account role is invalid. Please contact support.');
    }
  }

  // ─── Forgot Password → OTP Verification Screen ─────────────
  void _showForgotPasswordDialog() async {
    _forgotEmailController.text = _emailController.text.trim();
    bool isSending = false;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF0D1B4B) : Colors.white;
    final borderColor = isDark ? AppColors.darkBorder : const Color(0xFFDDE3F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0D1B4B);
    final subtitleColor = isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF0D1B4B).withValues(alpha: 0.5);
    final cancelBg = isDark ? AppColors.darkCard : const Color(0xFFF0F4FF);
    final cancelTextColor = isDark ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF0D1B4B).withValues(alpha: 0.7);

    final sentToEmail = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => Dialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: borderColor)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.lock_reset_outlined, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Text('Forgot Password',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Enter your email and we\'ll send you an OTP code.',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: subtitleColor, height: 1.4),
                ),
                const SizedBox(height: 20),

                _buildField(label: 'Email Address', controller: _forgotEmailController, icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: PressableScale(
                        onPressed: () => Navigator.pop(context),
                        scaleFactor: 0.98,
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(color: cancelBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
                          child: Center(child: Text('Cancel', style: TextStyle(fontFamily: 'Poppins', color: cancelTextColor, fontWeight: FontWeight.w600))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PressableScale(
                        onPressed: isSending ? null : () async {
                          final email = _forgotEmailController.text.trim();
                          if (email.isEmpty || !email.contains('@')) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid email.'), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating));
                            return;
                          }
                          setDialog(() => isSending = true);
                          try {
                            await _supabase.auth.resetPasswordForEmail(email, redirectTo: 'com.psulubao.it.lcms_app://reset-password');
                            if (context.mounted) {
                              // Return the email as the dialog's own pop result
                              // instead of popping then immediately pushing —
                              // that let the dialog's close transition and the
                              // OTP screen's enter transition overlap on the
                              // same navigator, which looked janky. Pushing
                              // only happens after the dialog has fully closed.
                              Navigator.pop(context, email);
                            }
                          } catch (e) {
                            setDialog(() => isSending = false);
                            if (kDebugMode) debugPrint('Reset password error: $e');
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Something went wrong. Please try again.'), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating));
                          }
                        },
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
                          child: Center(
                            child: isSending
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('Send OTP', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (sentToEmail != null && mounted) {
      context.push(AppRoutes.verifyOtp, extra: sentToEmail);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (kIsWeb) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF060d1f) : null,
            gradient: isDark
                ? null
                : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFF0F4FF), Color(0xFFE8EEFF)],
                  ),
          ),
          child: Column(
            children: [
              Container(
                height: 56,
                color: isDark ? const Color(0xFF080e20) : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Row(
                  children: [
                    Image.asset('assets/images/logo.png', height: 32),
                    const SizedBox(width: 10),
                    Image.asset('assets/images/app_name.png', height: 22),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 48,
                    ),
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: _buildLoginForm(),
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

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? const RadialGradient(
                  center: Alignment(0, -0.3),
                  radius: 1.2,
                  colors: [Color(0xFF0D1B4B), AppColors.darkBackground],
                )
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF0F4FF), Color(0xFFE8EEFF)],
                ),
        ),
        child: Stack(
          children: [
            _buildGridOverlay(size),
            if (isDark) _buildGlowEffect(size),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: _buildLoginForm(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          const SizedBox(height: 36),

          // ─── Header Image ──────────────────────
          if (!kIsWeb)
            Image.asset(
              'assets/images/logo.png',
              height: 120,
              fit: BoxFit.contain,
            ),
          if (!kIsWeb) const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Image.asset(
              _isSignIn
                  ? 'assets/images/welcome_text.png'
                  : 'assets/images/create_account_text.png',
              key: ValueKey(_isSignIn),
              height: 48,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 20),

          // ─── Sign In / Sign Up Toggle ──────────
          _buildTabSwitcher(
            leftLabel: 'Sign In',
            rightLabel: 'Sign Up',
            isLeftActive: _isSignIn,
            onLeftTap: () => setState(() => _isSignIn = true),
            onRightTap: () => setState(() => _isSignIn = false),
          ),

          const SizedBox(height: 22),

          AnimatedSize(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic,
            child: Column(
              children: [
                // ─── Role Tab (Sign Up only) ───────
                _animatedField(
                  isVisible: !_isSignIn,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _buildTabSwitcher(
                      leftLabel: 'Student',
                      rightLabel: 'Instructor',
                      isLeftActive: _isStudent,
                      onLeftTap: () => setState(() => _isStudent = true),
                      onRightTap: () => setState(() => _isStudent = false),
                    ),
                  ),
                ),

                // ─── Full Name (Sign Up only) ──────
                _animatedField(
                  isVisible: !_isSignIn,
                  child: _buildField(
                    label: 'Full Name',
                    controller: _nameController,
                    icon: Icons.person_outline,
                    validator: (v) {
                      if (!_isSignIn) {
                        final name = v?.trim() ?? '';
                        if (name.isEmpty) {
                          return 'Full name is required.';
                        }
                        if (name.length < 2) {
                          return 'Enter your full name.';
                        }
                      }
                      return null;
                    },
                  ),
                ),

                // ─── Sex Radio Buttons (Student Sign Up only) ─
                _buildSexSelector(),

                // ─── Email ─────────────────────────
                _buildField(
                  label: _emailFieldLabel,
                  controller: _emailController,
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Email is required.';
                    }
                    final emailRegex = RegExp(
                      r'^[a-zA-Z0-9._%+\-]+@'
                      r'[a-zA-Z0-9.\-]+\.'
                      r'[a-zA-Z]{2,}$',
                    );
                    if (!emailRegex.hasMatch(v.trim())) {
                      return 'Enter a valid email address.';
                    }
                    return null;
                  },
                ),

                // ─── Faculty Secret Code ───────────
                _animatedField(
                  isVisible: !_isSignIn && !_isStudent,
                  child: _buildField(
                    label: 'Faculty Secret Code',
                    controller: _secretController,
                    icon: Icons.verified_user_outlined,
                    isPassword: true,
                    passwordVisible: _secretVisible,
                    onToggle: () =>
                        setState(() => _secretVisible = !_secretVisible),
                    validator: (v) {
                      if (!_isSignIn &&
                          !_isStudent &&
                          (v == null || v.isEmpty)) {
                        return 'Enter the faculty secret code';
                      }
                      return null;
                    },
                  ),
                ),

                // ─── Password ──────────────────────
                _buildField(
                  label: 'Password',
                  hintText: !_isSignIn
                      ? 'Min 8 chars, 1 number, 1 special character'
                      : null,
                  controller: _passwordController,
                  icon: Icons.lock_outline,
                  isPassword: true,
                  passwordVisible: _passwordVisible,
                  onToggle: () =>
                      setState(() => _passwordVisible = !_passwordVisible),
                  validator: (v) {
                    // Sign in never enforces complexity — existing accounts
                    // created before these rules must still be able to log in.
                    if (_isSignIn) {
                      if (v == null || v.isEmpty) {
                        return 'Password is required.';
                      }
                      return null;
                    }
                    if (v == null || v.isEmpty) {
                      return 'Password is required.';
                    }
                    if (v.length < 8) {
                      return 'Password must be at least 8 characters.';
                    }
                    if (v.length > 128) {
                      return 'Password must not exceed 128 characters.';
                    }
                    if (!RegExp(r'[0-9]').hasMatch(v)) {
                      return 'Password must contain at least one number.';
                    }
                    if (!RegExp(
                      r'[!@#$%^&*()_+\-=\[\]{}|;:'
                      r"'"
                      r'",.<>?/\\`~]',
                    ).hasMatch(v)) {
                      return 'Password must contain at least one special '
                          'character.';
                    }
                    return null;
                  },
                ),

                // ─── Confirm Password (Sign Up only) ─
                _animatedField(
                  isVisible: !_isSignIn,
                  child: _buildField(
                    label: 'Confirm Password',
                    controller: _confirmPasswordController,
                    icon: Icons.lock_outline,
                    isPassword: true,
                    passwordVisible: _confirmPasswordVisible,
                    onToggle: () => setState(
                      () => _confirmPasswordVisible = !_confirmPasswordVisible,
                    ),
                    validator: (v) {
                      if (!_isSignIn) {
                        if (v == null || v.isEmpty) {
                          return 'Confirm your password';
                        }
                        if (v != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                      }
                      return null;
                    },
                  ),
                ),

                // ─── Forgot Password (Sign In only) ─
                _animatedField(
                  isVisible: _isSignIn,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: PressableScale(
                        onPressed: _showForgotPasswordDialog,
                        scaleFactor: 1.0, // DISABLES the shrink/animation
                        opacityFactor: 0.5, // ENABLES the dimming effect
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 4,
                          ),
                          child: Text(
                            'Forgot Password?',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ─── Submit Button ─────────────────────
          _buildActionButton(),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  String get _emailFieldLabel {
    if (_isSignIn) return 'Email Address';
    if (_isStudent) return 'Student Email Address';
    return 'Faculty Email Address';
  }

  Widget _buildSexSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _animatedField(
      isVisible: !_isSignIn && _isStudent,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : const Color(0xFFDDE3F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.wc_outlined,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.3)
                        : const Color(0xFF0D1B4B).withValues(alpha: 0.4),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Sex',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.5)
                          : const Color(0xFF0D1B4B).withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _selectedSex,
                onChanged: (v) => setState(() => _selectedSex = v ?? 'male'),
                child: Row(
                  children: [
                    // Male
                    Expanded(
                      child: PressableScale(
                        onPressed: () => setState(() => _selectedSex = 'male'),
                        scaleFactor: 0.97,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedSex == 'male'
                                ? AppColors.primary.withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectedSex == 'male'
                                  ? AppColors.primary
                                  : (isDark
                                        ? AppColors.darkBorder
                                        : const Color(0xFFDDE3F0)),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Radio<String>(
                                value: 'male',
                                activeColor: AppColors.primary,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              Text(
                                'Male',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0D1B4B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Female
                    Expanded(
                      child: PressableScale(
                        onPressed: () =>
                            setState(() => _selectedSex = 'female'),
                        scaleFactor: 0.97,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedSex == 'female'
                                ? const Color(0xFFFF69B4).withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectedSex == 'female'
                                  ? const Color(0xFFFF69B4)
                                  : (isDark
                                        ? AppColors.darkBorder
                                        : const Color(0xFFDDE3F0)),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Radio<String>(
                                value: 'female',
                                activeColor: Color(0xFFFF69B4),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              Text(
                                'Female',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0D1B4B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _animatedField({required bool isVisible, required Widget child}) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: isVisible ? 1.0 : 0.0,
        child: isVisible
            ? child
            : const SizedBox(width: double.infinity, height: 0),
      ),
    );
  }

  Widget _buildField({
    required String label,
    String? hintText,
    required TextEditingController controller,
    required IconData icon,
    bool isPassword = false,
    bool passwordVisible = false,
    VoidCallback? onToggle,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0D1B4B);
    final fillColor = context.cardColor;
    final borderColor = isDark
        ? AppColors.darkBorder
        : const Color(0xFFDDE3F0);
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.5)
        : const Color(0xFF0D1B4B).withValues(alpha: 0.4);
    final iconColor = isDark
        ? Colors.white.withValues(alpha: 0.3)
        : const Color(0xFF0D1B4B).withValues(alpha: 0.4);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword && !passwordVisible,
        keyboardType: keyboardType,
        validator: validator,
        style: TextStyle(fontFamily: 'Poppins', color: textColor, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          hintStyle: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            color: hintColor,
          ),
          labelStyle: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: hintColor,
          ),
          floatingLabelStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: Icon(icon, color: iconColor, size: 20),
          filled: true,
          fillColor: fillColor,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
          errorStyle: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.redAccent,
            fontSize: 11,
          ),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    passwordVisible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: iconColor,
                    size: 20,
                  ),
                  onPressed: onToggle,
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildTabSwitcher({
    required String leftLabel,
    required String rightLabel,
    required bool isLeftActive,
    required VoidCallback onLeftTap,
    required VoidCallback onRightTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : const Color(0xFFDDE3F0),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          _buildTab(leftLabel, isLeftActive, onLeftTap),
          _buildTab(rightLabel, !isLeftActive, onRightTap),
        ],
      ),
    );
  }

  Widget _buildTab(String label, bool isActive, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor = isDark
        ? Colors.white.withValues(alpha: 0.5)
        : const Color(0xFF0D1B4B).withValues(alpha: 0.5);
    return Expanded(
      child: PressableScale(
        onPressed: onTap,
        scaleFactor: 0.97,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            gradient: isActive
                ? const LinearGradient(
                    colors: [AppColors.primaryDark, AppColors.primary],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? Colors.white : inactiveColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
  return PressableScale(
    onPressed: _isLoading ? null : _handleSubmit,
    child: AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) => Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primaryDark, AppColors.primary],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: _glowAnimation.value * 0.5),
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
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Text(
                  _isSignIn ? 'Sign In' : 'Sign Up',
                  style: const TextStyle(
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

  Widget _buildGridOverlay(Size size) {
    return Opacity(
      opacity: 0.04,
      child: CustomPaint(size: size, painter: _GridPainter()),
    );
  }

  Widget _buildGlowEffect(Size size) {
    return Positioned(
      top: -60,
      left: size.width * 0.5 - 120,
      child: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) => Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFF1E90FF,
                ).withValues(alpha: _glowAnimation.value * 0.5),
                blurRadius: 100,
                spreadRadius: 30,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
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
