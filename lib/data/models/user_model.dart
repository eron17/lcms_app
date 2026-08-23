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

}