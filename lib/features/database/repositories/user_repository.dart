import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import '../../../models/user_model.dart';
import '../core/database_manager.dart';

/// Repository for user authentication and management
class UserRepository {
  static const String _userTable = 'users';

  /// Hash password using SHA-256
  static String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Create a new user
  static Future<UserModel?> createUser({
    required String email,
    required String password,
    required String name,
    String? phoneNumber,
    Map<String, dynamic>? additionalInfo,
    bool isOnlineUser = false,
  }) async {
    try {
      final db = await DatabaseManager.database;

      // Check if user already exists
      final existingUser = await getUserByEmail(email);
      if (existingUser != null) {
        debugPrint('❌ User already exists: $email');
        return null;
      }

      final hashedPassword = _hashPassword(password);
      final userId = 'user_${DateTime.now().millisecondsSinceEpoch}';

      final userData = {
        'userId': userId,
        'email': email,
        'password': hashedPassword,
        'name': name,
        'phoneNumber': phoneNumber,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'lastLogin': DateTime.now().millisecondsSinceEpoch,
        'isActive': 1,
        'additionalInfo': additionalInfo != null ? jsonEncode(additionalInfo) : null,
      };

      final insertedId = await db.insert(_userTable, userData);

      final user = UserModel(
        id: insertedId,
        userId: userId,
        email: email,
        passwordHash: hashedPassword,
        name: name,
        phoneNumber: phoneNumber,
        createdAt: DateTime.now(),
        lastLogin: DateTime.now(),
        isActive: true,
        additionalInfo: additionalInfo,
      );

      debugPrint('✅ User created: $email');
      return user;
    } catch (e) {
      debugPrint('❌ Error creating user: $e');
      return null;
    }
  }

  /// Login user with email and password
  static Future<UserModel?> loginUser(String email, String password) async {
    try {
      final db = await DatabaseManager.database;
      final hashedPassword = _hashPassword(password);

      final results = await db.query(
        _userTable,
        where: 'email = ? AND password = ? AND isActive = 1',
        whereArgs: [email, hashedPassword],
        limit: 1,
      );

      if (results.isEmpty) {
        debugPrint('❌ Invalid login credentials for: $email');
        return null;
      }

      // Update last login time
      await db.update(
        _userTable,
        {'lastLogin': DateTime.now().millisecondsSinceEpoch},
        where: 'email = ?',
        whereArgs: [email],
      );

      final userData = results.first;
      final user = UserModel(
        id: userData['id'] as int?,
        userId: userData['userId'] as String,
        email: userData['email'] as String,
        passwordHash: userData['password'] as String,
        name: userData['name'] as String,
        phoneNumber: userData['phoneNumber'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(userData['createdAt'] as int),
        lastLogin: DateTime.now(),
        isActive: (userData['isActive'] as int) == 1,
        additionalInfo: userData['additionalInfo'] != null
            ? jsonDecode(userData['additionalInfo'] as String)
            : null,
      );

      debugPrint('✅ User logged in: $email');
      return user;
    } catch (e) {
      debugPrint('❌ Error logging in user: $e');
      return null;
    }
  }

  /// Check if user exists
  static Future<bool> userExists(String email) async {
    try {
      final db = await DatabaseManager.database;
      final result = await db.query(
        _userTable,
        where: 'email = ?',
        whereArgs: [email],
        limit: 1,
      );

      return result.isNotEmpty;
    } catch (e) {
      debugPrint('❌ Error checking user exists: $e');
      return false;
    }
  }

  /// Get user by email
  static Future<UserModel?> getUserByEmail(String email) async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _userTable,
        where: 'email = ?',
        whereArgs: [email],
        limit: 1,
      );

      if (results.isEmpty) return null;

