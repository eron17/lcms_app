// lib/presentation/courses/offline_files_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import 'file_viewer_screen.dart';

class OfflineFilesScreen extends StatefulWidget {
  const OfflineFilesScreen({super.key});

  @override
  State<OfflineFilesScreen> createState() => _OfflineFilesScreenState();
}

class _OfflineFilesScreenState extends State<OfflineFilesScreen> {
  List<Map<String, dynamic>> _offlineFiles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOfflineFiles();
  }

  Future<void> _loadOfflineFiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final filesJson = prefs.getStringList('offline_files') ?? [];
      final files = filesJson
          .map((f) => Map<String, dynamic>.from(jsonDecode(f)))
          .where((f) => File(f['path']).existsSync())
          .toList();

      final validJson = files.map((f) => jsonEncode(f)).toList();
      await prefs.setStringList('offline_files', validJson);

      if (mounted) {
        setState(() {
          _offlineFiles = files;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteFile(Map<String, dynamic> file) async {
    try {
      final f = File(file['path']);
      if (await f.exists()) await f.delete();

      final prefs = await SharedPreferences.getInstance();
      final filesJson = prefs.getStringList('offline_files') ?? [];
      filesJson.removeWhere((j) {
        final decoded = jsonDecode(j) as Map;
        return decoded['path'] == file['path'];
      });
      await prefs.setStringList('offline_files', filesJson);
      await _loadOfflineFiles();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${file['name']} removed from offline storage.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Delete offline file error: $e');
    }
  }

  void _showDeleteConfirmation(Map<String, dynamic> file) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: context.borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.delete_sweep_rounded, color: AppColors.error, size: 48),
              const SizedBox(height: 16),
              Text(
                'Delete Offline File?',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textColor),
              ),
              const SizedBox(height: 8),
              Text(
                '"${file['name']}" will be permanently removed from your device storage.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: textColor.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: context.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Center(
                          child: Text('Cancel',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: textColor.withValues(alpha: 0.7),
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        await _deleteFile(file);
                      },
                      child: const Text('Delete',
                          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Proper Icons instead of Emojis ───
  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (ext == 'pdf') return Icons.picture_as_pdf_rounded;
    if (['mp4', 'mov', 'avi'].contains(ext)) return Icons.video_library_rounded;
    if (['jpg', 'jpeg', 'png'].contains(ext)) return Icons.image_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _getFileColor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (ext == 'pdf') return AppColors.primary;
    if (['mp4', 'mov', 'avi'].contains(ext)) return const Color(0xFF22C55E);
    if (['jpg', 'jpeg', 'png'].contains(ext)) return AppColors.accent;
    return AppColors.warning;
  }

  String _formatFileSize(String path) {
    try {
      final size = File(path).lengthSync();
      if (size < 1024) return '$size B';
      if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    } catch (_) {
      return '';
    }
  }

  String _formatSavedDate(String? savedAt) {
    if (savedAt == null) return '';
    final date = DateTime.tryParse(savedAt);
    if (date == null) return '';
    return '${date.day}/${date.month}/${date.year}';
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
                // ─── Custom Top Bar ───
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: context.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 18),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text('Offline Files',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: textColor)),
                      const Spacer(),
                      if (_offlineFiles.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('${_offlineFiles.length} files',
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary)),
                        ),
                    ],
                  ),
                ),

                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                      : _offlineFiles.isEmpty
                          ? _buildEmptyState(textColor)
                          : _buildFileList(textColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color textColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ─── Proper Icon instead of Emoji ───
            Icon(Icons.cloud_download_outlined, size: 80, color: textColor.withValues(alpha: 0.15)),
            const SizedBox(height: 24),
            Text('No Offline Files',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textColor)),
            const SizedBox(height: 12),
            Text(
              'Files you save for offline access will appear here.\nOpen a lesson and tap "Save Files Offline".',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: textColor.withValues(alpha: 0.5),
                  height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileList(Color textColor) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _offlineFiles.length,
      itemBuilder: (context, index) {
        final file = _offlineFiles[index];
        final color = _getFileColor(file['name'] ?? '');
        final icon = _getFileIcon(file['name'] ?? '');

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.borderColor),
            boxShadow: context.isDark
                ? []
                : [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 26), // Replaced Emoji with Icon
            ),
            title: Text(file['name'] ?? 'Unknown File',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: textColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (file['course_title'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(file['course_title'],
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                const SizedBox(height: 4),
                Text(
                  '${_formatFileSize(file['path'] ?? '')} • ${_formatSavedDate(file['saved_at'])}',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 11, color: textColor.withValues(alpha: 0.5)),
                ),
              ],
            ),
            trailing: GestureDetector(
              onTap: () => _showDeleteConfirmation(file),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
              ),
            ),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FileViewerScreen(
                    url: file['path'],
                    fileName: file['name'] ?? 'File',
                    isLocal: true,
                  ),
                )),
          ),
        );
      },
    );
  }
}