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

enum ButtonState { normal, loading, success, error }

class _OtpVerificationScreenState extends State<OtpVerificationScreen>
    with TickerProviderStateMixin {
  // Matches the same success-green constant used elsewhere in the app
  // (post_detail_screen.dart, three_d_meet_detail_screen.dart, etc.).
  static const Color _successGreen = Color(0xFF22C55E);

  final _supabase = Supabase.instance.client;
  final _pinController = TextEditingController();

  // Timer State
  late Timer _timer;
  int _secondsRemaining = 300; // 5 minutes

  // UI/Animation State
  bool _isError = false;
  ButtonState _buttonState = ButtonState.normal;

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
      setState(() {
        _isError = true;
        _buttonState = ButtonState.error;
      });
      _triggerShake();

      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        setState(() {
          _isError = false;
          _buttonState = ButtonState.normal;
        });
      }
      return;
    }

    setState(() {
      _buttonState = ButtonState.loading;
      _isError = false;
    });

    try {
      await _supabase.auth.verifyOTP(
        email: widget.email,
        token: otp,
        type: OtpType.recovery,
      );

      if (mounted) {
        setState(() => _buttonState = ButtonState.success);

        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          context.pushReplacement(AppRoutes.resetPassword);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isError = true;
          _pinController.clear();
          _buttonState = ButtonState.error;
        });
        _triggerShake();

        // Revert button back to normal after 1.5s
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          setState(() {
            _isError = false;
            _buttonState = ButtonState.normal;
          });
        }
      }
    }
  }

  Widget get _buildButtonChild {
    switch (_buttonState) {
      case ButtonState.loading:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.5,
          ),
        );
      case ButtonState.success:
        return const Icon(Icons.check_rounded, color: Colors.white, size: 28);
      case ButtonState.error:
        return const Icon(Icons.close_rounded, color: Colors.white, size: 28);
      case ButtonState.normal:
        return const Text(
          'Confirm',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0D1B4B);
    final isExpired = _secondsRemaining == 0;

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
                                    : _buttonState == ButtonState.success
                                        ? _successGreen
                                        : context.borderColor,
                                width: (_isError || _buttonState == ButtonState.success) ? 1.5 : 1,
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

                  Center( // Wrapped in Center so the button stays aligned as it
                          // shrinks — it's a direct child of a Column with
                          // crossAxisAlignment.start, so without this it would
                          // snap to the left edge instead of shrinking in place.
                    child: PressableScale(
                      onPressed: _buttonState == ButtonState.loading || isExpired ? null : _verifyOtp,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        // Finite width (screen width minus the 28+28 horizontal
                        // padding from the SingleChildScrollView above) instead
                        // of double.infinity — AnimatedContainer can't
                        // interpolate a width tween between infinity and a
                        // finite value, which crashed with "Cannot interpolate
                        // between finite and unbounded constraints" the moment
                        // the button tried to shrink.
                        width: _buttonState == ButtonState.normal
                            ? MediaQuery.of(context).size.width - 56.0
                            : 56.0,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(_buttonState == ButtonState.normal ? 32 : 28),
                          gradient: _buttonState == ButtonState.normal
                              ? LinearGradient(
                                  colors: [
                                    AppColors.primaryDark,
                                    isExpired ? Colors.grey : AppColors.primary,
                                  ],
                                )
                              : null,
                          color: _buttonState == ButtonState.success
                              ? _successGreen
                              : _buttonState == ButtonState.error
                                  ? Colors.redAccent
                                  : _buttonState == ButtonState.loading
                                      ? AppColors.primary
                                      : null,
                        ),
                        child: Center(
                          child: _buildButtonChild,
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
