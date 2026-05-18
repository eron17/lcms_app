// lib/data/models/course_model.dart
class CourseModel {
  final String id;
  final String title;
  final String description;
  final String instructorId; // Keep this camelCase
  final String instructorName;
  final String? thumbnailUrl;
  final List<String> tags;
  final bool isPublished;
  final int enrolledCount;
  final DateTime createdAt;
  final DateTime? updatedAt;

  CourseModel({
    required this.id,
    required this.title,
    required this.description,
    required this.instructorId,
    required this.instructorName,
    this.thumbnailUrl,
    this.tags = const [],
    this.isPublished = false,
    this.enrolledCount = 0,
    required this.createdAt,
    this.updatedAt,
  });

  factory CourseModel.fromMap(Map<String, dynamic> map) {
    return CourseModel(
      id: map['id']?.toString() ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      instructorId: map['instructor_id'] ?? '', // Maps DB name to Class name
      instructorName: map['instructor_name'] ?? '',
      thumbnailUrl: map['thumbnail_url'],
      tags: List<String>.from(map['tags'] ?? []),
      isPublished: map['is_published'] ?? false,
      enrolledCount: map['enrolled_count'] ?? 0,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'instructor_id': instructorId, // Maps Class name to DB name
      'instructor_name': instructorName,
      'thumbnail_url': thumbnailUrl,
      'tags': tags,
      'is_published': isPublished,
      'enrolled_count': enrolledCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  // CopyWith should use the CLASS variable names
  CourseModel copyWith({
    String? title,
    String? description,
    String? thumbnailUrl,
    List<String>? tags,
    bool? isPublished,
    int? enrolledCount,
    DateTime? updatedAt,
  }) {
    return CourseModel(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      instructorId: instructorId,
      instructorName: instructorName,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      tags: tags ?? this.tags,
      isPublished: isPublished ?? this.isPublished,
      enrolledCount: enrolledCount ?? this.enrolledCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// lib/data/models/module_model.dart
class ModuleModel {
  final String id;
  final String courseId;
  final String title;
  final String? description;
  final int order;
  final DateTime createdAt;

  ModuleModel({
    required this.id,
    required this.courseId,
    required this.title,
    this.description,
    required this.order,
    required this.createdAt,
  });

  factory ModuleModel.fromMap(Map<String, dynamic> map) {
    return ModuleModel(
      id: map['id']?.toString() ?? '',
      courseId: map['course_id'] ?? '',
      title: map['title'] ?? '',
      description: map['description'],
      order: map['order_index'] ?? 0, // Using order_index as 'order' is a SQL keyword
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'course_id': courseId,
      'title': title,
      'description': description,
      'order_index': order,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

// ─────────────────────────────────────────────────────────────
// lib/data/models/content_item_model.dart
class ContentItemModel {
  final String id;
  final String moduleId;
  final String courseId;
  final String title;
  final String type;
  final String? fileUrl;
  final String? linkUrl;
  final String? description;
  final int order;
  final int? durationMinutes;
  final DateTime createdAt;

  ContentItemModel({
    required this.id,
    required this.moduleId,
    required this.courseId,
    required this.title,
    required this.type,
    this.fileUrl,
    this.linkUrl,
    this.description,
    required this.order,
    this.durationMinutes,
    required this.createdAt,
  });

  factory ContentItemModel.fromMap(Map<String, dynamic> map) {
    return ContentItemModel(
      id: map['id']?.toString() ?? '',
      moduleId: map['module_id'] ?? '',
      courseId: map['course_id'] ?? '',
      title: map['title'] ?? '',
      type: map['type'] ?? 'pdf',
      fileUrl: map['file_url'],
      linkUrl: map['link_url'],
      description: map['description'],
      order: map['order_index'] ?? 0,
      durationMinutes: map['duration_minutes'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'module_id': moduleId,
      'course_id': courseId,
      'title': title,
      'type': type,
      'file_url': fileUrl,
      'link_url': linkUrl,
      'description': description,
      'order_index': order,
      'duration_minutes': durationMinutes,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

// ─────────────────────────────────────────────────────────────
// lib/data/models/assessment_model.dart
class AssessmentModel {
  final String id;
  final String moduleId;
  final String courseId;
  final String title;
  final String type;
  final List<QuizQuestion>? questions;
  final String? problemStatement;
  final String? starterCode;
  final int maxScore;
  final int? timeLimitMinutes;
  final DateTime? deadline;
  final DateTime createdAt;

  AssessmentModel({
    required this.id,
    required this.moduleId,
    required this.courseId,
    required this.title,
    required this.type,
    this.questions,
    this.problemStatement,
    this.starterCode,
    required this.maxScore,
    this.timeLimitMinutes,
    this.deadline,
    required this.createdAt,
  });

  factory AssessmentModel.fromMap(Map<String, dynamic> map) {
    return AssessmentModel(
      id: map['id']?.toString() ?? '',
      moduleId: map['module_id'] ?? '',
      courseId: map['course_id'] ?? '',
      title: map['title'] ?? '',
      type: map['type'] ?? 'quiz',
      questions: map['questions'] != null
          ? (map['questions'] as List).map((q) => QuizQuestion.fromMap(q)).toList()
          : null,
      problemStatement: map['problem_statement'],
      starterCode: map['starter_code'],
      maxScore: map['max_score'] ?? 100,
      timeLimitMinutes: map['time_limit_minutes'],
      deadline: map['deadline'] != null ? DateTime.parse(map['deadline']) : null,
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'module_id': moduleId,
      'course_id': courseId,
      'title': title,
      'type': type,
      'questions': questions?.map((q) => q.toMap()).toList(),
      'problem_statement': problemStatement,
      'starter_code': starterCode,
      'max_score': maxScore,
      'time_limit_minutes': timeLimitMinutes,
      'deadline': deadline?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class QuizQuestion {
  final String question;
  final List<String> choices;
  final int correctIndex;
  final int points;

  QuizQuestion({
    required this.question,
    required this.choices,
    required this.correctIndex,
    required this.points,
  });

  factory QuizQuestion.fromMap(Map<String, dynamic> map) {
    return QuizQuestion(
      question: map['question'] ?? '',
      choices: List<String>.from(map['choices'] ?? []),
      correctIndex: map['correctIndex'] ?? 0,
      points: map['points'] ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'question': question,
      'choices': choices,
      'correctIndex': correctIndex,
      'points': points,
    };
  }
}

// ─────────────────────────────────────────────────────────────
// lib/data/models/submission_model.dart
class SubmissionModel {
  final String id;
  final String studentId;
  final String studentName;
  final String assessmentId;
  final String courseId;
  final String type;
  final List<int>? quizAnswers;
  final String? codeAnswer;
  final String? fileUrl;
  final double? grade;
  final String? feedback;
  final bool isGraded;
  final DateTime submittedAt;
  final DateTime? gradedAt;

  SubmissionModel({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.assessmentId,
    required this.courseId,
    required this.type,
    this.quizAnswers,
    this.codeAnswer,
    this.fileUrl,
    this.grade,
    this.feedback,
    this.isGraded = false,
    required this.submittedAt,
    this.gradedAt,
  });

  factory SubmissionModel.fromMap(Map<String, dynamic> map) {
    return SubmissionModel(
      id: map['id']?.toString() ?? '',
      studentId: map['student_id'] ?? '',
      studentName: map['student_name'] ?? '',
      assessmentId: map['assessment_id'] ?? '',
      courseId: map['course_id'] ?? '',
      type: map['type'] ?? 'quiz',
      quizAnswers: map['quiz_answers'] != null
          ? List<int>.from(map['quiz_answers'])
          : null,
      codeAnswer: map['code_answer'],
      fileUrl: map['file_url'],
      grade: map['grade']?.toDouble(),
      feedback: map['feedback'],
      isGraded: map['is_graded'] ?? false,
      submittedAt: DateTime.parse(map['submitted_at']),
      gradedAt: map['graded_at'] != null 
          ? DateTime.parse(map['graded_at']) 
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'student_id': studentId,
      'student_name': studentName,
      'assessment_id': assessmentId,
      'course_id': courseId,
      'type': type,
      'quiz_answers': quizAnswers,
      'code_answer': codeAnswer,
      'file_url': fileUrl,
      'grade': grade,
      'feedback': feedback,
      'is_graded': isGraded,
      'submitted_at': submittedAt.toIso8601String(),
      'graded_at': gradedAt?.toIso8601String(),
    };
  }
}

// ─────────────────────────────────────────────────────────────
// lib/data/models/progress_model.dart
class ProgressModel {
  final String id;
  final String studentId;
  final String courseId;
  final List<String> completedContentIds;
  final List<String> completedAssessmentIds;
  final double percentage;
  final int earnedXp;
  final DateTime lastUpdated;

  ProgressModel({
    required this.id,
    required this.studentId,
    required this.courseId,
    this.completedContentIds = const [],
    this.completedAssessmentIds = const [],
    this.percentage = 0.0,
    this.earnedXp = 0,
    required this.lastUpdated,
  });

  factory ProgressModel.fromMap(Map<String, dynamic> map) {
    return ProgressModel(
      id: map['id']?.toString() ?? '',
      studentId: map['student_id'] ?? '',
      courseId: map['course_id'] ?? '',
      completedContentIds: List<String>.from(map['completed_content_ids'] ?? []),
      completedAssessmentIds: List<String>.from(map['completed_assessment_ids'] ?? []),
      percentage: map['percentage']?.toDouble() ?? 0.0,
      earnedXp: map['earned_xp'] ?? 0,
      lastUpdated: DateTime.parse(map['last_updated']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'student_id': studentId,
      'course_id': courseId,
      'completed_content_ids': completedContentIds,
      'completed_assessment_ids': completedAssessmentIds,
      'percentage': percentage,
      'earned_xp': earnedXp,
      'last_updated': lastUpdated.toIso8601String(),
    };
  }
}

// ─────────────────────────────────────────────────────────────
// lib/data/models/badge_model.dart
class BadgeModel {
  final String id;
  final String name;
  final String description;
  final String iconUrl;
  final String condition;
  final int xpReward;

  BadgeModel({
    required this.id,
    required this.name,
    required this.description,
    required this.iconUrl,
    required this.condition,
    required this.xpReward,
  });

  factory BadgeModel.fromMap(Map<String, dynamic> map) {
    return BadgeModel(
      id: map['id']?.toString() ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      iconUrl: map['icon_url'] ?? '',
      condition: map['condition'] ?? '',
      xpReward: map['xp_reward'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'icon_url': iconUrl,
      'condition': condition,
      'xp_reward': xpReward,
    };
  }
}
