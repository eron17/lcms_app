import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

enum SnackType { success, error, info, warning }

void showSnack(
  BuildContext context,
  String message, {
  SnackType type = SnackType.info,
  Duration duration = const Duration(seconds: 3),
}) {
  if (!context.mounted) return;

  Color bgColor;
  IconData icon;

  switch (type) {
    case SnackType.success:
      bgColor = const Color(0xFF22C55E);
      icon = Icons.check_circle_outline_rounded;
      break;
    case SnackType.error:
      bgColor = AppColors.error;
      icon = Icons.error_outline_rounded;
      break;
    case SnackType.warning:
      bgColor = const Color(0xFFF97316);
      icon = Icons.warning_amber_rounded;
      break;
    case SnackType.info:
      bgColor = AppColors.primary;
      icon = Icons.info_outline_rounded;
      break;
  }

  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: bgColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: duration,
      margin: const EdgeInsets.all(12),
    ),
  );
}
