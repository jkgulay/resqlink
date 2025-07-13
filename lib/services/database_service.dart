import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/user_model.dart';
import '../models/message_model.dart';

class DatabaseService {
  static Database? _database;
  static const String _userTable = 'users';
  static const String _messageTable = 'messages';

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  static Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'resqlink.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  static Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_userTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        display_name TEXT,
        created_at TEXT NOT NULL,
        last_login TEXT NOT NULL,
        is_online_user INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE $_messageTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        endpoint_id TEXT NOT NULL,
        from_user TEXT NOT NULL,
        message TEXT NOT NULL,
        is_me INTEGER NOT NULL,
        is_emergency INTEGER NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');
  }

  static String _hashPassword(String password) {
    var bytes = utf8.encode(password);
    var digest = sha256.convert(bytes);
    return digest.toString();
  }

  static Future<UserModel?> createUser(String email, String password, {bool isOnlineUser = false}) async {
    try {
      final db = await database;
      final now = DateTime.now();

      final user = UserModel(
        email: email.toLowerCase(),
        passwordHash: _hashPassword(password),
        createdAt: now,
        lastLogin: now,
        isOnlineUser: isOnlineUser,
      );

      final id = await db.insert(_userTable, user.toMap());
      return user.copyWith(id: id);
    } catch (e) {
      print('Error creating user: $e');
      return null;
    }
  }

  static Future<UserModel?> loginUser(String email, String password) async {
    try {
      final db = await database;
      final hashedPassword = _hashPassword(password);

      final result = await db.query(
        _userTable,
        where: 'email = ? AND password_hash = ?',
        whereArgs: [email.toLowerCase(), hashedPassword],
      );

      if (result.isNotEmpty) {
        final user = UserModel.fromMap(result.first);

        await db.update(
          _userTable,
          {'last_login': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [user.id],
        );

        return user;
      }
      return null;
    } catch (e) {
      print('Error logging in user: $e');
      return null;
    }
  }

  static Future<bool> userExists(String email) async {
    try {
      final db = await database;
      final result = await db.query(
        _userTable,
        where: 'email = ?',
        whereArgs: [email.toLowerCase()],
      );
      return result.isNotEmpty;
    } catch (e) {
      print('Error checking user existence: $e');
      return false;
    }
  }

  static Future<List<UserModel>> getAllUsers() async {
    try {
      final db = await database;
      final result = await db.query(_userTable);
      return result.map((map) => UserModel.fromMap(map)).toList();
    } catch (e) {
      print('Error getting all users: $e');
      return [];
    }
  }

  static Future<void> syncOnlineUser(UserModel user) async {
    try {
      final db = await database;
      await db.insert(
        _userTable,
        user.copyWith(isOnlineUser: true).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      print('Error syncing online user: $e');
    }
  }

  static Future<void> saveMessage(MessageModel message) async {
    try {
      final db = await database;
      await db.insert(_messageTable, message.toMap());
    } catch (e) {
      print('Error saving message: $e');
    }
  }

  static Future<List<MessageModel>> getMessages(String endpointId) async {
    try {
      final db = await database;
      final result = await db.query(
        _messageTable,
        where: 'endpoint_id = ?',
        whereArgs: [endpointId],
        orderBy: 'timestamp ASC',
      );
      return result.map((e) => MessageModel.fromMap(e)).toList();
    } catch (e) {
      print('Error loading messages: $e');
      return [];
    }
  }

  static Future<void> syncMessageToFirebaseIfOnline(MessageModel message, Future<bool> Function() isConnected, Future<void> Function(MessageModel) syncFn) async {
    if (await isConnected()) {
      try {
        await syncFn(message);
      } catch (e) {
        print('Error syncing message to Firebase: $e');
      }
    }
  }
}

extension UserModelExtension on UserModel {
  UserModel copyWith({
    int? id,
    String? email,
    String? passwordHash,
    String? displayName,
    DateTime? createdAt,
    DateTime? lastLogin,
    bool? isOnlineUser,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      passwordHash: passwordHash ?? this.passwordHash,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
      isOnlineUser: isOnlineUser ?? this.isOnlineUser,
    );
  }
}
