// lib/presentation/courses/class_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../shared/widgets/pressable_scale.dart';

class ClassSettingsScreen extends StatefulWidget {
  final Map<String, dynamic> course;
  const ClassSettingsScreen({super.key, required this.course});

  @override
  State<ClassSettingsScreen> createState() => _ClassSettingsScreenState();
}

class _ClassSettingsScreenState extends State<ClassSettingsScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _programController = TextEditingController();
  final _sectionController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isSaving = false;
  bool _notifyOnComments = true;

  @override
  void initState() {
    super.initState();
    _notifyOnComments = widget.course['notify_on_comments'] ?? true;
    final title = widget.course['title'] as String? ?? '';
    final parts = title.split(' - ');
    _titleController.text = parts.isNotEmpty ? parts[0] : title;
    _programController.text = widget.course['program'] as String? ?? '';
    _sectionController.text = widget.course['section'] as String? ?? '';
    _descriptionController.text = widget.course['description'] as String? ?? '';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _programController.dispose();
    _sectionController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      // 1. Build the title string using the correct controller name
      final titleBase = _titleController.text.trim();
      final program = _programController.text.trim();
      final section = _sectionController.text.trim();
      final fullTitle = '$titleBase - $program $section';

      // 2. Update Supabase using the 'fullTitle' variable
      await _supabase.from('courses').update({
        'title': fullTitle, // <--- USE THE VARIABLE HERE
        'description': _descriptionController.text.trim(),
        'program': program,
        'section': section,
        'notify_on_comments': _notifyOnComments,
      }).eq('id', widget.course['id']);

      if (mounted) {
        // ... (rest of your success SnackBar code)
        Navigator.pop(context, true);
      }
    } catch (e) {
      // ... (rest of your error handling)
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Scaffold(
      backgroundColor: context.bgColor,
      body: Stack(
        children: [
          Container(decoration: context.scaffoldGradient),
          SafeArea(
            child: Column(
              children: [
                _buildPremiumTopBar(textColor), // Your existing top bar, but with the PressableScale applied
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    physics: const BouncingScrollPhysics(), // Smooth scrolling
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ─── 1. CLASS DETAILS SECTION ───
                          _buildSectionHeader('CLASS DETAILS', Icons.class_outlined, textColor),
                          const SizedBox(height: 16),
                          _buildSettingsGroup([
                            _buildField(
                              label: 'Class Name',
                              controller: _titleController, // Use _titleController
                              icon: Icons.book_outlined,
                              textColor: textColor,
                              validator: (v) => v == null || v.isEmpty ? 'Enter class name' : null,
                            ),
                            _buildField(
                              label: 'Program',
                              controller: _programController,
                              icon: Icons.school_outlined,
                              textColor: textColor,
                              hint: 'e.g. BSIT',
                              validator: (v) => v == null || v.isEmpty ? 'Enter program' : null,
                            ),
                            _buildField(
                              label: 'Year & Section',
                              controller: _sectionController,
                              icon: Icons.group_outlined,
                              textColor: textColor,
                              hint: 'e.g. 1-A',
                              validator: (v) => v == null || v.isEmpty ? 'Enter year & section' : null,
                            ),
                            _buildField(
                              label: 'Class Description (Optional)',
                              controller: _descriptionController,
                              icon: Icons.description_outlined,
                              textColor: textColor,
                              maxLines: 3,
                            ),
                          ]),

                          const SizedBox(height: 5),

                          // ─── 2. CLASS INFO (READ-ONLY) SECTION ───
                          _buildSectionHeader('CLASS INFO', Icons.info_outline, textColor),
                          const SizedBox(height: 16),
                          _buildSettingsGroup([
                            _buildReadOnlyInfo('Course Code', widget.course['course_code'] ?? '—', Icons.tag, textColor),
                            _buildReadOnlyInfo('Class Code', widget.course['class_code'] ?? '—', Icons.key_outlined, textColor),
                            _buildReadOnlyInfo('Enrolled Students', '${widget.course['enrolled_count'] ?? 0} students', Icons.people_outline, textColor),
                          ]),

                          const SizedBox(height: 5),

                          // ─── 3. NOTIFICATION PREFERENCES SECTION ───
                          _buildSectionHeader('PREFERENCES', Icons.notifications_active_outlined, textColor),
                          const SizedBox(height: 16),
                          _buildSettingsGroup([
                            _buildToggleRow(
                              icon: Icons.notifications_active_outlined,
                              title: 'Class Comments',
                              subtitle: 'Notify me when students comment',
                              value: _notifyOnComments,
                              onChanged: (val) => setState(() => _notifyOnComments = val),
                            ),
                          ]),

                          const SizedBox(height: 30),

                          // ─── 4. PREMIUM SAVE BUTTON ───
                          _buildActionButton(label: 'Save Changes', onTap: _saveSettings, color: AppColors.primary),
                          const SizedBox(height: 20), // Bottom breathing room
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

  PreferredSizeWidget _buildPremiumTopBar(Color textColor) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leadingWidth: 70,
      leading: Center(
        child: PressableScale(
          onPressed: () => Navigator.pop(context),
          scaleFactor: 1.0,
          opacityFactor: 0.5,
          child: Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.all(10),
            child: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 25),
          ),
        ),
      ),
      title: Text('Class Settings', style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: textColor)),
      centerTitle: true,
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color textColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: textColor.withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Text(title.toUpperCase(), style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w900, color: textColor.withValues(alpha: 0.4), letterSpacing: 1.5)),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: context.isDark ? [] : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildField({
    required String label, 
    required TextEditingController controller, 
    required IconData icon, 
    required Color textColor,
    String? hint,
    int maxLines = 1,
    String? Function(String?)? validator
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        validator: validator,
        style: TextStyle(fontFamily: 'Poppins', color: textColor, fontSize: 14),
        decoration: InputDecoration(
          labelText: label, hintText: hint,
          filled: true, fillColor: textColor.withValues(alpha: 0.03),
          prefixIcon: Icon(icon, color: textColor.withValues(alpha: 0.4), size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
        ),
      ),
    );
  }

  Widget _buildReadOnlyInfo(String label, String value, IconData icon, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: textColor.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, color: textColor.withValues(alpha: 0.4), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: textColor.withValues(alpha: 0.5))),
                  Text(value, style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600, color: textColor)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: textColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
              child: Text('Read only', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: textColor.withValues(alpha: 0.4))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({required String label, required VoidCallback onTap, Color? color}) {
    return PressableScale(
      onPressed: _isSaving ? null : onTap, // Disable if saving
      scaleFactor: 0.96, opacityFactor: 0.7,
      child: Container(
        height: 54, width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color?.withValues(alpha: 0.8) ?? AppColors.primaryDark, color ?? AppColors.primary]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: (color ?? AppColors.primary).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Center(
          child: _isSaving ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                         : Text(label, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 16, letterSpacing: 0.5)),
        ),
      ),
    );
  }

  Widget _buildToggleRow({
    required IconData icon, 
    required String title, 
    required String subtitle, 
    required bool value, 
    required Function(bool) onChanged
  }) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          // Icon Box
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: textColor.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: value ? AppColors.primary : textColor.withValues(alpha: 0.3), size: 22),
          ),
          const SizedBox(width: 16),
          // Text Labels
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15, color: textColor)),
                Text(subtitle, style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: textColor.withValues(alpha: 0.5))),
              ],
            ),
          ),
          // The Premium Animated Switch
          _buildAnimatedToggle(
            value: value, 
            onTap: () => onChanged(!value)
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedToggle({required bool value, required VoidCallback onTap}) {
    // This helper must be defined in this file to work
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 48, height: 26, padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: value ? AppColors.primary : Colors.black12,
          boxShadow: value ? [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 10)] : [],
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 250),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(width: 20, height: 20, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
        ),
      ),
    );
  }
}
