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
│   ├── utils/
│   │   ├── app_security_manager.dart
│   │   ├── auto_grader.dart
│   │   ├── code_scanner.dart
│   │   ├── grading_service.dart
│   │   └── string_utils.dart
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
│   │   ├── archived_classes_screen.dart
│   │   ├── assignment_detail_screen.dart
│   │   ├── class_settings_screen.dart
│   │   ├── code_viewer_screen.dart
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

## Screen Notes

### lib/presentation/courses/archived_classes_screen.dart
Shows archived classes for instructor (with restore/delete
options) and student (read-only view). Accessed from Profile
page on both dashboards.

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
opening in the device's Office app (open_filex) instead.
AppBar has a Download action (dio) for any non-local file.

### lib/presentation/courses/code_viewer_screen.dart
Full-screen, GitHub-dark-style source code viewer
(StatelessWidget, takes studentName + sourceCode).
Monospace (Courier) with line numbers, basic C++ syntax
coloring, and a copy-to-clipboard button.

### lib/core/utils/grading_service.dart
Supabase realtime listener for submissions with
is_pending=true. Orchestrates the CodeScanner + AutoGrader
pipeline: fetches the post's grading config, runs
AutoGrader.grade(), saves score/xp_awarded/rank/grade_feedback
back to the submission, updates the student's xp/streak, and
upserts the course leaderboard. Static class, initialized once
from main.dart via GradingService.initialize().

### lib/core/utils/string_utils.dart
Shared string helpers. Currently just toTitleCase() — used
when saving a name at signup and in edit-profile, so names are
stored in Title Case regardless of how the student typed them.

### lib/core/utils/app_security_manager.dart
Manages app lifecycle security. Auto-logouts after 2 min
in the background (checked on resume and via a GoRouter
redirect on startup); signs out and clears session state
when the app is fully removed from recents (AppLifecycleState
.detached). Singleton, driven by WidgetsBindingObserver.

## Database Tables (9 active tables)

### users
id, name, email, role (student/instructor),
avatar_url, xp, level, badges[], streak,
sex, avatar_config (JSONB), pending_bonus_points

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
forbidden_patterns[], stdin_input

### submissions
id, assessment_id, student_id,
file_url, file_name, score, max_score,
is_graded, is_returned, returned_at,
submitted_at, source_code, actual_output,
is_pending, grade_feedback[],
xp_awarded, rank, graded_at
⚠️ NO created_at column — never insert it

### comments
id, post_id, user_id, user_name, text, created_at

### private_comments
id, post_id, student_id, sender_id,
sender_name, text, created_at
(instructor ↔ student thread scoped to one
assignment submission, separate from the public
`comments` table)

### notifications
id, user_id, course_id, post_id,
type, title, body, is_read, created_at

### leaderboard
student_id, course_id, total_xp, updated_at
Upserted by grading_service.dart after each 3D Meet
grade. Not currently read by either dashboard's
leaderboard UI, which computes rankings live from
`users.xp` instead — kept in sync for future use.

## Storage Buckets (all Public)
- course-materials → lesson files: PDF, MP4, Word, PPT, Excel
- course-assessments → assignment instructions + 3D Meet
  assessment files (PDF, Word, PPT — no Excel)
- submissions → student-submitted work files
- avatars → profile pictures (named with timestamp to
  bust CDN cache on update)

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
10. Layout: never use fixed pixel widths in Row widgets —
    always use Expanded or Flexible
11. Deprecated: withOpacity() is deprecated — always use
    withValues(alpha: value) instead
12. Avatar: always include onBackgroundImageError: (_, __) {}
    when using backgroundImage
13. XP updates: always use the increment_student_xp RPC —
    never update users.xp directly (blocked by RLS from an
    instructor context)
14. Const: add the const keyword to widgets and objects with
    compile-time constant args
15. Mounted: check if (!mounted) return (or guard the whole
    block) after every await before using context

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

