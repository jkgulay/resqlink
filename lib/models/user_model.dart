class UserModel {
  final int? id;
  final String email;
  final String passwordHash;
  final DateTime createdAt;
  final DateTime lastLogin;
  final bool isOnlineUser;

  UserModel({
    this.id,
    required this.email,
    required this.passwordHash,
    required this.createdAt,
    required this.lastLogin,
    this.isOnlineUser = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'password_hash': passwordHash,
      'created_at': createdAt.toIso8601String(),
      'last_login': lastLogin.toIso8601String(),
      'is_online_user': isOnlineUser ? 1 : 0,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'],
      email: map['email'],
      passwordHash: map['password_hash'],
      createdAt: DateTime.parse(map['created_at']),
      lastLogin: DateTime.parse(map['last_login']),
      isOnlineUser: map['is_online_user'] == 1,
    );
  }

  UserModel copyWith({
    int? id,
    String? email,
    String? passwordHash,
    DateTime? createdAt,
    DateTime? lastLogin,
    bool? isOnlineUser,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      passwordHash: passwordHash ?? this.passwordHash,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
      isOnlineUser: isOnlineUser ?? this.isOnlineUser,
    );
  }
}