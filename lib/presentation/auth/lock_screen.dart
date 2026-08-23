import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/utils/app_security_manager.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  final VoidCallback onLogout;

  const LockScreen({
    super.key,
    required this.onUnlocked,
    required this.onLogout,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _localAuth = LocalAuthentication();
  bool _isAuthenticating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isAvailable = await _localAuth.isDeviceSupported();

      if (canCheck && isAvailable) {
        final authenticated = await _localAuth.authenticate(
          localizedReason: 'Authenticate to access Code Lab 3D',
          options: const AuthenticationOptions(
            biometricOnly: false,
            stickyAuth: true,
          ),
        );
        if (authenticated && mounted) {
          AppSecurityManager().unlock();
          widget.onUnlocked();
        }
      } else {
        // No biometric — go straight to login
        widget.onLogout();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Authentication failed. Please log in again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isAuthenticating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1128),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // App logo/icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: AppColors.primary,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Code Lab 3D',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Authenticate to continue',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 40),
                if (_isAuthenticating)
                  const CircularProgressIndicator(color: AppColors.primary)
                else ...[
                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  ElevatedButton.icon(
                    onPressed: _authenticate,
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: const Text(
                      'Use Biometric',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: widget.onLogout,
                    child: Text(
                      'Log in with email instead',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
