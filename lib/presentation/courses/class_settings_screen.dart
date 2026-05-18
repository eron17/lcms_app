// lib/presentation/courses/class_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_extensions.dart';

class ClassSettingsScreen extends StatefulWidget {
  final Map<String, dynamic> course;
  const ClassSettingsScreen({super.key, required this.course});

  @override
  State<ClassSettingsScreen> createState() => _ClassSettingsScreenState();
}

class _ClassSettingsScreenState extends State<ClassSettingsScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _programController = TextEditingController();
  final _sectionController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill with existing data
    final title = widget.course['title'] as String? ?? '';
    // Title format is "CourseName - Program Section"
    // Try to parse it back
    final parts = title.split(' - ');
    _nameController.text = parts.isNotEmpty ? parts[0] : title;
    _programController.text = widget.course['program'] as String? ?? '';
    _sectionController.text = widget.course['section'] as String? ?? '';
    _descriptionController.text = widget.course['description'] as String? ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _programController.dispose();
    _sectionController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final newTitle = '${_nameController.text.trim()} - ${_programController.text.trim()} ${_sectionController.text.trim()}';
      await _supabase.from('courses').update({
        'title': newTitle,
        'program': _programController.text.trim(),
        'section': _sectionController.text.trim(),
        'description': _descriptionController.text.trim(),
      }).eq('id', widget.course['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text('Class details updated!', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
            ]),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        // Return true so course detail can refresh
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade800, behavior: SnackBarBehavior.floating),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    final bgColor = context.isDark ? const Color(0xFF080D1F) : const Color(0xFFF0F2F5);

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          // ─── Custom App Bar ────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: context.cardColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.borderColor),
                      ),
                      child: Icon(Icons.arrow_back, color: textColor, size: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text('Class Settings',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w700, color: textColor)),
                ],
              ),
            ),
          ),

          // ─── Form ─────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─── Section: Class Details ──────────────
                    _buildSectionLabel('Class Details', Icons.class_outlined, textColor),
                    const SizedBox(height: 14),

                    _buildField(
                      label: 'Class Name',
                      controller: _nameController,
                      icon: Icons.book_outlined,
                      textColor: textColor,
                      validator: (v) => v == null || v.isEmpty ? 'Enter class name' : null,
                    ),
                    const SizedBox(height: 14),

                    _buildField(
                      label: 'Program',
                      controller: _programController,
                      icon: Icons.school_outlined,
                      textColor: textColor,
                      hint: 'e.g. BSIT',
                      validator: (v) => v == null || v.isEmpty ? 'Enter program' : null,
                    ),
                    const SizedBox(height: 14),

                    _buildField(
                      label: 'Year & Section',
                      controller: _sectionController,
                      icon: Icons.group_outlined,
                      textColor: textColor,
                      hint: 'e.g. 1-A',
                      validator: (v) => v == null || v.isEmpty ? 'Enter year & section' : null,
                    ),
                    const SizedBox(height: 14),

                    _buildField(
                      label: 'Class Description (Optional)',
                      controller: _descriptionController,
                      icon: Icons.description_outlined,
                      textColor: textColor,
                      maxLines: 3,
                    ),

                    const SizedBox(height: 12),

                    // ─── Class Info (read-only) ──────────────
                    _buildSectionLabel('Class Info', Icons.info_outline, textColor),
                    const SizedBox(height: 14),

                    _buildReadOnlyInfo('Course Code', widget.course['course_code'] ?? '—', Icons.tag, textColor),
                    const SizedBox(height: 12),
                    _buildReadOnlyInfo('Class Code', widget.course['class_code'] ?? '—', Icons.key_outlined, textColor),
                    const SizedBox(height: 12),
                    _buildReadOnlyInfo('Enrolled Students', '${widget.course['enrolled_count'] ?? 0} students', Icons.people_outline, textColor),

                    const SizedBox(height: 32),

                    // ─── Save Button ─────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        onPressed: _isSaving ? null : _save,
                        child: _isSaving
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Save', style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String title, IconData icon, Color textColor) {
    return Row(children: [
      Icon(icon, color: AppColors.primary, size: 18),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
    ]);
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required Color textColor,
    String? hint,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: TextStyle(fontFamily: 'Poppins', color: textColor, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: textColor.withValues(alpha: 0.5)),
        floatingLabelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(fontFamily: 'Poppins', color: textColor.withValues(alpha: 0.3), fontSize: 13),
        prefixIcon: Icon(icon, color: textColor.withValues(alpha: 0.4), size: 20),
        filled: true,
        fillColor: context.cardColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent)),
        errorStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.redAccent),
      ),
    );
  }

  Widget _buildReadOnlyInfo(String label, String value, IconData icon, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(children: [
        Icon(icon, color: textColor.withValues(alpha: 0.4), size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: textColor.withValues(alpha: 0.5))),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: context.borderColor, borderRadius: BorderRadius.circular(6)),
          child: Text('Read only', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: textColor.withValues(alpha: 0.4))),
        ),
      ]),
    );
  }
}
