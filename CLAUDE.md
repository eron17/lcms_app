# CLAUDE.md - Code Lab 3D LCMS Project Guide

## Project Overview
- **App Name:** Code Lab 3D
- **Type:** Learning Content Management System (LCMS) for C++ programming
- **Stack:** Flutter + Dart, Supabase, Riverpod, GoRouter
- **App ID:** com.psulubao.it.lcms_app
- **GitHub:** https://github.com/eron17/lcms_app
- **Web:** https://lcms-app-alpha.vercel.app
- **Students:** Android APK | **Instructors:** Web (Vercel)

## Build & Maintenance Commands
- Get dependencies: `flutter pub get`
- Run app: `flutter run`
- Build APK: `flutter build apk`
- Build web: `flutter build web`
- Run analyzer: `flutter analyze`
- Format code: `dart format .`
- Push to Vercel: `git add . && git commit -m "message" && git push`

## Supabase Config
- URL: https://vzbkcakuvckfkcbkvwul.supabase.co
- Anon Key: stored in .env file
- Auth flow: PKCE
- Deep link: com.psulubao.it.lcms_app://reset-password

## Project Structure
lib/
├── core/
│   ├── constants/
│   │   ├── app_colors.dart
│   │   └── app_constants.dart
│   ├── router/
│   │   └── app_router.dart
│   ├── utils/               ← CREATE THIS FOLDER
│   │   ├── code_scanner.dart    ← to build
│   │   └── auto_grader.dart     ← to build
│   └── theme/
│       ├── app_theme.dart
│       └── theme_extensions.dart
├── data/
│   └── models/
│       ├── models.dart
│       └── user_model.dart
├── presentation/
│   ├── auth/
│   │   ├── login_screen.dart
│   │   ├── opening_screen.dart
│   │   └── reset_password_screen.dart
│   ├── courses/
│   │   ├── assignment_detail_screen.dart
│   │   ├── class_settings_screen.dart
│   │   ├── course_detail_screen.dart
│   │   ├── file_viewer_screen.dart
│   │   ├── offline_files_screen.dart
│   │   ├── post_detail_screen.dart
│   │   └── three_d_meet_detail_screen.dart
│   ├── dashboard/
│   │   ├── instructor_dashboard.dart
│   │   └── student_dashboard.dart
│   ├── notifications/
│   │   └── notifications_screen.dart
│   └── profile/
│       └── edit_profile_screen.dart
├── providers/
│   └── theme_provider.dart
├── shared/
│   └── widgets/
│       ├── common_widgets.dart
│       └── pressable_scale.dart
└── main.dart

## Files to CREATE (do not exist yet)
- lib/core/utils/code_scanner.dart
- lib/core/utils/auto_grader.dart

## Screen Notes

### lib/presentation/courses/three_d_meet_detail_screen.dart
Full detail screen for 3D Meet posts.
Instructor side: Instructions tab (description, PDFs,
join button, comments) + Student Work tab (score
distribution cards, student list, tap → grade view
with source code preview, auto-grader breakdown,
grade input, private comments).
Student side: Instructions tab + My Result tab
(pending state, graded score display with XP,
scanner breakdown, unsubmit).

### lib/presentation/courses/file_viewer_screen.dart
Shared in-app file viewer, reused by post_detail_screen,
assignment_detail_screen, three_d_meet_detail_screen, and
offline_files_screen (constructor takes url/fileName, plus
isLocal for files already saved on-device).
Renders PDF (Syncfusion), video (Chewie), and images
natively. Word/PPT/Excel (doc/docx/ppt/pptx/xls/xlsx)
render via a Google Docs Viewer WebView (webview_flutter) —
requires a public url, so isLocal office files fall back to
the "cannot preview" state. AppBar has a Download action
(dio) for any non-local file, saving to the device's
Downloads folder.

## Database Tables (8 active tables)

### users
id, name, email, role (student/instructor),
avatar_url, xp, level, badges[], streak,
sex, avatar_config (JSONB)

### courses
id, title, course_code, class_code,
instructor_id, program, section,
description, is_published, is_archived,
enrolled_count

### enrollments
id, student_id, course_id, enrolled_at