      final userData = results.first;
      return UserModel(
        id: userData['id'] as int?,
        userId: userData['userId'] as String,
        email: userData['email'] as String,
        passwordHash: userData['password'] as String,
        name: userData['name'] as String,
        phoneNumber: userData['phoneNumber'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(userData['createdAt'] as int),
        lastLogin: userData['lastLogin'] != null
            ? DateTime.fromMillisecondsSinceEpoch(userData['lastLogin'] as int)
            : null,
        isActive: (userData['isActive'] as int) == 1,
        additionalInfo: userData['additionalInfo'] != null
            ? jsonDecode(userData['additionalInfo'] as String)
            : null,
      );
    } catch (e) {
      debugPrint('❌ Error getting user by email: $e');
      return null;
    }
  }

  /// Get user by ID
  static Future<UserModel?> getUserById(String userId) async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _userTable,
        where: 'userId = ?',
        whereArgs: [userId],
        limit: 1,
      );

      if (results.isEmpty) return null;

      final userData = results.first;
      return UserModel(
        id: userData['id'] as int?,
        userId: userData['userId'] as String,
        email: userData['email'] as String,
        passwordHash: userData['password'] as String,
        name: userData['name'] as String,
        phoneNumber: userData['phoneNumber'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(userData['createdAt'] as int),
        lastLogin: userData['lastLogin'] != null
            ? DateTime.fromMillisecondsSinceEpoch(userData['lastLogin'] as int)
            : null,
        isActive: (userData['isActive'] as int) == 1,
        additionalInfo: userData['additionalInfo'] != null
            ? jsonDecode(userData['additionalInfo'] as String)
            : null,
      );
    } catch (e) {
      debugPrint('❌ Error getting user by ID: $e');
      return null;
    }
  }

  /// Get all users
  static Future<List<UserModel>> getAllUsers() async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _userTable,
        orderBy: 'createdAt DESC',
      );

      return results.map((userData) => UserModel(
        id: userData['id'] as int?,
        userId: userData['userId'] as String,
        email: userData['email'] as String,
        passwordHash: userData['password'] as String,
        name: userData['name'] as String,
        phoneNumber: userData['phoneNumber'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(userData['createdAt'] as int),
        lastLogin: userData['lastLogin'] != null
            ? DateTime.fromMillisecondsSinceEpoch(userData['lastLogin'] as int)
            : null,
        isActive: (userData['isActive'] as int) == 1,
        additionalInfo: userData['additionalInfo'] != null
            ? jsonDecode(userData['additionalInfo'] as String)
            : null,
      )).toList();
    } catch (e) {
      debugPrint('❌ Error getting all users: $e');
      return [];
    }
  }

  /// Update user information
  static Future<bool> updateUser({
    required String userId,
    String? name,
    String? phoneNumber,
    Map<String, dynamic>? additionalInfo,
  }) async {
    try {
      final db = await DatabaseManager.database;
      final updateData = <String, dynamic>{};

      if (name != null) updateData['name'] = name;
      if (phoneNumber != null) updateData['phoneNumber'] = phoneNumber;
      if (additionalInfo != null) updateData['additionalInfo'] = jsonEncode(additionalInfo);

      if (updateData.isEmpty) return false;

      final result = await db.update(
        _userTable,
        updateData,
        where: 'userId = ?',
        whereArgs: [userId],
      );

      return result > 0;
    } catch (e) {
      debugPrint('❌ Error updating user: $e');
      return false;
    }
  }

  /// Change user password
  static Future<bool> changePassword({
    required String userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final db = await DatabaseManager.database;

      // Verify old password
      final hashedOldPassword = _hashPassword(oldPassword);
      final userCheck = await db.query(
        _userTable,
        where: 'userId = ? AND password = ?',
        whereArgs: [userId, hashedOldPassword],
        limit: 1,
      );

      if (userCheck.isEmpty) {
        debugPrint('❌ Invalid old password for user: $userId');
        return false;
      }

      // Update with new password
      final hashedNewPassword = _hashPassword(newPassword);
      final result = await db.update(
        _userTable,
        {'password': hashedNewPassword},
        where: 'userId = ?',
        whereArgs: [userId],
      );

      debugPrint('✅ Password changed for user: $userId');
      return result > 0;
    } catch (e) {
      debugPrint('❌ Error changing password: $e');
      return false;
    }
  }

  /// Deactivate user (soft delete)
  static Future<bool> deactivateUser(String userId) async {
    try {
      final db = await DatabaseManager.database;
      final result = await db.update(
        _userTable,
        {'isActive': 0},
        where: 'userId = ?',
        whereArgs: [userId],
      );

      debugPrint('✅ User deactivated: $userId');
      return result > 0;
    } catch (e) {
      debugPrint('❌ Error deactivating user: $e');
      return false;
    }
  }

  /// Reactivate user
  static Future<bool> reactivateUser(String userId) async {
    try {
      final db = await DatabaseManager.database;
      final result = await db.update(
        _userTable,
        {'isActive': 1},
        where: 'userId = ?',
        whereArgs: [userId],
      );

      debugPrint('✅ User reactivated: $userId');
      return result > 0;
    } catch (e) {
      debugPrint('❌ Error reactivating user: $e');
      return false;
    }
  }

  /// Delete user permanently
  static Future<bool> deleteUser(String userId) async {
    try {
      final db = await DatabaseManager.database;
      final result = await db.delete(
        _userTable,
        where: 'userId = ?',
        whereArgs: [userId],
      );

      debugPrint('🗑️ User deleted permanently: $userId');
      return result > 0;
    } catch (e) {
      debugPrint('❌ Error deleting user: $e');
      return false;
    }
  }

  /// Sync online user (for cloud integration)
  static Future<void> syncOnlineUser(UserModel user) async {
    try {
      final db = await DatabaseManager.database;

      final userData = {
        'userId': user.userId,
        'email': user.email,
        'name': user.name,
        'phoneNumber': user.phoneNumber,
        'createdAt': user.createdAt.millisecondsSinceEpoch,
        'lastLogin': user.lastLogin?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch,
        'isActive': user.isActive ? 1 : 0,
        'additionalInfo': user.additionalInfo != null ? jsonEncode(user.additionalInfo!) : null,
        'synced': 1,
      };

      await db.insert(
        _userTable,
        userData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      debugPrint('📡 User synced from online: ${user.email}');
    } catch (e) {
      debugPrint('❌ Error syncing online user: $e');
    }
  }

  /// Get user statistics
  static Future<Map<String, dynamic>> getUserStats() async {
    try {
      final db = await DatabaseManager.database;

      final totalUsers = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_userTable'),
      ) ?? 0;

      final activeUsers = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_userTable WHERE isActive = 1'),
      ) ?? 0;

      final recentLogins = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM $_userTable WHERE lastLogin > ?',
          [DateTime.now().subtract(Duration(days: 7)).millisecondsSinceEpoch],
        ),
      ) ?? 0;

      return {
        'totalUsers': totalUsers,
        'activeUsers': activeUsers,
        'inactiveUsers': totalUsers - activeUsers,
        'recentLogins': recentLogins,
      };
    } catch (e) {
      debugPrint('❌ Error getting user stats: $e');
      return {};
    }
  }

  /// Clear all users (for testing/reset)
  static Future<void> clearUsers() async {
    try {
      final db = await DatabaseManager.database;
      await db.delete(_userTable);
      debugPrint('🧹 All users cleared');
    } catch (e) {
      debugPrint('❌ Error clearing users: $e');
    }
  }

  /// Export user data
  static Future<Map<String, dynamic>> exportUserData(String userId) async {
    try {
      final user = await getUserById(userId);
      if (user == null) return {};

      return {
        'exportDate': DateTime.now().toIso8601String(),
        'userId': user.userId,
        'email': user.email,
        'name': user.name,
        'phoneNumber': user.phoneNumber,
        'createdAt': user.createdAt.toIso8601String(),
        'lastLogin': user.lastLogin?.toIso8601String(),
        'isActive': user.isActive,
        'additionalInfo': user.additionalInfo,
      };
    } catch (e) {
      debugPrint('❌ Error exporting user data: $e');
      return {};
    }
  }

  // Compatibility methods for existing code
  static Future<void> clearAllData() => clearUsers();
  static Future<UserModel?> getByEmail(String email) => getUserByEmail(email);
  static Future<UserModel?> create({
    required String email,
    required String password,
    required String name,
    String? phoneNumber,
  }) => createUser(
    email: email,
    password: password,
    name: name,
    phoneNumber: phoneNumber,
    isOnlineUser: false,
  );
  static Future<UserModel?> login(String email, String password) => loginUser(email, password);
  static Future<bool> exists(String email) => userExists(email);
}