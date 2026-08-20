// lib/presentation/profile/edit_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../data/models/user_model.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../../shared/widgets/pressable_scale.dart';

class EditProfileScreen extends StatefulWidget {
  final UserModel user;
  const EditProfileScreen({super.key, required this.user});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  File? _newPhotoFile;
  String? _avatarUrl;
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final _localAuth = LocalAuthentication();
  bool _biometricsEnabled = false;

  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _showPasswordSection = false;
  bool _newPassVisible = false;
  bool _confirmPassVisible = false;
  bool _isChangingPassword = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.user.name;
    _avatarUrl = widget.user.avatarUrl;
    _checkBiometricStatus();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _checkBiometricStatus();
    super.dispose();
  }

  Future<void> _checkBiometricStatus() async {
    try {
      final savedEmail = await _storage.read(key: 'user_email');
      debugPrint('Checking biometrics... Found email: $savedEmail');

      if (mounted) {
        setState(() {
          // Only set to true if the email exists in storage
          _biometricsEnabled = savedEmail != null;
        });
      }
    } catch (e) {
      debugPrint('Biometric check error: $e');
    }
  }

  // This handles the logic when the user flips the switch
  Future<void> _toggleBiometrics(bool enabled) async {
    if (enabled) {
      _showEnableBiometricsDialog();
    } else {
      // If turning off, just delete the saved credentials
      await _storage.delete(key: 'user_email');
      await _storage.delete(key: 'user_password');
      setState(() => _biometricsEnabled = false);
    }
  }

  void _showEnableBiometricsDialog() {
    final passController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: const Text(
          'Enable Biometrics',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your current password to enable fingerprint login.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passController,
              obscureText: true,
              decoration: _inputDecoration(
                'Current Password',
                Icons.lock_outline,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (passController.text.isEmpty) return;

              // 1. Confirm biometrics works on this device
              final authenticated = await _localAuth.authenticate(
                localizedReason: 'Confirm fingerprint to enable fast login',
                options: const AuthenticationOptions(biometricOnly: true),
              );

              if (authenticated) {
                // 2. Store credentials securely
                await _storage.write(
                  key: 'user_email',
                  value: widget.user.email,
                );
                await _storage.write(
                  key: 'user_password',
                  value: passController.text.trim(),
                );

                if (mounted) {
                  setState(() => _biometricsEnabled = true);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Biometric login enabled!')),
                  );
                }
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked == null) return;
    setState(() => _newPhotoFile = File(picked.path));
  }

  Future<String?> _uploadPhoto() async {
    if (_newPhotoFile == null) return _avatarUrl;
    setState(() => _isUploadingPhoto = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      final ext = _newPhotoFile!.path.split('.').last;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'avatar_${userId}_$timestamp.$ext';
      final bytes = await _newPhotoFile!.readAsBytes();
      await _supabase.storage
          .from('avatars')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      final rawUrl = _supabase.storage.from('avatars').getPublicUrl(fileName);
      final cacheBust = DateTime.now().millisecondsSinceEpoch;
      return '$rawUrl?v=$cacheBust';
    } catch (e) {
      debugPrint('Photo upload error: $e');
      return _avatarUrl;
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final newAvatarUrl = await _uploadPhoto();
      // Strip the cache-bust query param before saving to DB
      // so the stored URL stays clean for other screens to use.
      final cleanUrl = newAvatarUrl?.split('?').first;
      await _supabase
          .from('users')
          .update({
            'name': _nameController.text.trim(),
            'avatar_url': cleanUrl,
          })
          .eq('id', userId);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profile Updated!'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _changePassword() async {
    if (_newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match!'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_newPasswordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password must be at least 6 characters.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _isChangingPassword = true);
    try {
      await _supabase.auth.updateUser(
        UserAttributes(password: _newPasswordController.text.trim()),
      );
      if (mounted) {
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        setState(() => _showPasswordSection = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Password changed! 🔒'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isChangingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = (widget.user.name.isNotEmpty ? widget.user.name : 'U')
        .substring(0, 1)
        .toUpperCase();
    return Scaffold(
      backgroundColor: context.bgColor,
      body: Stack(
        children: [
          Container(decoration: context.scaffoldGradient),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      PressableScale(
                        onPressed: () => Navigator.pop(context),
                        scaleFactor: 1.0,
                        opacityFactor: 0.5,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: context.textPrimary,
                            size: 25,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Edit Profile',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      PressableScale(
                        onPressed: _isSaving ? null : _saveProfile,
                        scaleFactor: 0.96, // Full tactile feedback
                        opacityFactor: 0.7,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppColors.primaryDark,
                                AppColors.primary,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Save',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // ─── Avatar ──────────────────────
                          GestureDetector(
                            onTap: _pickPhoto,
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 56,
                                  backgroundColor: AppColors.primary.withValues(
                                    alpha: 0.15,
                                  ),
                                  backgroundImage: _newPhotoFile != null
                                      ? FileImage(_newPhotoFile!)
                                            as ImageProvider
                                      : (_avatarUrl != null
                                            ? NetworkImage(_avatarUrl!)
                                            : null),
                                  child:
                                      (_newPhotoFile == null &&
                                          _avatarUrl == null)
                                      ? Text(
                                          initial,
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 40,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                          ),
                                        )
                                      : null,
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          AppColors.primaryDark,
                                          AppColors.primary,
                                        ],
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: _isUploadingPhoto
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.camera_alt_outlined,
                                            color: Colors.white,
                                            size: 14,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap to change photo',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: context.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 28),

                          // ─── Name ────────────────────────
                          _buildCard('Personal Information', [
                            TextFormField(
                              controller: _nameController,
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Name is required'
                                  : null,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                color: context.textPrimary,
                                fontSize: 14,
                              ),
                              decoration: _inputDecoration(
                                'Full Name',
                                Icons.person_outline,
                              ),
                            ),
                          ]),
                          const SizedBox(height: 20),

                          // ─── Password ─────────────────────
                          _buildCard('Security', [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: _biometricsEnabled
                                          ? AppColors.primary.withOpacity(0.1)
                                          : context.textHint.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.fingerprint,
                                      color: _biometricsEnabled
                                          ? AppColors.primary
                                          : context.textHint,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Biometric Login',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 14,
                                            color: context.textPrimary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          'Use fingerprint to sign in faster',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 11,
                                            color: context.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Custom Animated Switch
                                  GestureDetector(
                                    onTap: () =>
                                        _toggleBiometrics(!_biometricsEnabled),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 250,
                                      ),
                                      width: 48,
                                      height: 26,
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
                                        color: _biometricsEnabled
                                            ? AppColors.primary
                                            : (context.isDark
                                                  ? Colors.white10
                                                  : Colors.black12),
                                        boxShadow: _biometricsEnabled
                                            ? [
                                                BoxShadow(
                                                  color: AppColors.primary
                                                      .withOpacity(0.4),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ]
                                            : [],
                                      ),
                                      child: AnimatedAlign(
                                        duration: const Duration(
                                          milliseconds: 250,
                                        ),
                                        curve: Curves.easeInOut,
                                        alignment: _biometricsEnabled
                                            ? Alignment.centerRight
                                            : Alignment.centerLeft,
                                        child: Container(
                                          width: 20,
                                          height: 20,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black26,
                                                blurRadius: 4,
                                                offset: Offset(0, 1),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Divider(height: 1, thickness: 1),
                            const SizedBox(
                              height: 20,
                            ), // UPDATE BIGAY KAY YOW SWITCH LIST TILE

                            GestureDetector(
                              onTap: () => setState(
                                () => _showPasswordSection =
                                    !_showPasswordSection,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: context.bgColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: context.borderColor,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.lock_outline,
                                      color: context.textHint,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Change Password',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 14,
                                        color: context.textPrimary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const Spacer(),
                                    Icon(
                                      _showPasswordSection
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                      color: context.textSecondary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_showPasswordSection) ...[
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _newPasswordController,
                                obscureText: !_newPassVisible,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: context.textPrimary,
                                  fontSize: 14,
                                ),
                                decoration: _inputDecoration(
                                  'New Password',
                                  Icons.lock_outline,
                                  isPassword: true,
                                  isVisible: _newPassVisible,
                                  onToggle: () => setState(
                                    () => _newPassVisible = !_newPassVisible,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _confirmPasswordController,
                                obscureText: !_confirmPassVisible,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: context.textPrimary,
                                  fontSize: 14,
                                ),
                                decoration: _inputDecoration(
                                  'Confirm New Password',
                                  Icons.lock_outline,
                                  isPassword: true,
                                  isVisible: _confirmPassVisible,
                                  onToggle: () => setState(
                                    () => _confirmPassVisible =
                                        !_confirmPassVisible,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: PressableScale(
                                  onPressed: _isChangingPassword
                                      ? null
                                      : _changePassword,
                                  scaleFactor: 0.96,
                                  opacityFactor: 0.7,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          AppColors.primaryDark,
                                          AppColors.primary,
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.3,
                                          ),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: _isChangingPassword
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text(
                                              'Update Password',
                                              style: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                                fontSize: 15,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ]),
                          const SizedBox(height: 100),
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
    );
  }

  Widget _buildCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: context.isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
    String label,
    IconData icon, {
    bool isPassword = false,
    bool isVisible = false,
    VoidCallback? onToggle,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 13,
        color: context.textSecondary,
      ),
      floatingLabelStyle: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 12,
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
      ),
      prefixIcon: Icon(icon, color: context.textHint, size: 20),
      suffixIcon: isPassword
          ? IconButton(
              icon: Icon(
                isVisible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: context.textHint,
                size: 20,
              ),
              onPressed: onToggle,
            )
          : null,
      filled: true,
      fillColor: context.bgColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error),
      ),
    );
  }
}
