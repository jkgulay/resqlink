class UserModel {
  final int? id;
  final String userId;
  final String email;
  final String passwordHash;
  final String name;
  final String? phoneNumber;
  final DateTime createdAt;
  final DateTime? lastLogin;
  final bool isActive;
  final bool isOnlineUser;
  final Map<String, dynamic>? additionalInfo;

  UserModel({
    this.id,
    required this.userId,
    required this.email,
    required this.passwordHash,
    required this.name,
    this.phoneNumber,
    required this.createdAt,
    this.lastLogin,
    this.isActive = true,
    this.isOnlineUser = false,
    this.additionalInfo,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'email': email,
      'password': passwordHash,
      'name': name,
      'phoneNumber': phoneNumber,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'lastLogin': lastLogin?.millisecondsSinceEpoch,
      'isActive': isActive ? 1 : 0,
      'additionalInfo': additionalInfo,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'],
      userId: map['userId'] ?? '',
      email: map['email'] ?? '',
      passwordHash: map['password'] ?? '',
      name: map['name'] ?? '',
      phoneNumber: map['phoneNumber'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? 0),
      lastLogin: map['lastLogin'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastLogin'])
          : null,
      isActive: (map['isActive'] ?? 1) == 1,
      isOnlineUser: false, // This field is not in the database schema
      additionalInfo: map['additionalInfo'],
    );
  }

  UserModel copyWith({
    int? id,
    String? userId,
    String? email,
    String? passwordHash,
    String? name,
    String? phoneNumber,
    DateTime? createdAt,
    DateTime? lastLogin,
    bool? isActive,
    bool? isOnlineUser,
    Map<String, dynamic>? additionalInfo,
  }) {
    return UserModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      passwordHash: passwordHash ?? this.passwordHash,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
      isActive: isActive ?? this.isActive,
      isOnlineUser: isOnlineUser ?? this.isOnlineUser,
      additionalInfo: additionalInfo ?? this.additionalInfo,
    );
  }
}