### Scoring Rules (Updated)
Weights:
- Output match:       85% (main judge)
- Compiles:            5% (effort credit)
- Required keywords:  10% (guidance, 5% floor)
- Forbidden detected: wipes entire score to 0
                      (zero tolerance — cheating)

Keyword scoring tiers:
- All keywords found     → full 10%
- Some keywords found    → 7%
- No keywords found      → 5% floor (never 0)

Forbidden pattern = score becomes 0 regardless
of output or keywords. isLikelyHardcoded also
triggers zero-tolerance wipe.

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

## XP & Streak System

### 3D Meet Coding XP (from Unity)
Rank 1 correct submission  → 100 pts
Rank 2+ correct            → 99 down to 75 floor
Wrong output               → 0 pts
Streak activates when score = 100 genuinely
Streak resets when:
  - Next 3D Meet score < 100
  - Student skips a scheduled 3D Meet
Streak stays when no 3D Meet is scheduled

Streak bonus = streak × 10 XP (max streak = 10)
Next activity points bonus = streak × 10 pts
Bonus-assisted 100 does NOT count as genuine streak

### Assignment XP (instructor graded)
Formula: score × 0.20 = base XP
  100/100 → 20 XP
  85/100  → 17 XP
  50/100  → 10 XP
  0/100   → 0 XP

Streak bonus on assignments:
  Only if streak is active AND score = 100:
  → base XP + (streak × 10) streak bonus
Assignment scores do NOT activate streak
Assignment scores do NOT reset streak

⚠️ This formula assumes a 100-point scale. An
assignment whose points value isn't 100 gets
disproportionate XP under score × 0.20, and can
never trigger the streak bonus (which checks
score == 100 exactly, not "100%"). Not yet
reconciled in code — see Pending Features.

### XP Titles
Beginner: 0 XP
Novice: 100 XP
Intermediate: 300 XP
Advanced: 600 XP
Expert: 1000 XP
Master: 2000 XP

### Important: RLS Bypass for XP Updates
Always use Supabase RPC to update student XP —
never update users.xp directly from instructor
context (blocked by RLS):
  await _supabase.rpc('increment_student_xp',
    params: {'p_student_id': id, 'p_xp': xp});

This RPC must exist in Supabase (SECURITY DEFINER
function) before any grading code that calls it
will work — it is not something Flutter code can
create.

## Pending Features (Priority Order)
1. Pass data to Unity via deep link (url_launcher)
   — lesson_material_url, assessment_url,
     stdin_input, scheduled_time
2. Handle return deep link from Unity
   — source_code, actual_output → trigger grading
3. Avatar customization screen in Profile tab
4. Reconcile assignment XP formula with non-100-point
   assignments (see caveat under Assignment XP above)
5. Fix remaining flutter analyze warnings (75 as of
   last check — mostly deprecated withOpacity() calls
   and a handful of unused private members; re-run
   flutter analyze for the current count, this number
   drifts)
6. Weekly leaderboard now computes real weekly XP from
   graded submissions (see student_dashboard.dart /
   instructor_dashboard.dart _loadLeaderboard) — confirm
   this still matches intent, it was reworked since this
   list was first written
7. Reports page 3-level drill-down completion

## Key Dependencies (pubspec.yaml)
supabase_flutter, flutter_riverpod, riverpod_annotation,
go_router, file_picker, open_filex, path_provider,
local_auth, webview_flutter, dio, http,
syncfusion_flutter_pdfviewer, video_player, chewie,
shared_preferences, image_picker, flutter_secure_storage,
connectivity_plus, timeago, phosphor_flutter

## Need to Add to pubspec.yaml
- url_launcher (for launching Unity app via deep link)

## Removed
- image_cropper (added for profile-photo cropping, then
  removed — every version compatible with this project's
  Gradle/http setup had unresolvable dependency conflicts;
  profile photo picking is back to plain pick-and-upload)

## Scoring System
- Faculty secret code: PSULC123 (in app_settings table)
