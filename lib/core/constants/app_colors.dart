// lib/core/constants/app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ─── Dark Mode ────────────────────────────────────────
  static const darkBackground = Color(0xFF080D1F);
  static const darkSurface = Color(0xFF0D1530);
  static const darkCard = Color(0xFF0A1128);
  static const darkBorder = Color(0xFF1E3A6E);
  static const darkTopBar = Color(0xFF080D1F);

  // ─── Light Mode (Facebook-inspired) ──────────────────
  static const lightBackground = Color(0xFFF0F2F5);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFDDE1E7);
  static const lightTopBar = Color(0xFFFFFFFF);

  // ─── Text Colors ──────────────────────────────────────
  static const darkTextPrimary = Color(0xFFFFFFFF);
  static const darkTextSecondary = Color(0xFFB0B8C8);
  static const darkTextHint = Color(0xFF6B7A99);
  static const lightTextPrimary = Color(0xFF050505);
  static const lightTextSecondary = Color(0xFF65676B);
  static const lightTextHint = Color(0xFF8A8D91);

  // ─── Brand Colors (same in both modes) ────────────────
  static const primary = Color(0xFF1E90FF);
  static const primaryDark = Color(0xFF1565C0);
  static const accent = Color(0xFF7B2FBE);
  static const success = Color(0xFF28A745);
  static const warning = Color(0xFFFF6B35);
  static const error = Color(0xFFDC3545);
  static const gold = Color(0xFFFFD700);

  // ─── Keep old names for backward compatibility ────────
  static const background = darkBackground;
  static const surface = darkSurface;
  static const cardLight = Color(0xFFFFFFFF);
  static const cardDark = darkCard;
  static const border = darkBorder;
  static const divider = Color(0xFF1E3A6E);
  static const textPrimary = darkTextPrimary;
  static const textSecondary = darkTextSecondary;
  static const textHint = darkTextHint;
  static const textLight = Color(0xFFFFFFFF);
  static const backgroundDark = darkBackground;
  static const surfaceDark = darkSurface;
  static const xpGold = gold;
  static const streakOrange = warning;
  static const badgePurple = accent;
  static const studentColor = Color(0xFF2196F3);
  static const instructorColor = Color(0xFF9C27B0);
}