### topics
id, course_id, title, order_index

### posts
id, course_id, instructor_id, topic_id,
type (announcement/material/assignment/3d_meet),
title, instructions, material_url, material_name,
assessment_url, assessment_name,
scheduled_time, duration_minutes,
accept_submissions, is_published, points,
due_date, expected_output, required_keywords[],
forbidden_patterns[]

### submissions
id, assessment_id, student_id,
file_url, file_name, score, max_score,
is_graded, is_returned, returned_at,
submitted_at, source_code, actual_output,
is_pending, grade_feedback[]
⚠️ NO created_at column — never insert it

### comments
id, post_id, user_id, user_name, text, created_at

### notifications
id, user_id, course_id, post_id,
type, title, body, is_read, created_at

## Storage Buckets (all Public)
- course-materials → lesson PDFs, MP4s
- course-assessments → assignment PDFs
- avatars → profile pictures
- submissions → student submitted files

## CRITICAL RULES — NEVER BREAK THESE
1. submissions table has NO created_at — never insert it
2. File uploads: always withData: true in FilePicker
3. File bytes: file.bytes ?? await File(file.path!).readAsBytes()
4. Biometrics: always guard with !kIsWeb
5. Colors: never hardcode — use context.isDark ? pattern
6. Icons: never use emojis — use Flutter Icons only
7. Font: always fontFamily: Poppins
8. Changes: Find → Replace only — never rewrite entire files
9. Theme colors: use context.cardColor, context.textPrimary,
   context.bgColor, context.borderColor, context.textSecondary,
   context.textHint, context.surfaceColor

## Code Style
- Always prefer const constructors
- Use async/await never .then() chains
- Strict null safety — avoid force unwrap ! unless necessary
- Split complex UI into smaller reusable widgets

## 3D Meet Auto-Grading System

### How it works
1. Unity saves student submission to Supabase with is_pending=true
2. Flutter detects via realtime listener
3. Flutter runs CodeScanner on source_code
4. Flutter compares actual_output vs expected_output
5. Flutter calculates score and saves back to Supabase
6. Flutter awards XP to student
7. Unity polls Supabase and shows result to student

### Scoring Rules
- Output correct + all keywords found + no forbidden = 100
- Output wrong/close + all keywords found + no forbidden = 50
- Output correct + keywords missing = 0
- Any forbidden pattern found = 0 (always)

### CodeScanner — lib/core/utils/code_scanner.dart
Detects: for, while, do-while, class, objects,
encapsulation (private/public), inheritance,
polymorphism (virtual/override), abstraction,
templates, exception handling, recursion,
pointers, arrays, function overloading,
operator overloading, hardcoded patterns

### AutoGrader — lib/core/utils/auto_grader.dart
Inputs:
- source_code (from Unity via Supabase)
- actual_output (from JDoodle API via Unity)
- expected_output (from posts table)
- required_keywords[] (from posts table)
- forbidden_patterns[] (from posts table)
- total_points (from posts table, default 100)

Output:
- score (int)
- grade_feedback[] (list of strings)
- xp_awarded (int)

## Pending Features (Priority Order)
1. CodeScanner class → lib/core/utils/code_scanner.dart
2. AutoGrader class → lib/core/utils/auto_grader.dart
3. Supabase realtime listener for is_pending submissions
4. XP auto-award when grade saved
5. 3D Meet join button timing (15-min window)
6. Pass data to Unity via deep link (url_launcher)
7. Handle return deep link from Unity
8. Avatar customization screen in Profile tab

## Key Dependencies (pubspec.yaml)
supabase_flutter, flutter_riverpod, go_router,
file_picker, open_filex, path_provider,
local_auth, syncfusion_flutter_pdfviewer,
video_player, chewie, shared_preferences,
image_picker, flutter_secure_storage,
connectivity_plus, timeago, phosphor_flutter

## Need to Add to pubspec.yaml
- url_launcher (for launching Unity app)

## Scoring System
- Faculty secret code: PSULC123 (in app_settings table)
- XP titles: Beginner(0), Novice(100),
  Intermediate(300), Advanced(600),
  Expert(1000), Master(2000)