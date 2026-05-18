class UserModel {
  final String id;
  final String name;
  final String email;
  final String role; // 'student' or 'instructor'
  final String? avatarUrl;
  final int xp;
  final int level;
  final List<String> badges;
  final int streak;
  final DateTime createdAt;
  final DateTime? lastActiveAt;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.avatarUrl,
    this.xp = 0,
    this.level = 1,
    this.badges = const [],
    this.streak = 0,
    required this.createdAt,
    this.lastActiveAt,
  });

  bool get isInstructor => role == 'instructor';
  bool get isStudent => role == 'student';

  // ─── From Supabase JSON ──────────────────────────────────
  factory UserModel.fromMap(Map<String, dynamic> data) {
    return UserModel(
      id: data['id'] ?? '',
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      role: data['role'] ?? 'student',
      avatarUrl: data['avatar_url'],
      xp: data['xp'] ?? 0,
      level: data['level'] ?? 1,
      badges: List<String>.from(data['badges'] ?? []),
      streak: data['streak'] ?? 0,
      createdAt: DateTime.parse(data['created_at']),
      lastActiveAt: data['last_active_at'] != null
          ? DateTime.parse(data['last_active_at'])
          : null,
    );
  }

  // ─── To Supabase JSON ────────────────────────────────────
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'role': role,
      'avatar_url': avatarUrl,
      'xp': xp,
      'level': level,
      'badges': badges,
      'streak': streak,
      'created_at': createdAt.toIso8601String(),
      'last_active_at': lastActiveAt?.toIso8601String(),
    };
  }

  // ─── Copy With ───────────────────────────────────────────
  UserModel copyWith({
    String? name,
    String? avatarUrl,
    int? xp,
    int? level,
    List<String>? badges,
    int? streak,
    DateTime? lastActiveAt,
  }) {
    return UserModel(
      id: id,
      name: name ?? this.name,
      email: email,
      role: role,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      xp: xp ?? this.xp,
      level: level ?? this.level,
      badges: badges ?? this.badges,
      streak: streak ?? this.streak,
      createdAt: createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
    );
  }
}