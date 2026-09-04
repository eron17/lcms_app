import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pinput/pinput.dart';
import 'dart:async';
import '../../core/router/app_router.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/pressable_scale.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String email;

  const OtpVerificationScreen({super.key, required this.email});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen>
    with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _pinController = TextEditingController();

  // Timer State
  late Timer _timer;
  int _secondsRemaining = 300; // 5 minutes

  // UI/Animation State
  bool _isLoading = false;
  bool _isVerified = false;
  bool _isError = false;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _initShakeAnimation();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        if (mounted) setState(() => _secondsRemaining--);
      } else {
        _timer.cancel();
      }
    });
  }

  void _initShakeAnimation() {
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 12.0), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: 12.0, end: -12.0), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: -12.0, end: 12.0), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: 12.0, end: 0.0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
    );
  }

  Future<void> _triggerShake() async {
    HapticFeedback.vibrate();
    await _shakeController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _timer.cancel();
    _pinController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _maskEmail(String email) {
    try {
      final parts = email.split('@');
      if (parts.length != 2) return email;
      final name = parts[0];
      final domain = parts[1];
      if (name.length <= 2) return '$name@$domain';
      return '${name[0]}${'*' * (name.length - 2)}${name[name.length - 1]}@$domain';
    } catch (_) {
      return email;
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _pinController.text.trim();
    if (otp.length < 6) {
      setState(() => _isError = true);
      _triggerShake();
      return;
    }

    setState(() {
      _isLoading = true;
      _isError = false;
    });

    try {
      await _supabase.auth.verifyOTP(
        email: widget.email,
        token: otp,
        type: OtpType.recovery,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isVerified = true;
        });

        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          context.pushReplacement(AppRoutes.resetPassword);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isError = true;
          _pinController.clear();
        });
        _triggerShake();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0D1B4B);
    final isExpired = _secondsRemaining == 0;

    if (_isVerified) {
      return Scaffold(
        backgroundColor: const Color(0xFF22C55E),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 80,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Verified successfully',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.bgColor,
      body: Stack(
        children: [
          Container(decoration: context.scaffoldGradient),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  PressableScale(
                    onPressed: () => Navigator.pop(context),
                    scaleFactor: 1.0,
                    opacityFactor: 0.5,
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: textColor,
                      size: 25,
                    ),
                  ),
                  const SizedBox(height: 48),

                  Text(
                    'OTP Verification',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              color: textColor.withValues(alpha: 0.5),
                              height: 1.4,
                            ),
                            children: [
                              const TextSpan(text: 'We have sent the verification code to your email address '),
                              TextSpan(
                                text: _maskEmail(widget.email),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),

                  Center(
                    child: AnimatedBuilder(
                      animation: _shakeAnimation,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(_shakeAnimation.value, 0),
                        child: Pinput(
                          length: 6,
                          controller: _pinController,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          autofocus: true,
                          defaultPinTheme: PinTheme(
                            width: size.width * 0.12,
                            height: 56,
                            textStyle: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                            decoration: BoxDecoration(
                              color: context.cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _isError
                                    ? Colors.redAccent
                                    : context.borderColor,
                                width: _isError ? 1.5 : 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_isError)
                    const Center(
                      child: Text(
                        'Wrong code, please try again',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.redAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),

                  Center(
                    child: Text(
                      isExpired
                          ? 'The code has expired.'
                          : 'The code will expire - ${_formatTime(_secondsRemaining)}',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: isExpired ? Colors.redAccent : textColor.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  PressableScale(
                    onPressed: _isLoading || isExpired ? null : _verifyOtp,
                    child: Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primaryDark,
                            isExpired ? Colors.grey : AppColors.primary,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Center(
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                            : const Text(
                                'Confirm',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "If you didn't receive a code? ",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: textColor.withValues(alpha: 0.5),
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            if (!isExpired) return;
                            try {
                              await _supabase.auth.resetPasswordForEmail(widget.email);
                              setState(() {
                                _secondsRemaining = 300;
                                _isError = false;
                                _pinController.clear();
                              });
                              _startTimer();
                            } catch (_) {}
                          },
                          child: Text(
                            'Resend',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isExpired ? AppColors.primary : Colors.grey,
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
        ],
      ),
    );
  }
}
