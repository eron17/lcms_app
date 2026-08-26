import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';

class CodeViewerScreen extends StatelessWidget {
  final String studentName;
  final String sourceCode;

  const CodeViewerScreen({
    super.key,
    required this.studentName,
    required this.sourceCode,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white70,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              studentName,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const Text(
              'Source code',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: Colors.white54,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.copy_rounded,
              color: Colors.white70,
              size: 20,
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: sourceCode));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Code copied to clipboard',
                    style: TextStyle(fontFamily: 'Poppins'),
                  ),
                  backgroundColor: AppColors.primary,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(16),
          child: _buildCodeContent(context),
        ),
      ),
    );
  }

  Widget _buildCodeContent(BuildContext context) {
    final lines = sourceCode.split('\n');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Line numbers column
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(lines.length, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 13,
                  color: Colors.white24,
                  height: 1.6,
                ),
              ),
            );
          }),
        ),
        const SizedBox(width: 16),
        // Vertical divider
        Container(
          width: 0.5,
          color: Colors.white12,
          margin: const EdgeInsets.only(right: 16),
        ),
        // Code column
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines.map((line) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                line.isEmpty ? ' ' : line,
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 13,
                  color: _syntaxColor(line),
                  height: 1.6,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // Basic C++ syntax coloring
  Color _syntaxColor(String line) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//')) return const Color(0xFF6A9955);
    if (trimmed.startsWith('#')) return const Color(0xFF9CDCFE);
    final keywords = [
      'int', 'float', 'double', 'char', 'bool', 'void',
      'string', 'long', 'short', 'auto',
      'if', 'else', 'for', 'while', 'do', 'switch', 'case',
      'break', 'continue', 'return',
      'class', 'public', 'private', 'protected',
      'virtual', 'override', 'static', 'new', 'delete',
      'try', 'catch', 'throw', 'template', 'typename',
      'using', 'namespace', 'include',
    ];
    for (final kw in keywords) {
      if (RegExp('\\b$kw\\b').hasMatch(trimmed)) {
        return const Color(0xFFC586C0);
      }
    }
    if (trimmed.contains('"') || trimmed.contains("'")) {
      return const Color(0xFFCE9178);
    }
    return const Color(0xFFD4D4D4);
  }
}
