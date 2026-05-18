import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

extension ThemeX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  // --- Background colors ---
  Color get bgColor => isDark ? AppColors.darkBackground : AppColors.lightBackground;
  Color get surfaceColor => isDark ? AppColors.darkSurface : AppColors.lightSurface;
  Color get cardColor => isDark ? AppColors.darkCard : AppColors.lightCard;
  Color get borderColor => isDark ? AppColors.darkBorder : AppColors.lightBorder;
  Color get topBarColor => isDark ? AppColors.darkTopBar : AppColors.lightTopBar;

  // --- Text colors ---
  Color get textPrimary => isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
  Color get textSecondary => isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
  Color get textHint => isDark ? AppColors.darkTextHint : AppColors.lightTextHint;

  // --- Gradient for backgrounds ---
  // REMOVED 'const' and changed 'context.' to 'AppColors.'
  BoxDecoration get scaffoldGradient => isDark
      ? const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.5),
            radius: 1.5,
            colors: [AppColors.darkSurface, AppColors.darkBackground],
          ),
        )
      : const BoxDecoration(
          color: AppColors.lightBackground,
        );

  // --- Card decoration ---
  BoxDecoration cardDecoration({Color? borderColor}) => BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ?? this.borderColor,
          width: 1,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      );
}